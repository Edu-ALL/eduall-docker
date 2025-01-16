FROM nginx:stable

RUN apt-get update && apt-get install -y \
    procps \
    cron \
    bash \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Install PHP and required extensions
RUN apt-get update && apt-get install -y \
    php-fpm \
    php-cli \
    php-mbstring \
    php-xml \
    php-curl \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    && docker-php-ext-install pdo pdo_mysql bcmath gd

# CRON 
COPY ./cron/cronfile /etc/cron.d/cronfile
RUN echo "" >> /etc/cron.d/cronfile
RUN chmod 0644 /etc/cron.d/cronfile
RUN crontab /etc/cron.d/cronfile

RUN service cron reload

CMD cron && nginx -g 'daemon off;'
# CMD ["cron && nginx -g 'daemon off;'" "-f"]

EXPOSE 80