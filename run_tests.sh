#!/bin/bash

# Test runner for shell script unit tests

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "========================================"
echo "      Running Shell Unit Tests"
echo "========================================"

TOTAL_PASSED=0
TOTAL_FAILED=0
TEST_FILES=(tests/test_*.sh)

for test_file in "${TEST_FILES[@]}"; do
    if [[ ! -f "$test_file" ]]; then continue; fi

    echo -e "\n--- Executing $test_file ---"
    if bash "$test_file"; then
        echo -e "${GREEN}Result: SUCCESS${NC}"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    else
        echo -e "${RED}Result: FAILED${NC}"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
done

echo -e "\n========================================"
echo -e "Final Summary:"
echo -e "  Passed: $TOTAL_PASSED"
echo -e "  Failed: $TOTAL_FAILED"
echo "========================================"

if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi
