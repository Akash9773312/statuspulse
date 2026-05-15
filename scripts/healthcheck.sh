#!/bin/bash
set -e
DOMAIN="${DOMAIN_NAME:-statuspulse.umehta.xyz}"
curl -fsS "https://${DOMAIN}/health" | python3 -m json.tool
echo "Health check passed."
