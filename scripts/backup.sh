#!/usr/bin/env bash
# PostgreSQL backup with 7-day rotation; optional S3 upload
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/statuspulse/backups}"
LOG_FILE="${LOG_FILE:-/var/log/statuspulse-backup.log}"
COMPOSE_FILE="${COMPOSE_FILE:-/opt/statuspulse/docker-compose.yml}"
S3_BUCKET="${S3_BUCKET:-}"
KEEP=7

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"
STAMP=$(date +%Y-%m-%d_%H%M%S)
FILE="$BACKUP_DIR/statuspulse_db_${STAMP}.sql.gz"

log "Starting backup to $FILE"

docker-compose -f "$COMPOSE_FILE" exec -T postgres \
  pg_dump -U "${POSTGRES_USER:-statuspulse}" "${POSTGRES_DB:-statuspulse}" \
  | gzip > "$FILE"

log "Backup created ($(du -h "$FILE" | awk '{print $1}'))"

log "Rotating backups (keep last $KEEP)"
ls -1t "$BACKUP_DIR"/statuspulse_db_*.sql.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  log "Removing old backup: $old"
  rm -f "$old"
done

if [[ -n "$S3_BUCKET" ]]; then
  if command -v aws >/dev/null 2>&1; then
    log "Uploading to s3://$S3_BUCKET/"
    aws s3 cp "$FILE" "s3://${S3_BUCKET}/$(basename "$FILE")"
    log "S3 upload complete"
  else
    log "WARN: S3_BUCKET set but aws CLI not installed"
  fi
fi

log "Backup finished successfully"
