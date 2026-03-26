#!/usr/bin/env bash
# =============================================================
# 02_database.sh — Install PostgreSQL, set password, create DB
# Requires: DB_NAME, DB_USER, DB_PASS, DB_RESET,
#           UPDATE_POSTGRES_PASS
# =============================================================

echo ""
echo "=== [1/3] Install PostgreSQL ==="
apt-get install -y postgresql postgresql-contrib
systemctl enable --now postgresql

echo ""
echo "=== [2/3] Configure PostgreSQL user ==="
if [[ "${UPDATE_POSTGRES_PASS}" =~ ^[Yy]$ ]]; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -c "ALTER ROLE postgres WITH PASSWORD '${DB_PASS}';"
  echo "Updated postgres password."
else
  echo "Skipped postgres password update."
fi

echo ""
echo "=== [3/3] Create database '${DB_NAME}' ==="
if [[ "${DB_RESET}" =~ ^[Yy]$ ]]; then
  echo "FULL RESET: terminating connections and dropping '${DB_NAME}'..."

  sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();
SQL

  sudo -u postgres dropdb --if-exists "${DB_NAME}"
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
  echo "Database recreated: ${DB_NAME}"
else
  if ! sudo -u postgres psql -tAc \
      "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
    echo "Created database: ${DB_NAME}"
  else
    echo "Database already exists: ${DB_NAME}"
  fi
fi
