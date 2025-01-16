FROM nginx:stable

RUN apt-get update && apt-get install -y \
    cron \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

# CRON 
COPY ./cron/eduall_cron /etc/eduall_cron

RUN chmod 0644 /etc/eduall_cron

CMD ["sh", "-c", "cron && nginx -g 'daemon off;'"]

EXPOSE 80