#!/usr/bin/env bash
#
# test.sh — run the Valkey GLIDE test suites with gum.
#
# 1. PHP CLI tests (PHPUnit): Valkey standalone + replica, and PHP
#    connectivity to MariaDB, PostgreSQL, SQLite, and Memcached.
# 2. Web-server test: hits the OpenResty/PHP-FPM JSON endpoint and
#    validates the response with HTTPie + jq.
#
# Usage:
#   ./scripts/test.sh          # run every suite (default)
#   ./scripts/test.sh --pick   # interactive suite picker (gum choose)
#
# --all is still accepted as a no-op alias for the default behavior.

set -euo pipefail

cd "$(dirname "$0")/.."

PHP_CONTAINER="valkey-glide-php-docker-php-1"
WEB_URL="http://localhost:8080/"
PHPUNIT="/var/www/cli/vendor/bin/phpunit"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}

require gum
require http   # HTTPie
require jq
require docker

run_phpunit() {
    local file="$1"
    docker exec "$PHP_CONTAINER" "$PHPUNIT" "/var/www/cli/$file"
}

gum style --border double --margin "1" --padding "1 2" --border-foreground 212 \
    "Valkey GLIDE PHP — Tests"

# --- Preflight: valkey-glide PHP extension must be loaded ----------------
if docker exec "$PHP_CONTAINER" php -m 2>/dev/null | grep -qix "valkey_glide"; then
    VERSION=$(docker exec "$PHP_CONTAINER" php -r 'echo phpversion("valkey_glide");' 2>/dev/null)
    gum style --foreground 42 "✔ valkey-glide PHP extension loaded (v${VERSION})"
else
    gum style --foreground 196 "✘ valkey-glide PHP extension NOT loaded in $PHP_CONTAINER"
    gum style --foreground 244 "Rebuild the php image (see php.dockerfile) — cannot run tests without it."
    exit 1
fi

# --- Pick which suites to run --------------------------------------------
ALL_SUITES=$'Standalone (CLI)\nReplica (CLI)\nCluster (CLI)\nGLIDE features (CLI)\nTLS standalone (CLI)\nTLS cluster (CLI)\nMariaDB (CLI)\nPostgreSQL (CLI)\nSQLite (CLI)\nMemcached (CLI)\nWeb server (HTTPie)'

# Run everything by default. Only prompt when --pick is passed on a TTY.
RUN_ALL=1
[ "${1:-}" = "--pick" ] && RUN_ALL=0
# No interactive terminal? Always run everything regardless of flags.
[ -t 0 ] || RUN_ALL=1

if [ "$RUN_ALL" -eq 1 ]; then
    CHOICES="$ALL_SUITES"
    gum style --foreground 244 "Running all suites (non-interactive)."
else
    CHOICES=$(gum choose --no-limit \
        --selected="Standalone (CLI),Replica (CLI),Cluster (CLI),GLIDE features (CLI),TLS standalone (CLI),TLS cluster (CLI),MariaDB (CLI),PostgreSQL (CLI),SQLite (CLI),Memcached (CLI),Web server (HTTPie)" \
        "Standalone (CLI)" \
        "Replica (CLI)" \
        "Cluster (CLI)" \
        "GLIDE features (CLI)" \
        "TLS standalone (CLI)" \
        "TLS cluster (CLI)" \
        "MariaDB (CLI)" \
        "PostgreSQL (CLI)" \
        "SQLite (CLI)" \
        "Memcached (CLI)" \
        "Web server (HTTPie)")
fi

# --- Results tracking ----------------------------------------------------
RESULTS=""

record() {
    local suite="$1" status="$2"
    RESULTS="${RESULTS}${suite}\t${status}\n"
}

FAILED=0

if grep -q "Standalone (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: standalone"
    if run_phpunit "ValkeyStandaloneTest.php"; then
        record "Standalone" "PASS"
    else
        record "Standalone" "FAIL"
        FAILED=1
    fi
fi

if grep -q "Replica (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: replica (read from replica)"
    if run_phpunit "ValkeyReplicaTest.php"; then
        record "Replica" "PASS"
    else
        record "Replica" "FAIL"
        FAILED=1
    fi
fi

if grep -q "Cluster (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: cluster (AZ-affinity, 3 shards x 4 nodes)"
    if run_phpunit "ValkeyClusterTest.php"; then
        record "Cluster" "PASS"
    else
        record "Cluster" "FAIL"
        FAILED=1
    fi
fi

if grep -q "GLIDE features (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: GLIDE features (AZ routing, cross-slot, sharded pub/sub)"
    if run_phpunit "ValkeyGlideTest.php"; then
        record "GLIDE features" "PASS"
    else
        record "GLIDE features" "FAIL"
        FAILED=1
    fi
fi

