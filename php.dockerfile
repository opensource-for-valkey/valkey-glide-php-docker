FROM php:8.4-fpm

# --- Build arguments --------------------------------------------------
ARG VALKEY_GLIDE_VERSION=1.1.0
# Node.js LTS major version (24 = "Krypton"). Bump when a new LTS lands.
ARG NODE_MAJOR=24

ENV PHPGROUP=valkeyglide
ENV PHPUSER=valkeyglide

# Use bash for all subsequent RUN instructions.
SHELL ["/bin/bash", "-c"]

# --- Application user -------------------------------------------------
RUN groupadd -g 1000 ${PHPGROUP} && \
    useradd -r -u 1000 -g ${PHPGROUP} -s /bin/sh ${PHPUSER}

# Run php-fpm as the application user instead of www-data.
RUN sed -i "s/user = www-data/user = ${PHPUSER}/g"   /usr/local/etc/php-fpm.d/www.conf && \
    sed -i "s/group = www-data/group = ${PHPGROUP}/g" /usr/local/etc/php-fpm.d/www.conf

# --- System & development tools ---------------------------------------
# Editors, build toolchain and the libraries needed to compile the
# valkey-glide extension (protobuf, openssl, cmake, ...).
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    unzip \
    sqlite3 \
    nano \
    vim \
    gcc \
    g++ \
    make \
    cmake \
    autoconf \
    automake \
    libtool \
    bison \
    pkg-config \
    libssl-dev \
    libzip-dev \
    libonig-dev \
    libxml2-dev \
    libicu-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libpq-dev \
    libmemcached-dev \
    protobuf-compiler \
    protobuf-c-compiler \
    libprotobuf-c-dev \
    && rm -rf /var/lib/apt/lists/*

# --- Node.js (current LTS via NodeSource) -----------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# --- Rust toolchain (needed to build valkey-glide) --------------------
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install cbindgen

# --- PHP extensions ---------------------------------------------------
# Laravel's required extensions (ctype, mbstring, openssl, tokenizer, xml,
# ...) ship with the base image, as do pdo_sqlite + sqlite3 for SQLite.
# These add the remaining database drivers (MySQL/MariaDB + PostgreSQL)
# plus the commonly-needed extras: bcmath, zip (Composer), pcntl (queue
# workers), intl (localization), gd + exif (image handling).
RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-install pdo pdo_mysql pdo_pgsql bcmath zip pcntl intl gd exif

# --- PHP tooling: Composer & PIE --------------------------------------
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
RUN curl -L https://github.com/php/pie/releases/latest/download/pie.phar -o /usr/local/bin/pie && \
    chmod +x /usr/local/bin/pie && \
    pie --version

# --- PHP packages: valkey-glide + phpredis ----------------------------
# Download and install the valkey-glide extension from the pinned release.
RUN curl -L https://github.com/valkey-io/valkey-glide-php/releases/download/v${VALKEY_GLIDE_VERSION}/valkey_glide-${VALKEY_GLIDE_VERSION}.tgz \
        -o valkey_glide-${VALKEY_GLIDE_VERSION}.tgz && \
    pecl install valkey_glide-${VALKEY_GLIDE_VERSION}.tgz

# phpredis (ext-redis) so both drivers are available side by side.
RUN pecl install redis && docker-php-ext-enable redis

# ext-memcached (built against libmemcached) for the memcached service.
RUN pecl install memcached && docker-php-ext-enable memcached

# valkey-glide extension config (extension=valkey_glide).
ADD valkey.ini /usr/local/etc/php/conf.d/valkey.ini

# --- Runtime ----------------------------------------------------------
RUN mkdir -p /var/www/html/public
WORKDIR /var/www/html

# Switch user
# USER valkeyglide

CMD ["php-fpm", "-y", "/usr/local/etc/php-fpm.conf", "-R"]
