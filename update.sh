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

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/deploy}"

main() {
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

    source "$DEPLOY_ROOT/scripts/utils.sh"

    for service in "${SERVICES[@]}"; do
        if [ -d "$DEPLOY_ROOT/$service" ]; then
            echo -e "Updating $service..."
            cd "$DEPLOY_ROOT/$service"

            # Fix for Postgres 18+ data directory structure
            if [ "$service" == "db" ]; then
                migrate_postgres "$DEPLOY_ROOT"
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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
