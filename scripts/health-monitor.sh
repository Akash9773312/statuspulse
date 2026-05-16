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
EXPECTED_CONTAINERS="statuspulse-app statuspulse-postgres statuspulse-redis statuspulse-caddy statuspulse-uptime-kuma"

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

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
  else
    log "WARN: ALERT_WEBHOOK_URL not set — alert logged only"
  fi
}

# /health — HTTP 200 + valid JSON
if ! command -v curl >/dev/null 2>&1; then
  log "WARN: curl not installed — skipping health check"
else
  BODY_FILE=$(mktemp)
  HTTP_CODE=$(curl -sS --max-time 15 -o "$BODY_FILE" -w "%{http_code}" "$HEALTH_URL" 2>/dev/null) || HTTP_CODE="000"
  if [[ "$HTTP_CODE" != "200" ]]; then
    alert "Health returned HTTP $HTTP_CODE (expected 200)"
  elif ! python3 -c "import json; d=json.load(open('$BODY_FILE')); exit(0 if d.get('status') in ('healthy','degraded') else 1)" 2>/dev/null; then
    alert "Health JSON invalid or unhealthy: $(cat "$BODY_FILE")"
  else
    log "Health OK (HTTP 200)"
  fi
  rm -f "$BODY_FILE"
fi

# Disk usage
if command -v df >/dev/null 2>&1; then
  DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
  if [[ "$DISK_PCT" -gt "$DISK_THRESHOLD" ]] 2>/dev/null; then
    alert "Disk usage ${DISK_PCT}% exceeds ${DISK_THRESHOLD}%"
  else
    log "Disk OK (${DISK_PCT}%)"
  fi
else
  log "WARN: df not available — skipping disk check"
fi

# Memory usage
if command -v free >/dev/null 2>&1; then
  MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
  if [[ "$MEM_PCT" -gt "$MEM_THRESHOLD" ]] 2>/dev/null; then
    alert "Memory usage ${MEM_PCT}% exceeds ${MEM_THRESHOLD}%"
  else
    log "Memory OK (${MEM_PCT}%)"
  fi
else
  log "WARN: free not available — skipping memory check"
fi

# Docker containers
if command -v docker >/dev/null 2>&1 || command -v sudo >/dev/null 2>&1; then
  for name in $EXPECTED_CONTAINERS; do
    if ! docker_cmd inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
      alert "Container not running: $name"
    fi
  done
  log "Container check complete"
else
  log "WARN: docker not available — skipping container check"
fi

# TLS certificate expiry (within 14 days)
if command -v openssl >/dev/null 2>&1; then
  EXPIRY=$(echo | openssl s_client -servername "$DOMAIN_NAME" -connect "${DOMAIN_NAME}:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [[ -n "$EXPIRY" ]]; then
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %e %T %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo 0)
    NOW=$(date +%s)
    DAYS=$(( (EXPIRY_EPOCH - NOW) / 86400 ))
    if [[ "$DAYS" -lt "$TLS_DAYS_WARN" ]]; then
      alert "TLS certificate expires in ${DAYS} days (threshold ${TLS_DAYS_WARN})"
    else
      log "TLS OK (${DAYS} days remaining)"
    fi
  else
    log "WARN: could not read TLS certificate for $DOMAIN_NAME"
  fi
else
  log "WARN: openssl not available — skipping TLS check"
fi

log "Monitor run complete"
