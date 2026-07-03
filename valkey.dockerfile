FROM valkey/valkey:9-alpine

ENV VALKEYUSER=valkeyglide
ENV VALKEYGROUP=valkeyglide

RUN addgroup -g 1001 ${VALKEYGROUP} && \
    adduser -u 1001 -G ${VALKEYGROUP} -s /bin/sh -D ${VALKEYUSER}

CMD ["valkey-server", "--io-threads", "4", "--io-threads-do-reads", "yes", "--maxmemory", "250mb"]