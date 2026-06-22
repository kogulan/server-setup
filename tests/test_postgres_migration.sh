#!/bin/bash

# Test for Postgres 18+ Migration Logic specifically

export DEPLOY_ROOT="/tmp/deploy_migration_test"
OUTPUT_LOG="/tmp/migration_output.log"

# Colors
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Setup test environment
setup_test_env() {
    rm -rf "$DEPLOY_ROOT"
    mkdir -p "$DEPLOY_ROOT/db"
    mkdir -p "$DEPLOY_ROOT/data/postgres/data"
    rm -f "$OUTPUT_LOG"
    touch "$OUTPUT_LOG"
}

# Mock sudo
sudo() {
    case "$1" in
        bash)
            if [[ "$2" == "-c" ]]; then
                # Run the command
                /bin/bash -c "$3"
                return $?
            fi
            ;;
        test)
            test "${@:2}"
            return $?
            ;;
        cat)
            cat "${@:2}"
            return $?
            ;;
        rm)
            rm "${@:2}"
            return $?
            ;;
        docker|chown|ls)
            # Return 0 for docker/chown, actually run ls
            if [[ "$1" == "ls" ]]; then
                ls "${@:2}"
                return $?
            fi
            return 0
            ;;
    esac
    "$@"
}
export -f sudo

# The migration logic function (extracted from update.sh/setup.sh for isolation)
migrate_postgres() {
    local DEPLOY_ROOT="$1"
    if sudo test -d "$DEPLOY_ROOT/data/postgres/data"; then
        # Ensure container is stopped before moving files
        sudo docker compose -f "$DEPLOY_ROOT/db/docker-compose.yml" stop postgres 2>/dev/null || true
        echo -e "${YELLOW}Converting legacy Postgres data structure to flat format...${NC}"
        # Check current version if exists to warn about major upgrade
        if sudo test -f "$DEPLOY_ROOT/data/postgres/data/PG_VERSION"; then
            OLD_VER=$(sudo cat "$DEPLOY_ROOT/data/postgres/data/PG_VERSION")
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
            # If mv failed, it might be because the directory was already empty or move failed.
            # Check if directory still has files
            if [ -n "$(sudo ls -A "$DEPLOY_ROOT/data/postgres/data" 2>/dev/null)" ]; then
                echo -e "${RED}Failed to move Postgres data files. Manual intervention may be required.${NC}"
            else
                sudo rm -rf "$DEPLOY_ROOT/data/postgres/data"
            fi
        fi
    fi
}

# Test Utilities
PASSED=0
FAILED=0

assert_exists() {
    if [ -f "$1" ] || [ -d "$1" ]; then
        echo -e "  [PASS] $2"
        PASSED=$((PASSED + 1))
    else
        echo -e "  [FAIL] $2 (Not found: $1)"
        FAILED=$((FAILED + 1))
    fi
}

assert_not_exists() {
    if [ ! -e "$1" ]; then
        echo -e "  [PASS] $1 removed as expected"
        PASSED=$((PASSED + 1))
    else
        echo -e "  [FAIL] $1 still exists but should have been removed"
        ls -la "$(dirname "$1")" >&2
        FAILED=$((FAILED + 1))
    fi
}

assert_grep() {
    # Strip colors for grep
    if sed 's/\x1b\[[0-9;]*m//g' "$2" | grep -q "$1"; then
        echo -e "  [PASS] Log contains: $1"
        PASSED=$((PASSED + 1))
    else
        echo -e "  [FAIL] Log missing: $1"
        echo "Actual log content:" >&2
        cat "$2" >&2
        FAILED=$((FAILED + 1))
    fi
}

# --- Test Case 1: Full migration with hidden files and old version warning ---
echo "Test Case 1: Full migration with hidden files and old version warning"
setup_test_env
echo "15" > "$DEPLOY_ROOT/data/postgres/data/PG_VERSION"
touch "$DEPLOY_ROOT/data/postgres/data/.hidden_file"
touch "$DEPLOY_ROOT/data/postgres/data/normal_file"

migrate_postgres "$DEPLOY_ROOT" > "$OUTPUT_LOG" 2>&1

assert_grep "Converting legacy Postgres data structure" "$OUTPUT_LOG"
assert_grep "WARNING: Existing Postgres data version is 15" "$OUTPUT_LOG"
assert_exists "$DEPLOY_ROOT/data/postgres/PG_VERSION" "PG_VERSION moved"
assert_exists "$DEPLOY_ROOT/data/postgres/.hidden_file" "Hidden file moved"
assert_exists "$DEPLOY_ROOT/data/postgres/normal_file" "Normal file moved"
assert_not_exists "$DEPLOY_ROOT/data/postgres/data"

# --- Test Case 2: Already flat (data directory missing) ---
echo -e "\nTest Case 2: Already flat (data directory missing)"
setup_test_env
rm -rf "$DEPLOY_ROOT/data/postgres/data"
touch "$DEPLOY_ROOT/data/postgres/PG_VERSION"

migrate_postgres "$DEPLOY_ROOT" > "$OUTPUT_LOG" 2>&1

if [ ! -s "$OUTPUT_LOG" ]; then
    echo -e "  [PASS] No migration performed when data dir is missing"
    PASSED=$((PASSED + 1))
else
    echo -e "  [FAIL] Migration logic triggered unexpectedly"
    cat "$OUTPUT_LOG" >&2
    FAILED=$((FAILED + 1))
fi

# --- Test Case 3: Empty data directory ---
echo -e "\nTest Case 3: Empty data directory"
setup_test_env
# data/postgres/data exists but is empty

migrate_postgres "$DEPLOY_ROOT" > "$OUTPUT_LOG" 2>&1

assert_grep "Converting legacy Postgres data structure" "$OUTPUT_LOG"
assert_not_exists "$DEPLOY_ROOT/data/postgres/data"

# Cleanup
rm -rf "$DEPLOY_ROOT" "$OUTPUT_LOG"

echo -e "\nTest Summary: $PASSED passed, $FAILED failed."
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
