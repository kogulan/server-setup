#!/bin/bash

# Configuration
BACKUP_DIR="/opt/deploy/backups"
DATA_DIR="/opt/deploy/data"
DATE=$(date +%Y-%m-%d_%H%M%S)
RETENTION_DAYS=7

echo "Starting backup at $(date)"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# 1. Backup Databases using docker exec
echo "Backing up PostgreSQL..."
docker exec postgres-db pg_dumpall -U admin > "$BACKUP_DIR/postgres_full_$DATE.sql"

echo "Backing up MariaDB..."
# We use the root password from the environment file if possible, or assume it's set
MARIADB_ROOT_PASSWORD=$(grep MARIADB_ROOT_PASSWORD /opt/deploy/db/.env | cut -d'=' -f2)
docker exec mariadb-db mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --all-databases > "$BACKUP_DIR/mariadb_full_$DATE.sql"

# 2. Backup File Volumes
echo "Backing up files..."
tar -czf "$BACKUP_DIR/files_$DATE.tar.gz" -C "$DATA_DIR" . --exclude="postgres" --exclude="mariadb"

# 3. Compress SQL backups
gzip "$BACKUP_DIR/postgres_full_$DATE.sql"
gzip "$BACKUP_DIR/mariadb_full_$DATE.sql"

# 4. Clean up old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully at $(date)"
