#!/bin/bash

# =============================================================================
# OCI Deployment Credentials Retrieval Script
# This script extracts credentials from service .env files.
# =============================================================================

set -euo pipefail

DEPLOY_ROOT="/opt/deploy"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

get_secret() {
    local key="$1"
    local file="$2"
    if [ -f "$file" ]; then
        grep "^${key}=" "$file" | head -n 1 | cut -d'=' -f2- | tr -d '\r' || echo ""
    else
        echo ""
    fi
}

DB_ROOT_PASS=$(get_secret "MARIADB_ROOT_PASSWORD" "$DEPLOY_ROOT/db/.env")
WEB_DB_PASS=$(get_secret "WEB_DB_PASS" "$DEPLOY_ROOT/webserver/.env")
SFTP_WEB_PASS=$(get_secret "SFTP_WEB_PASS" "$DEPLOY_ROOT/.env")
SFTP_FILES_PASS=$(get_secret "SFTP_FILES_PASS" "$DEPLOY_ROOT/.env")
HUGINN_INVITATION_CODE=$(get_secret "HUGINN_INVITATION_CODE" "$DEPLOY_ROOT/automation/.env")

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}OCI DEPLOYMENT CREDENTIALS${NC}"
echo -e "${GREEN}================================================================${NC}"
echo "PostgreSQL Admin: admin / ${DB_ROOT_PASS:-N/A}"
echo "MariaDB Root: root / ${DB_ROOT_PASS:-N/A}"
echo "Web App DB: web_app_user / ${WEB_DB_PASS:-N/A} (DB: web_app_db)"
echo "SFTP (FileZilla protocol: SFTP, not FTP; Port 2222):"
echo "  Web Root: webuser / ${SFTP_WEB_PASS:-N/A}"
echo "  Storage:  filesuser / ${SFTP_FILES_PASS:-N/A}"
echo "Huginn invitation code: ${HUGINN_INVITATION_CODE:-N/A}"
echo -e "${GREEN}================================================================${NC}"
