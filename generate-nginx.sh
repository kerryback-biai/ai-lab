#!/bin/bash
# Regenerate nginx config from /etc/biai-ports
set -e

PORTS_FILE="/etc/biai-ports"
NGINX_LOCATIONS=""

while IFS=: read -r USERNAME TTYD_PORT FB_PORT TERM_PORT APP_PORT; do
    [ -z "$USERNAME" ] && continue
    # Default term port if missing (legacy 3-field format)
    [ -z "$TERM_PORT" ] && TERM_PORT=$((TTYD_PORT + 2000))
    # Default app port if missing (4-field legacy format)
    [ -z "$APP_PORT" ] && APP_PORT=$((TTYD_PORT + 3000))

    NGINX_LOCATIONS="$NGINX_LOCATIONS
    # $USERNAME — claude code terminal
    location /$USERNAME/ {
        proxy_pass http://127.0.0.1:$TTYD_PORT;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
    }

    # $USERNAME — plain terminal
    location /$USERNAME/term/ {
        proxy_pass http://127.0.0.1:$TERM_PORT;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
    }

    # $USERNAME — file browser (proxy auth: auto-login via X-FB-User header)
    location /$USERNAME/files/api/login {
        proxy_pass http://127.0.0.1:$FB_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-FB-User admin;
        proxy_http_version 1.1;
    }
    location /$USERNAME/files/ {
        proxy_pass http://127.0.0.1:$FB_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;

        # Inject auto-login script before </head>
        proxy_set_header Accept-Encoding \"\";
        sub_filter '</head>' '<script>
(function(){
  if(!localStorage.getItem(\"jwt\")){
    fetch(\"/$USERNAME/files/api/login\").then(r=>r.text()).then(t=>{
      localStorage.setItem(\"jwt\",t);
      location.reload();
    });
  }
})();
</script></head>';
        sub_filter_once on;
        sub_filter_types text/html;
    }

    # $USERNAME — app preview
    location /$USERNAME/app/ {
        proxy_pass http://127.0.0.1:$APP_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
    }"
done < "$PORTS_FILE"

cat > /etc/nginx/sites-available/biai-vm << NGINX
server {
    listen 80;
    server_name ai-lab.rice-business.org;
    client_max_body_size 50M;

    # Login page
    location = / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /login {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /provision {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /workspace {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /admin {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
$NGINX_LOCATIONS
}
NGINX

ln -sf /etc/nginx/sites-available/biai-vm /etc/nginx/sites-enabled/biai-vm
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Re-apply SSL certificate if certbot is installed and a cert exists
if command -v certbot &>/dev/null && [ -d /etc/letsencrypt/live/ai-lab.rice-business.org ]; then
    certbot install --cert-name ai-lab.rice-business.org --nginx --redirect --non-interactive 2>/dev/null
    echo "Nginx config regenerated (with SSL)."
else
    echo "Nginx config regenerated (no SSL — run certbot to enable HTTPS)."
fi
