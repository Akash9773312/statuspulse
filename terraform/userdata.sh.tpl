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
  unattended-upgrades

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

if systemctl list-unit-files caddy.service 2>/dev/null | grep -q caddy; then
  systemctl stop caddy || true
  systemctl disable caddy || true
fi

mkdir -p /opt/statuspulse
chown -R ubuntu:ubuntu /opt/statuspulse
chmod 755 /opt/statuspulse
