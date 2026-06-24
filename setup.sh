#!/bin/bash

# =============================================================================
# OCI Production-Ready Deployment Orchestrator
# Target: Ubuntu 24.04 Minimal (x86_64 / ARM64)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/deploy}"
CONFIG_FILE="${CONFIG_FILE:-$DEPLOY_ROOT/.env}"

upsert_env() {
    local key="$1" value="$2" file="$3"
    sudo touch "$file"
    if sudo grep -q "^${key}=" "$file"; then
        local escaped_value
        escaped_value=$(printf '%s' "$value" | sed 's/[&/\\]/\\&/g')
        sudo sed -i "s/^${key}=.*/${key}=${escaped_value}/" "$file"
    else
        sudo tee -a "$file" > /dev/null <<< "$key=$value"
    fi
}

replace_token() {
    local token="$1" value="$2" file="$3"
    local escaped_value
    escaped_value=$(printf '%s' "$value" | sed 's/[&/\\]/\\&/g')
    sudo sed -i "s/${token}/${escaped_value}/g" "$file"
}

should_prompt() {
    local var_name="$1"
    local current_value="${!var_name:-}"
    if [ -z "$current_value" ]; then
        return 0
    fi
    echo -e "${YELLOW}$var_name is currently set to: $current_value${NC}"
    read -p "Do you want to change it? (y/n) [n]: " change_choice
    if [[ "$change_choice" =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

prompt_env() {
    local var_name="$1"
    local prompt_msg="$2"
    local info_msg="${3:-}"

    if should_prompt "$var_name"; then
        [ -n "$info_msg" ] && echo -e "$info_msg"
        read -p "$prompt_msg" "$var_name"
        upsert_env "$var_name" "${!var_name}" "$CONFIG_FILE"
    fi
}

validate_timezone() {
    local tz="$1"
    if timedatectl list-timezones | grep -qx "$tz"; then
        return 0
    else
        return 1
    fi
}

sanitize_domain() {
    local domain="$1"
    # Remove protocol (http:// or https://)
    domain=$(echo "$domain" | sed -E 's|^https?://||i')
    # Remove trailing slash
    domain="${domain%/}"
    echo "$domain"
}

mariadb_can_auth_with_password() {
    local password="$1"
    # Pass password via STDIN to a subshell inside the container to avoid process list exposure
    sudo docker exec -i mariadb-db sh -c 'read -r MYSQL_PWD; export MYSQL_PWD; mariadb -u root -e "SELECT 1;"' <<< "$password" >/dev/null 2>&1
}

mariadb_can_auth_empty() {
    sudo docker exec -i mariadb-db mariadb -u root -e "SELECT 1;" >/dev/null 2>&1
}

discover_mariadb_root_auth() {
    MARIADB_ROOT_AUTH_MODE=""
    MARIADB_ROOT_WORKING_PASS=""
    local candidates=()
    candidates+=("$DB_ROOT_PASS")
    local container_env_pass
    container_env_pass=$(sudo docker exec mariadb-db printenv MARIADB_ROOT_PASSWORD 2>/dev/null || true)
    [ -n "$container_env_pass" ] && candidates+=("$container_env_pass")
    candidates+=("password")

    local -A seen
    local candidate
    for candidate in "${candidates[@]}"; do
        [ -z "$candidate" ] || [ -n "${seen[$candidate]:-}" ] && continue
        seen["$candidate"]=1
        if mariadb_can_auth_with_password "$candidate"; then
            MARIADB_ROOT_AUTH_MODE="password"
            MARIADB_ROOT_WORKING_PASS="$candidate"
            return 0
        fi
    done

    if mariadb_can_auth_empty; then
        MARIADB_ROOT_AUTH_MODE="empty"
        return 0
    fi

    return 1
}

mariadb_root_exec() {
    local sql="$1"
    if [ "${MARIADB_ROOT_AUTH_MODE:-}" = "empty" ]; then
        sudo docker exec -i mariadb-db mariadb -u root <<< "$sql"
    else
        # Use internal container environment variable for root password
        sudo docker exec -i mariadb-db sh -c 'export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"; mariadb -u root' <<< "$sql"
    fi
}

sync_mariadb_root_password() {
    if [ "${MARIADB_ROOT_AUTH_MODE:-}" = "empty" ] || [ "${MARIADB_ROOT_WORKING_PASS:-}" != "$DB_ROOT_PASS" ]; then
        echo "Synchronizing MariaDB root password with $DEPLOY_ROOT/db/.env..."
        mariadb_root_exec "
            ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
            ALTER USER IF EXISTS 'root'@'%' IDENTIFIED BY '$DB_ROOT_PASS';
            FLUSH PRIVILEGES;
        "
        MARIADB_ROOT_AUTH_MODE="password"
        MARIADB_ROOT_WORKING_PASS="$DB_ROOT_PASS"
    fi
}

allow_port() {
    local port="$1"
    local proto="${2:-tcp}"
    sudo iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT || true
    sudo ufw allow "$port/$proto"
}

get_secret() { grep "^$1=" "$2" 2>/dev/null | head -n 1 | cut -d'=' -f2- | tr -d '\r' || echo ""; }
ensure_secret() {
    local key="$1" file="$2" length="${3:-12}"
    local secret
    secret=$(get_secret "$key" "$file")
    [ -z "$secret" ] && secret=$(openssl rand -hex "$length")
    echo "$secret"
}
psql_admin() {
    # Use internal container environment variable for postgres password
    # Arguments are passed to psql, but SQL should preferably be passed via STDIN for security
    sudo docker exec -i postgres-db sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -v ON_ERROR_STOP=1 -U admin "$@"' psql "$@"
}
ensure_postgres_app_db() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"

    psql_admin -d postgres <<EOF
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$db_user') THEN CREATE USER $db_user WITH PASSWORD '$db_pass'; ELSE ALTER USER $db_user WITH PASSWORD '$db_pass'; END IF; END \$\$;
SELECT 'CREATE DATABASE $db_name OWNER $db_user' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db_name') \gexec
ALTER DATABASE $db_name OWNER TO $db_user;
GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;
\c $db_name
ALTER SCHEMA public OWNER TO $db_user;
GRANT ALL ON SCHEMA public TO $db_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $db_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $db_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $db_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $db_user;
EOF
}

phase0_preflight_checks() {
    # Phase 0: Pre-flight Checks
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Step 0] Pre-flight checks (fixing filesystem conflicts)...${NC}"
    sudo mkdir -p "$DEPLOY_ROOT"/{proxy/conf.d,proxy/certs,db,webserver,automation,storage,data/web_root,data/ftp_storage,data/postgres,data/mariadb,data/n8n,data/activepieces,data/huginn,data/redis,data/nginx,backups,scripts,templates}

    # If this script is launched from a checkout outside /opt/deploy, copy the
    # deployment assets into place before Compose or helper scripts are referenced.
    if [ "$SCRIPT_DIR" != "$DEPLOY_ROOT" ]; then
        echo "Synchronizing deployment files from $SCRIPT_DIR to $DEPLOY_ROOT..."
        sudo cp -a "$SCRIPT_DIR/setup.sh" "$DEPLOY_ROOT/setup.sh"
        for path in db webserver automation storage proxy; do
            if [ -f "$SCRIPT_DIR/$path/docker-compose.yml" ]; then
                sudo cp -a "$SCRIPT_DIR/$path/docker-compose.yml" "$DEPLOY_ROOT/$path/docker-compose.yml"
            fi
        done
        if [ -f "$SCRIPT_DIR/webserver/Dockerfile" ]; then
            sudo cp -a "$SCRIPT_DIR/webserver/Dockerfile" "$DEPLOY_ROOT/webserver/Dockerfile"
        fi
        sudo cp -a "$SCRIPT_DIR/scripts/." "$DEPLOY_ROOT/scripts/"
        sudo cp -a "$SCRIPT_DIR/templates/." "$DEPLOY_ROOT/templates/"
        sudo chmod +x "$DEPLOY_ROOT/setup.sh" "$DEPLOY_ROOT"/scripts/*.sh
    fi

    # Fix cases where Docker created directories instead of empty files
    for item in "$DEPLOY_ROOT/storage/users.conf" "$DEPLOY_ROOT/storage/passwd" "$DEPLOY_ROOT/storage/sftp.json" "$DEPLOY_ROOT/webserver/timezone.ini" "$CONFIG_FILE"; do
        if [ -d "$item" ]; then
            echo "Fixing directory conflict for $item"
            sudo rm -rf "$item"
        fi
        sudo touch "$item"
    done

}

phase1_load_config() {
    # Phase 1: Load/Save Configuration
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Step 1] Loading user configuration...${NC}"
    [ -f "$CONFIG_FILE" ] && set -a && source "$CONFIG_FILE" && set +a || sudo touch "$CONFIG_FILE"

    prompt_env MAIN_DOMAIN "Enter your main Domain or IP (e.g., yourdomain.com): "
    # Ensure MAIN_DOMAIN is clean even if loaded from file or prompted
    CLEAN_DOMAIN=$(sanitize_domain "$MAIN_DOMAIN")
    if [ "$CLEAN_DOMAIN" != "$MAIN_DOMAIN" ]; then
        MAIN_DOMAIN="$CLEAN_DOMAIN"
        upsert_env MAIN_DOMAIN "$MAIN_DOMAIN" "$CONFIG_FILE"
    fi

    prompt_env ADMIN_EMAIL "Enter Admin email (for SSL notifications): "
    prompt_env ACCESS_CHOICE "Choice [1-2]: " "\nHow would you like to access your tools?\n1) Subdomains (n8n.domain.com, ap.domain.com, etc.)\n2) Ports (domain.com:5678, domain.com:8081, etc.)"
    prompt_env SSL_CHOICE "Choice [1-3]: " "\nSSL Certificate Setup:\n1) Let's Encrypt (Requires Port 80 open & Domain pointed to IP)\n2) Self-Signed (Works for IP-based access)\n3) None (HTTP Only - insecure)"

    if should_prompt TIMEZONE; then
        while true; do
            read -p "Enter System Timezone [Asia/Colombo]: " user_tz
            TIMEZONE="${user_tz:-Asia/Colombo}"
            if validate_timezone "$TIMEZONE"; then
                upsert_env TIMEZONE "$TIMEZONE" "$CONFIG_FILE"
                break
            else
                echo -e "${RED}Invalid timezone: $TIMEZONE. Please try again.${NC}"
                echo "Tip: You can find a list of valid timezones using 'timedatectl list-timezones'"
            fi
        done
    fi
    echo -e "${YELLOW}Setting system timezone to $TIMEZONE...${NC}"
    sudo timedatectl set-timezone "$TIMEZONE"

    case "$ACCESS_CHOICE" in
        1|2) ;;
        *) echo -e "${RED}Invalid access choice: $ACCESS_CHOICE${NC}"; exit 1 ;;
    esac
    case "$SSL_CHOICE" in
        1|2|3) ;;
        *) echo -e "${RED}Invalid SSL choice: $SSL_CHOICE${NC}"; exit 1 ;;
    esac

}

phase1b_performance_tuning() {
    # 1b. System Performance Tuning
    # -----------------------------------------------------------------------------
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 2000 ]; then
        echo -e "${YELLOW}Detected ${TOTAL_RAM}MB RAM. Enabling Swap and strict container limits...${NC}"
        DB_LIMIT="512M"; AUTO_LIMIT="512M"; HUGINN_LIMIT="1G"; PHP_LIMIT="256M"
        REDIS_CMD="redis-server --maxmemory 64mb --maxmemory-policy allkeys-lru"
        if [ ! -f /swapfile ]; then
            sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
            sudo tee -a /etc/fstab <<< '/swapfile none swap sw 0 0'
        fi
    else
        echo -e "${GREEN}Detected ${TOTAL_RAM}MB RAM. Using standard performance settings.${NC}"
        DB_LIMIT="2G"; AUTO_LIMIT="2G"; HUGINN_LIMIT="2G"; PHP_LIMIT="1G"; REDIS_CMD="redis-server"
    fi

}

phase2_install_dependencies() {
    # Phase 2: Dependencies
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Step 2] Installing system dependencies (Docker, SSL, Cron)...${NC}"
    sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg lsb-release ufw certbot openssl cron lsof

    # Early Firewall Configuration (Critical for OCI)
    echo -e "${YELLOW}[Step 2.1] Opening ports 80/443/22/2222 in local firewall...${NC}"
    # Insert rules at top of iptables to bypass OCI default REJECT rules and configure UFW
    CORE_PORTS=(22 80 443 2222)
    for port in "${CORE_PORTS[@]}"; do
        allow_port "$port"
    done
    echo "y" | sudo ufw enable

    if ! command -v docker &> /dev/null; then
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null <<< "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

}

phase3_configure_secrets_users() {
    # Phase 3: Secrets & Users
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Step 3] Configuring persistent secrets and SFTP users...${NC}"

    DB_ROOT_PASS=$(ensure_secret "MARIADB_ROOT_PASSWORD" "$DEPLOY_ROOT/db/.env" 12)
    WEB_DB_PASS=$(ensure_secret "WEB_DB_PASS" "$DEPLOY_ROOT/webserver/.env" 12)
    N8N_DB_PASS=$(ensure_secret "N8N_DB_PASS" "$DEPLOY_ROOT/automation/.env" 12)
    AP_DB_PASS=$(ensure_secret "AP_DB_PASS" "$DEPLOY_ROOT/automation/.env" 12)
    HUGINN_DB_PASS=$(ensure_secret "HUGINN_DB_PASS" "$DEPLOY_ROOT/automation/.env" 12)
    N8N_ENCRYPTION_KEY=$(ensure_secret "N8N_ENCRYPTION_KEY" "$DEPLOY_ROOT/automation/.env" 32)
    AP_ENCRYPTION_KEY=$(ensure_secret "AP_ENCRYPTION_KEY" "$DEPLOY_ROOT/automation/.env" 16)
    AP_JWT_SECRET=$(ensure_secret "AP_JWT_SECRET" "$DEPLOY_ROOT/automation/.env" 32)
    HUGINN_APP_SECRET_TOKEN=$(ensure_secret "HUGINN_APP_SECRET_TOKEN" "$DEPLOY_ROOT/automation/.env" 64)
    HUGINN_INVITATION_CODE=$(ensure_secret "HUGINN_INVITATION_CODE" "$DEPLOY_ROOT/automation/.env" 12)

    # Handle SFTP Config for Emberstack (JSON format)
    SFTP_WEB_PASS=$(ensure_secret "SFTP_WEB_PASS" "$DEPLOY_ROOT/.env" 12)
    upsert_env SFTP_WEB_PASS "$SFTP_WEB_PASS" "$CONFIG_FILE"

    SFTP_FILES_PASS=$(ensure_secret "SFTP_FILES_PASS" "$DEPLOY_ROOT/.env" 12)
    upsert_env SFTP_FILES_PASS "$SFTP_FILES_PASS" "$CONFIG_FILE"

    sudo useradd -m -s /usr/sbin/nologin webuser || true
    sudo useradd -m -s /usr/sbin/nologin filesuser || true
    WEB_UID=$(id -u webuser); FILES_UID=$(id -u filesuser)

    sudo tee "$DEPLOY_ROOT/storage/sftp.json" > /dev/null <<EOF
{
    "Global": {
        "Chroot": { "Directory": "%h" }
    },
    "Users": [
        {
            "Username": "webuser",
            "Password": "$SFTP_WEB_PASS",
            "Uid": $WEB_UID,
            "Gid": $WEB_UID,
            "Directories": ["web_root"]
        },
        {
            "Username": "filesuser",
            "Password": "$SFTP_FILES_PASS",
            "Uid": $FILES_UID,
            "Gid": $FILES_UID,
            "Directories": ["my_ftp_files"]
        }
    ]
}
EOF

    sudo chown -R webuser:webuser "$DEPLOY_ROOT/data/web_root"
    sudo chown -R filesuser:filesuser "$DEPLOY_ROOT/data/ftp_storage"
    sudo chown -R 1000:1000 "$DEPLOY_ROOT/data/n8n"
    sudo chown -R root:root "$DEPLOY_ROOT/data/activepieces"
    sudo chmod -R 700 "$DEPLOY_ROOT/data/activepieces"

    # Ensure database directories have correct permissions and ownership
    # This prevents 'Permission denied' if Docker created them as root during a failed run
    sudo mkdir -p "$DEPLOY_ROOT/data/postgres" "$DEPLOY_ROOT/data/mariadb"
    # Postgres Alpine uses 70:70, MariaDB uses 999:999
    sudo chown -R 70:70 "$DEPLOY_ROOT/data/postgres"
    sudo chown -R 999:999 "$DEPLOY_ROOT/data/mariadb"
    sudo chmod -R 700 "$DEPLOY_ROOT/data/postgres" "$DEPLOY_ROOT/data/mariadb"

    # Fix for Postgres 18+ data directory structure
    source "$DEPLOY_ROOT/scripts/utils.sh"
    migrate_postgres "$DEPLOY_ROOT"

}

phase4_write_service_envs() {
    # Phase 4: Write Service Envs
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Step 4] Synchronizing service environment files...${NC}"
    PROTO="http"; [ "$SSL_CHOICE" != "3" ] && PROTO="https"
    BASE_URL="$PROTO://$MAIN_DOMAIN"
    AP_URL="$BASE_URL:8081"; [ "$ACCESS_CHOICE" == "1" ] && AP_URL="$PROTO://ap.$MAIN_DOMAIN"
    N8N_WEBHOOK_URL="$BASE_URL:5678/"; [ "$ACCESS_CHOICE" == "1" ] && N8N_WEBHOOK_URL="$PROTO://n8n.$MAIN_DOMAIN/"
    N8N_EDITOR_BASE_URL="$BASE_URL:5678"; [ "$ACCESS_CHOICE" == "1" ] && N8N_EDITOR_BASE_URL="$PROTO://n8n.$MAIN_DOMAIN"
    N8N_ALLOWED_ORIGINS="$BASE_URL:5678"; [ "$ACCESS_CHOICE" == "1" ] && N8N_ALLOWED_ORIGINS="$PROTO://n8n.$MAIN_DOMAIN"
    HUGINN_DOMAIN="$MAIN_DOMAIN:3000"; [ "$ACCESS_CHOICE" == "1" ] && HUGINN_DOMAIN="huginn.$MAIN_DOMAIN"

    sudo tee "$DEPLOY_ROOT/db/.env" > /dev/null <<EOF
POSTGRES_USER=admin
POSTGRES_PASSWORD=$DB_ROOT_PASS
MARIADB_ROOT_PASSWORD=$DB_ROOT_PASS
DB_MEMORY_LIMIT=$DB_LIMIT
ADMINER_PORT=8080
TIMEZONE=$TIMEZONE
EOF

    sudo tee "$DEPLOY_ROOT/automation/.env" > /dev/null <<EOF
AUTOMATION_MEMORY_LIMIT=$AUTO_LIMIT
HUGINN_MEMORY_LIMIT=$HUGINN_LIMIT
TIMEZONE=$TIMEZONE
N8N_DB=n8n
N8N_DB_USER=n8n_user
N8N_DB_PASS=$N8N_DB_PASS
N8N_PORT_EXTERNAL=5678
N8N_WEBHOOK_URL=$N8N_WEBHOOK_URL
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_EDITOR_BASE_URL=$N8N_EDITOR_BASE_URL
N8N_ALLOWED_ORIGINS=$N8N_ALLOWED_ORIGINS
AP_DB=activepieces
AP_DB_USER=ap_user
AP_DB_PASS=$AP_DB_PASS
AP_PORT_EXTERNAL=8081
AP_URL=$AP_URL
AP_ENCRYPTION_KEY=$AP_ENCRYPTION_KEY
AP_JWT_SECRET=$AP_JWT_SECRET
HUGINN_DB=huginn
HUGINN_DB_USER=huginn_user
HUGINN_DB_PASS=$HUGINN_DB_PASS
HUGINN_APP_SECRET_TOKEN=$HUGINN_APP_SECRET_TOKEN
HUGINN_INVITATION_CODE=$HUGINN_INVITATION_CODE
HUGINN_DOMAIN=$HUGINN_DOMAIN
HUGINN_PORT_EXTERNAL=3000
EOF

    sudo tee "$DEPLOY_ROOT/webserver/.env" > /dev/null <<EOF
PHP_MEMORY_LIMIT=$PHP_LIMIT
MARIADB_ROOT_PASSWORD=$DB_ROOT_PASS
POSTGRES_PASSWORD=$DB_ROOT_PASS
WEB_DB_USER=web_app_user
WEB_DB_PASS=$WEB_DB_PASS
WEB_DB_NAME=web_app_db
ACCESS_CHOICE=$ACCESS_CHOICE
TIMEZONE=$TIMEZONE
EOF

    # PHP timezone config
    sudo tee "$DEPLOY_ROOT/webserver/timezone.ini" > /dev/null <<< "date.timezone = $TIMEZONE"

    sudo sed -i "s/command: redis-server.*/command: $REDIS_CMD/g" "$DEPLOY_ROOT/automation/docker-compose.yml" || true
    TEMPLATE="nginx_ports.conf"; [ "$ACCESS_CHOICE" == "1" ] && TEMPLATE="nginx_subdomains.conf"
    if [ "$SSL_CHOICE" == "3" ]; then
        TEMPLATE="nginx_ports_http.conf"
        [ "$ACCESS_CHOICE" == "1" ] && TEMPLATE="nginx_subdomains_http.conf"
    fi
    sudo mkdir -p "$DEPLOY_ROOT/proxy/conf.d"
    sudo cp "$DEPLOY_ROOT/templates/$TEMPLATE" "$DEPLOY_ROOT/proxy/conf.d/default.conf"
    sudo cp "$DEPLOY_ROOT/templates/nginx_security_headers.conf" "$DEPLOY_ROOT/proxy/conf.d/security_headers.conf"
    replace_token "__WEB_DOMAIN__" "$MAIN_DOMAIN" "$DEPLOY_ROOT/proxy/conf.d/default.conf"
    replace_token "__DOMAIN_OR_IP__" "$MAIN_DOMAIN" "$DEPLOY_ROOT/proxy/conf.d/default.conf"
    replace_token "__ADMINER_DOMAIN__" "db.$MAIN_DOMAIN" "$DEPLOY_ROOT/proxy/conf.d/default.conf"
    replace_token "__N8N_DOMAIN__" "n8n.$MAIN_DOMAIN" "$DEPLOY_ROOT/proxy/conf.d/default.conf"
    replace_token "__AP_DOMAIN__" "ap.$MAIN_DOMAIN" "$DEPLOY_ROOT/proxy/conf.d/default.conf"
    replace_token "__HUGINN_DOMAIN__" "huginn.$MAIN_DOMAIN" "$DEPLOY_ROOT/proxy/conf.d/default.conf"

}

phase5_configure_ssl() {
    # Phase 5: SSL
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Step 5] Configuring SSL...${NC}"
    sudo chmod +x "$DEPLOY_ROOT"/scripts/*.sh
    cd "$DEPLOY_ROOT/proxy" && sudo docker compose stop || true
    if [ "$SSL_CHOICE" == "1" ]; then
        sudo "$DEPLOY_ROOT/scripts/ssl_setup.sh" letsencrypt "$MAIN_DOMAIN" "$ADMIN_EMAIL" "$ACCESS_CHOICE"
    elif [ "$SSL_CHOICE" == "2" ]; then
        sudo "$DEPLOY_ROOT/scripts/ssl_setup.sh" selfsigned "$MAIN_DOMAIN"
    fi
    sudo cp "$DEPLOY_ROOT/templates/index.php" "$DEPLOY_ROOT/data/web_root/index.php"

}

phase6_start_services_db_init() {
    # Phase 6: Service Start & DB Setup
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Step 6] Initializing containerized services...${NC}"
    sudo docker network inspect deploy-network >/dev/null 2>&1 || sudo docker network create deploy-network
    cd "$DEPLOY_ROOT/db" && sudo docker compose up -d

    echo -e "Waiting for databases (up to 2 mins)..."
    DATABASES_READY=0
    for i in {1..24}; do
        if discover_mariadb_root_auth && \
           sudo docker exec postgres-db pg_isready -U admin -q; then
            DATABASES_READY=1
            echo -e "${GREEN}Databases verified.${NC}"
            break
        fi
        sleep 5
    done

    if [ "$DATABASES_READY" -ne 1 ]; then
        echo -e "${RED}Database verification failed.${NC}"
        echo "MariaDB did not accept the generated root password from $DEPLOY_ROOT/db/.env."
        echo "This usually means $DEPLOY_ROOT/data/mariadb already contains data initialized with an unknown old password."
        echo "If this is a fresh install and you do not need that old data, run:"
        echo "  cd $DEPLOY_ROOT/db && sudo docker compose down"
        echo "  sudo mv $DEPLOY_ROOT/data/mariadb $DEPLOY_ROOT/data/mariadb.bak.$(date +%Y%m%d%H%M%S)"
        echo "  sudo mkdir -p $DEPLOY_ROOT/data/mariadb"
        echo "  sudo ./setup.sh"
        exit 1
    fi
    sync_mariadb_root_password

    # DB Inits
    echo "Setting up databases and users..."
    # MariaDB
    mariadb_root_exec "
        CREATE DATABASE IF NOT EXISTS web_app_db;
        CREATE USER IF NOT EXISTS 'web_app_user'@'%' IDENTIFIED BY '$WEB_DB_PASS';
        ALTER USER 'web_app_user'@'%' IDENTIFIED BY '$WEB_DB_PASS';
        GRANT ALL PRIVILEGES ON web_app_db.* TO 'web_app_user'@'%';
        FLUSH PRIVILEGES;
    "

    # PostgreSQL

    ensure_postgres_app_db "n8n" "n8n_user" "$N8N_DB_PASS"
    ensure_postgres_app_db "activepieces" "ap_user" "$AP_DB_PASS"
    ensure_postgres_app_db "huginn" "huginn_user" "$HUGINN_DB_PASS"

    cd "$DEPLOY_ROOT/webserver" && sudo docker compose up -d --build
    cd "$DEPLOY_ROOT/automation" && sudo docker compose up -d
    cd "$DEPLOY_ROOT/storage" && sudo docker compose up -d
    cd "$DEPLOY_ROOT/proxy" && sudo docker compose up -d

}

phase7_final_firewall_credentials() {
    # Final: Firewall & Credentials
    # -----------------------------------------------------------------------------
    echo -e "${YELLOW}[Final] Updating Firewall...${NC}"
    for port in "${CORE_PORTS[@]}"; do
        allow_port "$port"
    done
    if [ "$ACCESS_CHOICE" == "2" ]; then
        EXTRA_PORTS=(8080 5678 8081 3000)
        for port in "${EXTRA_PORTS[@]}"; do
            allow_port "$port"
        done
    fi
    echo "y" | sudo ufw enable

    (sudo crontab -l 2>/dev/null; echo "0 2 * * 0 $DEPLOY_ROOT/scripts/backup.sh >> $DEPLOY_ROOT/backups/backup.log 2>&1") | sudo crontab - || true

    echo -e "\n${GREEN}Setup Successful!${NC}"
    echo -e "${YELLOW}IMPORTANT: Save these credentials securely!${NC}"
    sudo "$DEPLOY_ROOT/scripts/show_credentials.sh"
    echo -e "You can retrieve them later by running: ${YELLOW}sudo $DEPLOY_ROOT/scripts/show_credentials.sh${NC}"

    echo -e "\nWould you like to run a smoke test to verify all services are reachable?"
    read -p "Run smoke test? (y/n) [y]: " run_smoke
    if [[ ! "$run_smoke" =~ ^[Nn]$ ]]; then
        sudo "$DEPLOY_ROOT/scripts/smoke_test.sh" "$MAIN_DOMAIN" "$PROTO" "$ACCESS_CHOICE"
    fi
}

main() {
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}Starting OCI Deployment Setup (v5.1)${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo -e "NOTE: All database and SFTP passwords will be automatically"
    echo -e "generated at the end of this setup. No manual .env editing is required."
    echo -e "You can view them anytime with: ${YELLOW}sudo $DEPLOY_ROOT/scripts/show_credentials.sh${NC}\n"

    phase0_preflight_checks
    phase1_load_config
    phase1b_performance_tuning
    phase2_install_dependencies
    phase3_configure_secrets_users
    phase4_write_service_envs
    phase5_configure_ssl
    phase6_start_services_db_init
    phase7_final_firewall_credentials
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
