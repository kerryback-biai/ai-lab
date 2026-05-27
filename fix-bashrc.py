#!/usr/bin/env python3
"""Update .bashrc terminal banner in all containers."""
import os

CONTAINERS_FILE = "/etc/biai-containers"
OLD_BANNER_START = "# BIAI-APP-PORT-BANNER"
OLD_BANNER_END = "# END-BIAI-APP-PORT-BANNER"

NEW_BANNER = r'''# BIAI-APP-PORT-BANNER
echo ""
echo "  -----------------------------------------------------------------------"
echo ""
echo "  To run a web app, cd to the folder containing it and run:"
echo ""
echo "    uvicorn {filename without .py}:app --host 0.0.0.0 --port 8000"
echo ""
echo "  For example, to run session4/workover_app.py:"
echo ""
echo "    cd session4"
echo "    uvicorn workover_app:app --host 0.0.0.0 --port 8000"
echo ""
echo "  Then click the App tab to see it."
echo ""
echo "  Before starting a second app, stop the first one:"
echo ""
echo "    Option 1: Press Ctrl+C in this terminal (if the app is running here)"
echo "    Option 2: Run    kill \$(lsof -t -i:8000)"
echo "    Option 3: Ask Claude Code to kill the app on port 8000"
echo ""
echo "  To stop a Docker container: docker compose down"
echo "  (run this in the folder containing the Dockerfile)"
echo ""
echo "  -----------------------------------------------------------------------"
echo ""
# END-BIAI-APP-PORT-BANNER'''

with open(CONTAINERS_FILE) as f:
    lines = f.read().strip().splitlines()

for line in lines:
    parts = line.split(":")
    if len(parts) < 3:
        continue
    username, machine_name = parts[0], parts[1]
    filepath = f"/var/lib/machines/{machine_name}/home/{username}/.bashrc"
    if not os.path.exists(filepath):
        print(f"  SKIP: {username}")
        continue
    with open(filepath) as f:
        content = f.read()
    if OLD_BANNER_START in content:
        start = content.index(OLD_BANNER_START)
        end = content.index(OLD_BANNER_END) + len(OLD_BANNER_END)
        content = content[:start] + content[end:]
    content = content.rstrip() + "\n\n" + NEW_BANNER + "\n"
    with open(filepath, "w") as f:
        f.write(content)
    os.system(f'chroot /var/lib/machines/{machine_name} chown {username}:{username} /home/{username}/.bashrc')
    print(f"  Updated: {username}")
