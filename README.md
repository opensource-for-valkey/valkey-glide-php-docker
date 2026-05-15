# Docker Valkey-Glide PHP

A Docker environment for developing with [valkey-glide-php](https://github.com/valkey-io/valkey-glide-php) — includes Nginx, PHP-FPM, and both standalone and cluster Valkey instances.

## Prerequisites

- Docker & Docker Compose

## Quick Start

```bash
git clone https://github.com/opensource-for-valkey/valkey-glide-php-docker.git
cd valkey-glide-php-docker

# Build and start all services
docker compose up -d --build
```

## Testing

Run CLI demos:
```bash
# SSH into the container if needed
docker exec -it valkey-glide-php-docker-php-1 bash

# Install PHPUnit in the PHP container
docker exec valkey-glide-php-docker-php-1 sh -c "cd /var/www/cli/ && composer require --dev phpunit/phpunit"

# Test standalone Valkey connection
docker exec valkey-glide-php-docker-php-1 /var/www/cli/vendor/bin/phpunit /var/www/cli/ValkeyStandaloneTest.php
```

**Note:** Cluster configuration is still work in progress.

## Project Structure

| File | Description |
|------|-------------|
| `tests/ValkeyTestBase.php` | Abstract PHPUnit test class with all 18 test methods. |
| `tests/ValkeyStandaloneTest.php` | Standalone test implementation (extends ValkeyTestBase). |
| `php.dockerfile` | PHP 8.4 FPM with Rust toolchain and valkey-glide compiled from source. |
| `nginx.dockerfile` | Nginx stable-alpine with PHP-FPM integration. |
| `valkey.dockerfile` | Valkey 9 Alpine image. |
| `docker-compose.yml` | Full stack: Nginx, PHP-FPM, MariaDB, standalone Valkey. |

## Architecture

```mermaid
flowchart TD
    nginx@{ shape: rect, label: "Nginx" }
    php@{ shape: rect, label: "PHP-FPM \n + valkey glide" }
    v@{ shape: lin-cyl, label: "valkey \n :6379 \n (standalone)" }
    vn@{ shape: processes, label: "valkey-node-{1,2,3} \n :700, :7001, :7002 \n (cluster)"}

    START[ ] --- |:80| nginx
    nginx --- |fastcgi: 9000| php
    php --> v 
    php --> vn

    style START fill:#FFFFFF00, stroke:#FFFFFF00;
```

## Configuration

The valkey-glide version is configurable via build arg:

```bash
docker compose build --build-arg VALKEY_GLIDE_VERSION=1.0.0
```

## Stopping

```bash
docker compose down
```

## Notes

- The cluster uses 3 primary nodes with no replicas (suitable for local dev/testing).
- `valkey-cluster-init` is a one-shot container that creates the cluster topology and exits.
- Alpine Linux is **not** supported by valkey-glide — the Dockerfile uses Debian-based PHP.
- Requires PHP 8.1+ (8.4 used here).
