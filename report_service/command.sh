#!/usr/bin/env sh
set -eu

docker rmi report_service:latest 2>/dev/null || true
docker build --no-cache -t report_service:latest .
docker images | grep report_service 2>/dev/null || true


# DEV
docker rm -f report_service_dev 2>/dev/null || true
docker rmi report_service:dev 2>/dev/null || true
docker build -t report_service:dev .
docker run -d --name report_service_dev --env-file .env.dev -p 5050:8080  --restart=always report_service:dev
docker ps -a

# STAGE
docker rm -f report_service_stage 2>/dev/null || true
docker rmi report_service:stage 2>/dev/null || true
docker build -t report_service:stage .
docker run -d --name report_service_stage --env-file .env.stage -p 5051:8080  --restart=always report_service:stage
docker ps -a

# PRODUCTION
docker rm -f report_service_prod 2>/dev/null || true
docker rmi report_service:prod 2>/dev/null || true
docker build -t report_service:prod .
docker run -d --name report_service_prod --env-file .env.prod -p 5052:8080  --restart=always report_service:prod
docker ps -a

