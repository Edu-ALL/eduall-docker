FROM nginx:stable

RUN apt-get update && apt-get install -y \
    procps \
    brotli \
    cron \
    bash \
    nano \
    nodejs \
    npm \
    php-fpm \
    php-cli \
    php-pdo \
    php-mysql \
    php-xml \
    php-bcmath \
    php-gd\
    php-mbstring\
    && rm -rf /var/lib/apt/lists/*

# CRON 
COPY ./cron/cronfile /etc/cron.d/cronfile
RUN echo "" >> /etc/cron.d/cronfile
RUN chmod 0644 /etc/cron.d/cronfile
# RUN touch /etc/cron.d/cronfile
RUN crontab /etc/cron.d/cronfile

RUN service cron reload

# CMD cron && nginx -g 'daemon off;'
CMD ["cron && nginx -g 'daemon off;'" "-f"]

EXPOSE 80