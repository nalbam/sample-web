# Dockerfile

FROM nginx:1.30-alpine

LABEL maintainer="me@nalbam.com" \
      org.opencontainers.image.description="A Sample Docker image for Nginx App" \
      org.opencontainers.image.authors="Jungyoul Yu, me@nalbam.com, https://www.nalbam.com/" \
      org.opencontainers.image.source="https://github.com/nalbam/sample-web" \
      org.opencontainers.image.title="sample-web"

# RUN apk add --no-cache bash curl

# The entrypoint renders /etc/nginx/templates/*.template into /etc/nginx/conf.d,
# substituting only PORT.
ENV PORT=8080 \
    NGINX_ENVSUBST_FILTER="^PORT\$"

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/templates /etc/nginx/templates

# Let the unprivileged nginx user (uid 101) write the rendered config.
RUN rm -f /etc/nginx/conf.d/default.conf \
 && chown -R 101:101 /etc/nginx/conf.d

COPY src /usr/share/nginx/html

EXPOSE 8080

USER 101
