#!/usr/bin/env sh
set -eu

docker rmi calculator_service:latest 2>/dev/null || true
docker build --no-cache -t calculator_service:latest .
docker images | grep calculator_service 2>/dev/null || true

# DEV
docker rm -f calculator_service_dev 2>/dev/null || true
docker rmi calculator_service:dev 2>/dev/null || true
docker build -t calculator_service:dev .
docker run -d --name calculator_service_dev --env-file .env.dev -p 2020:8080  --restart=always calculator_service:dev
docker ps -a    

# STAGE
docker rm -f calculator_service_stage 2>/dev/null || true
docker rmi calculator_service:stage 2>/dev/null || true
docker build -t calculator_service:stage .
docker run -d --name calculator_service_stage --env-file .env.stage -p 2021:8080  --restart=always calculator_service:stage
docker ps -a

# PRODUCTION
docker rm -f calculator_service_prod 2>/dev/null || true
docker rmi calculator_service:prod 2>/dev/null || true
docker build -t calculator_service:prod .
docker run -d --name calculator_service_prod --env-file .env.prod -p 2022:8080  --restart=always calculator_service:prod
docker ps -a

