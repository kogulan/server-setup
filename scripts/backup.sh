#!/bin/bash

# Configuration
BACKUP_DIR="/opt/deploy/backups"
DATA_DIR="/opt/deploy/data"
DATE=$(date +%Y-%m-%d_%H%M%S)
RETENTION_DAYS=7

echo "Starting backup at $(date)"
mkdir -p "$BACKUP_DIR"

# Get root password from env
DB_ROOT_PASS=$(grep MARIADB_ROOT_PASSWORD /opt/deploy/db/.env | cut -d'=' -f2)

echo "Backing up PostgreSQL..."
docker exec -e PGPASSWORD="$DB_ROOT_PASS" postgres-db pg_dumpall -U admin > "$BACKUP_DIR/postgres_full_$DATE.sql"

echo "Backing up MariaDB..."
docker exec mariadb-db mariadb-dump -u root -p"$DB_ROOT_PASS" --all-databases > "$BACKUP_DIR/mariadb_full_$DATE.sql"

echo "Backing up files..."
tar -czf "$BACKUP_DIR/files_$DATE.tar.gz" -C "$DATA_DIR" . --exclude="postgres" --exclude="mariadb"

gzip "$BACKUP_DIR/postgres_full_$DATE.sql"
gzip "$BACKUP_DIR/mariadb_full_$DATE.sql"

echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully at $(date)"
