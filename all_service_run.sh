###############################################################################################################################################
# ADMIN SERVICE
###############################################################################################################################################
cd ./admin_service
docker rm -f admin_service_dev 2>/dev/null || true
docker rm -f admin_service_stage 2>/dev/null || true
docker rm -f admin_service_prod 2>/dev/null || true

docker rmi admin_service:dev 2>/dev/null || true
docker rmi admin_service:stage 2>/dev/null || true
docker rmi admin_service:prod 2>/dev/null || true

docker rmi admin_service:latest 2>/dev/null || true
docker build --no-cache -t admin_service:latest .

# DEV
docker build -t admin_service:dev .
docker run -d --name admin_service_dev --env-file .env.dev -p 1010:8080  --restart=always admin_service:dev
docker ps -a


# STAGE
docker build -t admin_service:stage .
docker run -d --name admin_service_stage --env-file .env.stage -p 1011:8080  --restart=always admin_service:stage
docker ps -a



# PRODUCTION
docker build -t admin_service:prod .
docker run -d --name admin_service_prod --env-file .env.prod -p 1012:8080  --restart=always admin_service:prod
docker ps -a

##############################################################################################################################################
# CALCULATOR SERVICE
###############################################################################################################################################
cd ./calculator_service
docker rm -f calculator_service_dev 2>/dev/null || true
docker rm -f calculator_service_stage 2>/dev/null || true
docker rm -f calculator_service_prod 2>/dev/null || true

docker rmi calculator_service:dev 2>/dev/null || true
docker rmi calculator_service:stage 2>/dev/null || true
docker rmi calculator_service:prod 2>/dev/null || true
docker rmi calculator_service:latest 2>/dev/null || true

docker build --no-cache -t calculator_service:latest .

# DEV
docker build -t calculator_service:dev .
docker run -d --name calculator_service_dev --env-file .env.dev -p 2020:8080  --restart=always calculator_service:dev
docker ps -a

# STAGE
docker build -t calculator_service:stage .
docker run -d --name calculator_service_stage --env-file .env.stage -p 2021:8080  --restart=always calculator_service:stage
docker ps -a

# PRODUCTION
docker build -t calculator_service:prod .
docker run -d --name calculator_service_prod --env-file .env.prod -p 2022:8080  --restart=always calculator_service:prod
docker ps -a

###############################################################################################################################################
# TODO LIST SERVICE
###############################################################################################################################################
cd ./todo_list_service
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
docker run -d --name todo_list_service_dev --env-file .env.dev -p 3030:8080  --restart=always todo_list_service:dev
docker ps -a


# STAGE
docker build -t todo_list_service:stage .
docker run -d --name todo_list_service_stage --env-file .env.stage -p 3031:8080  --restart=always todo_list_service:stage
docker ps -a



# PRODUCTION
docker build -t todo_list_service:prod .
docker run -d --name todo_list_service_prod --env-file .env.prod -p 3032:8080  --restart=always todo_list_service:prod
docker ps -a

###############################################################################################################################################
# USER SERVICE
###############################################################################################################################################
cd ./user_service
docker rm -f user_service_dev 2>/dev/null || true
docker rm -f user_service_stage 2>/dev/null || true
docker rm -f user_service_prod 2>/dev/null || true

docker rmi user_service:dev 2>/dev/null || true
docker rmi user_service:stage 2>/dev/null || true
docker rmi user_service:prod 2>/dev/null || true
docker rmi user_service:latest 2>/dev/null || true

docker build --no-cache -t user_service:latest .

# DEV
docker build -t user_service:dev .
docker run -d --name user_service_dev --env-file .env.dev -p 4040:8080  --restart=always user_service:dev
docker ps -a

# STAGE
docker build -t user_service:stage .
docker run -d --name user_service_stage --env-file .env.stage -p 4041:8080  --restart=always user_service:stage
docker ps -a

# PRODUCTION
docker build -t user_service:prod .
docker run -d --name user_service_prod --env-file .env.prod -p 4042:8080  --restart=always user_service:prod
docker ps -a

###############################################################################################################################################
# REPORT SERVICE
###############################################################################################################################################
cd ./report_service
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
docker run -d --name report_service_dev --env-file .env.dev -p 5050:8080  --restart=always report_service:dev
docker ps -a

# STAGE
docker build -t report_service:stage .
docker run -d --name report_service_stage --env-file .env.stage -p 5051:8080  --restart=always report_service:stage
docker ps -a

# PRODUCTION
docker build -t report_service:prod .
docker run -d --name report_service_prod --env-file .env.prod -p 5052:8080  --restart=always report_service:prod
docker ps -a

#############################################################################################################################################
#  AUTH SERVICE 
#############################################################################################################################################
cd ./auth_service
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
docker run -d --name auth_service_dev --env-file .env.dev -p 6060:8080  --restart=always auth_service:dev
docker ps -a


# STAGE
docker build -t auth_service:stage .
docker run -d --name auth_service_stage --env-file .env.stage -p 6061:8080  --restart=always auth_service:stage
docker ps -a



# PRODUCTION
docker build -t auth_service:prod .
docker run -d --name auth_service_prod --env-file .env.prod -p 6062:8080  --restart=always auth_service:prod
docker ps -a

