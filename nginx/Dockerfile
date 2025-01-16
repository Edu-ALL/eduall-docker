FROM nginx:alpine

RUN apk update && \
    apk add --no-cache \
    bash \
    cron \
    && rm -rf /var/cache/apk/*

# CRON 
COPY ./cron/eduall_cron /etc/cron.d/eduall_cron

RUN chmod 0644 /etc/cron.d/eduall_cron

RUN crontab /etc/cron.d/eduall_cron

EXPOSE 80

CMD crond && nginx -g "daemon off;"