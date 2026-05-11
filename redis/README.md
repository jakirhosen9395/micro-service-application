```bash
# -------------------------------------------------
# Host prerequisites (run on host before starting)
# -------------------------------------------------   
sudo mkdir -p /opt/volumes/redis/data && sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/redis && sudo chmod -R 775 /opt/volumes/redis && docker compose up -d --build
docker logs -f redis
```
