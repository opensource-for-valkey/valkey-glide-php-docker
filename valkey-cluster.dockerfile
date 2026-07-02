FROM valkey/valkey:9-alpine

ARG VALKEY_PORT=7000

ENV VALKEYUSER=valkeyglide
ENV VALKEYGROUP=valkeyglide

RUN addgroup -g 1000 ${VALKEYGROUP} && \
    adduser -u 1000 -G ${VALKEYGROUP} -s /bin/sh -D ${VALKEYUSER}

CMD ["sh", "-c", "valkey-server --port ${VALKEY_PORT} --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 5000 --appendonly yes"]
