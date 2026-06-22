#!/bin/bash

# Shared utility functions for OCI Deployment scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

migrate_postgres() {
    local deploy_root="$1"
    local postgres_data_dir="$deploy_root/data/postgres"

    if sudo test -d "$postgres_data_dir/data"; then
        # Ensure container is stopped before moving files
        # Try both with and without explicit file path to be compatible with setup and update scripts
        if [ -f "$deploy_root/db/docker-compose.yml" ]; then
            sudo docker compose -f "$deploy_root/db/docker-compose.yml" stop postgres 2>/dev/null || true
        else
            sudo docker compose stop postgres 2>/dev/null || true
        fi

        echo -e "${YELLOW}Converting legacy Postgres data structure to flat format...${NC}"

        # Check current version if exists to warn about major upgrade
        if sudo test -f "$postgres_data_dir/data/PG_VERSION"; then
            local old_ver
            old_ver=$(sudo cat "$postgres_data_dir/data/PG_VERSION")
            if [ "$old_ver" != "18" ]; then
                echo -e "${YELLOW}WARNING: Existing Postgres data version is $old_ver. Upgrading to 18 requires a dump/restore or pg_upgrade.${NC}"
                echo -e "${YELLOW}This script will move your files to the new structure, but Postgres 18 may fail to start.${NC}"
            fi
        fi

        # Move all files (including hidden ones) to the parent directory
        if sudo bash -c "shopt -s dotglob; mv \"$postgres_data_dir/data\"/* \"$postgres_data_dir/\" 2>/dev/null"; then
            sudo rm -rf "$postgres_data_dir/data"
            sudo chown -R 999:999 "$postgres_data_dir"
            echo -e "${GREEN}Postgres data structure conversion complete.${NC}"
        else
            # If mv failed, it might be because the directory was already empty or move failed.
            if [ -n "$(sudo ls -A "$postgres_data_dir/data" 2>/dev/null)" ]; then
                echo -e "${RED}Failed to move Postgres data files. Manual intervention may be required.${NC}"
            else
                sudo rm -rf "$postgres_data_dir/data"
            fi
        fi
    fi
}
