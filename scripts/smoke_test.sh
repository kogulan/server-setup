#!/bin/bash

# Simple Integration / Smoke Test for OCI Deployment

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_url() {
    local name="$1"
    local url="$2"
    local expected_code="${3:-200}"

    echo -n "Checking $name ($url)... "
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

    if [ "$code" == "$expected_code" ]; then
        echo -e "${GREEN}PASS ($code)${NC}"
        return 0
    else
        echo -e "${RED}FAIL ($code, expected $expected_code)${NC}"
        return 1
    fi
}

main() {
    local domain="$1"
    local proto="${2:-https}"
    local access_choice="${3:-1}" # 1 for subdomains, 2 for ports

    echo "Starting smoke tests for $domain..."

    local failed=0

    if [ "$access_choice" == "1" ]; then
        check_url "Main Website" "$proto://$domain" || failed=$((failed + 1))
        check_url "Adminer" "$proto://db.$domain" || failed=$((failed + 1))
        check_url "n8n" "$proto://n8n.$domain" || failed=$((failed + 1))
        check_url "Activepieces" "$proto://ap.$domain" || failed=$((failed + 1))
        check_url "Huginn" "$proto://huginn.$domain" || failed=$((failed + 1))
    else
        check_url "Main Website" "$proto://$domain" || failed=$((failed + 1))
        check_url "Adminer" "$proto://$domain:8080" || failed=$((failed + 1))
        check_url "n8n" "$proto://$domain:5678" || failed=$((failed + 1))
        check_url "Activepieces" "$proto://$domain:8081" || failed=$((failed + 1))
        check_url "Huginn" "$proto://$domain:3000" || failed=$((failed + 1))
    fi

    if [ $failed -eq 0 ]; then
        echo -e "\n${GREEN}All smoke tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}$failed smoke tests failed!${NC}"
        exit 1
    fi
}

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <domain> [proto] [access_choice]"
    exit 1
fi

main "$@"
