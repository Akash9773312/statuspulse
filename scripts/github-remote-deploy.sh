#!/usr/bin/env bash
# Executed on the server by GitHub Actions (appleboy/ssh-action script_path)
set -euxo pipefail

if [ -n "${GHCR_TOKEN:-}" ]; then
  echo "$GHCR_TOKEN" | sudo docker login ghcr.io -u "${GHCR_USER}" --password-stdin
fi

sudo mkdir -p /opt/statuspulse
sudo chown -R "${USER:-ubuntu}:ubuntu" /opt/statuspulse
cd /opt/statuspulse

BASE="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${GIT_SHA}"
curl -fsSL "${BASE}/scripts/deploy.sh" -o deploy.sh
curl -fsSL "${BASE}/docker-compose.prod.yml" -o docker-compose.yml
chmod +x deploy.sh

export APP_IMAGE DOMAIN_NAME
./deploy.sh
