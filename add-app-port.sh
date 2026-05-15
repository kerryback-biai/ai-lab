#!/bin/bash
# Migration script: add APP_PORT to all existing users
# Run on the server: sudo bash add-app-port.sh
set -e

PORTS_FILE="/etc/biai-ports"

if [ ! -f "$PORTS_FILE" ]; then
    echo "No $PORTS_FILE found."
    exit 1
fi

# Install fastapi and uvicorn system-wide
pip install --quiet fastapi uvicorn 2>/dev/null || pip3 install --quiet fastapi uvicorn 2>/dev/null || true

echo "Updating /etc/biai-ports with APP_PORT and patching user environments..."

while IFS=: read -r USERNAME TTYD_PORT FB_PORT TERM_PORT APP_PORT; do
    [ -z "$USERNAME" ] && continue

    # Default term port if missing
    [ -z "$TERM_PORT" ] && TERM_PORT=$((TTYD_PORT + 2000))
    # Assign app port if missing
    [ -z "$APP_PORT" ] && APP_PORT=$((TTYD_PORT + 3000))

    # Rewrite line with all 5 fields
    sed -i "s/^$USERNAME:.*/$USERNAME:$TTYD_PORT:$FB_PORT:$TERM_PORT:$APP_PORT/" "$PORTS_FILE"

    # Add APP_PORT to .bashrc (idempotent)
    BASHRC="/home/$USERNAME/.bashrc"
    if [ -f "$BASHRC" ]; then
        if ! grep -q "APP_PORT" "$BASHRC" 2>/dev/null; then
            sed -i "/ANTHROPIC_API_KEY/a export APP_PORT=$APP_PORT" "$BASHRC"
        else
            sed -i "s/^export APP_PORT=.*/export APP_PORT=$APP_PORT/" "$BASHRC"
        fi
    fi

    # Add APP_PORT to Claude Code settings env
    SETTINGS_FILE="/home/$USERNAME/.claude/settings.json"
    if [ -f "$SETTINGS_FILE" ] && ! grep -q "APP_PORT" "$SETTINGS_FILE"; then
        sed -i "s/\"ANTHROPIC_API_KEY\"/\"APP_PORT\": \"$APP_PORT\",\n    \"ANTHROPIC_API_KEY\"/" "$SETTINGS_FILE"
        chown "$USERNAME" "$SETTINGS_FILE"
    fi

    # Update workspace CLAUDE.md with app instructions
    CLAUDE_MD="/home/$USERNAME/workspace/CLAUDE.md"
    if [ -f "$CLAUDE_MD" ] && ! grep -q "Running Web Apps" "$CLAUDE_MD"; then
        sed -i '/^## Guidelines/i ## Running Web Apps\n- Your app port is available as `$APP_PORT` in the terminal\n- To run a FastAPI app: `uvicorn app:app --host 0.0.0.0 --port $APP_PORT`\n- Click the **App** tab in the left pane to view your running app\n- FastAPI and uvicorn are pre-installed\n' "$CLAUDE_MD"
        chown "$USERNAME" "$CLAUDE_MD"
    fi

    echo "  $USERNAME: APP_PORT=$APP_PORT"
done < "$PORTS_FILE"

# Regenerate nginx with new app proxy locations
bash /opt/biai-vm/generate-nginx.sh

# Restart login app to pick up the new App tab
systemctl restart biai-login

echo "Done. All users now have APP_PORT and the App tab is live."
