```bash
# -------------------------------------------------
# Host prerequisites (run on host before starting)
# -------------------------------------------------  
sudo mkdir -p /opt/volumes/postgres/data && sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/postgres && sudo chmod -R 775 /opt/volumes/postgres && docker compose up -d --build
docker logs -f postgres
```
