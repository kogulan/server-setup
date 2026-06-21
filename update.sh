#!/bin/bash

# =============================================================================
# OCI One-Click Update & Upgrade Script
# This script updates the OS, performs a backup, and updates all containers.
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DEPLOY_ROOT="/opt/deploy"

echo -e "${GREEN}Starting Full System Update & Upgrade...${NC}"

# 1. Perform Backup
if [ -f "$DEPLOY_ROOT/scripts/backup.sh" ]; then
    echo -e "${YELLOW}[1/4] Performing safety backup...${NC}"
    sudo bash "$DEPLOY_ROOT/scripts/backup.sh"
else
    echo -e "${RED}Warning: Backup script not found at $DEPLOY_ROOT/scripts/backup.sh. Skipping backup...${NC}"
fi

# 2. Update OS Packages
echo -e "${YELLOW}[2/4] Updating OS packages...${NC}"
sudo apt update
sudo apt upgrade -y

# 3. Update Docker Containers
echo -e "${YELLOW}[3/4] Updating Docker containers...${NC}"
SERVICES=("db" "automation" "webserver" "storage" "proxy")

for service in "${SERVICES[@]}"; do
    if [ -d "$DEPLOY_ROOT/$service" ]; then
        echo -e "Updating $service..."
        cd "$DEPLOY_ROOT/$service"

        # Fix for Postgres 18+ data directory structure
        if [ "$service" == "db" ] && [ -d "$DEPLOY_ROOT/data/postgres/data" ]; then
            echo -e "${YELLOW}Converting legacy Postgres data structure to flat format...${NC}"
            sudo docker compose stop postgres 2>/dev/null || true

            # Check current version if exists to warn about major upgrade
            if [ -f "$DEPLOY_ROOT/data/postgres/data/PG_VERSION" ]; then
                OLD_VER=$(<"$DEPLOY_ROOT/data/postgres/data/PG_VERSION")
                if [ "$OLD_VER" != "18" ]; then
                    echo -e "${YELLOW}WARNING: Existing Postgres data version is $OLD_VER. Upgrading to 18 requires a dump/restore or pg_upgrade.${NC}"
                    echo -e "${YELLOW}This script will move your files to the new structure, but Postgres 18 may fail to start.${NC}"
                fi
            fi

            # Move all files (including hidden ones) to the parent directory
            if sudo bash -c "shopt -s dotglob; mv \"$DEPLOY_ROOT/data/postgres/data\"/* \"$DEPLOY_ROOT/data/postgres/\" 2>/dev/null"; then
                sudo rm -rf "$DEPLOY_ROOT/data/postgres/data"
                sudo chown -R 999:999 "$DEPLOY_ROOT/data/postgres"
                echo -e "${GREEN}Postgres data structure conversion complete.${NC}"
            else
                if [ -n "$(sudo ls -A "$DEPLOY_ROOT/data/postgres/data" 2>/dev/null)" ]; then
                    echo -e "${RED}Failed to move Postgres data files. Manual intervention may be required.${NC}"
                else
                    sudo rm -rf "$DEPLOY_ROOT/data/postgres/data"
                fi
            fi
        fi

        sudo docker compose pull
        sudo docker compose up -d
    fi
done

# 4. Clean up
echo -e "${YELLOW}[4/4] Cleaning up old Docker images...${NC}"
sudo docker image prune -f

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}Update Completed Successfully!${NC}"
echo -e "${GREEN}================================================================${NC}"

if [ -f /var/run/reboot-required ]; then
    echo -e "${RED}NOTE: A system reboot is required to complete some OS updates.${NC}"
    echo -e "You can reboot by typing: ${YELLOW}sudo reboot${NC}"
else
    echo -e "No system reboot is required."
fi
