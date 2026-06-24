FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY config.js.template /etc/nginx/config.js.template

# The nginx image runs every /docker-entrypoint.d/*.sh on startup; this one
# envsubst's the backend URLs into a browser-readable config.js.
COPY docker-entrypoint.d/40-config-js.sh /docker-entrypoint.d/40-config-js.sh
RUN chmod +x /docker-entrypoint.d/40-config-js.sh

EXPOSE 80
