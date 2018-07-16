# Dockerfile

FROM nginx:latest

ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

EXPOSE 80

COPY src /usr/share/nginx/html
