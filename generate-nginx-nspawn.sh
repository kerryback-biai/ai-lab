#!/bin/bash
# Regenerate nginx config from /etc/biai-containers
# Format: username:container_ip
set -e

CONTAINERS_FILE="/etc/biai-containers"
NGINX_LOCATIONS=""

while IFS=: read -r USERNAME MACHINE_NAME CONTAINER_IP; do
    [ -z "$USERNAME" ] && continue
    [ -z "$CONTAINER_IP" ] && continue

    NGINX_LOCATIONS="$NGINX_LOCATIONS
    # $USERNAME — claude code terminal
    location /$USERNAME/ {
        proxy_pass http://$CONTAINER_IP:9000;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
    }

    # $USERNAME — plain terminal
    location /$USERNAME/term/ {
        proxy_pass http://$CONTAINER_IP:9001;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
    }

    # $USERNAME — file browser (proxy auth: auto-login via X-FB-User header)
    location /$USERNAME/files/api/login {
        proxy_pass http://$CONTAINER_IP:9002;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-FB-User admin;
        proxy_http_version 1.1;
    }
    location /$USERNAME/files/ {
        proxy_pass http://$CONTAINER_IP:9002;
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

    # $USERNAME — app (always port 8000 inside container)
    location /$USERNAME/app/ {
        proxy_pass http://$CONTAINER_IP:8000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_intercept_errors on;
        error_page 502 =200 /$USERNAME/app/_no_app;
    }
    location = /$USERNAME/app/_no_app {
        internal;
        default_type text/html;
        return 200 '<html><body style=\"font-family:Arial,sans-serif;display:flex;align-items:center;justify-content:center;height:100%;margin:0;background:#f5f5f5\"><p style=\"color:#555;font-size:14px\">If you have started an app, refresh this page to view it.</p></body></html>';
    }"
done < "$CONTAINERS_FILE"

cat > /etc/nginx/sites-available/biai-vm << NGINX
server {
    listen 80;
    server_name ai-lab.rice-business.org;
    client_max_body_size 50M;

    # Login page
    location = / {
        proxy_pass http://127.0.0.1:7900;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /login {
        proxy_pass http://127.0.0.1:7900;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /provision {
        proxy_pass http://127.0.0.1:7900;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /workspace {
        proxy_pass http://127.0.0.1:7900;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /admin {
        proxy_pass http://127.0.0.1:7900;
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
