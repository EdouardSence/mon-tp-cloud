#!/bin/sh
# Inject backend URLs (from env) into a browser-readable config.js at startup.
set -e
envsubst '${TASK_API_URL} ${AUTH_API_URL}' \
  < /etc/nginx/config.js.template \
  > /usr/share/nginx/html/config.js
