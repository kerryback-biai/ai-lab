#!/usr/bin/env python3
"""Update CLAUDE.md in all containers: replace old app port instructions with port 8000."""
import os

CONTAINERS_FILE = "/etc/biai-containers"

OLD_SECTION = """## Running Web Apps

IMPORTANT: When asked to run a Python web app (FastAPI, Streamlit, or any .py file that serves HTTP), ALWAYS use this command:

    uvicorn <module>:app --host 0.0.0.0 --port $APP_PORT --root-path /$USER/app

- Replace <module> with the filename without .py (e.g., `my_app:app` for my_app.py)
- The app will be visible in the **App** tab in the left pane of the workspace
- $APP_PORT and $USER are already set in the environment
- NEVER use `python app.py` to run web apps — always use uvicorn with the flags above
- Use only relative paths (no leading /) in HTML, JavaScript fetch calls, and links — see the web-app skill for details
- FastAPI and uvicorn are pre-installed"""

NEW_SECTION = """## Running Web Apps

IMPORTANT: When asked to run a Python web app (FastAPI, Streamlit, or any .py file that serves HTTP), ALWAYS use this command:

    uvicorn <module>:app --host 0.0.0.0 --port 8000

- Replace <module> with the filename without .py (e.g., `my_app:app` for my_app.py)
- The app will be visible in the **App** tab in the left pane of the workspace
- NEVER use `python app.py` to run web apps — always use uvicorn with the flags above
- Use only relative paths (no leading /) in HTML, JavaScript fetch calls, and links
- FastAPI and uvicorn are pre-installed
- To kill a running app before starting another: `kill $(lsof -t -i:8000)`"""

with open(CONTAINERS_FILE) as f:
    lines = f.read().strip().splitlines()

for line in lines:
    parts = line.split(":")
    if len(parts) < 3:
        continue
    username, machine_name, container_ip = parts[0], parts[1], parts[2]
    filepath = f"/var/lib/machines/{machine_name}/home/{username}/workspace/CLAUDE.md"
    if not os.path.exists(filepath):
        print(f"  SKIP (no file): {username}")
        continue
    with open(filepath) as f:
        content = f.read()
    if OLD_SECTION in content:
        content = content.replace(OLD_SECTION, NEW_SECTION)
        with open(filepath, "w") as f:
            f.write(content)
        print(f"  Updated: {username}")
    else:
        print(f"  Already up to date: {username}")
