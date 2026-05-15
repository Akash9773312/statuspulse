#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y \
  docker.io \
  docker-compose \
  curl \
  git \
  ufw \
  fail2ban \
  unattended-upgrades \
  openssl

# Automatic security updates
dpkg-reconfigure -plow unattended-upgrades || true

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Swap (free-tier VMs)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

# SSH hardening
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd

# Firewall — SSH, HTTP, HTTPS only
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Host Caddy conflicts with Docker Caddy
if systemctl list-unit-files caddy.service 2>/dev/null | grep -q caddy; then
  systemctl stop caddy || true
  systemctl disable caddy || true
fi

mkdir -p /opt/statuspulse/backups
chown -R ubuntu:ubuntu /opt/statuspulse
chmod 755 /opt/statuspulse

touch /var/log/statuspulse-deploy.log /var/log/statuspulse-monitor.log /var/log/statuspulse-backup.log
chown ubuntu:ubuntu /var/log/statuspulse-*.log
