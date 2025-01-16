FROM nginx:alpine

RUN apk update && apk add --no-cache \
    curl \
    bash \
    && rm -rf /var/cache/apk/*

RUN curl -O http://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/cron-3.0.1-r0.apk && \
    apk add --allow-untrusted cron-3.0.1-r0.apk && \
    rm cron-3.0.1-r0.apk

# CRON 
COPY ./cron/eduall_cron /etc/eduall_cron

RUN chmod 0644 /etc/eduall_cron

RUN crontab /etc/eduall_cron

CMD ["sh", "-c", "crond && nginx -g 'daemon off;'"]

EXPOSE 80