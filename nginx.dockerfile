FROM nginx:stable

ENV NGINXUSER=aluna
ENV NGINXGROUP=aluna

RUN mkdir -p /var/www/html/

ADD nginx/default.conf /etc/nginx/conf.d/default.conf

RUN sed -i "s/user www-data/user ${NGINXUSER}/g" /etc/nginx/nginx.conf

RUN groupadd -g 1000 ${NGINXGROUP} && \
    useradd -r -u 1000 -g ${NGINXGROUP} ${NGINXUSER}