#!/bin/sh
envsubst '${ACTIVE_POOL}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
exec nginx -g 'daemon off;'


