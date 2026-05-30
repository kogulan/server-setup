FROM php:8.3-fpm-alpine

# Install system dependencies for Alpine
RUN apk update && apk add --no-cache \
    libpng-dev \
    libzip-dev \
    postgresql-dev \
    curl-dev \
    libxml2-dev \
    oniguruma-dev \
    zip \
    unzip \
    gcc \
    g++ \
    make \
    autoconf

# Install PHP extensions
RUN docker-php-ext-install \
    mysqli \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    gd \
    zip \
    curl \
    mbstring \
    xml

# Clean up build dependencies to keep it small
RUN apk del gcc g++ make autoconf
