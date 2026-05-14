#!/usr/bin/env sh
set -eu



docker rm -f auth_service_dev
docker rm -f auth_service_stage
docker rm -f auth_service_prod  

docker rmi auth_service:dev
docker rmi auth_service:stage
docker rmi auth_service:prod    

docker rmi auth_service:latest
docker build --no-cache -t auth_service:latest .

# DEV
docker build -t auth_service:dev .
docker run -d --name auth_service_dev --env-file .env.dev -p 6060:8080 --restart=always auth_service:dev
docker ps -a


# STAGE
docker build -t auth_service:stage .
docker run -d --name auth_service_stage --env-file .env.stage -p 6061:8080 --restart=always auth_service:stage
docker ps -a



# PRODUCTION
docker build -t auth_service:prod .
docker run -d --name auth_service_prod --env-file .env.prod -p 6062:8080 --restart=always auth_service:prod
docker ps -a

