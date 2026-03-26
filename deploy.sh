#!/usr/bin/env bash
set -euo pipefail

############################################################
# Interactive Laravel Production Deploy Script
# Ubuntu 24.04 LTS
#
# Prompts for:
#  - App name
#  - Domain
#  - Git repo URL
#  - Branch
#  - Database name
#  - Database user
#  - Database password
#  - PHP version
#  - Node.js major version
#  - App env
#  - App debug
#  - Node build heap size
#  - Swap size
#  - Full DB reset
#  - Install Node.js + build frontend
#  - Paste Cloudflare Origin CERT + KEY
############################################################

# ===============================
# ROOT CHECK
# ===============================
if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

# ===============================
# CONFIGURATION PROMPTS
# ===============================
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

# ===============================
# SYSTEM SETUP
# ===============================
echo "=== 1) System update + base packages ==="
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release software-properties-common \
  git unzip zip acl ufw build-essential openssl

echo "=== 2) Firewall (UFW) allow OpenSSH, HTTP, HTTPS ==="
ufw allow OpenSSH || true
ufw allow 'Nginx Full' || true
ufw --force enable || true

echo "=== 3) Install Nginx ==="
apt-get install -y nginx
systemctl enable --now nginx

echo "=== 4) Install PHP ${PHP_VER} + extensions ==="
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt-get update -y
apt-get install -y \
  php${PHP_VER}-fpm php${PHP_VER}-cli php${PHP_VER}-common \
  php${PHP_VER}-pgsql php${PHP_VER}-mbstring php${PHP_VER}-xml php${PHP_VER}-curl \
  php${PHP_VER}-zip php${PHP_VER}-bcmath php${PHP_VER}-intl php${PHP_VER}-gd
systemctl enable --now php${PHP_VER}-fpm

echo "=== 5) Install Composer (global) ==="
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm -f /tmp/composer-setup.php
composer --version

if [[ "${INSTALL_NODE}" =~ ^[Yy]$ ]]; then
  echo "=== 6) Install Node.js (NodeSource) ==="
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
  node -v
  npm -v
else
  echo "=== 6) Skipping Node.js installation ==="
fi

echo "=== 7) Install PostgreSQL ==="
apt-get install -y postgresql postgresql-contrib
systemctl enable --now postgresql

echo "=== 8) Configure PostgreSQL ==="
if [[ "${UPDATE_POSTGRES_PASS}" =~ ^[Yy]$ ]]; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE postgres WITH PASSWORD '${DB_PASS}';"
  echo "Updated postgres password."
else
  echo "Skipped postgres password update."
fi

if [[ "${DB_RESET}" =~ ^[Yy]$ ]]; then
  echo "FULL RESET selected: terminating connections, dropping and recreating DB '${DB_NAME}'..."

  sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
SQL

  sudo -u postgres dropdb --if-exists "${DB_NAME}"
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
  echo "Database recreated: ${DB_NAME}"
else
  if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
    echo "Created database: ${DB_NAME}"
  else
    echo "Database already exists: ${DB_NAME}"
  fi
fi

echo "=== 9) Prepare project directory ${APP_ROOT} ==="
mkdir -p "${APP_ROOT}"
chown -R root:root "${APP_ROOT}"
chmod 755 /var/www
chmod 755 "${APP_ROOT}"

echo "=== 10) Clone/Update repository ==="
if [[ ! -d "${APP_ROOT}/.git" ]]; then
  if [[ -n "$(ls -A "${APP_ROOT}" 2>/dev/null)" ]]; then
    echo "ERROR: ${APP_ROOT} is not empty and not a git repo. Move/empty it first."
    exit 1
  fi
  git clone -b "${BRANCH}" "${REPO_URL}" "${APP_ROOT}"
else
  git -C "${APP_ROOT}" fetch --all
  git -C "${APP_ROOT}" reset --hard "origin/${BRANCH}"
fi

echo "=== 11) Laravel .env setup ==="
if [[ ! -f "${APP_ROOT}/.env" ]]; then
  if [[ -f "${APP_ROOT}/.env.example" ]]; then
    cp "${APP_ROOT}/.env.example" "${APP_ROOT}/.env"
  else
    cat > "${APP_ROOT}/.env" <<ENV
APP_NAME=${APP_NAME}
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=
QUEUE_CONNECTION=database
ENV
  fi
fi

chmod 640 "${APP_ROOT}/.env"
chown root:www-data "${APP_ROOT}/.env"

