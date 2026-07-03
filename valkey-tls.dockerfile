FROM valkey/valkey:9-alpine

# TLS-enabled standalone Valkey. The server listens ONLY on the TLS port
# (--port 0 disables the plaintext port). Certificates are provided at
# runtime by mounting the ./certs directory to /etc/certs (see the
# `valkey-tls` service in docker-compose.yml). Generate them first with
# `./certs/gen-test-certs.sh`.
#
# --tls-auth-clients no: the server encrypts the connection but does NOT
# require clients to present a certificate, so a GLIDE client only needs
# `use_tls: true` (+ the CA) — no mutual-TLS setup. Flip to `yes` and hand
# clients client.crt/client.key for mutual TLS.

ENV VALKEYUSER=valkeyglide
ENV VALKEYGROUP=valkeyglide

RUN addgroup -g 1001 ${VALKEYGROUP} && \
    adduser -u 1001 -G ${VALKEYGROUP} -s /bin/sh -D ${VALKEYUSER}

CMD ["valkey-server", \
     "--tls-port", "6379", \
     "--port", "0", \
     "--tls-cert-file", "/etc/certs/server.crt", \
     "--tls-key-file", "/etc/certs/server.key", \
     "--tls-ca-cert-file", "/etc/certs/ca.crt", \
     "--tls-auth-clients", "no", \
     "--io-threads", "4", \
     "--io-threads-do-reads", "yes", \
     "--maxmemory", "250mb"]
