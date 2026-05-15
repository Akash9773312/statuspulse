#!/bin/bash

set -e

cd /opt/statuspulse

sudo systemctl stop caddy 2>/dev/null || true
sudo systemctl disable caddy 2>/dev/null || true

sudo docker-compose down --remove-orphans 2>/dev/null || true

for port in 80 443 3001; do
  ids=$(sudo docker ps -q --filter "publish=${port}" 2>/dev/null || true)
  if [ -n "$ids" ]; then
    sudo docker stop $ids
    sudo docker rm $ids
  fi
done

sudo docker-compose pull

sudo docker-compose up -d --build

sleep 15

DOMAIN=$(grep -E '^[a-zA-Z0-9._-]+ \{' Caddyfile | awk '{print $1}')
curl -fsS -H "Host: ${DOMAIN}" http://127.0.0.1/health

echo "Deployment successful"
