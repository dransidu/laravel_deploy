#!/usr/bin/env bash
# =============================================================
# 05_services.sh — Supervisor queue worker + Laravel scheduler
# Requires: APP_NAME, APP_ROOT, APP_ENV
# =============================================================

echo ""
echo "=== [1/2] Install Supervisor + configure queue worker ==="
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
supervisorctl restart "${APP_NAME}-queue:*" \
  || supervisorctl start "${APP_NAME}-queue:*" || true

echo "Queue worker configured: /var/log/${APP_NAME}-queue.log"

echo ""
echo "=== [2/2] Laravel scheduler cron (every minute, www-data) ==="
cat > "/etc/cron.d/${APP_NAME}-scheduler" <<EOF
* * * * * www-data cd ${APP_ROOT} && /usr/bin/php artisan schedule:run >> /dev/null 2>&1
EOF
chmod 644 "/etc/cron.d/${APP_NAME}-scheduler"

echo "Scheduler cron written: /etc/cron.d/${APP_NAME}-scheduler"
