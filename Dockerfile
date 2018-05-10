# Dockerfile

FROM nginx:latest

MAINTAINER me@nalbam.com

ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

EXPOSE 80

ADD index.html /usr/share/nginx/html/
