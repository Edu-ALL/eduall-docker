FROM php:8.2-fpm-alpine

RUN apk add --no-cache \
    curl \
    bash \
    libpng-dev \
    libjpeg-turbo-dev \
    libwebp-dev \
    freetype-dev \
    libzip-dev \
    zip \
    unzip \
    nano \
    nodejs \
    npm \
    && docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    && docker-php-ext-install pdo pdo_mysql bcmath gd zip

WORKDIR /editing

COPY ./src /editing/
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN composer install
RUN chmod -R 777 storage/

COPY php.ini /etc/php7/conf.d/

EXPOSE 9000

CMD ["sh", "-c", "php-fpm"]