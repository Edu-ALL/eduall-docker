FROM php:8.2-fpm-alpine

RUN apt-get update && apt-get install -y \
    curl \
    bash \
    libpng-dev \
    libjpeg-turbo8-dev \
    libwebp-dev \
    libfreetype6-dev \
    zip \
    unzip \
    nano \
    nodejs \
    npm \
    cron \
    && docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    && docker-php-ext-install pdo pdo_mysql bcmath gd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /eduall
COPY ./src /eduall/

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN chmod -R 777 storage/
RUN composer install

# CRON 
COPY ./cron/cronfile /etc/cron.d/cronfile
RUN echo "" >> /etc/cron.d/cronfile
RUN chmod 0644 /etc/cron.d/cronfile
RUN crontab /etc/cron.d/cronfile

EXPOSE 9000

CMD ["sh", "-c", "php-fpm"]