#!/usr/bin/env sh
set -eu


docker rm -f todo_list_service_dev 2>/dev/null || true
docker rm -f todo_list_service_stage 2>/dev/null || true
docker rm -f todo_list_service_prod 2>/dev/null || true

docker rmi todo_list_service:dev 2>/dev/null || true
docker rmi todo_list_service:stage 2>/dev/null || true
docker rmi todo_list_service:prod 2>/dev/null || true

docker rmi todo_list_service:latest 2>/dev/null || true
docker build --no-cache -t todo_list_service:latest .

# DEV
docker build -t todo_list_service:dev .
docker run -d --name todo_list_service_dev --env-file .env.dev -p 3030:8080 --restart=always todo_list_service:dev
docker ps -a


# STAGE
docker build -t todo_list_service:stage .
docker run -d --name todo_list_service_stage --env-file .env.stage -p 3031:8080 --restart=always todo_list_service:stage
docker ps -a



# PRODUCTION
docker build -t todo_list_service:prod .
docker run -d --name todo_list_service_prod --env-file .env.prod -p 3032:8080 --restart=always todo_list_service:prod
docker ps -a
