FROM valkey/valkey:9-alpine

# Cluster-mode Valkey node. Each node advertises its simulated AWS
# availability zone via --availability-zone, which is what an AZ-affinity
# GLIDE client reads to route reads to a same-AZ replica. The AZ is supplied
# per-service in docker-compose.yml as the VALKEY_AZ env var. The port stays
# the default 6379 since every node has its own hostname on the network.

# Default AZ; overridden per-service via `environment: VALKEY_AZ=...`.
ENV VALKEY_AZ=us-east-1a

# Entrypoint bakes in the cluster flags and injects the per-node AZ so
# compose only needs to set VALKEY_AZ. exec keeps valkey-server as PID 1.
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    'exec valkey-server \' \
    '  --port 6379 \' \
    '  --cluster-enabled yes \' \
    '  --cluster-config-file nodes.conf \' \
    '  --cluster-node-timeout 5000 \' \
    '  --appendonly yes \' \
    '  --io-threads 4 \' \
    '  --io-threads-do-reads yes \' \
    '  --maxmemory 250mb \' \
    '  --availability-zone "${VALKEY_AZ}"' \
    > /usr/local/bin/cluster-node.sh && \
    chmod +x /usr/local/bin/cluster-node.sh

ENTRYPOINT ["/usr/local/bin/cluster-node.sh"]
