#!/usr/bin/env sh
set -eu



docker rm -f admin_service_dev
docker rm -f admin_service_stage
docker rm -f admin_service_prod  

docker rmi admin_service:dev
docker rmi admin_service:stage
docker rmi admin_service:prod    

docker rmi admin_service:latest
docker build --no-cache -t admin_service:latest .

# DEV
docker build -t admin_service:dev .
docker run -d --name admin_service_dev --env-file .env.dev -p 1010:8080 admin_service:dev
docker ps -a


# STAGE
docker build -t admin_service:stage .
docker run -d --name admin_service_stage --env-file .env.stage -p 1011:8080 admin_service:stage
docker ps -a



# PRODUCTION
docker build -t admin_service:prod .
docker run -d --name admin_service_prod --env-file .env.prod -p 1012:8080 admin_service:prod
docker ps -a
