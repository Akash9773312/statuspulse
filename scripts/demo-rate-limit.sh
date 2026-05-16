#!/usr/bin/env bash
# Assessment proof: rate limit 100 req/min → HTTP 429
# Usage: ./scripts/demo-rate-limit.sh [domain]
set -uo pipefail

DOMAIN="${1:-statuspulse.umehta.xyz}"
URL="https://${DOMAIN}/health"
OUT="${OUT:-screenshots/rate-limit-demo.txt}"

mkdir -p "$(dirname "$OUT")"
echo "Rate limit demo: $URL ($(date -Iseconds))" | tee "$OUT"
echo "---" | tee -a "$OUT"

for i in $(seq 1 120); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "err")
  echo "$code" | tee -a "$OUT"
done

echo "---" | tee -a "$OUT"
echo "Summary:" | tee -a "$OUT"
sort "$OUT" | grep -E '^[0-9]+$' | uniq -c | tee -a "$OUT"
echo "Done. Expect 200 then 429." | tee -a "$OUT"
