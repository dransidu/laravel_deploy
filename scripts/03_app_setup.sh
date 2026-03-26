#!/usr/bin/env bash
# =============================================================
# 03_app_setup.sh — Clone/update repo, .env, Composer install,
#                   artisan commands, migrations, permissions
# Requires: APP_NAME, APP_ROOT, REPO_URL, BRANCH,
#           APP_ENV, APP_DEBUG, APP_URL,
#           DB_NAME, DB_USER, DB_PASS, PHP_VER
# =============================================================

# ---------------------------------------------------------------
# Helper: set or update a key in a .env file
# ---------------------------------------------------------------
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

echo ""
echo "=== [1/6] Prepare project directory ${APP_ROOT} ==="
mkdir -p "${APP_ROOT}"
chown -R root:root "${APP_ROOT}"
chmod 755 /var/www
chmod 755 "${APP_ROOT}"

echo ""
echo "=== [2/6] Clone or update repository ==="
if [[ ! -d "${APP_ROOT}/.git" ]]; then
  if [[ -n "$(ls -A "${APP_ROOT}" 2>/dev/null)" ]]; then
    echo "ERROR: ${APP_ROOT} is not empty and not a git repo. Move or empty it first."
    exit 1
  fi
  git clone -b "${BRANCH}" "${REPO_URL}" "${APP_ROOT}"
else
  git -C "${APP_ROOT}" fetch --all
  git -C "${APP_ROOT}" reset --hard "origin/${BRANCH}"
fi

echo ""
echo "=== [3/6] Laravel .env setup ==="
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

ensure_env "APP_NAME"        "${APP_NAME}"    "${APP_ROOT}/.env"
ensure_env "APP_ENV"         "${APP_ENV}"     "${APP_ROOT}/.env"
ensure_env "APP_DEBUG"       "${APP_DEBUG}"   "${APP_ROOT}/.env"
ensure_env "APP_URL"         "${APP_URL}"     "${APP_ROOT}/.env"
ensure_env "DB_CONNECTION"   "pgsql"          "${APP_ROOT}/.env"
ensure_env "DB_HOST"         "127.0.0.1"      "${APP_ROOT}/.env"
ensure_env "DB_PORT"         "5432"           "${APP_ROOT}/.env"
ensure_env "DB_DATABASE"     "${DB_NAME}"     "${APP_ROOT}/.env"
ensure_env "DB_USERNAME"     "${DB_USER}"     "${APP_ROOT}/.env"
ensure_env "DB_PASSWORD"     "${DB_PASS}"     "${APP_ROOT}/.env"
ensure_env "QUEUE_CONNECTION" "database"      "${APP_ROOT}/.env"

echo ""
echo "=== [4/6] Fix file permissions ==="
chown -R root:root "${APP_ROOT}"
find "${APP_ROOT}" -type d -exec chmod 755 {} \; || true
find "${APP_ROOT}" -type f -exec chmod 644 {} \; || true

mkdir -p "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
find "${APP_ROOT}/storage"           -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/storage"           -type f -exec chmod 664 {} \; || true
find "${APP_ROOT}/bootstrap/cache"   -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/bootstrap/cache"   -type f -exec chmod 664 {} \; || true

echo ""
echo "=== [5/6] Install Composer dependencies ==="
cd "${APP_ROOT}"
composer install --no-interaction --no-dev --prefer-dist --optimize-autoloader

echo ""
echo "=== [6/6] Artisan commands — key, cache, migrate, seed, wayfinder ==="

# Generate app key first so all subsequent commands can bootstrap correctly
if ! grep -qE '^APP_KEY=base64:' "${APP_ROOT}/.env"; then
  php artisan key:generate --force
fi

# Clear stale caches before anything else
php artisan config:clear || true
php artisan route:clear  || true
php artisan view:clear   || true
php artisan cache:clear  || true

# Build fresh production caches so service providers resolve correctly
# (missing config cache is a common cause of "Call to a member function on null")
php artisan config:cache || true
php artisan route:cache  || true
php artisan view:cache   || true

# Migrations are strict — a failed migration means a broken app
php artisan migrate --force

# Seeder failures (e.g. "Call to a member function name() on null") are app-level
# bugs that must not block Nginx/PHP-FPM coming up. We warn and continue.
if ! php artisan db:seed --force; then
  echo ""
  echo "  !! WARNING: db:seed failed — your seeder has an application error."
  echo "  !! Common cause: calling ->relationship->property on a null model."
  echo "  !! Fix the seeder in database/seeders/ then re-run:"
  echo "  !!   cd ${APP_ROOT} && php artisan db:seed --force"
  echo ""
fi

php artisan wayfinder:generate || true

# Re-apply writable permissions after artisan tasks
chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
find "${APP_ROOT}/storage"           -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/storage"           -type f -exec chmod 664 {} \; || true
find "${APP_ROOT}/bootstrap/cache"   -type d -exec chmod 775 {} \; || true
find "${APP_ROOT}/bootstrap/cache"   -type f -exec chmod 664 {} \; || true
