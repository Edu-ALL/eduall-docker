FROM nginx:stable

RUN apt-get update && apt-get install -y \
    procps \
    cron \
    bash \
    nano \
    php-fpm \
    php-cli \
    && rm -rf /var/lib/apt/lists/*

# CRON 
COPY ./cron/cronfile /etc/cron.d/cronfile
RUN echo "" >> /etc/cron.d/cronfile
RUN chmod 0644 /etc/cron.d/cronfile
RUN crontab /etc/cron.d/cronfile

RUN service cron reload

CMD cron && nginx -g 'daemon off;'
# CMD ["cron && nginx -g 'daemon off;'" "-f"]

EXPOSE 80