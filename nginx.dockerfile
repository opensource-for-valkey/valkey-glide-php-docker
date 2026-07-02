FROM nginx:stable-alpine

ENV NGINXUSER=valkeyglide
ENV NGINXGROUP=valkeyglide

RUN mkdir -p /var/www/html/ /var/www/web/

ADD nginx/default.conf /etc/nginx/conf.d/default.conf
ADD nginx/web.conf /etc/nginx/conf.d/web.conf

RUN sed -i "s/user www-data/user ${NGINXUSER}/g" /etc/nginx/nginx.conf

RUN addgroup -g 1001 ${NGINXGROUP} && \
    adduser -u 1001 -G ${NGINXGROUP} -s /bin/sh -D ${NGINXUSER}
