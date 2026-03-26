#!/usr/bin/env bash
# =============================================================
# 07_frontend.sh — Swap memory setup + npm frontend build +
#                  final permission/service restart
# Requires: ADD_SWAP, SWAP_SIZE_MB, INSTALL_NODE, APP_ROOT,
#           NODE_BUILD_HEAP_MB, PHP_VER, APP_NAME
# =============================================================

# ---------------------------------------------------------------
# Swap memory (independent of Node/frontend)
# ---------------------------------------------------------------
echo ""
if [[ "${ADD_SWAP:-N}" =~ ^[Yy]$ ]]; then
  echo "=== [1/3] Add swap (${SWAP_SIZE_MB} MB) ==="
  if ! swapon --show | awk '{print $1}' | grep -qx "/swapfile"; then
    echo "No swap found — creating ${SWAP_SIZE_MB} MB swapfile..."
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile 2>/dev/null \
      || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_SIZE_MB}"
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab \
      || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap created and enabled."
  else
    echo "Swap already enabled."
  fi
  free -h || true
else
  echo "=== [1/3] Swap: skipped ==="
fi

# ---------------------------------------------------------------
# Frontend build
# ---------------------------------------------------------------
echo ""
if [[ "${INSTALL_NODE:-N}" =~ ^[Yy]$ ]]; then
  echo "=== [2/3] Build frontend ==="
  cd "${APP_ROOT}"

  if [[ -f "${APP_ROOT}/package-lock.json" ]]; then
    npm ci
  else
    npm install
  fi

  NODE_OPTIONS="--max-old-space-size=${NODE_BUILD_HEAP_MB}" npm run build
else
  echo "=== [2/3] Frontend build: skipped (Node.js not requested) ==="
fi

echo ""
echo "=== [3/3] Final permission fix + restart services ==="
chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
find "${APP_ROOT}/storage"           -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/storage"           -type f -exec chmod 664 {} \; || true
find "${APP_ROOT}/bootstrap/cache"   -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/bootstrap/cache"   -type f -exec chmod 664 {} \; || true

systemctl restart php${PHP_VER}-fpm
supervisorctl restart "${APP_NAME}-queue:*" || true
