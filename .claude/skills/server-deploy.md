---
name: server-deploy
description: Deploy files to the BIAI lab server (ai-lab.rice-business.org) and distribute them to all user workspace directories. This skill should be used when uploading data files, scripts, templates, or configuration to student workspaces on the server, or when running admin commands on the server remotely.
---

# Server Deploy — BIAI Lab

Deploy files to the ai-lab server and distribute them to all user directories.

- **Server:** `157.245.133.86` (ai-lab.rice-business.org)
- **Root access:** `sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86`
- **User registry:** `/etc/biai-ports` (format: `username:ttyd_port:fb_port:term_port:app_port`)
- **Workspace path:** `/home/<username>/workspace/`

## Uploading Files to the Server

Use `scp` via `sshpass` to copy files to a staging location (`/tmp/` or `/shared/data/`):

```bash
sshpass -p 'FdsaJkl0!A' scp <local-file> root@157.245.133.86:/tmp/
```

For multiple files or directories:

```bash
sshpass -p 'FdsaJkl0!A' scp -r <local-dir>/* root@157.245.133.86:/tmp/
```

## Distributing to All Users

Loop over `/etc/biai-ports` and copy from staging to each user's workspace:

```bash
sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 'while IFS=: read -r username rest; do
  WS="/home/$username/workspace"
  if [ -d "$WS" ]; then
    cp /tmp/<filename> "$WS/"
    chown "$username" "$WS/<filename>"
    echo "OK: $username"
  fi
done < /etc/biai-ports'
```

### Important Patterns

- **Always `chown`** after copying — files copied as root will be owned by root otherwise.
- **Use `cp -n`** (no-clobber) when distributing files students may have already modified.
- **Use plain `cp`** when updating files that should overwrite (e.g., CLAUDE.md, new exercises).
- **Use `-R` with `chown`** for directories: `chown -R "$username" "$WS/session3/"`.

## Deploy Script Pattern (for complex updates)

For multi-file deployments, create a script locally, scp it to the server, and execute:

```bash
# 1. Create deploy script locally
cat > /tmp/deploy-all.sh << 'SCRIPT'
#!/bin/bash
while IFS=: read -r username rest; do
  WS="/home/$username/workspace"
  if [ -d "$WS" ]; then
    cp /tmp/new_exercise.py "$WS/"
    cp -n /tmp/data_file.csv "$WS/data/"
    chown -R "$username" "$WS/"
    echo "OK: $username"
  fi
done < /etc/biai-ports
SCRIPT

# 2. Upload script and files to server
sshpass -p 'FdsaJkl0!A' scp /tmp/deploy-all.sh /tmp/new_exercise.py /tmp/data_file.csv root@157.245.133.86:/tmp/

# 3. Execute remotely
sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 "bash /tmp/deploy-all.sh"
```

## Running Admin Commands

To run any command on the server as root:

```bash
sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 '<command>'
```

Examples:

```bash
# Check a user's services
sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 'systemctl status ttyd-kerry_back'

# Restart the login app
sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 'systemctl restart biai-login'

# Regenerate nginx config
sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 'bash /opt/biai-vm/generate-nginx.sh'

# View /etc/biai-ports
sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 'cat /etc/biai-ports'
```

## Updating Server Scripts

To update files in `/opt/biai-vm/` from the GitHub repo:

```bash
for f in setup-user.sh generate-nginx.sh login-app.py add-app-port.sh; do
  sshpass -p 'FdsaJkl0!A' ssh root@157.245.133.86 "curl -sL https://raw.githubusercontent.com/kerryback-biai/ai-lab/master/$f -o /opt/biai-vm/$f"
done
```
