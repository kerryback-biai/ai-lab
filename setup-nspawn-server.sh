#!/bin/bash
# Set up the host for nspawn containers
# Run once on fresh Ubuntu 24.04 droplet after base packages are installed
set -e

# ── Bridge network ──────────────────────────────────────────────
echo "Creating bridge network br-biai..."
ip link add br-biai type bridge 2>/dev/null || true
ip addr add 10.100.0.1/24 dev br-biai 2>/dev/null || true
ip link set br-biai up

# Make bridge persistent via netplan
cat > /etc/netplan/60-biai-bridge.yaml << 'EOF'
network:
  version: 2
  bridges:
    br-biai:
      addresses: [10.100.0.1/24]
      dhcp4: false
EOF
netplan apply 2>/dev/null || true

# ── NAT for container internet access ───────────────────────────
echo "Setting up NAT..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-biai.conf
sysctl -p /etc/sysctl.d/99-biai.conf

# Get the public interface
PUB_IF=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')
iptables -t nat -C POSTROUTING -s 10.100.0.0/24 -o "$PUB_IF" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o "$PUB_IF" -j MASQUERADE

# Persist iptables
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
netfilter-persistent save

# ── Create base nspawn template ─────────────────────────────────
echo "Creating base filesystem template (this takes a few minutes)..."
BASE=/var/lib/machines/biai-base
if [ ! -d "$BASE/usr" ]; then
    debootstrap --include=systemd,dbus,sudo,bash-completion,curl,wget,ca-certificates,git,openssh-client,locales,python3,python3-pip,python3-venv,sqlite3,lsof \
        noble "$BASE" http://archive.ubuntu.com/ubuntu
fi

# Configure base template
echo "Configuring base template..."

# Set locale
chroot "$BASE" bash -c 'locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8'

# DNS
echo "nameserver 8.8.8.8" > "$BASE/etc/resolv.conf"
echo "nameserver 8.8.4.4" >> "$BASE/etc/resolv.conf"

# Install Node.js 22
chroot "$BASE" bash -c '
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
apt-get install -y nodejs && \
apt-get clean
'

# Install Claude Code CLI
chroot "$BASE" bash -c 'npm install -g @anthropic-ai/claude-code'

# Install ttyd
TTYD_VERSION="1.7.7"
curl -fsSL "https://github.com/nicehash/ttyd/releases/download/${TTYD_VERSION}/ttyd.x86_64" -o "$BASE/usr/local/bin/ttyd"
chmod +x "$BASE/usr/local/bin/ttyd"

# Install Python packages commonly needed
chroot "$BASE" bash -c '
pip3 install --break-system-packages fastapi uvicorn python-dotenv anthropic openai matplotlib numpy pandas
'

# Install Docker (rootless) prerequisites
chroot "$BASE" bash -c '
apt-get update && apt-get install -y uidmap fuse-overlayfs slirp4netns docker.io && apt-get clean
'

# Install FileBrowser
chroot "$BASE" bash -c '
curl -fsSL https://raw.githubusercontent.com/filebrowser/filebrowser/master/install.sh | bash
'

# ── Login app dependencies ──────────────────────────────────────
echo "Installing login app dependencies on host..."
pip3 install --break-system-packages psycopg2-binary fastapi uvicorn

# ── Create /opt/biai-vm on host ─────────────────────────────────
mkdir -p /opt/biai-vm

echo ""
echo "=== Base setup complete ==="
echo "Base template at: $BASE"
echo "Bridge network: br-biai (10.100.0.1/24)"
echo "Next: deploy scripts to /opt/biai-vm and run setup-user.sh for each student"
