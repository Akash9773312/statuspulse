#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
TERRAFORM_DIR = ROOT_DIR / "terraform"
DEPLOY_DIR = ROOT_DIR / "deploy"
SCRIPTS_DIR = ROOT_DIR / "scripts"

TERRAFORM_COMMANDS = [
    ["terraform", "init"],
    ["terraform", "fmt"],
    ["terraform", "validate"],
    ["terraform", "plan"],
    ["terraform", "apply", "-auto-approve"],
]


def die(message: str, code: int = 1) -> None:
    print(f"\nError: {message}\n", file=sys.stderr)
    sys.exit(code)


def require_command(name: str) -> None:
    if shutil.which(name) is None:
        die(f"'{name}' not found. Install it and ensure it is on your PATH.")


def run_command(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    print(f"\nRunning: {' '.join(command)}\n")
    result = subprocess.run(command, cwd=cwd)
    if result.returncode != 0:
        die(f"Command failed: {' '.join(command)}")
    return result


def terraform_output(name: str) -> str:
    result = subprocess.run(
        ["terraform", "output", "-raw", name],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        die(f"Failed to read terraform output '{name}': {result.stderr.strip()}")
    return result.stdout.strip()


def private_key_path() -> Path:
    tfvars = TERRAFORM_DIR / "terraform.tfvars"
    default = Path.home() / ".ssh" / "id_ed25519"

    if not tfvars.exists():
        return default

    for line in tfvars.read_text().splitlines():
        line = line.strip()
        if line.startswith("public_key_path"):
            _, _, value = line.partition("=")
            pub = value.strip().strip('"').strip("'")
            pub_path = Path(pub).expanduser()
            if pub_path.suffix == ".pub":
                private = pub_path.with_suffix("")
                if private.exists():
                    return private
            break

    return default


def wait_for_ssh(host: str, user: str, key: Path, timeout: int = 600) -> None:
    print(f"Waiting for SSH on {user}@{host} (up to {timeout}s)...")
    deadline = time.time() + timeout

    while time.time() < deadline:
        result = subprocess.run(
            [
                "ssh",
                "-i",
                str(key),
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "ConnectTimeout=5",
                f"{user}@{host}",
                "cloud-init status --wait || true",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            print("SSH is ready.")
            return
        time.sleep(10)

    die(f"Timed out waiting for SSH on {host}")


def prepare_deploy_bundle(domain: str, kuma_domain: str) -> Path:
    bundle = Path(tempfile.mkdtemp(prefix="statuspulse-deploy-"))

    for name in ("docker-compose.yml", "Dockerfile"):
        shutil.copy2(DEPLOY_DIR / name, bundle / name)

    shutil.copytree(DEPLOY_DIR / "app", bundle / "app")

    caddy_template = (DEPLOY_DIR / "Caddyfile.tpl").read_text()
    caddyfile = (
        caddy_template.replace("__DOMAIN__", domain).replace("__KUMA_DOMAIN__", kuma_domain)
    )
    (bundle / "Caddyfile").write_text(caddyfile)

    return bundle


def ensure_deploy_dir(host: str, user: str, key: Path) -> None:
    subprocess.run(
        [
            "ssh",
            "-i",
            str(key),
            "-o",
            "StrictHostKeyChecking=accept-new",
            f"{user}@{host}",
            "sudo mkdir -p /opt/statuspulse && sudo chown -R ubuntu:ubuntu /opt/statuspulse",
        ],
        check=True,
    )


def sync_to_server(bundle: Path, host: str, user: str, key: Path) -> None:
    require_command("rsync")
    ensure_deploy_dir(host, user, key)
    remote = f"{user}@{host}:/opt/statuspulse/"

    run_command(
        [
            "rsync",
            "-rz",
            "--delete",
            "--omit-dir-times",
            "-e",
            f"ssh -i {key} -o StrictHostKeyChecking=accept-new",
            f"{bundle}/",
            remote,
        ]
    )


def run_remote_deploy(host: str, user: str, key: Path, domain: str) -> None:
    remote_script = (
        "set -e; "
        "cd /opt/statuspulse; "
        "sudo systemctl stop caddy 2>/dev/null || true; "
        "sudo systemctl disable caddy 2>/dev/null || true; "
        "sudo docker-compose down --remove-orphans 2>/dev/null || true; "
        "for port in 80 443 3001; do "
        "ids=$(sudo docker ps -q --filter publish=${port} 2>/dev/null || true); "
        '[ -n "$ids" ] && sudo docker stop $ids && sudo docker rm $ids || true; '
        "done; "
        "sudo docker-compose pull; "
        "sudo docker-compose up -d --build; "
        "sleep 20; "
        f'curl -fsS -H "Host: {domain}" http://127.0.0.1/health'
    )

    run_command(
        [
            "ssh",
            "-i",
            str(key),
            "-o",
            "StrictHostKeyChecking=accept-new",
            f"{user}@{host}",
            remote_script,
        ]
    )


def main() -> None:
    print("StatusPulse bootstrap\n")

    for cmd in ("terraform", "ssh", "rsync", "curl"):
        require_command(cmd)

    key = private_key_path()
    if not key.exists():
        die(f"SSH private key not found at {key}")

    for command in TERRAFORM_COMMANDS:
        run_command(command, cwd=TERRAFORM_DIR)

    host = terraform_output("server_ip")
    user = terraform_output("ssh_user")
    domain = terraform_output("domain_name")
    kuma_domain = terraform_output("kuma_domain_name")
    app_url = terraform_output("app_url")
    kuma_url = terraform_output("kuma_url")
    allocation_id = terraform_output("elastic_ip_allocation_id")

    wait_for_ssh(host, user, key)

    bundle = prepare_deploy_bundle(domain, kuma_domain)
    try:
        sync_to_server(bundle, host, user, key)
        run_remote_deploy(host, user, key, domain)
    finally:
        shutil.rmtree(bundle, ignore_errors=True)

    print("\nBootstrap completed successfully.\n")
    print(f"  Elastic IP:      {host}")
    print(f"  Allocation ID:   {allocation_id}")
    print(f"  Application URL: {app_url}")
    print(f"  Uptime Kuma URL: {kuma_url}")
    print(f"  SSH:             ssh -i {key} {user}@{host}")
    print(f"  Server files:    /opt/statuspulse/")
    print()


if __name__ == "__main__":
    main()
