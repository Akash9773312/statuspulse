#!/usr/bin/env bash
# Production deploy — pull GHCR image, zero-downtime app update, rollback on failure
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/statuspulse}"
LOG_FILE="${LOG_FILE:-/var/log/statuspulse-deploy.log}"
COMPOSE="docker-compose"
DOMAIN_NAME="${DOMAIN_NAME:-}"
APP_IMAGE="${APP_IMAGE:-}"

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

cd "$DEPLOY_DIR"

if [[ -z "$APP_IMAGE" ]]; then
  log "ERROR: APP_IMAGE is not set"
  exit 1
fi

if [[ -z "$DOMAIN_NAME" ]]; then
  DOMAIN_NAME=$(grep -E '^[a-zA-Z0-9._-]+ \{' caddy/Caddyfile 2>/dev/null | head -1 | awk '{print $1}' || true)
fi

log "Stopping host Caddy if present"
sudo systemctl stop caddy 2>/dev/null || true
sudo systemctl disable caddy 2>/dev/null || true

PREVIOUS_IMAGE=""
if docker inspect statuspulse-app >/dev/null 2>&1; then
  PREVIOUS_IMAGE=$(docker inspect --format='{{.Config.Image}}' statuspulse-app)
  log "Previous image: $PREVIOUS_IMAGE"
fi

log "Pulling image: $APP_IMAGE"
docker pull "$APP_IMAGE"

export APP_IMAGE

log "Ensuring data services are up"
sudo $COMPOSE up -d postgres redis caddy uptime-kuma 2>/dev/null || $COMPOSE up -d postgres redis caddy uptime-kuma

log "Starting new app container"
sudo $COMPOSE up -d --no-deps --force-recreate app

log "Waiting for health check"
sleep 15
HEALTH_OK=false
for _ in $(seq 1 12); do
  if curl -fsS -H "Host: ${DOMAIN_NAME}" http://127.0.0.1/health >/dev/null 2>&1; then
    HEALTH_OK=true
    break
  fi
  sleep 5
done

if [[ "$HEALTH_OK" != "true" ]]; then
  log "Health check FAILED — rolling back"
  if [[ -n "$PREVIOUS_IMAGE" && "$PREVIOUS_IMAGE" != "$APP_IMAGE" ]]; then
    export APP_IMAGE="$PREVIOUS_IMAGE"
    log "Rollback to: $PREVIOUS_IMAGE"
    docker pull "$PREVIOUS_IMAGE" || true
    sudo $COMPOSE up -d --no-deps --force-recreate app
  else
    sudo $COMPOSE stop app || true
  fi
  exit 1
fi

log "Deploy successful — $(curl -fsS -H "Host: ${DOMAIN_NAME}" http://127.0.0.1/health)"
echo "$APP_IMAGE" > .deployed-image
log "Recorded deployed image in .deployed-image"
