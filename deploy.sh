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
# Resume support: if a previous run broke, run this script
# again and choose "yes" to resume — already-completed steps
# are skipped automatically.
#
# Steps:
#   00_config.sh       — interactive prompts + confirmation
#   01_system_tools.sh — apt, UFW, Nginx, PHP, Composer, Node
#   02_database.sh     — PostgreSQL install + DB creation
#   03_app_setup.sh    — clone/update repo, .env, Composer, artisan
#   04_ssl.sh          — paste Cloudflare Origin cert + key
#   05_services.sh     — Supervisor queue worker + cron scheduler
#   06_nginx.sh        — Nginx virtual-host config + reload
#   07_frontend.sh     — swap, npm build, final permission fix
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
# State directory — persists progress so broken runs can resume
# ---------------------------------------------------------------
STATE_DIR="/var/tmp/laravel_deploy_state"
STATE_CONFIG="${STATE_DIR}/config.env"

RESUME=false

if [[ -f "${STATE_CONFIG}" ]]; then
  echo ""
  echo "A previous deployment state was found at: ${STATE_DIR}"
  echo "You can resume from the step that failed, skipping everything already done."
  read -rp "Resume from last run? (y/N): " _RESUME_CHOICE
  if [[ "${_RESUME_CHOICE}" =~ ^[Yy]$ ]]; then
    RESUME=true
    # shellcheck source=/dev/null
    source "${STATE_CONFIG}"
    echo "Previous configuration loaded."
  else
    rm -rf "${STATE_DIR}"
    echo "Starting a fresh deployment."
  fi
fi

mkdir -p "${STATE_DIR}"

# ---------------------------------------------------------------
# Helper: persist all config variables to the state file so a
# resumed run can reload them without re-prompting the user.
# ---------------------------------------------------------------
save_config() {
  {
    for _var in APP_NAME APP_ROOT DOMAIN APP_URL REPO_URL BRANCH \
                DB_NAME DB_USER DB_PASS \
                PHP_VER NODE_MAJOR \
                APP_ENV APP_DEBUG \
                NODE_BUILD_HEAP_MB ADD_SWAP SWAP_SIZE_MB \
                DB_RESET INSTALL_NODE UPDATE_POSTGRES_PASS \
                SSL_DIR_CERT SSL_DIR_KEY ORIGIN_CERT_PATH ORIGIN_KEY_PATH \
                PHP_SOCK; do
      printf 'export %s=%q\n' "${_var}" "${!_var}"
    done
  } > "${STATE_CONFIG}"
}

# ---------------------------------------------------------------
# Step runner — auto-skips steps that already finished
# ---------------------------------------------------------------
run_step() {
  local label="$1"
  local file="$2"
  local flag="${STATE_DIR}/${file%.sh}.done"

  if [[ "${RESUME}" == "true" && -f "${flag}" ]]; then
    echo ""
    echo "  >> ${label}: already completed — skipping"
    return 0
  fi

  echo ""
  echo "##############################################"
  echo "#  ${label}"
  echo "##############################################"

  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/scripts/${file}"

  # Mark step as done
  touch "${flag}"
}

# ---------------------------------------------------------------
# Run all steps
# ---------------------------------------------------------------

# Config step: skip prompts entirely when resuming (already loaded above)
if [[ "${RESUME}" == "true" ]]; then
  echo ""
  echo "  >> STEP 0 — Configuration: already loaded from state — skipping"
else
  run_step "STEP 0 — Configuration" "00_config.sh"
  # Persist config immediately so any subsequent break can be resumed
  save_config
  touch "${STATE_DIR}/00_config.done"
fi

run_step "STEP 1 — System tools"           "01_system_tools.sh"
run_step "STEP 2 — Database"               "02_database.sh"
run_step "STEP 3 — Application setup"      "03_app_setup.sh"
run_step "STEP 4 — SSL certificate"        "04_ssl.sh"
run_step "STEP 5 — Services (queue/cron)"  "05_services.sh"
run_step "STEP 6 — Nginx"                  "06_nginx.sh"
run_step "STEP 7 — Frontend build"         "07_frontend.sh"

# All steps succeeded — clean up state
rm -rf "${STATE_DIR}"

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