# TLS suites need the `tls` profile running. Detect once: if valkey-tls
# answers a TLS ping, the profile is up; otherwise skip (recorded as SKIP).
tls_up() {
    docker compose exec -T valkey-tls valkey-cli --tls --cacert /etc/certs/ca.crt ping >/dev/null 2>&1
}

if grep -q "TLS standalone (CLI)" <<<"$CHOICES"; then
    if tls_up; then
        gum style --foreground 39 "▶ PHPUnit: TLS standalone (encrypted primary + replica)"
        if run_phpunit "ValkeyGlideTlsTest.php"; then
            record "TLS standalone" "PASS"
        else
            record "TLS standalone" "FAIL"
            FAILED=1
        fi
    else
        gum style --foreground 214 "▶ TLS standalone — skipped (tls profile not running)"
        record "TLS standalone" "SKIP"
    fi
fi

if grep -q "TLS cluster (CLI)" <<<"$CHOICES"; then
    if tls_up; then
        gum style --foreground 39 "▶ PHPUnit: TLS cluster (AZ-aware, encrypted bus, 3 shards)"
        if run_phpunit "ValkeyGlideClusterTlsTest.php"; then
            record "TLS cluster" "PASS"
        else
            record "TLS cluster" "FAIL"
            FAILED=1
        fi
    else
        gum style --foreground 214 "▶ TLS cluster — skipped (tls profile not running)"
        record "TLS cluster" "SKIP"
    fi
fi

if grep -q "MariaDB (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: MariaDB connectivity (PDO)"
    if run_phpunit "MariaDbConnectionTest.php"; then
        record "MariaDB" "PASS"
    else
        record "MariaDB" "FAIL"
        FAILED=1
    fi
fi

if grep -q "PostgreSQL (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: PostgreSQL connectivity (PDO)"
    if run_phpunit "PostgresConnectionTest.php"; then
        record "PostgreSQL" "PASS"
    else
        record "PostgreSQL" "FAIL"
        FAILED=1
    fi
fi

if grep -q "SQLite (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: SQLite connectivity (PDO)"
    if run_phpunit "SqliteConnectionTest.php"; then
        record "SQLite" "PASS"
    else
        record "SQLite" "FAIL"
        FAILED=1
    fi
fi

if grep -q "Memcached (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: Memcached connectivity (ext-memcached)"
    if run_phpunit "MemcachedConnectionTest.php"; then
        record "Memcached" "PASS"
    else
        record "Memcached" "FAIL"
        FAILED=1
    fi
fi

if grep -q "Web server (HTTPie)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ Web server: GET $WEB_URL"

    # Wait for the endpoint to answer, but give up after ~30s so a stopped
    # web server fails the suite instead of hanging forever.
    if gum spin --spinner dot --title "Waiting for web endpoint..." -- \
        bash -c "for i in \$(seq 1 30); do http --check-status --timeout=3 GET $WEB_URL >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1"
    then
        # Fetch the JSON body with HTTPie and pretty-print it.
        BODY=$(http --body --print=b GET "$WEB_URL")
        echo "$BODY" | gum format --type code --language json || echo "$BODY"

        # Validate the JSON contract with jq.
        OK=$(echo "$BODY" | jq -r '.ok' 2>/dev/null || echo "error")
        REPLICATED=$(echo "$BODY" | jq -r '.replica.replicated' 2>/dev/null || echo "error")
    else
        gum style --foreground 196 "✘ Web endpoint unreachable at $WEB_URL (is openresty up?)"
        OK="unreachable"; REPLICATED="unreachable"
    fi

    if [ "$OK" = "true" ] && [ "$REPLICATED" = "true" ]; then
        gum style --foreground 42 "✔ Web endpoint OK — primary write replicated to replica"
        record "Web server" "PASS"
    else
        gum style --foreground 196 "✘ Web endpoint FAILED (ok=$OK, replicated=$REPLICATED)"
        record "Web server" "FAIL"
        FAILED=1
    fi
fi

# --- Summary table -------------------------------------------------------
echo
gum style --bold --foreground 39 "Results:"

GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

{
    printf "SUITE\tSTATUS\n"
    printf "%b" "$RESULTS" | while IFS=$'\t' read -r suite status; do
        [ -z "$suite" ] && continue
        case "$status" in
            PASS) printf "%s\t${GREEN}%s${RESET}\n" "$suite" "$status" ;;
            SKIP) printf "%s\t${YELLOW}%s${RESET}\n" "$suite" "$status" ;;
            *)    printf "%s\t${RED}%s${RESET}\n" "$suite" "$status" ;;
        esac
    done
} | gum table --print --separator $'\t' --border.foreground 212

echo
if [ "$FAILED" -eq 0 ]; then
    gum style --foreground 42 "All selected tests passed."
else
    gum style --foreground 196 "Some tests failed."
    exit 1
fi
