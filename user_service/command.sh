#!/usr/bin/env sh
set -eu


docker rmi user_service:latest 2>/dev/null || true
docker build --no-cache -t user_service:latest .
docker images | grep user_service 2>/dev/null || true

# DEV
docker rm -f user_service_dev 2>/dev/null || true
docker rmi user_service:dev 2>/dev/null || true
docker build -t user_service:dev .
docker run -d --name user_service_dev --env-file .env.dev -p 4040:8080  --restart=always user_service:dev
docker ps -a

# STAGE
docker rm -f user_service_stage 2>/dev/null || true
docker rmi user_service:stage 2>/dev/null || true
docker build -t user_service:stage .
docker run -d --name user_service_stage --env-file .env.stage -p 4041:8080  --restart=always user_service:stage
docker ps -a

# PRODUCTION
docker rm -f user_service_prod 2>/dev/null || true
docker rmi user_service:prod 2>/dev/null || true
docker build -t user_service:prod .
docker run -d --name user_service_prod --env-file .env.prod -p 4042:8080  --restart=always user_service:prod
docker ps -a

