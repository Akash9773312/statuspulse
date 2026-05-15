# Security

## Secret management

- **No secrets in Git** — `.env`, `terraform.tfvars` with passwords, and keys are gitignored
- **Runtime secrets** — `/opt/statuspulse/.env` on the server only
- **CI/CD** — GitHub Actions secrets: `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, `DOMAIN_NAME`
- **Registry** — `GITHUB_TOKEN` for GHCR push (workflow permissions)

## Container scanning (Trivy)

```bash
docker build -t statuspulse:scan .
trivy image --severity HIGH,CRITICAL statuspulse:scan
```

Mitigations applied:

- Multi-stage build (minimal runtime image)
- Non-root user `appuser`
- Slim `python:3.11-slim` base
- Pin dependency versions in `app/requirements.txt`

Re-scan after changes and document results in `screenshots/` for assessment proof.

## SSH hardening (userdata)

- `PermitRootLogin no`
- `PasswordAuthentication no`
- UFW: deny incoming by default; allow 22, 80, 443 only

## Reverse proxy

Caddy (`caddy/Caddyfile`) enforces:

| Control | Implementation |
|---------|----------------|
| Rate limit | Use Cloudflare free tier, `fail2ban`, or a Caddy build with [caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) (stock Caddy image does not include `rate_limit`) |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Strict-Transport-Security` | 1 year, includeSubDomains |
| `X-XSS-Protection` | `1; mode=block` |
| HTTPS | Automatic Let's Encrypt |

Rate limit test:

```bash
for i in $(seq 1 120); do
  curl -s -o /dev/null -w "%{http_code}\n" https://YOUR_DOMAIN/health
done
```

Expect `429` after ~100 requests/minute (when `rate_limit` is supported by Caddy build).

## Verify headers

```bash
curl -sI https://statuspulse.umehta.xyz/
```

## Git history

No credentials should appear in history. If leaked, rotate passwords and use `git filter-repo` before force-push (coordinate with team).
