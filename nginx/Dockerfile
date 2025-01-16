FROM nginx:stable

RUN apt-get update && apt-get install -y \
    procps \
    cron \
    bash \
    nano \
    && rm -rf /var/lib/apt/lists/*

# CRON 
COPY ./cron/cronfile /etc/cron.d/cronfile
RUN chmod 0644 /etc/cron.d/crontab
RUN crontab /etc/cron.d/cronfile

CMD ["cron && nginx -g 'daemon off;'" "-f"]

EXPOSE 80