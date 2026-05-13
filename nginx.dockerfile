FROM nginx:stable-alpine

ENV NGINXUSER=laravel
ENV NGINXGROUP=laravel

RUN mkdir -p /var/www/html/

ADD nginx/default.conf /etc/nginx/conf.d/default.conf

RUN sed -i "s/user www-data/user ${NGINXUSER}/g" /etc/nginx/nginx.conf

RUN addgroup -g 1001 ${NGINXGROUP} && \
    adduser -u 1001 -G ${NGINXGROUP} -s /bin/sh -D ${NGINXUSER}
