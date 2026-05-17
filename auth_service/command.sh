#!/usr/bin/env sh
set -eu

docker rmi auth_service:latest 2>/dev/null || true
docker build --no-cache -t auth_service:latest .
docker images | grep auth_service 2>/dev/null || true

# DEV
docker rm -f auth_service_dev 2>/dev/null || true
docker rmi auth_service:dev 2>/dev/null || true
docker build -t auth_service:dev .
docker run -d --name auth_service_dev --env-file .env.dev -p 6060:8080  --restart=always auth_service:dev
docker ps -a


# STAGE
docker rm -f auth_service_stage 2>/dev/null || true
docker rmi auth_service:stage 2>/dev/null || true
docker build -t auth_service:stage .
docker run -d --name auth_service_stage --env-file .env.stage -p 6061:8080  --restart=always auth_service:stage
docker ps -a

# PRODUCTION
docker rm -f auth_service_prod 2>/dev/null || true
docker rmi auth_service:prod 2>/dev/null || true
docker build -t auth_service:prod .
docker run -d --name auth_service_prod --env-file .env.prod -p 6062:8080  --restart=always auth_service:prod
docker ps -a

