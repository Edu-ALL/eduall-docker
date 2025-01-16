FROM nginx:alpine

RUN apk update && apk add --no-cache cron bash

# NGINX CONFIGURATION 
COPY ./nginx/default.conf /etc/nginx/conf.d/default.conf
COPY /etc/letsencrypt/live/all-inedu.com/fullchain.pem /etc/letsencrypt/live/all-inedu.com/fullchain.pem
COPY /etc/letsencrypt/live/all-inedu.com/privkey.pem /etc/letsencrypt/live/all-inedu.com/privkey.pem

# WEB FOLDER 
COPY ./eduall/src /eduall
COPY ./registration/src /registration
COPY ./junior/src /junior


# CRON 
COPY ./nginx/cron/eduall_cron /etc/cron.d/eduall_cron

RUN chmod 0644 /etc/cron.d/eduall_cron

RUN crontab /etc/cron.d/eduall_cron

EXPOSE 80

CMD crond && nginx -g "daemon off;"