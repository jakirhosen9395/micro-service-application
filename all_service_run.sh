###############################################################################################################################################
# ADMIN SERVICE
###############################################################################################################################################
cd admin_service

docker rmi admin_service:latest 2>/dev/null || true
docker build --no-cache -t admin_service:latest .
docker images | grep admin_service
cd ..

##############################################################################################################################################
# CALCULATOR SERVICE
###############################################################################################################################################

cd calculator_service

docker rmi calculator_service:latest 2>/dev/null || true
docker build --no-cache -t calculator_service:latest .
docker images | grep calculator_service 2>/dev/null || true
cd ..

###############################################################################################################################################
# TODO LIST SERVICE
###############################################################################################################################################
cd todo_list_service

docker rmi todo_list_service:latest 2>/dev/null || true
docker build --no-cache -t todo_list_service:latest .
docker images | grep todo_list_service 2>/dev/null || true
cd ..

###############################################################################################################################################
# USER SERVICE
###############################################################################################################################################
cd user_service

docker rmi user_service:latest 2>/dev/null || true
docker build --no-cache -t user_service:latest .
docker images | grep user_service 2>/dev/null || true
cd ..

###############################################################################################################################################
# REPORT SERVICE
###############################################################################################################################################
cd report_service

docker rmi report_service:latest 2>/dev/null || true
docker build --no-cache -t report_service:latest .
docker images | grep report_service 2>/dev/null || true
cd ..

#############################################################################################################################################
#  AUTH SERVICE 
#############################################################################################################################################
cd auth_service

docker rmi auth_service:latest 2>/dev/null || true
docker build --no-cache -t auth_service:latest .
docker images | grep auth_service 2>/dev/null || true
cd ..

docker images

###############################################################################################################################################
# ADMIN SERVICE
###############################################################################################################################################
cd admin_service

# DEV
docker rm -f admin_service_dev 2>/dev/null || true
docker rmi admin_service:dev 2>/dev/null || true
docker build -t admin_service:dev .
docker run -d --name admin_service_dev --env-file .env.dev -p 1010:8080  --restart=always admin_service:dev
docker ps -a

# STAGE
docker rm -f admin_service_stage 2>/dev/null || true
docker rmi admin_service:stage 2>/dev/null || true
docker build -t admin_service:stage .
docker run -d --name admin_service_stage --env-file .env.stage -p 1011:8080  --restart=always admin_service:stage
docker ps -a

# PRODUCTION
docker rm -f admin_service_prod 2>/dev/null || true
docker rmi admin_service:prod 2>/dev/null || true
docker build -t admin_service:prod .
docker run -d --name admin_service_prod --env-file .env.prod -p 1012:8080  --restart=always admin_service:prod
docker ps -a

cd ..


##############################################################################################################################################
# CALCULATOR SERVICE
###############################################################################################################################################
cd calculator_service

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

cd ..


###############################################################################################################################################
# TODO LIST SERVICE
###############################################################################################################################################
cd todo_list_service


# DEV
docker rm -f todo_list_service_dev 2>/dev/null || true
docker rmi todo_list_service:dev 2>/dev/null || true
docker build -t todo_list_service:dev .
docker run -d --name todo_list_service_dev --env-file .env.dev -p 3030:8080  --restart=always todo_list_service:dev
docker ps -a

# STAGE
docker rm -f todo_list_service_stage 2>/dev/null || true
docker rmi todo_list_service:stage 2>/dev/null || true
docker build -t todo_list_service:stage .
docker run -d --name todo_list_service_stage --env-file .env.stage -p 3031:8080  --restart=always todo_list_service:stage
docker ps -a

# PRODUCTION
docker rm -f todo_list_service_prod 2>/dev/null || true
docker rmi todo_list_service:prod 2>/dev/null || true
docker build -t todo_list_service:prod .
docker run -d --name todo_list_service_prod --env-file .env.prod -p 3032:8080  --restart=always todo_list_service:prod
docker ps -a
cd ..

###############################################################################################################################################
# USER SERVICE
###############################################################################################################################################
cd user_service

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

cd ..

###############################################################################################################################################
# REPORT SERVICE
###############################################################################################################################################
cd report_service

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
cd ..


#############################################################################################################################################
#  AUTH SERVICE 
#############################################################################################################################################
cd auth_service


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


cd ..

watch docker ps -a

