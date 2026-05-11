```bash
sudo mkdir -p /opt/volumes/npm/{data,letsencrypt} && sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /opt/volumes/npm && sudo chmod -R 775 /opt/volumes/npm && docker compose up -d
```
