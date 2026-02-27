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
    oniguruma-dev \
    && docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp \
    && docker-php-ext-install pdo pdo_mysql bcmath gd zip mbstring

WORKDIR /helpdesk

COPY ./src /helpdesk/

EXPOSE 9000

CMD ["sh", "-c", "php-fpm"]