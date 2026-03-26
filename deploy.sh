#!/usr/bin/env bash
set -euo pipefail

############################################################
# Laravel Production Deploy — Main Orchestrator
# Ubuntu 24.04 LTS
#
# Runs each step in order by sourcing the scripts/ modules.
# All configuration is collected once in 00_config.sh and
# exported for the remaining scripts.
#
# Steps:
#   00_config.sh     — interactive prompts + confirmation
#   01_system_tools.sh — apt, UFW, Nginx, PHP, Composer, Node
#   02_database.sh   — PostgreSQL install + DB creation
#   03_app_setup.sh  — clone/update repo, .env, Composer, artisan
#   04_ssl.sh        — paste Cloudflare Origin cert + key
#   05_services.sh   — Supervisor queue worker + cron scheduler
#   06_nginx.sh      — Nginx virtual-host config + reload
#   07_frontend.sh   — swap, npm build, final permission fix
############################################################

# ---------------------------------------------------------------
# Root check
# ---------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------
# Source each module in order
# Variables set/exported in 00_config.sh are available to all
# subsequent scripts because they run in the same shell.
# ---------------------------------------------------------------
run_step() {
  local label="$1"
  local file="$2"
  echo ""
  echo "##############################################"
  echo "#  ${label}"
  echo "##############################################"
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/scripts/${file}"
}

run_step "STEP 0 — Configuration"          "00_config.sh"
run_step "STEP 1 — System tools"           "01_system_tools.sh"
run_step "STEP 2 — Database"               "02_database.sh"
run_step "STEP 3 — Application setup"      "03_app_setup.sh"
run_step "STEP 4 — SSL certificate"        "04_ssl.sh"
run_step "STEP 5 — Services (queue/cron)"  "05_services.sh"
run_step "STEP 6 — Nginx"                  "06_nginx.sh"
run_step "STEP 7 — Frontend build"         "07_frontend.sh"

# ---------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------
echo ""
echo "=============================================="
echo "  DEPLOYMENT COMPLETE"
echo "=============================================="
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
