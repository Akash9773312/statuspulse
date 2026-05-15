#!/usr/bin/env bash
# Integration tests — run against live stack (CI or local after make up)
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
PASS=0
FAIL=0

log_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
log_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_status() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    log_pass "$name (HTTP $actual)"
  else
    log_fail "$name (expected HTTP $expected, got $actual)"
  fi
}

assert_json_keys() {
  local name="$1" body="$2"
  shift 2
  for key in "$@"; do
    if echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if '$key' in d else 1)" 2>/dev/null; then
      log_pass "$name contains key '$key'"
    else
      log_fail "$name missing key '$key'"
    fi
  done
}

echo "=== StatusPulse integration tests ==="
echo "Base URL: $BASE_URL"
echo

# GET /health
code=$(curl -sS -o /tmp/sp_health.json -w "%{http_code}" "$BASE_URL/health")
assert_status "GET /health" "200" "$code"
if [[ "$code" == "200" ]]; then
  assert_json_keys "GET /health" "$(cat /tmp/sp_health.json)" status checks timestamp
fi

# GET /
code=$(curl -sS -o /tmp/sp_root.json -w "%{http_code}" "$BASE_URL/")
assert_status "GET /" "200" "$code"
if [[ "$code" == "200" ]]; then
  assert_json_keys "GET /" "$(cat /tmp/sp_root.json)" service version docs health
fi

# POST /services
code=$(curl -sS -o /tmp/sp_svc.json -w "%{http_code}" \
  -X POST "$BASE_URL/services" \
  -H "Content-Type: application/json" \
  -d '{"name":"integration-test","url":"https://example.com"}')
if [[ "$code" == "201" ]] || [[ "$code" == "200" ]]; then
  log_pass "POST /services (HTTP $code)"
  assert_json_keys "POST /services" "$(cat /tmp/sp_svc.json)" id name url
elif [[ "$code" == "409" ]]; then
  log_pass "POST /services duplicate (HTTP 409)"
else
  log_fail "POST /services (expected 201 or 409, got $code)"
fi

# POST duplicate → 409
code=$(curl -sS -o /dev/null -w "%{http_code}" \
  -X POST "$BASE_URL/services" \
  -H "Content-Type: application/json" \
  -d '{"name":"integration-test","url":"https://example.com"}')
assert_status "POST /services duplicate" "409" "$code"

# GET /services
code=$(curl -sS -o /tmp/sp_svcs.json -w "%{http_code}" "$BASE_URL/services")
assert_status "GET /services" "200" "$code"

# POST /incidents
code=$(curl -sS -o /tmp/sp_inc.json -w "%{http_code}" \
  -X POST "$BASE_URL/incidents" \
  -H "Content-Type: application/json" \
  -d '{"service_name":"integration-test","title":"Test incident","description":"CI run"}')
if [[ "$code" == "201" ]] || [[ "$code" == "200" ]]; then
  log_pass "POST /incidents (HTTP $code)"
  assert_json_keys "POST /incidents" "$(cat /tmp/sp_inc.json)" id status
else
  log_fail "POST /incidents (got HTTP $code)"
fi

# GET /incidents
code=$(curl -sS -o /tmp/sp_incs.json -w "%{http_code}" "$BASE_URL/incidents")
assert_status "GET /incidents" "200" "$code"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
