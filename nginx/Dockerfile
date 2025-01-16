FROM nginx:stable

RUN apt-get update && apt-get install -y \
    procps \
    cron \
    bash \
    && rm -rf /var/lib/apt/lists/*

# CRON 
COPY ./cron/crontab /etc/crontab

RUN chmod 0644 /etc/crontab

RUN crontab /etc/crontab

CMD ["sh", "-c", "cron && nginx -g 'daemon off;'"]

EXPOSE 80