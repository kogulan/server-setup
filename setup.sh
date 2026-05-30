#!/bin/bash

# =============================================================================
# OCI Production-Ready Deployment Orchestrator
# Target: Ubuntu 24.04 Minimal (x86_64 / ARM64)
# Optimized for VM.Standard.E2.1.Micro (1GB) and VM.Standard.A1.Flex (24GB)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting OCI Deployment Setup...${NC}"

DEPLOY_ROOT="/opt/deploy"
sudo mkdir -p $DEPLOY_ROOT/{proxy/conf.d,proxy/certs,db,webserver,automation,storage/pureftpd-data,data/web_root,data/ftp_storage,data/postgres,data/mariadb,data/n8n,data/activepieces,data/huginn,data/redis,data/nginx,backups,scripts,templates}
sudo chmod +x $DEPLOY_ROOT/scripts/*.sh $DEPLOY_ROOT/setup.sh
sudo touch $DEPLOY_ROOT/storage/passwd

# 1. System Requirements & RAM Detection
# -----------------------------------------------------------------------------
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
echo "Detected Total RAM: ${TOTAL_RAM}MB"

if [ "$TOTAL_RAM" -lt 2000 ]; then
    echo -e "${YELLOW}Low RAM detected (<2GB). Configuring 4GB Swap space and memory limits...${NC}"
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
else
    echo -e "${GREEN}Sufficient RAM detected. Skipping Swap and applying relaxed limits.${NC}"
    DB_LIMIT="2G"
    AUTO_LIMIT="2G"
    PHP_LIMIT="1G"
fi

# 2. Dependency Installation
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Installing dependencies (Docker, Certbot, UFW)...${NC}"
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release ufw certbot openssl

if ! command -v docker &> /dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# 3. User Input & Configuration
# -----------------------------------------------------------------------------
echo -e "${GREEN}Configuration Section${NC}"

read -p "Enter your main Domain or IP (e.g., example.com or 1.2.3.4): " MAIN_DOMAIN
read -p "Enter Admin email (for SSL): " ADMIN_EMAIL

echo -e "\nAccess Method:"
echo "1) Subdomains (e.g., n8n.example.com) - Requires custom domain"
echo "2) Ports (e.g., example.com:5678) - Works with IP or No-IP"
read -p "Choose an option [1-2]: " ACCESS_CHOICE

echo -e "\nSSL Choice:"
echo "1) Let's Encrypt (Requires domain pointed to this IP)"
echo "2) Self-Signed (Works for IP access)"
echo "3) None (HTTP only)"
read -p "Choose an option [1-3]: " SSL_CHOICE

# 4. Generate Credentials
# -----------------------------------------------------------------------------
DB_PASS=$(openssl rand -hex 12)
N8N_DB_PASS=$(openssl rand -hex 12)
AP_DB_PASS=$(openssl rand -hex 12)
HUGINN_DB_PASS=$(openssl rand -hex 12)
FTP_WEB_PASS=$(openssl rand -hex 12)
FTP_FILES_PASS=$(openssl rand -hex 12)

# 5. Linux Users for FTP
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Creating Linux users for FTP isolation...${NC}"
sudo useradd -m -s /usr/sbin/nologin webuser || true
sudo useradd -m -s /usr/sbin/nologin filesuser || true

WEB_UID=$(id -u webuser)
FILES_UID=$(id -u filesuser)

sudo chown -R webuser:webuser $DEPLOY_ROOT/data/web_root
sudo chown -R filesuser:filesuser $DEPLOY_ROOT/data/ftp_storage

# 6. Writing Environment Files
# -----------------------------------------------------------------------------
PROTO="http"
[ "$SSL_CHOICE" != "3" ] && PROTO="https"

AP_URL="$PROTO://$MAIN_DOMAIN:8081"
[ "$ACCESS_CHOICE" == "1" ] && AP_URL="$PROTO://ap.$MAIN_DOMAIN"

cat <<EOF > $DEPLOY_ROOT/db/.env
POSTGRES_USER=admin
POSTGRES_PASSWORD=$DB_PASS
MARIADB_ROOT_PASSWORD=$DB_PASS
DB_MEMORY_LIMIT=$DB_LIMIT
ADMINER_PORT=8080
EOF

cat <<EOF > $DEPLOY_ROOT/automation/.env
AUTOMATION_MEMORY_LIMIT=$AUTO_LIMIT
N8N_DB=n8n
N8N_DB_USER=n8n_user
N8N_DB_PASS=$N8N_DB_PASS
N8N_PORT_EXTERNAL=5678
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

cat <<EOF > $DEPLOY_ROOT/storage/.env
FTP_PUBLIC_HOST=$MAIN_DOMAIN
EOF

cat <<EOF > $DEPLOY_ROOT/webserver/.env
PHP_MEMORY_LIMIT=$PHP_LIMIT
MARIADB_ROOT_PASSWORD=$DB_PASS
POSTGRES_PASSWORD=$DB_PASS
EOF

# 7. Nginx & SSL Configuration
# -----------------------------------------------------------------------------
if [ "$SSL_CHOICE" == "3" ]; then
    cp $DEPLOY_ROOT/templates/nginx_http_only.conf $DEPLOY_ROOT/proxy/conf.d/default.conf
    sed -i "s/__DOMAIN_OR_IP__/$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
else
    if [ "$ACCESS_CHOICE" == "1" ]; then
        cp $DEPLOY_ROOT/templates/nginx_subdomains.conf $DEPLOY_ROOT/proxy/conf.d/default.conf
        sed -i "s/__WEB_DOMAIN__/$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
        sed -i "s/__ADMINER_DOMAIN__/db.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
        sed -i "s/__N8N_DOMAIN__/n8n.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
        sed -i "s/__AP_DOMAIN__/ap.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
        sed -i "s/__HUGINN_DOMAIN__/huginn.$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
    else
        cp $DEPLOY_ROOT/templates/nginx_ports.conf $DEPLOY_ROOT/proxy/conf.d/default.conf
        sed -i "s/__DOMAIN_OR_IP__/$MAIN_DOMAIN/g" $DEPLOY_ROOT/proxy/conf.d/default.conf
    fi

    if [ "$SSL_CHOICE" == "1" ]; then
        $DEPLOY_ROOT/scripts/ssl_setup.sh letsencrypt "$MAIN_DOMAIN" "$ADMIN_EMAIL" "$ACCESS_CHOICE"
    elif [ "$SSL_CHOICE" == "2" ]; then
        $DEPLOY_ROOT/scripts/ssl_setup.sh selfsigned "$MAIN_DOMAIN"
    fi
fi

cp $DEPLOY_ROOT/templates/index.php $DEPLOY_ROOT/data/web_root/index.php

# 8. Start Services
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Starting database services...${NC}"
sudo docker network create deploy-network || true
cd $DEPLOY_ROOT/db && sudo docker compose up -d

echo "Waiting for PostgreSQL to be ready..."
sleep 10

# Initialize databases and users in PostgreSQL
echo -e "${YELLOW}Initializing application databases in PostgreSQL...${NC}"
sudo docker exec -i postgres-db psql -U admin -c "CREATE DATABASE n8n;" || true
sudo docker exec -i postgres-db psql -U admin -c "CREATE USER n8n_user WITH PASSWORD '$N8N_DB_PASS';" || true
sudo docker exec -i postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;" || true

sudo docker exec -i postgres-db psql -U admin -c "CREATE DATABASE activepieces;" || true
sudo docker exec -i postgres-db psql -U admin -c "CREATE USER ap_user WITH PASSWORD '$AP_DB_PASS';" || true
sudo docker exec -i postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE activepieces TO ap_user;" || true

sudo docker exec -i postgres-db psql -U admin -c "CREATE DATABASE huginn;" || true
sudo docker exec -i postgres-db psql -U admin -c "CREATE USER huginn_user WITH PASSWORD '$HUGINN_DB_PASS';" || true
sudo docker exec -i postgres-db psql -U admin -c "GRANT ALL PRIVILEGES ON DATABASE huginn TO huginn_user;" || true

echo -e "${YELLOW}Starting remaining services...${NC}"
cd $DEPLOY_ROOT/webserver && sudo docker compose build && sudo docker compose up -d
cd $DEPLOY_ROOT/automation && sudo docker compose up -d
cd $DEPLOY_ROOT/storage && sudo docker compose up -d

sleep 5
sudo docker exec pure-ftpd /bin/bash -c "(echo $FTP_WEB_PASS; echo $FTP_WEB_PASS) | pure-pw useradd webuser -u $WEB_UID -g $WEB_UID -d /home/webuser"
sudo docker exec pure-ftpd /bin/bash -c "(echo $FTP_FILES_PASS; echo $FTP_FILES_PASS) | pure-pw useradd filesuser -u $FILES_UID -g $FILES_UID -d /home/filesuser"
sudo docker exec pure-ftpd pure-pw mkdb

cd $DEPLOY_ROOT/proxy && sudo docker compose up -d

# 9. Firewall Configuration
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Configuring UFW firewall...${NC}"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 21/tcp
sudo ufw allow 30000:30009/tcp
if [ "$ACCESS_CHOICE" == "2" ]; then
    sudo ufw allow 8080/tcp
    sudo ufw allow 5678/tcp
    sudo ufw allow 8081/tcp
    sudo ufw allow 3000/tcp
fi
echo "y" | sudo ufw enable

# 10. Cron for Backups
# -----------------------------------------------------------------------------
(sudo crontab -l 2>/dev/null; echo "0 2 * * 0 $DEPLOY_ROOT/scripts/backup.sh >> $DEPLOY_ROOT/backups/backup.log 2>&1") | sudo crontab -

# 11. Final Summary
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "================================================================"
echo -e "Web Root FTP: User: webuser / Pass: $FTP_WEB_PASS"
echo -e "Storage FTP:  User: filesuser / Pass: $FTP_FILES_PASS"
echo -e "================================================================"
