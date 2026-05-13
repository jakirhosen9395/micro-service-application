#!/usr/bin/env sh
set -eu

docker rm -f user_service_dev || true
docker rm -f user_service_stage || true
docker rm -f user_service_prod || true

docker rmi user_service:dev || true
docker rmi user_service:stage || true
docker rmi user_service:prod || true
docker rmi user_service:latest || true

docker build --no-cache -t user_service:latest .

# DEV
docker build -t user_service:dev .
docker run -d --name user_service_dev --env-file .env.dev -p 4040:8080 user_service:dev
docker ps -a

# STAGE
docker build -t user_service:stage .
docker run -d --name user_service_stage --env-file .env.stage -p 4041:8080 user_service:stage
docker ps -a

# PRODUCTION
docker build -t user_service:prod .
docker run -d --name user_service_prod --env-file .env.prod -p 4042:8080 user_service:prod
docker ps -a
