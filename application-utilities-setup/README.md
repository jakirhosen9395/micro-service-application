<p align="center">
  <img src="https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker Ready" />
  <img src="https://img.shields.io/badge/Elastic_APM-Enabled-005571?style=for-the-badge&logo=elastic&logoColor=white" alt="Elastic APM Enabled" />
  <img src="https://img.shields.io/badge/Databases-Postgres%20%7C%20MongoDB%20%7C%20Redis-blueviolet?style=for-the-badge" alt="Databases" />
  <img src="https://img.shields.io/badge/Infra-Kafka%20%7C%20RustFS%20%7C%20NGINX-success?style=for-the-badge" alt="Infrastructure" />
</p>

<h1 align="center">🚀 Dockerized Infrastructure Quickstart</h1>

<p align="center">
  A clean, production-friendly quickstart for bootstrapping Docker, Elastic APM, PostgreSQL, MongoDB, Redis, Kafka, RustFS, and NGINX Proxy Manager on a Linux host.
</p>

---

## 📚 Table of Contents

- [🧭 Overview](#-overview)
- [✅ Requirements](#-requirements)
- [🐳 Docker Host Setup](#-docker-host-setup)
- [📈 Elastic APM Setup](#-elastic-apm-setup)
- [🐘 PostgreSQL Setup](#-postgresql-setup)
- [🍃 MongoDB Setup](#-mongodb-setup)
- [⚡ Redis Setup](#-redis-setup)
- [🛰️ Kafka Setup](#️-kafka-setup)
- [🦀 RustFS Setup](#-rustfs-setup)
- [🌐 NGINX Proxy Manager Setup](#-nginx-proxy-manager-setup)
- [🛠️ Useful Docker Commands](#️-useful-docker-commands)
- [🔐 Security Notes](#-security-notes)
- [📖 References](#-references)

---

## 🧭 Overview

This README provides host-level setup commands and service bootstrap commands for a Docker Compose based infrastructure stack.

| Icon | Service | Purpose |
|---|---|---|
| 🐳 | Docker | Container runtime and Compose orchestration |
| 📈 | Elastic APM | Application performance monitoring and observability |
| 🐘 | PostgreSQL | Relational database |
| 🍃 | MongoDB | Document database |
| ⚡ | Redis | Cache, queue, and in-memory data store |
| 🛰️ | Kafka | Event streaming and messaging platform |
| 🦀 | RustFS | S3-compatible object storage |
| 🌐 | NGINX Proxy Manager | Reverse proxy, SSL, and domain routing |

> [!IMPORTANT]
> Run the service-specific commands from the directory that contains the relevant `docker-compose.yml` file.

---

## ✅ Requirements

Before starting, make sure the host has:

- A Linux server or VM.
- A user with `sudo` privileges.
- Internet access for package and image downloads.
- `curl`, `openssl`, and `nano` or another text editor.
- Enough disk space under `/opt/volumes` for persistent service data.

---

## 🐳 Docker Host Setup

Install Docker Engine and enable the Docker services on the host.

```bash
# Download Docker installation script
curl -fsSL https://get.docker.com -o get-docker.sh

# Install Docker
sudo sh get-docker.sh

# Create docker group if it does not already exist
sudo groupadd docker 2>/dev/null || true

# Add current user to docker group
sudo usermod -aG docker "$USER"

# Apply group changes for the current shell session
newgrp docker

# Enable Docker and containerd on boot
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
```

### ✅ Verify Docker

```bash
docker --version
docker compose version
docker run hello-world
```

---

## 📈 Elastic APM Setup

Clone the Elastic APM quickstart project, generate secure credentials, configure `.env`, and run the setup script.

### 1. Clone the Project

```bash
git clone https://github.com/siyamsarker/elastic-apm-quickstart.git
cd elastic-apm-quickstart
```

### 2. Create Environment File

```bash
cp .env.example .env
```

### 3. Generate Secure Values

Use the following commands to generate strong secrets.

```bash
# Generate Elasticsearch password
openssl rand -base64 24

# Generate Kibana password
openssl rand -base64 24

# Generate Kibana encryption key - exactly 32 characters
openssl rand -base64 32 | head -c 32

# Generate APM secret token
openssl rand -base64 24
```

### 4. Update `.env`

Open the `.env` file and replace every `changeme` value with a strong, unique value.

```bash
nano .env
```

> [!WARNING]
> Do not reuse the same password for Elasticsearch, Kibana, and the APM secret token.

### 5. Run APM Setup

```bash
# Make setup script executable
chmod +x setup.sh

# Normal setup
./setup.sh
```

### 6. Optional APM Maintenance Commands

```bash
# Clean installation - removes existing data and re-runs setup
./setup.sh --clean

# Remove containers and volumes only - no re-setup
./setup.sh --clean-only

# Check service status
./setup.sh --status

# Stop all services
./setup.sh --stop

# Show help
./setup.sh --help
```

### 7. Configure ILM Retention

```bash
# Make maintenance scripts executable
chmod +x ilm-15-day-retention.sh cleanup-old-indices.sh disk-usage-monitor.sh

# Apply 15-day ILM retention policy
./ilm-15-day-retention.sh
```

---

## 🐘 PostgreSQL Setup

Create the persistent PostgreSQL data directory, fix permissions, start the service, and follow logs.

```bash
sudo mkdir -p /opt/volumes/postgres/data

sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/postgres

sudo chmod -R 775 /opt/volumes/postgres

docker compose up -d --build

docker compose logs -f postgres
```

---

## 🍃 MongoDB Setup

Create the persistent MongoDB data directory, fix permissions, start the service, and follow logs.

```bash
sudo mkdir -p /opt/volumes/mongodb/data

sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/mongodb

sudo chmod -R 775 /opt/volumes/mongodb

docker compose up -d --build

docker compose logs -f mongodb
```

---

## ⚡ Redis Setup

Create the persistent Redis data directory, fix permissions, start the service, and follow logs.

```bash
sudo mkdir -p /opt/volumes/redis/data

sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/redis

sudo chmod -R 775 /opt/volumes/redis

docker compose up -d --build

docker compose logs -f redis
```

---

## 🛰️ Kafka Setup

Create the persistent Kafka data directory, fix permissions, start the service, and follow logs.

```bash
sudo mkdir -p /opt/volumes/kafka/data

sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/kafka

sudo chmod -R 775 /opt/volumes/kafka

docker compose up -d --build

docker compose logs -f kafka
```

---

## 🦀 RustFS Setup

Create RustFS persistent data and log directories, fix permissions, start the service, and follow logs.

```bash
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

docker compose logs -f rustfs
```

---

## 🌐 NGINX Proxy Manager Setup

Create persistent NGINX Proxy Manager directories, fix permissions, and start the service.

```bash
sudo mkdir -p /opt/volumes/npm/{data,letsencrypt}

sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/npm

sudo chmod -R 775 /opt/volumes/npm

docker compose up -d
```

### 🌍 Common Access Ports

| Port | Purpose |
|---:|---|
| `80` | Public HTTP |
| `443` | Public HTTPS |
| `81` | NGINX Proxy Manager admin UI |

> [!NOTE]
> Make sure ports `80`, `443`, and `81` are allowed by your firewall or cloud security group.

---

## 🛠️ Useful Docker Commands

### View Running Containers

```bash
docker ps
```

### View All Containers

```bash
docker ps -a
```

### Stop a Compose Stack

```bash
docker compose down
```

### Stop a Compose Stack and Remove Volumes

```bash
docker compose down -v
```

### Rebuild and Restart

```bash
docker compose up -d --build
```

### Follow Logs for a Service

```bash
docker compose logs -f <service-name>
```

Example:

```bash
docker compose logs -f postgres
```

### Check Disk Usage

```bash
docker system df
```

### Clean Unused Docker Resources

```bash
docker system prune -f
```

---

## 🔐 Security Notes

- 🔑 Replace all default credentials before exposing any service.
- 🚫 Never commit `.env` files to Git.
- 🧱 Restrict public access to database ports.
- 🔥 Use a firewall or cloud security group.
- 🔐 Use strong, unique passwords for every service.
- 🧾 Back up `/opt/volumes` regularly.
- 📦 Pin Docker image versions in production instead of using `latest`.
- 🧪 Test destructive commands such as `--clean`, `--clean-only`, and `docker compose down -v` in a non-production environment first.

---

## 📖 References

- 🐳 [Docker Engine Installation Guide](https://docs.docker.com/engine/install/)
- 📦 [Docker Compose Documentation](https://docs.docker.com/compose/)
- 📈 [Elastic APM Documentation](https://www.elastic.co/docs/solutions/observability/apm)
- 🐘 [PostgreSQL Official Docker Image](https://hub.docker.com/_/postgres)
- 🍃 [MongoDB Official Docker Image](https://hub.docker.com/_/mongo)
- ⚡ [Redis Official Docker Image](https://hub.docker.com/_/redis)
- 🛰️ [Apache Kafka Docker Image](https://hub.docker.com/r/apache/kafka)
- 🦀 [RustFS Docker Installation Guide](https://docs.rustfs.com/installation/docker/)
- 🌐 [NGINX Proxy Manager Setup Guide](https://nginxproxymanager.com/setup/)

---

<p align="center">
  <strong>Built for fast infrastructure bootstrap, clean service separation, and repeatable Docker-based deployments.</strong>
</p>