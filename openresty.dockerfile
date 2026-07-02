FROM openresty/openresty:alpine

# OpenResty is nginx + LuaJIT; it reads /etc/nginx/conf.d/*.conf vhosts.
# It has its own config folder (openresty/) so it can diverge from the
# stock nginx configs without affecting them.

ENV NGINXUSER=valkeyglide
ENV NGINXGROUP=valkeyglide

RUN mkdir -p /var/www/html/ /var/www/web/

# OpenResty ships its own default.conf; drop it and use our vhosts.
RUN rm -f /etc/nginx/conf.d/default.conf

ADD openresty/default.conf /etc/nginx/conf.d/default.conf
ADD openresty/web.conf /etc/nginx/conf.d/web.conf

RUN addgroup -g 1001 ${NGINXGROUP} && \
    adduser -u 1001 -G ${NGINXGROUP} -s /bin/sh -D ${NGINXUSER}

# Run workers as the valkeyglide user (directive is commented out by default).
RUN sed -i "s/#user  nobody;/user ${NGINXUSER};/" /usr/local/openresty/nginx/conf/nginx.conf
