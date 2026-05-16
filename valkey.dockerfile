FROM valkey/valkey:9-alpine

ARG MODE=cluster

ENV VALKEYUSER=laravel
ENV VALKEYGROUP=laravel
ENV MODE=${MODE}

RUN addgroup -g 1001 ${VALKEYGROUP} && \
    adduser -u 1001 -G ${VALKEYGROUP} -s /bin/sh -D ${VALKEYUSER}

COPY valkey_entrypoint.sh /valkey_entrypoint.sh
RUN chmod +x /valkey_entrypoint.sh

ENTRYPOINT ["/valkey_entrypoint.sh"]
