#!/bin/bash

# =============================================================================
# OCI Production-Ready Deployment Orchestrator
# Target: Ubuntu 24.04 Minimal (x86_64 / ARM64)
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEPLOY_ROOT="/opt/deploy"
CONFIG_FILE="$DEPLOY_ROOT/.env"

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}Starting OCI Deployment Setup (v5.1)${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "NOTE: All database and SFTP passwords will be automatically"
echo -e "generated and saved to ${YELLOW}$DEPLOY_ROOT/credentials.txt${NC}"
echo -e "at the end of this setup. No manual .env editing is required.\n"

# Phase 0: Pre-flight Checks
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Step 0] Pre-flight checks (fixing filesystem conflicts)...${NC}"
sudo mkdir -p $DEPLOY_ROOT/{proxy/conf.d,proxy/certs,db,webserver,automation,storage,data/web_root,data/ftp_storage,data/postgres,data/mariadb,data/n8n,data/activepieces,data/huginn,data/redis,data/nginx,backups,scripts,templates}

# Fix cases where Docker created directories instead of empty files
for item in "$DEPLOY_ROOT/storage/users.conf" "$DEPLOY_ROOT/storage/passwd" "$CONFIG_FILE"; do
    if [ -d "$item" ]; then
        echo "Fixing directory conflict for $item"
        sudo rm -rf "$item"
        sudo touch "$item"
    fi
done

# Phase 1: Load/Save Configuration
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Step 1] Loading user configuration...${NC}"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || sudo touch "$CONFIG_FILE"

if [ -z "$MAIN_DOMAIN" ]; then
    read -p "Enter your main Domain or IP (e.g., yourdomain.com): " MAIN_DOMAIN
    echo "MAIN_DOMAIN=$MAIN_DOMAIN" | sudo tee -a "$CONFIG_FILE" > /dev/null
fi
if [ -z "$ADMIN_EMAIL" ]; then
    read -p "Enter Admin email (for SSL notifications): " ADMIN_EMAIL
    echo "ADMIN_EMAIL=$ADMIN_EMAIL" | sudo tee -a "$CONFIG_FILE" > /dev/null
fi
if [ -z "$ACCESS_CHOICE" ]; then
    echo -e "\nHow would you like to access your tools?"
    echo "1) Subdomains (n8n.domain.com, ap.domain.com, etc.)"
    echo "2) Ports (domain.com:5678, domain.com:8081, etc.)"
    read -p "Choice [1-2]: " ACCESS_CHOICE
    echo "ACCESS_CHOICE=$ACCESS_CHOICE" | sudo tee -a "$CONFIG_FILE" > /dev/null
fi
if [ -z "$SSL_CHOICE" ]; then
    echo -e "\nSSL Certificate Setup:"
    echo "1) Let's Encrypt (Requires Port 80 open & Domain pointed to IP)"
    echo "2) Self-Signed (Works for IP-based access)"
    echo "3) None (HTTP Only - insecure)"
    read -p "Choice [1-3]: " SSL_CHOICE
    echo "SSL_CHOICE=$SSL_CHOICE" | sudo tee -a "$CONFIG_FILE" > /dev/null
fi

# 1b. System Performance Tuning
# -----------------------------------------------------------------------------
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 2000 ]; then
    echo -e "${YELLOW}Detected 1GB RAM. Enabling Swap and strict container limits...${NC}"
    DB_LIMIT="512M"; AUTO_LIMIT="512M"; PHP_LIMIT="256M"
    REDIS_CMD="redis-server --maxmemory 64mb --maxmemory-policy allkeys-lru"
    if [ ! -f /swapfile ]; then
        sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
else
    echo -e "${GREEN}Detected 24GB RAM. Using standard performance settings.${NC}"
    DB_LIMIT="2G"; AUTO_LIMIT="2G"; PHP_LIMIT="1G"; REDIS_CMD="redis-server"
fi

# Phase 2: Dependencies
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Step 2] Installing system dependencies (Docker, SSL, Cron)...${NC}"
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg lsb-release ufw certbot openssl cron lsof

# Early Firewall Configuration (Critical for OCI)
echo -e "${YELLOW}[Step 2.1] Opening ports 80/443/22 in local firewall...${NC}"
# Insert rules at top of iptables to bypass OCI default REJECT rules
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT || true
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT || true
sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT || true
# Configure UFW
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 2222/tcp
echo "y" | sudo ufw enable

if ! command -v docker &> /dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Phase 3: Secrets & Users
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Step 3] Configuring persistent secrets and SFTP users...${NC}"
get_secret() { grep "^$1=" "$2" 2>/dev/null | head -n 1 | cut -d'=' -f2- | tr -d '\r' || echo ""; }

DB_ROOT_PASS=$(get_secret "MARIADB_ROOT_PASSWORD" "$DEPLOY_ROOT/db/.env")
[ -z "$DB_ROOT_PASS" ] && DB_ROOT_PASS=$(openssl rand -hex 12)

WEB_DB_PASS=$(get_secret "WEB_DB_PASS" "$DEPLOY_ROOT/webserver/.env")
[ -z "$WEB_DB_PASS" ] && WEB_DB_PASS=$(openssl rand -hex 12)

N8N_DB_PASS=$(get_secret "N8N_DB_PASS" "$DEPLOY_ROOT/automation/.env")
[ -z "$N8N_DB_PASS" ] && N8N_DB_PASS=$(openssl rand -hex 12)

AP_DB_PASS=$(get_secret "AP_DB_PASS" "$DEPLOY_ROOT/automation/.env")
[ -z "$AP_DB_PASS" ] && AP_DB_PASS=$(openssl rand -hex 12)

HUGINN_DB_PASS=$(get_secret "HUGINN_DB_PASS" "$DEPLOY_ROOT/automation/.env")
[ -z "$HUGINN_DB_PASS" ] && HUGINN_DB_PASS=$(openssl rand -hex 12)

SFTP_WEB_PASS=$(grep "webuser" "$DEPLOY_ROOT/storage/users.conf" 2>/dev/null | cut -d':' -f2)
[ -z "$SFTP_WEB_PASS" ] && SFTP_WEB_PASS=$(openssl rand -hex 12)
SFTP_FILES_PASS=$(grep "filesuser" "$DEPLOY_ROOT/storage/users.conf" 2>/dev/null | cut -d':' -f2)
[ -z "$SFTP_FILES_PASS" ] && SFTP_FILES_PASS=$(openssl rand -hex 12)

sudo useradd -m -s /usr/sbin/nologin webuser || true
sudo useradd -m -s /usr/sbin/nologin filesuser || true
WEB_UID=$(id -u webuser); FILES_UID=$(id -u filesuser)

echo "webuser:$SFTP_WEB_PASS:$WEB_UID:$WEB_UID:web_root" | sudo tee $DEPLOY_ROOT/storage/users.conf > /dev/null
echo "filesuser:$SFTP_FILES_PASS:$FILES_UID:$FILES_UID:my_ftp_files" | sudo tee -a $DEPLOY_ROOT/storage/users.conf > /dev/null

sudo chown -R webuser:webuser $DEPLOY_ROOT/data/web_root
sudo chown -R filesuser:filesuser $DEPLOY_ROOT/data/ftp_storage
sudo chown -R 1000:1000 $DEPLOY_ROOT/data/n8n
sudo chmod -R 777 $DEPLOY_ROOT/data/activepieces
sudo chown -R 999:999 $DEPLOY_ROOT/data/{postgres,mariadb}

# Phase 4: Write Service Envs
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Step 4] Synchronizing service environment files...${NC}"
PROTO="http"; [ "$SSL_CHOICE" != "3" ] && PROTO="https"
BASE_URL="$PROTO://$MAIN_DOMAIN"
AP_URL="$BASE_URL:8081"; [ "$ACCESS_CHOICE" == "1" ] && AP_URL="$PROTO://ap.$MAIN_DOMAIN"
N8N_WEBHOOK_URL="$BASE_URL:5678/"; [ "$ACCESS_CHOICE" == "1" ] && N8N_WEBHOOK_URL="$PROTO://n8n.$MAIN_DOMAIN/"

cat <<EOF > $DEPLOY_ROOT/db/.env
POSTGRES_USER=admin
POSTGRES_PASSWORD=$DB_ROOT_PASS
MARIADB_ROOT_PASSWORD=$DB_ROOT_PASS
DB_MEMORY_LIMIT=$DB_LIMIT
ADMINER_PORT=8080
EOF

cat <<EOF > $DEPLOY_ROOT/automation/.env
AUTOMATION_MEMORY_LIMIT=$AUTO_LIMIT
N8N_DB=n8n
N8N_DB_USER=n8n_user
N8N_DB_PASS=$N8N_DB_PASS
N8N_PORT_EXTERNAL=5678
N8N_WEBHOOK_URL=$N8N_WEBHOOK_URL
AP_DB=activepieces
AP_DB_USER=ap_user
AP_DB_PASS=$AP_DB_PASS
AP_PORT_EXTERNAL=8081
AP_URL=$AP_URL
HUGINN_DB=huginn
HUGINN_DB_USER=huginn_user
HUGINN_DB_PASS=$HUGINN_DB_PASS
HUGINN_PORT_EXTERNAL=3000
EOF

cat <<EOF > $DEPLOY_ROOT/webserver/.env
PHP_MEMORY_LIMIT=$PHP_LIMIT
MARIADB_ROOT_PASSWORD=$DB_ROOT_PASS
POSTGRES_PASSWORD=$DB_ROOT_PASS
WEB_DB_USER=web_app_user
WEB_DB_PASS=$WEB_DB_PASS
WEB_DB_NAME=web_app_db
EOF

