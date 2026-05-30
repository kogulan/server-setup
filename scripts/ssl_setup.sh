#!/bin/bash

# Script to handle SSL setup based on user choice

MODE=$1 # selfsigned, letsencrypt, or none
DOMAIN=$2
EMAIL=$3
ACCESS_MODE=$4 # 1 for subdomains, 2 for ports

CERT_DIR="/opt/deploy/proxy/certs"
mkdir -p "$CERT_DIR"

if [ "$MODE" == "selfsigned" ]; then
    echo "Generating self-signed certificate for $DOMAIN..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/privkey.pem" \
        -out "$CERT_DIR/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"

elif [ "$MODE" == "letsencrypt" ]; then
    echo "Ensuring port 80 is free for Certbot..."

    # 1. Stop the docker proxy
    cd /opt/deploy/proxy && docker compose stop || true

    # 2. Stop host-based web servers that might be running
    sudo systemctl stop nginx 2>/dev/null || true
    sudo systemctl stop apache2 2>/dev/null || true

    # 3. Kill anything else on port 80
    if command -v lsof >/dev/null; then
        PID_80=$(sudo lsof -t -i :80)
        if [ ! -z "$PID_80" ]; then
            echo "Killing process on port 80 (PID: $PID_80)..."
            sudo kill -9 $PID_80 || true
        fi
    fi

    # Prepare domains list
    DOMAINS="-d $DOMAIN"
    if [ "$ACCESS_MODE" == "1" ]; then
        DOMAINS="$DOMAINS -d db.$DOMAIN -d n8n.$DOMAIN -d ap.$DOMAIN -d huginn.$DOMAIN -d ftp.$DOMAIN"
    fi

    echo "Running Certbot for $DOMAINS..."
    certbot certonly --standalone $DOMAINS --non-interactive --agree-tos -m "$EMAIL" --preferred-challenges http

    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$CERT_DIR/privkey.pem"
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERT_DIR/fullchain.pem"
        echo "SSL certificate obtained and copied."
    else
        echo "Error: Certbot failed. Generating fallback self-signed certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$CERT_DIR/privkey.pem" \
            -out "$CERT_DIR/fullchain.pem" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"
    fi
fi
