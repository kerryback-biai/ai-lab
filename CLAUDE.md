# BIAI Lab Server

Multi-user AI lab for Rice Business Executive Education. Each student runs in an isolated **systemd-nspawn container** with their own network namespace, so everyone can use port 8000 without conflicts.

- **Domain:** `ai-lab.rice-business.org`
- **IP:** `159.223.186.195` (old server: `157.245.133.86`)
- **SSH:** `root@159.223.186.195` (key-based auth from Kerry's machine)
- **Architecture:** systemd-nspawn containers on a bridge network (10.100.0.0/24)
- **Container registry:** `/etc/biai-containers` (format: `username:machine-name:container_ip`)

Each user has a workspace at `/var/lib/machines/<machine-name>/home/<user>/workspace/`.

**Important:** nspawn machine names use hyphens (e.g., `kerry-back`), but Linux usernames inside containers use underscores (e.g., `kerry_back`).

## Container Management

```bash
# List running containers
machinectl list

# Start/stop a container
systemctl start systemd-nspawn@<machine-name>
systemctl stop systemd-nspawn@<machine-name>

# Shell into a container
PID=$(machinectl show <machine-name> -p Leader --value)
nsenter -t $PID -m -u -i -n -p -- su - <username>

# Check services inside a container
nsenter -t $PID -m -u -i -n -p -- systemctl status ttyd-claude ttyd-term filebrowser
```

## Distributing Files to Users

To upload files to every user's workspace:

```bash
# 1. Copy the file(s) to the server
scp <local-file> root@159.223.186.195:/tmp/

# 2. SSH in and distribute to all containers
ssh root@159.223.186.195 'while IFS=: read -r USERNAME MACHINE_NAME CONTAINER_IP; do
    [ -z "$USERNAME" ] && continue
    DEST="/var/lib/machines/$MACHINE_NAME/home/$USERNAME/workspace"
    mkdir -p "$DEST/<target-path>"
    cp -r /tmp/<file-or-dir> "$DEST/<target-path>/"
    chroot "/var/lib/machines/$MACHINE_NAME" chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/workspace/<target-path>"
    echo "Done: $USERNAME"
done < /etc/biai-containers
rm -rf /tmp/<file-or-dir>'
```

## Web App Path Fix (absolute → relative)

When distributing files that contain a **web app** (look for HTML/JS with `fetch()` calls, Dockerfile, docker-compose.yml, or FastAPI/Flask apps), **ask Kerry** if absolute API paths should be converted to relative paths before uploading.

**Why:** Each user's app is served behind an nginx sub-path (`/username/app/`). Absolute fetch URLs like `fetch('/api/chat')` resolve to the server root and hit the login app, which returns HTML. The JS then fails with `Unexpected token '<'... is not valid JSON`. Relative URLs like `fetch('api/chat')` resolve correctly against the sub-path.

**What to look for:** `fetch('/...')` patterns in JS, `action="/..."` in HTML forms, `href="/api/..."`, or any hardcoded absolute API paths.

## Installing Python Packages for All Users

```bash
ssh root@159.223.186.195 '
while IFS=: read -r USERNAME MACHINE_NAME CONTAINER_IP; do
    [ -z "$MACHINE_NAME" ] && continue
    PID=$(machinectl show "$MACHINE_NAME" -p Leader --value 2>/dev/null)
    [ -z "$PID" ] && continue
    nsenter -t "$PID" -m -u -i -n -p -- pip3 install --break-system-packages <package> 2>/dev/null
    echo "Done: $USERNAME"
done < /etc/biai-containers'
```

Also install in the base template for future containers:
```bash
ssh root@159.223.186.195 'chroot /var/lib/machines/biai-base pip3 install --break-system-packages <package>'
```

## Known Issue: App Tab Shows "Bad Gateway" Before Any App Is Running

When a student first clicks the App tab, they see a 502 Bad Gateway because nothing is listening on port 8000 yet. This is cosmetic — once they start an app, clicking refresh shows it. Fix planned for the June server (e.g., nginx `error_page 502` with a friendly message).

## Key Scripts

| Script | Purpose |
|---|---|
| `setup-nspawn-server.sh` | One-time host setup (bridge, NAT, base template) |
| `setup-nspawn-user.sh` | Provision a single user container |
| `generate-nginx-nspawn.sh` | Regenerate nginx config from `/etc/biai-containers` |
| `login-app-nspawn.py` | FastAPI login + workspace + admin panel (port 7900) |
| `fix-claudemd.py` | Update CLAUDE.md in all containers |
| `fix-bashrc.py` | Update terminal banner in all containers |

## System Tuning (required for 45+ containers)

These sysctl settings must be applied for all containers to start:
```
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
fs.nr_open=1048576
fs.file-max=2097152
net.ipv4.ip_forward=1
```

Each container also needs `DefaultLimitNOFILE=65536` in `/etc/systemd/system.conf.d/limits.conf`.
