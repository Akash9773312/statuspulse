#!/usr/bin/env bash
# Production deploy — pull GHCR image, update app container, rollback on failure
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/statuspulse}"
LOG_FILE="${LOG_FILE:-/var/log/statuspulse-deploy.log}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
NETWORK_NAME="${NETWORK_NAME:-statuspulse-prod}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
APP_IMAGE="${APP_IMAGE:-}"

docker_cmd() { sudo docker "$@"; }
compose_cmd() { sudo docker-compose -f "$COMPOSE_FILE" "$@"; }

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

cd "$DEPLOY_DIR"

if [[ -z "$APP_IMAGE" ]]; then
  log "ERROR: APP_IMAGE is not set"
  exit 1
fi

if [[ -z "$DOMAIN_NAME" ]]; then
  if [[ -f caddy/Caddyfile ]]; then
    DOMAIN_NAME=$(grep -E '^[a-zA-Z0-9._-]+ \{' caddy/Caddyfile | head -1 | awk '{print $1}')
  elif [[ -f Caddyfile ]]; then
    DOMAIN_NAME=$(grep -E '^[a-zA-Z0-9._-]+ \{' Caddyfile | head -1 | awk '{print $1}')
  fi
fi

log "Deploying image: $APP_IMAGE (domain: ${DOMAIN_NAME:-unknown})"

sudo systemctl stop caddy 2>/dev/null || true
sudo systemctl disable caddy 2>/dev/null || true

PREVIOUS_IMAGE=""
if docker_cmd inspect statuspulse-app >/dev/null 2>&1; then
  PREVIOUS_IMAGE=$(docker_cmd inspect --format='{{.Config.Image}}' statuspulse-app)
  log "Previous image: $PREVIOUS_IMAGE"
fi

log "Pulling image: $APP_IMAGE"
docker_cmd pull "$APP_IMAGE"

log "Ensuring data services are running"
for c in statuspulse-postgres statuspulse-redis statuspulse-caddy statuspulse-uptime-kuma; do
  if ! docker_cmd ps -a --format '{{.Names}}' | grep -qx "$c"; then
    log "ERROR: container $c missing — run bootstrap.py first"
    exit 1
  fi
  docker_cmd start "$c" 2>/dev/null || true
done

start_app() {
  local image="$1"
  docker_cmd rm -f statuspulse-app 2>/dev/null || true
  docker_cmd run -d \
    --name statuspulse-app \
    --network "$NETWORK_NAME" \
    --network-alias app \
    --network-alias statuspulse-app \
    --env-file "$DEPLOY_DIR/.env" \
    --restart unless-stopped \
    --memory 384m \
    "$image"
}

log "Starting app container"
start_app "$APP_IMAGE"

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
  docker_cmd logs --tail=30 statuspulse-app 2>/dev/null || true
  if [[ -n "$PREVIOUS_IMAGE" && "$PREVIOUS_IMAGE" != "$APP_IMAGE" ]]; then
    log "Rollback to: $PREVIOUS_IMAGE"
    docker_cmd pull "$PREVIOUS_IMAGE" || true
    start_app "$PREVIOUS_IMAGE"
  else
    docker_cmd rm -f statuspulse-app 2>/dev/null || true
  fi
  exit 1
fi

log "Deploy successful — $(curl -fsS -H "Host: ${DOMAIN_NAME}" http://127.0.0.1/health)"
echo "$APP_IMAGE" > .deployed-image
log "Recorded deployed image in .deployed-image"
