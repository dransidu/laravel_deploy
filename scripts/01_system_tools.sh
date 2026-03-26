#!/usr/bin/env bash
# =============================================================
# 01_system_tools.sh — System packages, Nginx, PHP, Composer,
#                      and optionally Node.js
# Requires: APP_NAME, PHP_VER, NODE_MAJOR, INSTALL_NODE
# =============================================================

echo ""
echo "=== [1/7] System update + base packages ==="
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release software-properties-common \
  git unzip zip acl ufw build-essential openssl

echo ""
echo "=== [2/7] Firewall — allow OpenSSH, HTTP, HTTPS ==="
ufw allow OpenSSH   || true
ufw allow 'Nginx Full' || true
ufw --force enable  || true

echo ""
echo "=== [3/7] Install Nginx ==="
apt-get install -y nginx
systemctl enable --now nginx

echo ""
echo "=== [4/7] Install PHP ${PHP_VER} + extensions ==="
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt-get update -y
apt-get install -y \
  php${PHP_VER}-fpm php${PHP_VER}-cli php${PHP_VER}-common \
  php${PHP_VER}-pgsql php${PHP_VER}-mbstring php${PHP_VER}-xml php${PHP_VER}-curl \
  php${PHP_VER}-zip php${PHP_VER}-bcmath php${PHP_VER}-intl php${PHP_VER}-gd
systemctl enable --now php${PHP_VER}-fpm

echo ""
echo "=== [5/7] Install Composer (global) ==="
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm -f /tmp/composer-setup.php
composer --version

echo ""
if [[ "${INSTALL_NODE}" =~ ^[Yy]$ ]]; then
  echo "=== [6/7] Install Node.js ${NODE_MAJOR} (NodeSource) ==="
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
  node -v
  npm -v
else
  echo "=== [6/7] Skipping Node.js installation ==="
fi

echo ""
echo "=== [7/7] System tools done ==="
