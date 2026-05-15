#!/usr/bin/env bash
# Install cron jobs on the server (run once after bootstrap)
set -euo pipefail

DIR="/opt/statuspulse"
CRON_FILE="/tmp/statuspulse-cron"

cat > "$CRON_FILE" <<EOF
# StatusPulse monitoring and backups
*/5 * * * * DOMAIN_NAME=${DOMAIN_NAME:-statuspulse.umehta.xyz} ALERT_WEBHOOK_URL=${ALERT_WEBHOOK_URL:-} ${DIR}/health-monitor.sh
0 2 * * * ${DIR}/backup.sh
EOF

crontab -l 2>/dev/null | grep -v statuspulse > /tmp/cron.bak || true
cat /tmp/cron.bak "$CRON_FILE" | crontab -
rm -f "$CRON_FILE" /tmp/cron.bak
echo "Cron jobs installed:"
crontab -l | grep statuspulse