ensure_env() {
  local key="$1"
  local val="$2"
  local file="$3"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${val}|g" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

ensure_env "APP_NAME" "${APP_NAME}" "${APP_ROOT}/.env"
ensure_env "APP_ENV" "${APP_ENV}" "${APP_ROOT}/.env"
ensure_env "APP_DEBUG" "${APP_DEBUG}" "${APP_ROOT}/.env"
ensure_env "APP_URL" "${APP_URL}" "${APP_ROOT}/.env"
ensure_env "DB_CONNECTION" "pgsql" "${APP_ROOT}/.env"
ensure_env "DB_HOST" "127.0.0.1" "${APP_ROOT}/.env"
ensure_env "DB_PORT" "5432" "${APP_ROOT}/.env"
ensure_env "DB_DATABASE" "${DB_NAME}" "${APP_ROOT}/.env"
ensure_env "DB_USERNAME" "${DB_USER}" "${APP_ROOT}/.env"
ensure_env "DB_PASSWORD" "${DB_PASS}" "${APP_ROOT}/.env"
ensure_env "QUEUE_CONNECTION" "database" "${APP_ROOT}/.env"

echo "=== 12) Fix Laravel permissions ==="
chown -R root:root "${APP_ROOT}"
find "${APP_ROOT}" -type d -exec chmod 755 {} \; || true
find "${APP_ROOT}" -type f -exec chmod 644 {} \; || true

mkdir -p "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
find "${APP_ROOT}/storage" -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/storage" -type f -exec chmod 664 {} \; || true
find "${APP_ROOT}/bootstrap/cache" -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/bootstrap/cache" -type f -exec chmod 664 {} \; || true

echo "=== 13) Install Laravel dependencies ==="
cd "${APP_ROOT}"
composer install --no-interaction --no-dev --prefer-dist --optimize-autoloader

if ! grep -qE '^APP_KEY=base64:' "${APP_ROOT}/.env"; then
  php artisan key:generate --force
fi

php artisan config:clear || true
php artisan route:clear || true
php artisan view:clear || true
php artisan cache:clear || true

echo "=== 14) Migrate + Seed ==="
php artisan migrate --force
php artisan db:seed --force

echo "=== 15) Wayfinder generate ==="
php artisan wayfinder:generate || true

echo "=== 16) Re-apply writable permissions after artisan tasks ==="
chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
find "${APP_ROOT}/storage" -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/storage" -type f -exec chmod 664 {} \; || true
find "${APP_ROOT}/bootstrap/cache" -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/bootstrap/cache" -type f -exec chmod 664 {} \; || true

echo "=== 17) Paste Cloudflare Origin Certificate + Private Key (multi-line safe) ==="
SSL_DIR_CERT="/etc/ssl/certs"
SSL_DIR_KEY="/etc/ssl/private"
ORIGIN_CERT_PATH="${SSL_DIR_CERT}/${APP_NAME}.crt"
ORIGIN_KEY_PATH="${SSL_DIR_KEY}/${APP_NAME}.key"

mkdir -p "${SSL_DIR_CERT}" "${SSL_DIR_KEY}"
chmod 700 "${SSL_DIR_KEY}"

echo ""
echo "PASTE Cloudflare Origin CERTIFICATE now (multi-line)."
echo "When finished, type: ENDCERT"
CERT_TMP="$(mktemp)"

while IFS= read -r line </dev/tty; do
  [[ "$line" == "ENDCERT" ]] && break
  printf "%s\n" "$line" >> "$CERT_TMP"
done

echo ""
echo "PASTE Cloudflare Origin PRIVATE KEY now (multi-line)."
echo "When finished, type: ENDKEY"
KEY_TMP="$(mktemp)"

while IFS= read -r line </dev/tty; do
  [[ "$line" == "ENDKEY" ]] && break
  printf "%s\n" "$line" >> "$KEY_TMP"
done

if ! grep -q "BEGIN CERTIFICATE" "$CERT_TMP"; then
  echo "ERROR: Certificate paste looks invalid."
  exit 1
fi

if ! grep -q "BEGIN" "$KEY_TMP"; then
  echo "ERROR: Private key paste looks invalid."
  exit 1
fi

install -m 644 "$CERT_TMP" "$ORIGIN_CERT_PATH"
install -m 600 "$KEY_TMP" "$ORIGIN_KEY_PATH"
rm -f "$CERT_TMP" "$KEY_TMP"

echo "Saved cert: ${ORIGIN_CERT_PATH}"
echo "Saved key : ${ORIGIN_KEY_PATH}"

echo "=== 18) Install Supervisor + Queue Worker ==="
apt-get install -y supervisor
systemctl enable --now supervisor

SUPERVISOR_CONF="/etc/supervisor/conf.d/${APP_NAME}-queue.conf"
cat > "${SUPERVISOR_CONF}" <<EOF
[program:${APP_NAME}-queue]
process_name=%(program_name)s_%(process_num)02d
command=/usr/bin/php ${APP_ROOT}/artisan queue:work --sleep=2 --tries=3 --timeout=120
directory=${APP_ROOT}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/log/${APP_NAME}-queue.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stopwaitsecs=3600
environment=APP_ENV="${APP_ENV}"
EOF

touch /var/log/${APP_NAME}-queue.log
chown www-data:www-data /var/log/${APP_NAME}-queue.log
chmod 664 /var/log/${APP_NAME}-queue.log

supervisorctl reread
supervisorctl update
supervisorctl restart "${APP_NAME}-queue:*" || supervisorctl start "${APP_NAME}-queue:*" || true

echo "=== 19) Laravel Scheduler Cron (every minute as www-data) ==="
cat > "/etc/cron.d/${APP_NAME}-scheduler" <<EOF
* * * * * www-data cd ${APP_ROOT} && /usr/bin/php artisan schedule:run >> /dev/null 2>&1
EOF
chmod 644 "/etc/cron.d/${APP_NAME}-scheduler"

echo "=== 20) Configure Nginx ==="
NGINX_SITE="/etc/nginx/sites-available/${APP_NAME}"
PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"

cat > "${NGINX_SITE}" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     ${ORIGIN_CERT_PATH};
    ssl_certificate_key ${ORIGIN_KEY_PATH};

    ssl_protocols TLSv1.2 TLSv1.3;

    root ${APP_ROOT}/public;
    index index.php index.html;

    client_max_body_size 50M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        fastcgi_buffer_size 64k;
        fastcgi_buffers 16 64k;
        fastcgi_busy_buffers_size 128k;
    }

    location ~ /\. {
        deny all;
    }
}
NGINX

