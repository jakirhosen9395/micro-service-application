```bash

# -------------------------------------------------
# Host prerequisites (run on host before starting)
# -------------------------------------------------  
sudo mkdir -p /opt/volumes/kafka/data && sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/kafka && sudo chmod -R 775 /opt/volumes/kafka && docker compose up -d --build
docker logs -f kafka
```
