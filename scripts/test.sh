#!/usr/bin/env bash
#
# test.sh — run the Valkey GLIDE test suites with gum.
#
# 1. PHP CLI tests (PHPUnit) for standalone + replica connections.
# 2. Web-server test: hits the nginx/PHP-FPM JSON endpoint and validates
#    the response with HTTPie.
#
# Usage:
#   ./scripts/test.sh          # interactive suite picker (gum choose)
#   ./scripts/test.sh --all    # run every suite, no prompt (CI-friendly)
#
# When stdin is not a TTY (e.g. CI, piped), --all is assumed automatically.

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
ALL_SUITES=$'Standalone (CLI)\nReplica (CLI)\nWeb server (HTTPie)'

RUN_ALL=0
[ "${1:-}" = "--all" ] && RUN_ALL=1
# No interactive terminal? Fall back to running everything.
[ -t 0 ] || RUN_ALL=1

if [ "$RUN_ALL" -eq 1 ]; then
    CHOICES="$ALL_SUITES"
    gum style --foreground 244 "Running all suites (non-interactive)."
else
    CHOICES=$(gum choose --no-limit --selected="Standalone (CLI),Replica (CLI),Web server (HTTPie)" \
        "Standalone (CLI)" \
        "Replica (CLI)" \
        "Web server (HTTPie)")
fi

FAILED=0

if grep -q "Standalone (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: standalone"
    run_phpunit "ValkeyStandaloneTest.php" || FAILED=1
fi

if grep -q "Replica (CLI)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ PHPUnit: replica (read from replica)"
    run_phpunit "ValkeyReplicaTest.php" || FAILED=1
fi

if grep -q "Web server (HTTPie)" <<<"$CHOICES"; then
    gum style --foreground 39 "▶ Web server: GET $WEB_URL"

    # Wait for the endpoint to answer.
    gum spin --spinner dot --title "Waiting for web endpoint..." -- \
        bash -c "until http --check-status --timeout=3 GET $WEB_URL >/dev/null 2>&1; do sleep 1; done"

    # Fetch the JSON body with HTTPie and pretty-print it.
    BODY=$(http --body --print=b GET "$WEB_URL")
    echo "$BODY" | gum format --type code --language json || echo "$BODY"

    # Validate the JSON contract with jq.
    OK=$(echo "$BODY" | jq -r '.ok' 2>/dev/null || echo "error")
    REPLICATED=$(echo "$BODY" | jq -r '.replica.replicated' 2>/dev/null || echo "error")

    if [ "$OK" = "true" ] && [ "$REPLICATED" = "true" ]; then
        gum style --foreground 42 "✔ Web endpoint OK — primary write replicated to replica"
    else
        gum style --foreground 196 "✘ Web endpoint FAILED (ok=$OK, replicated=$REPLICATED)"
        FAILED=1
    fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
    gum style --foreground 42 "All selected tests passed."
else
    gum style --foreground 196 "Some tests failed."
    exit 1
fi
