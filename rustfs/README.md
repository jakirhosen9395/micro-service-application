```bash
      
# -------------------------------------------------
# Host prerequisites (run on host before starting)
# ------------------------------------------------- 
sudo mkdir -p /opt/volumes/rustfs/data/rustfs-data /opt/volumes/rustfs/data/rustfs-logs && sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/rustfs/data/rustfs-data /opt/volumes/rustfs/data/rustfs-logs && sudo chmod -R 775 /opt/volumes/rustfs/data/rustfs-data /opt/volumes/rustfs/data/rustfs-logs && docker compose up -d --build
docker logs -f rustfs
```
