# Dockerfile

FROM nginx:latest

ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

EXPOSE 80

ADD index.html /usr/share/nginx/html/
ADD favicon.ico /usr/share/nginx/html/
