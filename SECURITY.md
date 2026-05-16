# Security

## Secret management

| Rule | Implementation |
|------|----------------|
| No secrets in Git | `.env` gitignored; use `.env.example` as template |
| Runtime secrets | `/opt/statuspulse/.env` on server only |
| CI/CD secrets | GitHub Actions: `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, `DOMAIN_NAME`, optional `GHCR_TOKEN` |
| Registry auth | `GITHUB_TOKEN` for GHCR push in Actions |

Verify no secrets in history:

```bash
git log -p | grep -iE 'password|secret|api_key' | head
# Should only show placeholders like change-me in examples
```

## Container image scanning (Trivy)

```bash
docker build -t statuspulse:scan .
trivy image --severity HIGH,CRITICAL statuspulse:scan
```

**Mitigations applied:**

- Multi-stage Dockerfile (`python:3.11-slim` runtime)
- Non-root user `appuser`
- Pinned dependencies in `app/requirements.txt`
- Minimal OS packages (no apt cache in final image)

Save before/after scan output under `screenshots/trivy-*.txt` for assessment proof.

## Reverse proxy security headers

Caddy (`caddy/Caddyfile.tpl`) sets on the main site:

| Header | Value |
|--------|--------|
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` |
| `X-XSS-Protection` | `1; mode=block` |

Verify:

```bash
curl -sI https://statuspulse.umehta.xyz/ | grep -iE 'x-content|x-frame|strict|x-xss'
```

## Rate limiting (100 requests / minute / IP)

Enforced at the **reverse proxy** (Caddy) using the [caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) module. Custom Caddy image: `caddy/Dockerfile` (built via `xcaddy`).

Configuration: `caddy/Caddyfile.tpl` — `rate_limit` zone `statuspulse_api` (100 events / 1m per `{remote_host}`). Excess requests receive **HTTP 429** before reaching the app.

Application code (`app/main.py`) is unchanged.

### Rate limit demo (assessment proof)

```bash
for i in $(seq 1 120); do
  curl -s -o /dev/null -w "%{http_code}\n" https://statuspulse.umehta.xyz/health
done
```

Expected: mostly `200`, then `429` after ~100 requests in the same minute from your IP.

Save terminal output to `screenshots/rate-limit-demo.txt`.

```bash
# Quick count of 429s
for i in $(seq 1 120); do
  curl -s -o /dev/null -w "%{http_code}\n" https://statuspulse.umehta.xyz/health
done | sort | uniq -c
```

## HTTPS

- Let's Encrypt via Caddy (automatic)
- HTTP redirects to HTTPS
- TLS 1.2+ from Caddy defaults

## SSH & firewall (server)

- `PermitRootLogin no`, `PasswordAuthentication no` (userdata)
- UFW: allow 22, 80, 443 only

## Reporting issues

Document any findings and fixes in this file and in PR/commit messages.