ln -sf "${NGINX_SITE}" "/etc/nginx/sites-enabled/${APP_NAME}"
rm -f /etc/nginx/sites-enabled/default || true

nginx -t
systemctl reload nginx

if [[ "${INSTALL_NODE}" =~ ^[Yy]$ ]]; then
  echo "=== 21) (LAST) Add Swap + Build Frontend (1GB droplet safe) ==="
  if ! swapon --show | awk '{print $1}' | grep -qx "/swapfile"; then
    echo "No swap found. Creating ${SWAP_SIZE_MB}MB swapfile..."
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_SIZE_MB}"
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  else
    echo "Swap already enabled."
  fi

  free -h || true

  cd "${APP_ROOT}"
  if [[ -f "${APP_ROOT}/package-lock.json" ]]; then
    npm ci
  else
    npm install
  fi

  NODE_OPTIONS="--max-old-space-size=${NODE_BUILD_HEAP_MB}" npm run build
else
  echo "=== 21) Skipping frontend build because Node.js was not requested ==="
fi

echo "=== 22) Final Laravel permission fix ==="
chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
find "${APP_ROOT}/storage" -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/storage" -type f -exec chmod 664 {} \; || true
find "${APP_ROOT}/bootstrap/cache" -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/bootstrap/cache" -type f -exec chmod 664 {} \; || true

systemctl restart php${PHP_VER}-fpm
supervisorctl restart "${APP_NAME}-queue:*" || true

echo ""
echo "=== ✅ DONE ==="
echo "Site                : https://${DOMAIN}"
echo "App name            : ${APP_NAME}"
echo "App root            : ${APP_ROOT}"
echo "DB name             : ${DB_NAME}"
echo "DB user             : ${DB_USER}"
echo "DB password         : ${DB_PASS}"
echo "DB reset            : ${DB_RESET}"
echo "Node.js installed   : ${INSTALL_NODE}"
echo "Laravel web root    : ${APP_ROOT}/public"
echo "Queue worker log    : /var/log/${APP_NAME}-queue.log"
echo "Supervisor status   : sudo supervisorctl status"
echo "PHP-FPM status      : systemctl status php${PHP_VER}-fpm"
echo "Swap check          : swapon --show"