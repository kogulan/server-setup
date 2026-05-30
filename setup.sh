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

echo -e "${GREEN}Starting OCI Deployment Setup...${NC}"

DEPLOY_ROOT="/opt/deploy"
sudo mkdir -p $DEPLOY_ROOT/{proxy/conf.d,proxy/certs,db,webserver,automation,storage,data/web_root,data/ftp_storage,data/postgres,data/mariadb,data/n8n,data/activepieces,data/huginn,data/redis,data/nginx,backups,scripts,templates}
sudo chmod +x $DEPLOY_ROOT/scripts/*.sh || true

# 1. RAM Detection & Optimization
# -----------------------------------------------------------------------------
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
echo "Detected Total RAM: ${TOTAL_RAM}MB"

if [ "$TOTAL_RAM" -lt 2000 ]; then
    echo -e "${YELLOW}Low RAM detected (<2GB). Configuring 4GB Swap and Tiny Redis...${NC}"
    if [ ! -f /swapfile ]; then
        sudo fallocate -l 4G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    DB_LIMIT="512M"
    AUTO_LIMIT="512M"
    PHP_LIMIT="256M"
    REDIS_CMD="redis-server --maxmemory 64mb --maxmemory-policy allkeys-lru"
else
    echo -e "${GREEN}High RAM detected. Configuring standard performance...${NC}"
    DB_LIMIT="2G"
    AUTO_LIMIT="2G"
    PHP_LIMIT="1G"
    REDIS_CMD="redis-server"
fi

sed -i "s/command: redis-server.*/command: $REDIS_CMD/g" $DEPLOY_ROOT/automation/docker-compose.yml

# 2. Dependencies
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Installing system dependencies (Docker, Certbot, UFW, Cron)...${NC}"
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release ufw certbot openssl cron

if ! command -v docker &> /dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# 3. User Input
# -----------------------------------------------------------------------------
echo -e "${GREEN}Interactive Configuration${NC}"
read -p "Enter your main Domain or IP: " MAIN_DOMAIN
read -p "Enter Admin email: " ADMIN_EMAIL
echo "1) Subdomains (e.g., n8n.example.com)"
echo "2) Ports (e.g., example.com:5678)"
read -p "Access Choice [1-2]: " ACCESS_CHOICE
echo "1) Let's Encrypt | 2) Self-Signed | 3) HTTP Only"
read -p "SSL Choice [1-3]: " SSL_CHOICE

# 4. Secrets
# -----------------------------------------------------------------------------
DB_ROOT_PASS=$(openssl rand -hex 12)
WEB_DB_PASS=$(openssl rand -hex 12)
N8N_DB_PASS=$(openssl rand -hex 12)
AP_DB_PASS=$(openssl rand -hex 12)
HUGINN_DB_PASS=$(openssl rand -hex 12)
SFTP_WEB_PASS=$(openssl rand -hex 12)
SFTP_FILES_PASS=$(openssl rand -hex 12)

# 5. Linux Users & SFTP Config
# -----------------------------------------------------------------------------
sudo useradd -m -s /usr/sbin/nologin webuser || true
sudo useradd -m -s /usr/sbin/nologin filesuser || true
WEB_UID=$(id -u webuser)
FILES_UID=$(id -u filesuser)

echo "webuser:$SFTP_WEB_PASS:$WEB_UID:$WEB_UID:web_root" | sudo tee $DEPLOY_ROOT/storage/users.conf
echo "filesuser:$SFTP_FILES_PASS:$FILES_UID:$FILES_UID:my_ftp_files" | sudo tee -a $DEPLOY_ROOT/storage/users.conf

sudo chown -R webuser:webuser $DEPLOY_ROOT/data/web_root
sudo chown -R filesuser:filesuser $DEPLOY_ROOT/data/ftp_storage
sudo mkdir -p $DEPLOY_ROOT/data/n8n && sudo chown -R 1000:1000 $DEPLOY_ROOT/data/n8n
sudo mkdir -p $DEPLOY_ROOT/data/activepieces && sudo chmod -R 777 $DEPLOY_ROOT/data/activepieces

# 6. Environment Files
# -----------------------------------------------------------------------------
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

# 7. Nginx & SSL
# -----------------------------------------------------------------------------
TEMPLATE="nginx_ports.conf"; [ "$ACCESS_CHOICE" == "1" ] && TEMPLATE="nginx_subdomains.conf"
[ "$SSL_CHOICE" == "3" ] && TEMPLATE="nginx_http_only.conf"

cp $DEPLOY_ROOT/templates/$TEMPLATE $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__WEB_DOMAIN__/$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__DOMAIN_OR_IP__/$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__ADMINER_DOMAIN__/db.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__N8N_DOMAIN__/n8n.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__AP_DOMAIN__/ap.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
sed -i "s/__HUGINN_DOMAIN__/huginn.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf

if [ "$SSL_CHOICE" == "1" ]; then
    sudo $DEPLOY_ROOT/scripts/ssl_setup.sh letsencrypt "$MAIN_DOMAIN" "$ADMIN_EMAIL" "$ACCESS_CHOICE"
elif [ "$SSL_CHOICE" == "2" ]; then
    sudo $DEPLOY_ROOT/scripts/ssl_setup.sh selfsigned "$MAIN_DOMAIN"
fi

cp $DEPLOY_ROOT/templates/index.php $DEPLOY_ROOT/data/web_root/index.php

# 8. Start Services & Init DB
# -----------------------------------------------------------------------------
sudo docker network create deploy-network || true
cd $DEPLOY_ROOT/db && sudo docker compose up -d

echo -e "${YELLOW}Waiting for databases to be ready...${NC}"
# Improved health check for MariaDB
RETRIES=10
until sudo docker exec mariadb-db mariadb-admin ping -p"$DB_ROOT_PASS" --silent || [ $RETRIES -eq 0 ]; do
    echo "Waiting for MariaDB... ($RETRIES retries left)"
    sleep 5
    RETRIES=$((RETRIES-1))
done

# Improved health check for Postgres
RETRIES=10
until sudo docker exec postgres-db pg_isready -U admin || [ $RETRIES -eq 0 ]; do
    echo "Waiting for PostgreSQL... ($RETRIES retries left)"
    sleep 5
    RETRIES=$((RETRIES-1))
done

# MariaDB Init
sudo docker exec -i mariadb-db mariadb -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS web_app_db;"
sudo docker exec -i mariadb-db mariadb -u root -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS 'web_app_user'@'%' IDENTIFIED BY '$WEB_DB_PASS';"
sudo docker exec -i mariadb-db mariadb -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON web_app_db.* TO 'web_app_user'@'%';"
sudo docker exec -i mariadb-db mariadb -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# Postgres Init
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE DATABASE n8n;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE USER n8n_user WITH PASSWORD '$N8N_DB_PASS';" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE DATABASE activepieces;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE USER ap_user WITH PASSWORD '$AP_DB_PASS';" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE activepieces TO ap_user;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE DATABASE huginn;" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "CREATE USER huginn_user WITH PASSWORD '$HUGINN_DB_PASS';" || true
sudo docker exec -i -e PGPASSWORD="$DB_ROOT_PASS" postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE huginn TO huginn_user;" || true

echo -e "${YELLOW}Starting applications...${NC}"
cd $DEPLOY_ROOT/webserver && sudo docker compose build && sudo docker compose up -d
cd $DEPLOY_ROOT/automation && sudo docker compose up -d
cd $DEPLOY_ROOT/storage && sudo docker compose up -d
cd $DEPLOY_ROOT/proxy && sudo docker compose up -d

# 9. Firewall
# -----------------------------------------------------------------------------
sudo ufw default deny incoming; sudo ufw allow 22/tcp; sudo ufw allow 80/tcp; sudo ufw allow 443/tcp; sudo ufw allow 2222/tcp
[ "$ACCESS_CHOICE" == "2" ] && (sudo ufw allow 8080/tcp; sudo ufw allow 5678/tcp; sudo ufw allow 8081/tcp; sudo ufw allow 3000/tcp)
echo "y" | sudo ufw enable

# 10. Credentials File
# -----------------------------------------------------------------------------
cat <<EOF | sudo tee $DEPLOY_ROOT/credentials.txt > /dev/null
================================================================
OCI DEPLOYMENT CREDENTIALS
================================================================
Postgres/MariaDB Root: admin / $DB_ROOT_PASS
Web App DB (MariaDB): web_app_user / $WEB_DB_PASS (DB: web_app_db)
SFTP (Port 2222):
  Web Root: webuser / $SFTP_WEB_PASS
  Storage:  filesuser / $SFTP_FILES_PASS
================================================================
EOF
sudo chmod 600 $DEPLOY_ROOT/credentials.txt

# 11. Cron
# -----------------------------------------------------------------------------
(sudo crontab -l 2>/dev/null; echo "0 2 * * 0 $DEPLOY_ROOT/scripts/backup.sh >> $DEPLOY_ROOT/backups/backup.log 2>&1") | sudo crontab - || true

echo -e "\n${GREEN}Setup Complete! Credentials in $DEPLOY_ROOT/credentials.txt${NC}"
sudo cat $DEPLOY_ROOT/credentials.txt
