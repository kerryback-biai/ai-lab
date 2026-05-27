#!/bin/bash
# Provision a student inside an nspawn container
# Usage: setup-nspawn-user.sh <username> <container_ip> [password]
# Username can have underscores (e.g., test_student) — machine name uses hyphens
set -e

USERNAME="$1"
CONTAINER_IP="$2"
PASSWORD="${3:-jgsbai}"
BASE="/var/lib/machines/biai-base"

# nspawn machine names cannot have underscores
MACHINE_NAME="${USERNAME//_/-}"
MACHINE="/var/lib/machines/$MACHINE_NAME"

if [ -z "$USERNAME" ] || [ -z "$CONTAINER_IP" ]; then
    echo "Usage: $0 <username> <container_ip> [password]"
    exit 1
fi

echo "=== Provisioning $USERNAME (machine: $MACHINE_NAME, IP: $CONTAINER_IP) ==="

# ── Create container from base template ─────────────────────────
if [ ! -d "$MACHINE/usr" ]; then
    echo "Cloning base template..."
    cp -a "$BASE" "$MACHINE"
fi

# ── Create user inside container ────────────────────────────────
echo "Creating user..."
chroot "$MACHINE" bash -c "
    id '$USERNAME' &>/dev/null || useradd -m -s /bin/bash '$USERNAME'
    echo '${USERNAME}:${PASSWORD}' | chpasswd
    usermod -aG docker '$USERNAME' 2>/dev/null || true
"

# ── Create workspace ────────────────────────────────────────────
mkdir -p "$MACHINE/home/$USERNAME/workspace"
chroot "$MACHINE" chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/workspace"

# ── Network config inside container ─────────────────────────────
cat > "$MACHINE/etc/systemd/network/80-container-host0.network" << EOF
[Match]
Name=host0

[Network]
Address=$CONTAINER_IP/24
Gateway=10.100.0.1
DNS=8.8.8.8
DNS=8.8.4.4
EOF

chroot "$MACHINE" bash -c 'systemctl enable systemd-networkd 2>/dev/null || true'

# ── ttyd: Claude Code terminal (port 9000) ──────────────────────
cat > "$MACHINE/etc/systemd/system/ttyd-claude.service" << EOF
[Unit]
Description=Claude Code terminal
After=network.target

[Service]
Type=simple
User=$USERNAME
Environment=HOME=/home/$USERNAME
WorkingDirectory=/home/$USERNAME/workspace
ExecStart=/usr/local/bin/ttyd --port 9000 --writable --base-path /$USERNAME/ -t titleFixed="AI+Code Lab" -t theme={"background":"white","foreground":"#333"} bash -l -c "claude"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ── ttyd: Plain terminal (port 9001) ────────────────────────────
cat > "$MACHINE/etc/systemd/system/ttyd-term.service" << EOF
[Unit]
Description=Plain terminal
After=network.target

[Service]
Type=simple
User=$USERNAME
Environment=HOME=/home/$USERNAME
WorkingDirectory=/home/$USERNAME/workspace
ExecStart=/usr/local/bin/ttyd --port 9001 --writable --base-path /$USERNAME/term/ -t titleFixed="Terminal" -t theme={"background":"white","foreground":"#333"} bash -l
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ── FileBrowser (port 9002) ─────────────────────────────────────
cat > "$MACHINE/etc/systemd/system/filebrowser.service" << EOF
[Unit]
Description=FileBrowser
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/filebrowser -r /home/$USERNAME/workspace -a 0.0.0.0 -p 9002 --noauth --baseurl /$USERNAME/files
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

chroot "$MACHINE" bash -c 'systemctl enable ttyd-claude ttyd-term filebrowser 2>/dev/null || true'

# ── Claude Code settings ────────────────────────────────────────
CLAUDE_DIR="$MACHINE/home/$USERNAME/.claude"
mkdir -p "$CLAUDE_DIR"
cat > "$CLAUDE_DIR/settings.json" << 'EOF'
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)", "WebFetch(*)", "WebSearch(*)"],
    "deny": []
  },
  "theme": "light"
}
EOF
chroot "$MACHINE" chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.claude"

# ── .bashrc banner ──────────────────────────────────────────────
# Remove any existing banner first
sed -i '/# BIAI-APP-PORT-BANNER/,/# END-BIAI-APP-PORT-BANNER/d' "$MACHINE/home/$USERNAME/.bashrc"
cat >> "$MACHINE/home/$USERNAME/.bashrc" << 'BASHRC'

# BIAI-APP-PORT-BANNER
echo ""
echo "  -----------------------------------------------------------------------"
echo ""
echo "  Your app runs on port 8000 — just use: uvicorn app:app --port 8000"
echo ""
echo "  To kill a running app:  kill $(lsof -t -i:8000)"
echo ""
echo "  To stop a Docker container: docker compose down"
echo ""
echo "  -----------------------------------------------------------------------"
echo ""
# END-BIAI-APP-PORT-BANNER
BASHRC

# ── Anthropic API key (read from host env file) ────────────────
if [ -f /etc/biai.env ]; then
    API_KEY=$(grep ANTHROPIC_API_KEY /etc/biai.env | cut -d= -f2)
    if [ -n "$API_KEY" ]; then
        # Add to container's environment for Claude Code
        sed -i '/ANTHROPIC_API_KEY/d' "$MACHINE/home/$USERNAME/.bashrc"
        echo "export ANTHROPIC_API_KEY=$API_KEY" >> "$MACHINE/home/$USERNAME/.bashrc"
        # Also set in ttyd-claude service
        sed -i "s|Environment=HOME=/home/$USERNAME|Environment=HOME=/home/$USERNAME\nEnvironment=ANTHROPIC_API_KEY=$API_KEY|" \
            "$MACHINE/etc/systemd/system/ttyd-claude.service"
    fi
fi

chroot "$MACHINE" chown "$USERNAME:$USERNAME" "/home/$USERNAME/.bashrc"

# ── Register in /etc/biai-containers ────────────────────────────
# Format: username:machine_name:container_ip
sed -i "/^${USERNAME}:/d" /etc/biai-containers 2>/dev/null || true
echo "${USERNAME}:${MACHINE_NAME}:${CONTAINER_IP}" >> /etc/biai-containers

# ── nspawn config ───────────────────────────────────────────────
mkdir -p /etc/systemd/nspawn
cat > "/etc/systemd/nspawn/${MACHINE_NAME}.nspawn" << EOF
[Exec]
Boot=yes
Capability=CAP_NET_ADMIN CAP_SYS_ADMIN
PrivateUsers=no

[Network]
VirtualEthernet=yes
Bridge=br-biai
EOF

# ── Start the container ─────────────────────────────────────────
echo "Starting container..."
systemctl enable systemd-nspawn@"$MACHINE_NAME" 2>/dev/null || true
systemctl start systemd-nspawn@"$MACHINE_NAME" 2>/dev/null || true

# Wait for container networking
sleep 3

echo "=== $USERNAME provisioned (machine: $MACHINE_NAME, IP: $CONTAINER_IP) ==="
