# syntax=docker/dockerfile:1

# build: runs the tests on the build platform and writes the site to /out.
FROM --platform=$BUILDPLATFORM nginx:1.31-alpine AS build
RUN apk add --no-cache bash openssl
WORKDIR /src
COPY nginx nginx
COPY src src
COPY test test
RUN sh test/runtime.sh && bash test/content.sh && cp -R src /out

# artifact: the release artifact, exported by scripts/release.sh artifact.
FROM scratch AS artifact
COPY --from=build /out /

FROM nginx:1.31-alpine

LABEL org.opencontainers.image.title="sample-web" \
      org.opencontainers.image.description="A sample static site on Nginx" \
      org.opencontainers.image.source="https://github.com/nalbam/sample-web"

ARG VERSION=v0.0.0-dev

# The image entrypoint renders /etc/nginx/templates/*.template into
# /etc/nginx/conf.d and substitutes only PORT and VERSION.
ENV PORT=8080 \
    VERSION=${VERSION} \
    NGINX_ENVSUBST_FILTER="^(PORT|VERSION)$"

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/templates /etc/nginx/templates

# The unprivileged nginx user (uid 101) writes the rendered config.
RUN rm -f /etc/nginx/conf.d/default.conf \
 && chown -R 101:101 /etc/nginx/conf.d

COPY --from=artifact / /usr/share/nginx/html/

USER 101

EXPOSE 8080
