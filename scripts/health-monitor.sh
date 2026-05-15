#!/usr/bin/env bash
# Cron health monitor — /health, disk, memory, containers, TLS expiry
set -euo pipefail

LOG_FILE="${LOG_FILE:-/var/log/statuspulse-monitor.log}"
DOMAIN_NAME="${DOMAIN_NAME:-statuspulse.umehta.xyz}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
HEALTH_URL="${HEALTH_URL:-https://${DOMAIN_NAME}/health}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
MEM_THRESHOLD="${MEM_THRESHOLD:-90}"
TLS_DAYS_WARN="${TLS_DAYS_WARN:-14}"
COMPOSE_FILE="${COMPOSE_FILE:-/opt/statuspulse/docker-compose.yml}"
EXPECTED_CONTAINERS="statuspulse-app statuspulse-postgres statuspulse-redis statuspulse-caddy statuspulse-uptime-kuma"

log() {
  echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
}

alert() {
  local msg="$1"
  log "ALERT: $msg"
  if [[ -n "$ALERT_WEBHOOK_URL" ]]; then
    curl -fsS -X POST "$ALERT_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"StatusPulse: $msg\"}" \
      --max-time 10 \
      >/dev/null 2>&1 || log "WARN: webhook delivery failed"
  fi
}

# /health
if ! OUT=$(curl -fsS --max-time 15 "$HEALTH_URL" 2>&1); then
  alert "Health endpoint failed: $OUT"
else
  if ! echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('status') in ('healthy','degraded') else 1)" 2>/dev/null; then
    alert "Health JSON invalid or unhealthy: $OUT"
  else
    log "Health OK"
  fi
fi

# Disk usage
DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
if [[ "$DISK_PCT" -gt "$DISK_THRESHOLD" ]] 2>/dev/null; then
  alert "Disk usage ${DISK_PCT}% exceeds ${DISK_THRESHOLD}%"
else
  log "Disk OK (${DISK_PCT}%)"
fi

# Memory usage
MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
if [[ "$MEM_PCT" -gt "$MEM_THRESHOLD" ]] 2>/dev/null; then
  alert "Memory usage ${MEM_PCT}% exceeds ${MEM_THRESHOLD}%"
else
  log "Memory OK (${MEM_PCT}%)"
fi

# Docker containers
for name in $EXPECTED_CONTAINERS; do
  if ! docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
    alert "Container not running: $name"
  fi
done
log "Container check complete"

# TLS expiry
if command -v openssl >/dev/null 2>&1; then
  EXPIRY=$(echo | openssl s_client -servername "$DOMAIN_NAME" -connect "${DOMAIN_NAME}:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [[ -n "$EXPIRY" ]]; then
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %e %T %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo 0)
    NOW=$(date +%s)
    DAYS=$(( (EXPIRY_EPOCH - NOW) / 86400 ))
    if [[ "$DAYS" -lt "$TLS_DAYS_WARN" ]]; then
      alert "TLS certificate expires in ${DAYS} days"
    else
      log "TLS OK (${DAYS} days remaining)"
    fi
  fi
fi

log "Monitor run complete"
