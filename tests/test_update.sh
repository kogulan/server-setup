#!/bin/bash

# Simple Bash Unit Test for update.sh

export DEPLOY_ROOT="/tmp/deploy_update_test"
COMMAND_LOG="/tmp/commands.log"
OUTPUT_LOG="/tmp/output.log"

# Global original script directory
ORIGINAL_SCRIPT_DIR=$(pwd)

# Setup test environment
setup_test_env() {
    mkdir -p "$DEPLOY_ROOT/scripts"
    cp "$ORIGINAL_SCRIPT_DIR/scripts/utils.sh" "$DEPLOY_ROOT/scripts/"
    rm -f "$COMMAND_LOG" "$OUTPUT_LOG"
    touch "$COMMAND_LOG" "$OUTPUT_LOG"

    # Create dummy service directories
    mkdir -p "$DEPLOY_ROOT/db"
    mkdir -p "$DEPLOY_ROOT/automation"
    mkdir -p "$DEPLOY_ROOT/webserver"
    mkdir -p "$DEPLOY_ROOT/storage"
    mkdir -p "$DEPLOY_ROOT/proxy"
}

# Mock sudo
sudo() {
    echo "sudo $*" >> "$COMMAND_LOG"

    # Intercept specific commands to avoid side effects or simulate behavior
    if [[ "$1" == "apt" ]]; then
        return 0
    fi
    if [[ "$1" == "docker" ]]; then
        return 0
    fi
    if [[ "$1" == "chown" ]]; then
        return 0
    fi

    # For the postgres migration move command
    if [[ "$1" == "bash" && "$2" == "-c" && "$3" == *"mv"* ]]; then
        # Actually execute the move in the test env to verify it works
        eval "$3"
        return $?
    fi

    "$@"
}
export -f sudo

# Mock cd to log it
cd() {
    echo "cd $*" >> "$COMMAND_LOG"
    builtin cd "$@"
}

# Source the script under test
source ./update.sh

# Test Utilities
PASSED=0
FAILED=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" == "$actual" ]]; then
        echo -e "  [PASS] $message"
        PASSED=$((PASSED + 1))
    else
        echo -e "  [FAIL] $message"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual:   '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

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

# --- Test Case 1: Standard Update Flow ---
echo "Test Case 1: Standard Update Flow"
setup_test_env

# Create backup script to test its execution
mkdir -p "$DEPLOY_ROOT/scripts"
touch "$DEPLOY_ROOT/scripts/backup.sh"

main > "$OUTPUT_LOG" 2>&1

assert_grep "sudo bash $DEPLOY_ROOT/scripts/backup.sh" "$COMMAND_LOG" "Backup script called"
assert_grep "sudo apt update" "$COMMAND_LOG" "Apt update called"
assert_grep "sudo apt upgrade -y" "$COMMAND_LOG" "Apt upgrade called"
assert_grep "cd $DEPLOY_ROOT/db" "$COMMAND_LOG" "Changed directory to db service"
assert_grep "sudo docker compose pull" "$COMMAND_LOG" "Docker compose pull called"
assert_grep "sudo docker compose up -d" "$COMMAND_LOG" "Docker compose up called"
assert_grep "sudo docker image prune -f" "$COMMAND_LOG" "Docker image prune called"

# --- Test Case 2: Postgres Migration ---
echo -e "\nTest Case 2: Postgres Migration"
setup_test_env

# Setup legacy postgres data structure
mkdir -p "$DEPLOY_ROOT/data/postgres/data"
echo "17" > "$DEPLOY_ROOT/data/postgres/data/PG_VERSION"
touch "$DEPLOY_ROOT/data/postgres/data/dump.sql"

main > "$OUTPUT_LOG" 2>&1

assert_grep "Converting legacy Postgres data structure" "$OUTPUT_LOG" "Migration log message found in output"
# Check if files were moved
if [ -f "$DEPLOY_ROOT/data/postgres/PG_VERSION" ] && [ -f "$DEPLOY_ROOT/data/postgres/dump.sql" ]; then
    echo -e "  [PASS] Postgres data files moved to flat structure"
    PASSED=$((PASSED + 1))
else
    echo -e "  [FAIL] Postgres data files NOT moved"
    FAILED=$((FAILED + 1))
fi

if [ ! -d "$DEPLOY_ROOT/data/postgres/data" ]; then
    echo -e "  [PASS] Legacy data directory removed"
    PASSED=$((PASSED + 1))
else
    echo -e "  [FAIL] Legacy data directory still exists"
    FAILED=$((FAILED + 1))
fi
assert_grep "sudo chown -R 70:70 $DEPLOY_ROOT/data/postgres" "$COMMAND_LOG" "Chown called after migration"

# --- Test Case 3: Missing Backup Script ---
echo -e "\nTest Case 3: Missing Backup Script"
setup_test_env
# Remove the backup script created by setup_test_env
rm -f "$DEPLOY_ROOT/scripts/backup.sh"

main > "$OUTPUT_LOG" 2>&1

assert_grep "Warning: Backup script not found" "$OUTPUT_LOG" "Handled missing backup script"

# --- Test Case 4: Reboot Required ---
echo -e "\nTest Case 4: Reboot Required"
setup_test_env

# Define a function to mock [ because we want to intercept the reboot check
# We need to do this carefully because [ is also used for other things
mock_bracket() {
    if [[ "$*" == "-f /var/run/reboot-required" ]]; then
        return 0
    fi
    builtin [ "$@"
}

# Since we want to use the mock just for this test, we can redefine main or use an alias
# Redefining the check in a subshell might be easier

(
    # In subshell, redefine [
    alias [='mock_bracket'
    # We need to re-source or re-define main to pick up the alias if it was already parsed
    # Actually, functions don't pick up aliases after they are defined.
    # Let's just override the [ command
    [() {
        if [[ "$1" == "-f" && "$2" == "/var/run/reboot-required" ]]; then
            return 0
        fi
        builtin [ "$@"
    }
    main > "$OUTPUT_LOG" 2>&1
    if grep -q "A system reboot is required" "$OUTPUT_LOG"; then
        exit 0
    else
        exit 1
    fi
)
if [ $? -eq 0 ]; then
    echo -e "  [PASS] Reboot message shown when file exists"
    PASSED=$((PASSED + 1))
else
    echo -e "  [FAIL] Reboot message NOT shown"
    FAILED=$((FAILED + 1))
fi

# Cleanup
rm -rf "$DEPLOY_ROOT" "$COMMAND_LOG" "$OUTPUT_LOG"

echo -e "\nTest Summary: $PASSED passed, $FAILED failed."

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
