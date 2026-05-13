FROM valkey/valkey:9-alpine

ENV VALKEYUSER=laravel
ENV VALKEYGROUP=laravel

RUN addgroup -g 1001 ${VALKEYGROUP} && \
    adduser -u 1001 -G ${VALKEYGROUP} -s /bin/sh -D ${VALKEYUSER}