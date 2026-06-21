#!/bin/bash

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/opt/deploy/backups}"
DATA_DIR="${DATA_DIR:-/opt/deploy/data}"
DATE=$(date +%Y-%m-%d_%H%M%S)
RETENTION_DAYS="${RETENTION_DAYS:-7}"

main() {
    echo "Starting backup at $(date)"
    mkdir -p "$BACKUP_DIR"

    echo "Backing up PostgreSQL..."
    docker exec postgres-db sh -c 'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_dumpall -U admin' | gzip > "$BACKUP_DIR/postgres_full_$DATE.sql.gz"

    echo "Backing up MariaDB..."
    docker exec mariadb-db sh -c 'export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"; mariadb-dump -u root --all-databases' | gzip > "$BACKUP_DIR/mariadb_full_$DATE.sql.gz"

    echo "Backing up files..."
    tar -czf "$BACKUP_DIR/files_$DATE.tar.gz" -C "$DATA_DIR" . --exclude="postgres" --exclude="mariadb"

    echo "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

    echo "Backup completed successfully at $(date)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
