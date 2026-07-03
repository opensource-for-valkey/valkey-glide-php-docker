FROM valkey/valkey:9-alpine

# TLS-enabled, cluster-mode Valkey node. Mirrors valkey-cluster.dockerfile
# but serves the client protocol AND the cluster bus over TLS:
#   --tls-cluster yes      encrypt the inter-node cluster bus
#   --tls-replication yes  encrypt primary<->replica replication
#   --port 0               disable the plaintext port (TLS only)
#
# NOTE: uses valkey.crt (the unrestricted cert) rather than server.crt. The
# cluster bus is MUTUAL TLS — each node dials its peers as a *client*, so the
# cert must be valid for clientAuth too. server.crt is nsCertType=server only,
# which peers reject ("Clusterbus handshake timeout"). valkey.crt has no
# usage restriction, so it works as both server and client.
#
# Certificates are mounted at /etc/certs at runtime (see the vk-tls-* services
# in docker-compose.yml). Generate them with `./certs/gen-test-certs.sh`.
#
# Each node advertises its simulated AWS availability zone via
# --availability-zone so an AZ-affinity GLIDE client can route reads to a
# same-AZ replica. The AZ is supplied per-service via the VALKEY_AZ env var.

# Default AZ; overridden per-service via `environment: VALKEY_AZ=...`.
ENV VALKEY_AZ=us-east-1a

# Entrypoint bakes in the TLS + cluster flags and injects the per-node AZ so
# compose only needs to set VALKEY_AZ. exec keeps valkey-server as PID 1.
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    'exec valkey-server \' \
    '  --tls-port 6379 \' \
    '  --port 0 \' \
    '  --tls-cert-file /etc/certs/valkey.crt \' \
    '  --tls-key-file /etc/certs/valkey.key \' \
    '  --tls-ca-cert-file /etc/certs/ca.crt \' \
    '  --tls-auth-clients no \' \
    '  --tls-cluster yes \' \
    '  --tls-replication yes \' \
    '  --cluster-enabled yes \' \
    '  --cluster-config-file nodes.conf \' \
    '  --cluster-node-timeout 5000 \' \
    '  --appendonly yes \' \
    '  --io-threads 4 \' \
    '  --io-threads-do-reads yes \' \
    '  --maxmemory 250mb \' \
    '  --availability-zone "${VALKEY_AZ}"' \
    > /usr/local/bin/cluster-node-tls.sh && \
    chmod +x /usr/local/bin/cluster-node-tls.sh

ENTRYPOINT ["/usr/local/bin/cluster-node-tls.sh"]
