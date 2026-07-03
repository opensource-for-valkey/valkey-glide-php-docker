# valkey-bundle (Valkey + json/search/bloom/ldap modules). ValkeyJSON is
# required by Valkey Admin (it runs JSON.TYPE while building the dashboard).
FROM valkey/valkey-bundle:latest

# Cluster-mode Valkey node. Each node advertises its simulated AWS
# availability zone via --availability-zone, which is what an AZ-affinity
# GLIDE client reads to route reads to a same-AZ replica. The AZ is supplied
# per-service in docker-compose.yml as the VALKEY_AZ env var. The port stays
# the default 6379 since every node has its own hostname on the network.

# Default AZ; overridden per-service via `environment: VALKEY_AZ=...`.
ENV VALKEY_AZ=us-east-1a

# Bake in the cluster flags and inject the per-node AZ. We delegate to the
# bundle entrypoint (rather than exec valkey-server directly) so it still
# auto-loads every module in /usr/lib/valkey; it drops privileges to the
# valkey user and exec's valkey-server with our flags + the module args.
RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -e' \
    'exec bundle-docker-entrypoint.sh valkey-server \' \
    '  --port 6379 \' \
    '  --cluster-enabled yes \' \
    '  --cluster-config-file nodes.conf \' \
    '  --cluster-node-timeout 5000 \' \
    '  --appendonly yes \' \
    '  --availability-zone "${VALKEY_AZ}"' \
    > /usr/local/bin/cluster-node.sh && \
    chmod +x /usr/local/bin/cluster-node.sh

ENTRYPOINT ["/usr/local/bin/cluster-node.sh"]
