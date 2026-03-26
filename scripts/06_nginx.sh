#!/usr/bin/env bash
# =============================================================
# 06_nginx.sh — Write Nginx virtual-host config and reload
# Requires: APP_NAME, APP_ROOT, DOMAIN,
#           ORIGIN_CERT_PATH, ORIGIN_KEY_PATH,
#           PHP_VER, PHP_SOCK
# =============================================================

echo ""
echo "=== Nginx — virtual-host for ${DOMAIN} ==="

NGINX_SITE="/etc/nginx/sites-available/${APP_NAME}"

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

        fastcgi_buffer_size     64k;
        fastcgi_buffers         16 64k;
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

echo "Nginx configured and reloaded for https://${DOMAIN}"
