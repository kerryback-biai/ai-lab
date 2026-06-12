---
name: digitalocean
description: "Manage the BIAI lab DigitalOcean droplets. Use this skill for server management: SSH access, droplet power operations, API access, checking status, and recovering SSH access when locked out."
---

# DigitalOcean Server Management — BIAI Labs

## Current Droplets (as of June 2026)

| Droplet | ID | IP | Domain |
|---|---|---|---|
| biai-vm-v2 (ai-lab) | 572016029 | 159.223.186.195 | ai-lab.rice-business.org |
| junelab-biai | 572894552 | 68.183.59.1 | lab-june.rice-business.org |
| auglab-biai | 575347814 | 138.197.23.251 | lab-aug.rice-business.org |

The old `biai-vm` droplet (157.245.133.86, vm.kerryback.com) was DESTROYED. Any reference to it, or to the `sshpass -p 'FdsaJkl0!A'` root password, is obsolete — that password works nowhere now.

## SSH Access

All servers accept publickey auth only (no passwords). Kerry's key is `~/.ssh/id_ed25519` (ed25519, generated June 2, 2026; registered on DO as "kerry-macbook").

```bash
ssh root@<ip> '<command>'
```

If a server rejects the key ("Permission denied (publickey)"), the fix is the DO web console:
1. DigitalOcean dashboard → Droplets → <droplet> → Access → Launch Droplet Console (the droplets have the agent, so this opens a root shell directly).
2. Paste:
```
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3/LFU8k1Y4Y0fQHclJJf9KeQO82/Beo4rWDbsXZfnv kerryback@gmail.com' >> /root/.ssh/authorized_keys
```
Do NOT trigger a DO password reset unless the console demands a password — on June 2, 2026 a password reset power-cycled the droplet and briefly broke its networking.

There is no old private key on this Mac, none in Bitwarden, and the DO API cannot inject keys into a running droplet. Don't re-search for these.

## API Access (no doctl installed)

The token is `DIGITAL_OCEAN_TOKEN` in `~/.env`. Use curl:

```bash
source ~/.env
# List droplets
curl -s -H "Authorization: Bearer $DIGITAL_OCEAN_TOKEN" 'https://api.digitalocean.com/v2/droplets?per_page=50'

# Droplet actions (reboot, power-off, power-on)
curl -s -X POST -H "Authorization: Bearer $DIGITAL_OCEAN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"type":"reboot"}' 'https://api.digitalocean.com/v2/droplets/<id>/actions'

# Recent actions on a droplet
curl -s -H "Authorization: Bearer $DIGITAL_OCEAN_TOKEN" 'https://api.digitalocean.com/v2/droplets/<id>/actions'
```

DNS is at DNSimple (`DNSIMPLE_ACCESS_TOKEN` in `~/.env`), not in DO DNS.

## Known Issue: All Containers Down, Host Still Up

Symptom: login page loads, every user path returns 502, `machinectl list` shows no machines, all `systemd-nspawn@*` units failed with "Failed to register machine: Machine already exists".

Cause: unattended-upgrades upgrading the `systemd-container` package restarts all nspawn services; the restart races systemd-machined's cleanup and fails. This took down all 45 ai-lab containers on June 10, 2026 (the host never rebooted).

Prevention (applied to all three servers June 12, 2026): `/etc/systemd/system/systemd-nspawn@.service.d/restart.conf` containing `[Service]`, `Restart=on-failure`, `RestartSec=10`.

Recovery:
```bash
while IFS=: read -r U M I; do systemctl start systemd-nspawn@$M; done < /etc/biai-containers
```

Verify with `machinectl list` (expect 45) and a user path (expect 200 — note the Claude tab is at `/<username>/`, terminal at `/<username>/term/`, files at `/<username>/files/`):
```bash
curl -s -o /dev/null -w '%{http_code}' https://<domain>/<username>/
```