sed -i "s/command: redis-server.*/command: $REDIS_CMD/g" $DEPLOY_ROOT/automation/docker-compose.yml || true
TEMPLATE="nginx_ports.conf"; [ "$ACCESS_CHOICE" == "1" ] && TEMPLATE="nginx_subdomains.conf"
[ "$SSL_CHOICE" == "3" ] && TEMPLATE="nginx_http_only.conf"
cp $DEPLOY_ROOT/templates/$TEMPLATE $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__WEB_DOMAIN__/$MAIN_DOMAIN/g; s/__DOMAIN_OR_IP__/$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__ADMINER_DOMAIN__/db.$MAIN_DOMAIN/g; s/__N8N_DOMAIN__/n8n.$MAIN_DOMAIN/g; s/__AP_DOMAIN__/ap.$MAIN_DOMAIN/g; s/__HUGINN_DOMAIN__/huginn.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf

# Phase 5: SSL
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Step 5] Configuring SSL...${NC}"
cd $DEPLOY_ROOT/proxy && sudo docker compose stop || true
if [ "$SSL_CHOICE" == "1" ]; then
    sudo $DEPLOY_ROOT/scripts/ssl_setup.sh letsencrypt "$MAIN_DOMAIN" "$ADMIN_EMAIL" "$ACCESS_CHOICE"
elif [ "$SSL_CHOICE" == "2" ]; then
    sudo $DEPLOY_ROOT/scripts/ssl_setup.sh selfsigned "$MAIN_DOMAIN"
fi
cp $DEPLOY_ROOT/templates/index.php $DEPLOY_ROOT/data/web_root/index.php

# Phase 6: Service Start & DB Setup
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Step 6] Initializing containerized services...${NC}"
sudo docker network create deploy-network || true
cd $DEPLOY_ROOT/db && sudo docker compose up -d

echo -e "Waiting for databases (up to 2 mins)..."
for i in {1..24}; do
    if sudo docker exec mariadb-db mariadb-admin ping -p"$DB_ROOT_PASS" --silent && \
       sudo docker exec -e PGPASSWORD="$DB_ROOT_PASS" postgres-db pg_isready -U admin --silent; then
        echo -e "${GREEN}Databases verified.${NC}"; break
    fi
    sleep 5
done

# DB Inits
sudo docker exec -i mariadb-db mariadb -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS web_app_db; CREATE USER IF NOT EXISTS 'web_app_user'@'%' IDENTIFIED BY '$WEB_DB_PASS'; GRANT ALL PRIVILEGES ON web_app_db.* TO 'web_app_user'@'%'; FLUSH PRIVILEGES;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE DATABASE n8n;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE USER n8n_user WITH PASSWORD '$N8N_DB_PASS';" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE DATABASE activepieces;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE USER ap_user WITH PASSWORD '$AP_DB_PASS';" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE activepieces TO ap_user;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE DATABASE huginn;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE USER huginn_user WITH PASSWORD '$HUGINN_DB_PASS';" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE huginn TO huginn_user;" || true

cd $DEPLOY_ROOT/webserver && sudo docker compose up -d --build
cd $DEPLOY_ROOT/automation && sudo docker compose up -d
cd $DEPLOY_ROOT/storage && sudo docker compose up -d
cd $DEPLOY_ROOT/proxy && sudo docker compose up -d

# Final: Firewall & Credentials
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[Final] Updating Firewall...${NC}"
sudo iptables -I INPUT -p tcp --dport 2222 -j ACCEPT || true
sudo ufw allow 22/tcp; sudo ufw allow 80/tcp; sudo ufw allow 443/tcp; sudo ufw allow 2222/tcp
if [ "$ACCESS_CHOICE" == "2" ]; then
    sudo ufw allow 8080/tcp; sudo ufw allow 5678/tcp; sudo ufw allow 8081/tcp; sudo ufw allow 3000/tcp
    sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT || true
    sudo iptables -I INPUT -p tcp --dport 5678 -j ACCEPT || true
    sudo iptables -I INPUT -p tcp --dport 8081 -j ACCEPT || true
    sudo iptables -I INPUT -p tcp --dport 3000 -j ACCEPT || true
fi
echo "y" | sudo ufw enable

cat <<EOF | sudo tee $DEPLOY_ROOT/credentials.txt > /dev/null
================================================================
OCI DEPLOYMENT CREDENTIALS
================================================================
Postgres/MariaDB Root: admin / $DB_ROOT_PASS
Web App DB: web_app_user / $WEB_DB_PASS (DB: web_app_db)
SFTP (Port 2222):
  Web Root: webuser / $SFTP_WEB_PASS
  Storage:  filesuser / $SFTP_FILES_PASS
================================================================
EOF
sudo chmod 600 $DEPLOY_ROOT/credentials.txt
(sudo crontab -l 2>/dev/null; echo "0 2 * * 0 $DEPLOY_ROOT/scripts/backup.sh >> $DEPLOY_ROOT/backups/backup.log 2>&1") | sudo crontab - || true

echo -e "\n${GREEN}Setup Successful! Credentials saved to ${NC}$DEPLOY_ROOT/credentials.txt"
sudo cat $DEPLOY_ROOT/credentials.txt
