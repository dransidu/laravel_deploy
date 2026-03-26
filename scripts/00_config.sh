#!/usr/bin/env bash
# =============================================================
# 00_config.sh — Interactive configuration prompts
# Sourced by deploy.sh; all variables are exported for use
# in every subsequent script.
# =============================================================

echo "=== CONFIGURATION SETUP ==="
echo ""

read -rp "App name (default: bugcommerce): " APP_NAME
APP_NAME="${APP_NAME:-bugcommerce}"

APP_ROOT="/var/www/${APP_NAME}"

read -rp "Enter your domain (example: app.bugcommerce.lk): " DOMAIN
[[ -z "${DOMAIN}" ]] && { echo "Domain is required."; exit 1; }
APP_URL="https://${DOMAIN}"

read -rp "Enter your Git repository URL (SSH/HTTPS): " REPO_URL
[[ -z "${REPO_URL}" ]] && { echo "Repository URL is required."; exit 1; }

read -rp "Enter branch (default: main): " BRANCH
BRANCH="${BRANCH:-main}"

read -rp "Database name (default: ${APP_NAME}): " DB_NAME
DB_NAME="${DB_NAME:-$APP_NAME}"

read -rp "Database user (default: postgres): " DB_USER
DB_USER="${DB_USER:-postgres}"

DEFAULT_DB_PASS="$(openssl rand -base64 16 2>/dev/null || date +%s | sha256sum | head -c 24)"
read -rp "Database password (leave empty to auto-generate): " DB_PASS
DB_PASS="${DB_PASS:-$DEFAULT_DB_PASS}"

read -rp "PHP version (default: 8.5): " PHP_VER
PHP_VER="${PHP_VER:-8.5}"

read -rp "Node.js major version (default: 22): " NODE_MAJOR
NODE_MAJOR="${NODE_MAJOR:-22}"

read -rp "App environment (default: production): " APP_ENV
APP_ENV="${APP_ENV:-production}"

read -rp "Enable debug? (true/false, default: false): " APP_DEBUG
APP_DEBUG="${APP_DEBUG:-false}"

read -rp "Node build heap memory MB (default: 1536): " NODE_BUILD_HEAP_MB
NODE_BUILD_HEAP_MB="${NODE_BUILD_HEAP_MB:-1536}"

read -rp "Swap size MB (default: 2048): " SWAP_SIZE_MB
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"

echo ""
read -rp "FULL DB RESET? Drops & recreates DB '${DB_NAME}' (DELETES ALL DATA) (y/N): " DB_RESET
DB_RESET="${DB_RESET:-N}"

echo ""
read -rp "Do you need Node.js and frontend build on this server? (y/N): " INSTALL_NODE
INSTALL_NODE="${INSTALL_NODE:-N}"

echo ""
read -rp "Update postgres user password to the value above? (y/N): " UPDATE_POSTGRES_PASS
UPDATE_POSTGRES_PASS="${UPDATE_POSTGRES_PASS:-N}"

# ---------------------------------------------------------------
# Derived paths (used by ssl and nginx scripts)
# ---------------------------------------------------------------
SSL_DIR_CERT="/etc/ssl/certs"
SSL_DIR_KEY="/etc/ssl/private"
ORIGIN_CERT_PATH="${SSL_DIR_CERT}/${APP_NAME}.crt"
ORIGIN_KEY_PATH="${SSL_DIR_KEY}/${APP_NAME}.key"

PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"

# ---------------------------------------------------------------
# Export everything so sourced child scripts can use them
# ---------------------------------------------------------------
export APP_NAME APP_ROOT DOMAIN APP_URL REPO_URL BRANCH
export DB_NAME DB_USER DB_PASS
export PHP_VER NODE_MAJOR
export APP_ENV APP_DEBUG
export NODE_BUILD_HEAP_MB SWAP_SIZE_MB
export DB_RESET INSTALL_NODE UPDATE_POSTGRES_PASS
export SSL_DIR_CERT SSL_DIR_KEY ORIGIN_CERT_PATH ORIGIN_KEY_PATH
export PHP_SOCK

# ---------------------------------------------------------------
# Summary + confirmation
# ---------------------------------------------------------------
echo ""
echo "=== CONFIG SUMMARY ==="
echo "App name           : ${APP_NAME}"
echo "App root           : ${APP_ROOT}"
echo "Domain             : ${DOMAIN}"
echo "App URL            : ${APP_URL}"
echo "Repo URL           : ${REPO_URL}"
echo "Branch             : ${BRANCH}"
echo "DB name            : ${DB_NAME}"
echo "DB user            : ${DB_USER}"
echo "DB password        : ${DB_PASS}"
echo "PHP version        : ${PHP_VER}"
echo "Node major         : ${NODE_MAJOR}"
echo "App env            : ${APP_ENV}"
echo "App debug          : ${APP_DEBUG}"
echo "Node heap MB       : ${NODE_BUILD_HEAP_MB}"
echo "Swap MB            : ${SWAP_SIZE_MB}"
echo "Full DB reset      : ${DB_RESET}"
echo "Install Node.js    : ${INSTALL_NODE}"
echo "Update PG password : ${UPDATE_POSTGRES_PASS}"
echo ""

read -rp "Proceed with these settings? (y/N): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi
