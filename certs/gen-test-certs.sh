#!/bin/sh
#
# gen-test-certs.sh — generate self-signed certificates for local TLS testing.
#
# Adapted from the standard Redis/Valkey test-cert generator. Run it from
# this directory; it writes the following into the current folder:
#
#   ca.{crt,key}        Self-signed CA (the trust anchor clients verify against).
#   server.{crt,key}    Server cert (used by valkey-server --tls-cert-file).
#   client.{crt,key}    Client cert (only needed for mutual TLS / tls-auth-clients yes).
#   valkey.{crt,key}    Generic cert with no usage restrictions.
#   valkey.dh           Diffie-Hellman params.
#
# These are for LOCAL DEVELOPMENT ONLY — never use them in production.
# The generated *.key/*.crt/*.dh files are git-ignored (see ../.gitignore).

set -eu

# Resolve to this script's own directory so it works from any CWD.
cd "$(dirname "$0")"

generate_cert() {
    name="$1"
    cn="$2"
    opts="${3:-}"

    keyfile="${name}.key"
    certfile="${name}.crt"

    [ -f "$keyfile" ] || openssl genrsa -out "$keyfile" 2048
    # shellcheck disable=SC2086
    openssl req \
        -new -nodes -sha256 \
        -subj "/O=Valkey Test/CN=$cn" \
        -key "$keyfile" | \
        openssl x509 \
            -req -sha256 \
            -CA ca.crt \
            -CAkey ca.key \
            -CAserial ca.txt \
            -CAcreateserial \
            -days 365 \
            $opts \
            -out "$certfile"
}

# 1) Certificate Authority.
[ -f ca.key ] || openssl genrsa -out ca.key 4096
openssl req \
    -x509 -new -nodes -sha256 \
    -key ca.key \
    -days 3650 \
    -subj '/O=Valkey Test/CN=Certificate Authority' \
    -out ca.crt

# 2) Key-usage extensions for the server- and client-restricted certs.
cat > openssl.cnf <<'_END_'
[ server_cert ]
keyUsage = digitalSignature, keyEncipherment
nsCertType = server

[ client_cert ]
keyUsage = digitalSignature, keyEncipherment
nsCertType = client
_END_

# 3) Leaf certificates signed by the CA.
generate_cert server "Server-only" "-extfile openssl.cnf -extensions server_cert"
generate_cert client "Client-only" "-extfile openssl.cnf -extensions client_cert"
generate_cert valkey "Generic-cert"

# 4) DH params.
[ -f valkey.dh ] || openssl dhparam -out valkey.dh 2048

echo "Certificates generated in $(pwd):"
ls -1 ca.crt server.crt server.key client.crt client.key valkey.crt valkey.key valkey.dh
