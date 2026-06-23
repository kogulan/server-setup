#!/bin/bash

# Test script for sanitize_domain function

sanitize_domain() {
    local domain="$1"
    # Remove protocol (http:// or https://)
    domain=$(echo "$domain" | sed -E 's|^https?://||i')
    # Remove trailing slash
    domain="${domain%/}"
    echo "$domain"
}

declare -a inputs=(
    "example.com"
    "http://example.com"
    "https://example.com"
    "https://example.com/"
    "HTTP://EXAMPLE.COM"
    "https://sub.example.com/path"
)

declare -a expecteds=(
    "example.com"
    "example.com"
    "example.com"
    "example.com"
    "EXAMPLE.COM"
    "sub.example.com/path"
)

exit_code=0

for i in "${!inputs[@]}"; do
    input="${inputs[$i]}"
    expected="${expecteds[$i]}"
    actual=$(sanitize_domain "$input")

    if [ "$actual" == "$expected" ]; then
        echo -e "\e[32mPASS\e[0m: input='$input', expected='$expected', actual='$actual'"
    else
        echo -e "\e[31mFAIL\e[0m: input='$input', expected='$expected', actual='$actual'"
        exit_code=1
    fi
done

exit $exit_code
