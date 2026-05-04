FROM php:8.2-fpm

ENV PHPGROUP=aluna
ENV PHPUSER=aluna

RUN groupadd -g 1000 ${PHPGROUP} && \
    useradd -r -u 1000 -g ${PHPGROUP} -s /bin/sh ${PHPUSER}

# Change the default shell for all subsequent RUN instructions
SHELL ["/bin/bash", "-c"]

RUN sed -i "s/user = www-data/user = ${PHPUSER}/g" /usr/local/etc/php-fpm.d/www.conf
RUN sed -i "s/group = www-data/group = ${PHPGROUP}/g" /usr/local/etc/php-fpm.d/www.conf

# Fix sources + install PHP dev tools
# RUN echo "deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware" > /etc/apt/sources.list \
#  && echo "deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list \
#  && echo "deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list

RUN apt-get update -y && apt-get install -y \
    nodejs \
    npm \
    nano \
    vim \
    bison \
    libtool \
    automake \
    git \
    gcc \
    g++ \
    make \
    autoconf \
    pkg-config \
    libssl-dev \
    unzip \
    curl \
    libzip-dev \
    libonig-dev \
    libxml2-dev \
    cmake \
    protobuf-compiler \
    libprotobuf-c-dev \
    wget \
    protobuf-c-compiler \
    && docker-php-ext-install bcmath \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install pdo pdo_mysql

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

RUN mkdir -p /var/www/html/public

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

RUN curl -L https://github.com/php/pie/releases/latest/download/pie.phar -o /usr/local/bin/pie \
 && chmod +x /usr/local/bin/pie

RUN cargo install cbindgen

# Download the package
RUN curl -L https://github.com/valkey-io/valkey-glide-php/releases/download/v1.0.0/valkey_glide-1.0.0.tgz -o valkey_glide-1.0.0.tgz

# Install with PECL
RUN pecl install valkey_glide-1.0.0.tgz

RUN pie --version

CMD ["php-fpm", "-y", "/usr/local/etc/php-fpm.conf", "-R"]

ADD valkey.ini /usr/local/etc/php/conf.d/valkey.ini

# Switch user
# USER aluna

WORKDIR /var/www/html