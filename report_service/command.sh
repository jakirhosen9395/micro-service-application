#!/usr/bin/env sh
set -eu

# Idempotent cleanup. Missing containers/images must not fail the whole script.
docker rm -f report_service_dev 2>/dev/null || true
docker rm -f report_service_stage 2>/dev/null || true
docker rm -f report_service_prod 2>/dev/null || true

docker rmi report_service:dev 2>/dev/null || true
docker rmi report_service:stage 2>/dev/null || true
docker rmi report_service:prod 2>/dev/null || true
docker rmi report_service:latest 2>/dev/null || true

docker build --no-cache -t report_service:latest .

# DEV
docker build -t report_service:dev .
docker run -d --name report_service_dev --env-file .env.dev -p 5050:8080 report_service:dev
docker ps -a

# STAGE
docker build -t report_service:stage .
docker run -d --name report_service_stage --env-file .env.stage -p 5051:8080 report_service:stage
docker ps -a

# PRODUCTION
docker build -t report_service:prod .
docker run -d --name report_service_prod --env-file .env.prod -p 5052:8080 report_service:prod
docker ps -a
