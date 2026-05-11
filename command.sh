sudo rm -rf /opt/volumes || true

# APM Server, Elasticsearch, Kibana, and ILM setup
cd elastic-apm
sudo cp .env.example .env
chmod +x setup.sh
./setup.sh
chmod +x ilm-15-day-retention.sh cleanup-old-indices.sh disk-usage-monitor.sh
./ilm-15-day-retention.sh

# Postgres setup
cd ../postgres
sudo mkdir -p /opt/volumes/postgres/data
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/postgres
sudo chmod -R 775 /opt/volumes/postgres
docker compose up -d --build

# MongoDB setup
cd ../mongodb
sudo mkdir -p /opt/volumes/mongodb/data
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/mongodb
sudo chmod -R 775 /opt/volumes/mongodb
docker compose up -d --build

# Redis Setup
cd ../redis
sudo mkdir -p /opt/volumes/redis/data
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/redis
sudo chmod -R 775 /opt/volumes/redis
docker compose up -d --build



# Kafka Setup
cd ../kafka
sudo mkdir -p /opt/volumes/kafka/data
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/kafka
sudo chmod -R 775 /opt/volumes/kafka
docker compose up -d --build



# RustFS Setup
cd ../rustfs
sudo mkdir -p \
  /opt/volumes/rustfs/data/rustfs-data \
  /opt/volumes/rustfs/data/rustfs-logs
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" \
  /opt/volumes/rustfs/data/rustfs-data \
  /opt/volumes/rustfs/data/rustfs-logs
sudo chmod -R 775 \
  /opt/volumes/rustfs/data/rustfs-data \
  /opt/volumes/rustfs/data/rustfs-logs
docker compose up -d --build

cd ..
docker ps -a



















# APM Server, Elasticsearch, Kibana, and ILM setup
cd elastic-apm
./setup.sh --stop

# Postgres setup
cd ../postgres
docker compose down -v

# MongoDB setup
cd ../mongodb
docker compose down -v


# Redis Setup
cd ../redis
docker compose down -v



# Kafka Setup
cd ../kafka
docker compose down -v



# RustFS Setup
cd ../rustfs
docker compose down -v
cd ..