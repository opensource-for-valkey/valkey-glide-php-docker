FROM valkey/valkey:8.1

ENV VALKEYUSER=aluna
ENV VALKEYGROUP=aluna

# RUN adduser -g ${VALKEYGROUP} -s /bin/sh -D ${VALKEYUSER}
RUN groupadd -g 1000 ${VALKEYGROUP} && \
    useradd -r -u 1000 -g ${VALKEYGROUP} ${VALKEYUSER}