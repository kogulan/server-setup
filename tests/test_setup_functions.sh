#!/bin/bash

# Simple Bash Unit Test for setup.sh functions

# Mock DEPLOY_ROOT and CONFIG_FILE to avoid affecting system
export DEPLOY_ROOT="/tmp/deploy_test"
export CONFIG_FILE="$DEPLOY_ROOT/.env"
mkdir -p "$DEPLOY_ROOT"

# Mock sudo to just run the command since we are in a sandbox
sudo() {
    "$@"
}
export -f sudo

# Mock timedatectl
timedatectl() {
    if [[ "$1" == "list-timezones" ]]; then
        echo "Asia/Colombo"
        echo "UTC"
    fi
}
export -f timedatectl

# Source the script under test
# We use a subshell or carefully source it because setup.sh has 'set -euo pipefail'
# which might exit the test script on any failure.
source ./setup.sh

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

# --- Tests for get_secret ---

echo "Running tests for get_secret..."

TEST_ENV="/tmp/test.env"

# Case 1: Basic key-value extraction
echo "KEY1=VALUE1" > "$TEST_ENV"
assert_eq "VALUE1" "$(get_secret "KEY1" "$TEST_ENV")" "Basic key-value extraction"

# Case 2: Values containing '=' characters
echo "KEY2=VALUE=WITH=EQUALS" > "$TEST_ENV"
assert_eq "VALUE=WITH=EQUALS" "$(get_secret "KEY2" "$TEST_ENV")" "Values containing '=' characters"

# Case 3: Handling of missing keys
assert_eq "" "$(get_secret "MISSING_KEY" "$TEST_ENV")" "Handling of missing keys"

# Case 4: Handling of empty values
echo "EMPTY_KEY=" > "$TEST_ENV"
assert_eq "" "$(get_secret "EMPTY_KEY" "$TEST_ENV")" "Handling of empty values"

# Case 5: Handling of multiple occurrences of the same key (should return the first)
echo -e "MULTI=FIRST\nMULTI=SECOND" > "$TEST_ENV"
assert_eq "FIRST" "$(get_secret "MULTI" "$TEST_ENV")" "Return the first occurrence of a key"

# Case 6: Handling of missing files
assert_eq "" "$(get_secret "KEY" "/non/existent/file")" "Handling of missing files"

# Case 7: Handling of CRLF line endings
echo -e "CRLF_KEY=VALUE\r" > "$TEST_ENV"
assert_eq "VALUE" "$(get_secret "CRLF_KEY" "$TEST_ENV")" "Handling of CRLF line endings"

# Case 8: Exact key matching (ensuring prefixes don't match)
echo -e "PREFIX_KEY=VALUE1\nKEY=VALUE2" > "$TEST_ENV"
assert_eq "VALUE2" "$(get_secret "KEY" "$TEST_ENV")" "Exact key matching (no prefix match)"

# --- Tests for ensure_secret ---

echo -e "\nRunning tests for ensure_secret..."

# Case 1: Retrieve existing secret
echo "EXISTING_SECRET=ALREADY_HERE" > "$TEST_ENV"
assert_eq "ALREADY_HERE" "$(ensure_secret "EXISTING_SECRET" "$TEST_ENV")" "Retrieve existing secret"

# Case 2: Generate new secret when missing
NEW_SECRET_FILE="/tmp/new_secret.env"
rm -f "$NEW_SECRET_FILE"
touch "$NEW_SECRET_FILE"
SECRET=$(ensure_secret "NEW_KEY" "$NEW_SECRET_FILE")
if [[ -n "$SECRET" ]]; then
    echo -e "  [PASS] Generated new secret when missing"
    PASSED=$((PASSED + 1))
else
    echo -e "  [FAIL] Generated new secret when missing"
    FAILED=$((FAILED + 1))
fi

# Cleanup
rm -f "$TEST_ENV" "$NEW_SECRET_FILE"
rm -rf "$DEPLOY_ROOT"

echo -e "\nTest Summary: $PASSED passed, $FAILED failed."

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
