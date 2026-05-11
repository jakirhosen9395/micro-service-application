```bash
# -------------------------------------------------
# Host prerequisites (run on host before starting)
# -------------------------------------------------  
sudo mkdir -p /opt/volumes/mongodb/data && sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/mongodb && sudo chmod -R 775 /opt/volumes/mongodb && docker compose up -d --build
docker logs -f mongodb
```
