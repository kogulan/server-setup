#!/bin/bash

# Simple Bash Unit Test for backup.sh

export DEPLOY_ROOT="/tmp/deploy_backup_test"
export BACKUP_DIR="$DEPLOY_ROOT/backups"
export DATA_DIR="$DEPLOY_ROOT/data"
COMMAND_LOG="/tmp/backup_commands.log"
OUTPUT_LOG="/tmp/backup_output.log"

# Setup test environment
setup_test_env() {
    rm -rf "$DEPLOY_ROOT"
    mkdir -p "$BACKUP_DIR" "$DATA_DIR"
    rm -f "$COMMAND_LOG" "$OUTPUT_LOG"
    touch "$COMMAND_LOG" "$OUTPUT_LOG"

    # Create some dummy data
    mkdir -p "$DATA_DIR/web_root"
    echo "test" > "$DATA_DIR/web_root/index.php"
}

# Mock docker
docker() {
    echo "docker $*" >> "$COMMAND_LOG"
}
export -f docker

# Mock tar
tar() {
    echo "tar $*" >> "$COMMAND_LOG"
}
export -f tar

# Mock find
find() {
    echo "find $*" >> "$COMMAND_LOG"
    # Don't actually delete anything for now
}
export -f find

# Mock date to be deterministic
date() {
    if [[ "$*" == "+%Y-%m-%d_%H%M%S" ]]; then
        echo "2023-10-27_120000"
    else
        echo "2023-10-27 12:00:00"
    fi
}
export -f date

# Mock gzip to just cat
gzip() {
    cat
}
export -f gzip

# Source the script
source ./scripts/backup.sh

# Test Utilities
PASSED=0
FAILED=0

assert_grep() {
    local pattern="$1"
    local file="$2"
    local message="$3"

    if grep -q "$pattern" "$file"; then
        echo -e "  [PASS] $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "  [FAIL] $message"
        echo -e "    Pattern '$pattern' not found in $file"
        FAILED=$((FAILED + 1))
    fi
}

# --- Test Case 1: Standard Backup Flow ---
echo "Test Case 1: Standard Backup Flow"
setup_test_env

# Run the main function from the sourced script
main > "$OUTPUT_LOG" 2>&1

assert_grep "docker exec postgres-db" "$COMMAND_LOG" "PostgreSQL backup command called"
assert_grep "pg_dumpall -U admin" "$COMMAND_LOG" "pg_dumpall called"
assert_grep "docker exec mariadb-db" "$COMMAND_LOG" "MariaDB backup command called"
assert_grep "mariadb-dump -u root --all-databases" "$COMMAND_LOG" "mariadb-dump called"
assert_grep "tar -czf $BACKUP_DIR/files_2023-10-27_120000.tar.gz -C $DATA_DIR . --exclude=postgres --exclude=mariadb" "$COMMAND_LOG" "Tar command called with correct arguments"
assert_grep "find $BACKUP_DIR -type f -mtime +7 -delete" "$COMMAND_LOG" "Cleanup command called"

# Check if output files would have been created (since we mocked gzip to cat)
if [ -f "$BACKUP_DIR/postgres_full_2023-10-27_120000.sql.gz" ]; then
    echo -e "  [PASS] Postgres backup file created"
    PASSED=$((PASSED + 1))
else
    echo -e "  [FAIL] Postgres backup file NOT created"
    FAILED=$((FAILED + 1))
fi

# --- Test Case 2: Custom Retention ---
echo -e "\nTest Case 2: Custom Retention"
setup_test_env
export RETENTION_DAYS=30

main > "$OUTPUT_LOG" 2>&1

assert_grep "find $BACKUP_DIR -type f -mtime +30 -delete" "$COMMAND_LOG" "Cleanup command called with custom retention"

# Cleanup
rm -rf "$DEPLOY_ROOT" "$COMMAND_LOG" "$OUTPUT_LOG"

echo -e "\nTest Summary: $PASSED passed, $FAILED failed."

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
