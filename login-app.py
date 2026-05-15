"""Login page with admin panel for user management."""
import os
import re
import subprocess
from fastapi import FastAPI, Form, Cookie, Header, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from typing import Optional
import secrets
import time

import psycopg2
import psycopg2.extras

app = FastAPI()

DATABASE_URL = os.environ.get("DATABASE_URL", "")
PROVISION_SECRET = os.environ.get("PROVISION_SECRET", "")

# Simple session store: token -> (username, expiry)
sessions: dict[str, tuple[str, float]] = {}
SESSION_HOURS = 12
DEFAULT_PASSWORD = "jgsbai"

BANNER_STYLE = """
body { font-family: Arial, sans-serif; margin: 0; padding: 0; background: #7C7E7F; color: #333; }
.banner { text-align: center; padding: 24px 0 8px; position: relative; }
.banner h1 { font-size: 1.5em; margin: 0; color: #ffffff; }
.banner p { margin: 4px 0; font-size: 0.95em; color: #e0e0e0; }
.card { max-width: 420px; margin: 40px auto; background: #ffffff; border-radius: 4px; padding: 32px; box-shadow: 0 0 20px rgba(0,0,0,0.2), 0 5px 5px rgba(0,0,0,0.24); }
.card h2 { margin: 0 0 20px; font-size: 1.1em; text-align: center; color: #333; font-weight: normal; }
label { display: block; margin-bottom: 4px; font-size: 0.85em; color: #555; }
input { width: 100%; padding: 10px; margin-bottom: 16px; border: 1px solid #ccc; border-radius: 4px; background: #f2f2f2; color: #333; font-size: 1em; box-sizing: border-box; }
input:focus { outline: none; border-color: #00205B; }
button, .btn { padding: 10px; border: none; border-radius: 4px; background: #00205B; color: #ffffff; font-size: 1em; font-weight: 600; cursor: pointer; text-transform: uppercase; }
button:hover, .btn:hover { background: #00205B; filter: brightness(85%); }
.btn-full { width: 100%; }
.error { color: #cc0000; text-align: center; margin-bottom: 12px; font-size: 0.9em; }
.success { color: #2e7d32; text-align: center; margin-bottom: 12px; font-size: 0.9em; }
.instructions { font-size: 0.9em; color: #555; line-height: 1.6; margin-top: 16px; }
.about-btn { position: absolute; bottom: 5px; right: 20px; background: rgba(255,255,255,0.15); border: none; color: #e0e0e0; width: 28px; height: 28px; border-radius: 50%; cursor: pointer; font-size: 14px; display: flex; align-items: center; justify-content: center; transition: all 0.2s; }
.about-btn:hover { background: rgba(255,255,255,0.3); color: #fff; transform: scale(1.1); }
.about-tooltip { position: absolute; bottom: 40px; right: 0; background: #00205B; color: #fff; padding: 10px 14px; border-radius: 8px; font-size: 0.8em; line-height: 1.5; white-space: nowrap; opacity: 0; visibility: hidden; transition: opacity 0.2s, visibility 0.2s; pointer-events: none; box-shadow: 0 2px 12px rgba(0,0,0,0.3); }
.about-btn:hover .about-tooltip { opacity: 1; visibility: visible; pointer-events: auto; }
.about-tooltip::before { content: ''; position: absolute; bottom: -4px; right: 12px; width: 8px; height: 8px; background: #00205B; transform: rotate(45deg); }
.admin-link { position: absolute; bottom: 5px; left: 20px; background: rgba(255,255,255,0.15); border: none; color: #e0e0e0; width: 28px; height: 28px; border-radius: 50%; cursor: pointer; font-size: 16px; display: flex; align-items: center; justify-content: center; transition: all 0.2s; text-decoration: none; }
.admin-link:hover { background: rgba(255,255,255,0.3); color: #fff; transform: scale(1.1); }
table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 0.9em; }
th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #ddd; }
th { color: #555; font-weight: normal; font-size: 0.85em; }
td { color: #333; }
.btn-sm { padding: 4px 10px; font-size: 0.8em; border-radius: 4px; }
.btn-danger { background: #cc0000; }
.btn-danger:hover { background: #aa0000; filter: none; }
.admin-card { max-width: 560px; }
.add-form { display: flex; gap: 8px; align-items: end; }
.add-form input { margin-bottom: 0; flex: 1; }
.add-form button { white-space: nowrap; }
"""

ABOUT_WIDGET = """<div class="about-btn">&#9432;<div class="about-tooltip">Developed by Kerry Back,<br>J. Howard Creekmore Professor of Finance<br>and Professor of Economics,<br>Rice University</div></div>"""

LOGIN_PAGE = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AI Lab</title><style>{style}</style></head>
<body>
<div class="banner">
  <h1>AI Lab</h1>
  <p>Rice Business</p>
  {about}
</div>
<div class="card">
  <h2>Log in to your workspace</h2>
  {error}
  <form method="post" action="/login" style="margin-top:20px">
    <label for="username">Username</label>
    <input type="text" id="username" name="username" autofocus required>
    <label for="password">Password</label>
    <input type="password" id="password" name="password" required>
    <button type="submit" class="btn-full">Log In</button>
  </form>
</div>
</body></html>"""

WORKSPACE_PAGE = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AI Lab — {username}</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
html, body {{ height: 100%; overflow: hidden; font-family: Arial, sans-serif; }}
.toolbar {{
    height: 36px; background: #00205B; color: #fff;
    display: flex; align-items: center; padding: 0 16px;
    font-size: 13px; gap: 12px;
}}
.toolbar .title {{ font-weight: 600; letter-spacing: 0.3px; }}
.toolbar .sep {{ opacity: 0.4; }}
.toolbar .subtitle {{ opacity: 0.85; font-size: 12px; }}
.toolbar .spacer {{ flex: 1; }}
.toolbar a {{ color: rgba(255,255,255,0.7); text-decoration: none; font-size: 12px; }}
.toolbar a:hover {{ color: #fff; }}
.workspace {{ display: flex; height: calc(100% - 36px); }}
.pane {{ overflow: hidden; display: flex; flex-direction: column; }}
.pane iframe {{ flex: 1; width: 100%; border: none; }}
.pane-label {{
    height: 24px; flex-shrink: 0;
    background: rgba(0,32,91,0.85); color: #fff; font-size: 11px;
    display: flex; align-items: center; padding: 0 10px;
    letter-spacing: 0.3px;
}}
.pane-label .tab {{
    cursor: pointer; padding: 2px 10px; border-radius: 3px;
    margin-right: 4px; transition: background 0.15s;
}}
.pane-label .tab:hover {{ background: rgba(255,255,255,0.15); }}
.pane-label .tab.active {{ background: rgba(255,255,255,0.25); font-weight: 600; }}
.pane-label .refresh-btn {{
    cursor: pointer; margin-left: auto; padding: 1px 6px; border-radius: 3px;
    font-size: 13px; line-height: 1; transition: background 0.15s; opacity: 0.7;
}}
.pane-label .refresh-btn:hover {{ background: rgba(255,255,255,0.15); opacity: 1; }}
.divider {{
    width: 5px; background: #00205B; cursor: col-resize;
    flex-shrink: 0; position: relative; z-index: 20;
}}
.divider:hover, .divider.active {{ background: #003a9e; }}
</style>
</head>
<body>
<div class="toolbar">
    <span class="title">AI Lab</span>
    <span class="sep">|</span>
    <span class="subtitle">Rice Business</span>
    <span class="spacer"></span>
    <span style="opacity:0.7">{username}</span>
    {admin_link}
    <a href="/">Logout</a>
</div>
<div class="workspace">
    <div class="pane" id="pane-left" style="flex: 1 1 30%;">
        <div class="pane-label">
            <span class="tab active" id="tab-files" onclick="switchLeft('files')">Files</span>
            <span class="tab" id="tab-term" onclick="switchLeft('term')">Terminal</span>
            <span class="tab" id="tab-app" onclick="switchLeft('app')">App</span>
            <span class="refresh-btn" id="refresh-btn" title="Refresh" onclick="refreshLeft()">&#x21bb;</span>
        </div>
        <iframe id="left-iframe" src="/{username}/files/"></iframe>
    </div>
    <div class="divider" id="divider"></div>
    <div class="pane" id="pane-right" style="flex: 1 1 70%;">
        <div class="pane-label">Claude Code</div>
        <iframe src="/{username}/"></iframe>
    </div>
</div>
<script>
(function() {{
    const divider = document.getElementById('divider');
    const left = document.getElementById('pane-left');
    const right = document.getElementById('pane-right');
    const workspace = document.querySelector('.workspace');
    let dragging = false;

    // Refresh left pane iframe
    window.refreshLeft = function() {{
        const iframe = document.getElementById('left-iframe');
        iframe.src = iframe.src;
    }};

    // Left pane tab switching
    window.switchLeft = function(mode) {{
        const iframe = document.getElementById('left-iframe');
        const tabs = ['files', 'term', 'app'];
        tabs.forEach(t => document.getElementById('tab-' + t).classList.remove('active'));
        document.getElementById('tab-' + mode).classList.add('active');
        if (mode === 'files') {{
            iframe.src = '/{username}/files/';
        }} else if (mode === 'term') {{
            iframe.src = '/{username}/term/';
        }} else {{
            iframe.src = '/{username}/app/';
        }}
    }};

    divider.addEventListener('mousedown', function(e) {{
        dragging = true;
        divider.classList.add('active');
        document.body.style.cursor = 'col-resize';
        document.body.style.userSelect = 'none';
        // Prevent iframes from capturing mouse events while dragging
        left.querySelector('iframe').style.pointerEvents = 'none';
        right.querySelector('iframe').style.pointerEvents = 'none';
        e.preventDefault();
    }});

    document.addEventListener('mousemove', function(e) {{
        if (!dragging) return;
        const rect = workspace.getBoundingClientRect();
        const pct = ((e.clientX - rect.left) / rect.width) * 100;
        if (pct < 20 || pct > 80) return;
        left.style.flex = '0 0 ' + pct + '%';
        right.style.flex = '0 0 ' + (100 - pct) + '%';
    }});

    document.addEventListener('mouseup', function() {{
        if (!dragging) return;
        dragging = false;
        divider.classList.remove('active');
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
        left.querySelector('iframe').style.pointerEvents = '';
        right.querySelector('iframe').style.pointerEvents = '';
    }});
}})();
</script>
</body></html>"""

ADMIN_PAGE = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AI Lab — Admin</title><style>{style}</style></head>
<body>
<div class="banner">
  <h1>AI Lab</h1>
  <p>Rice Business</p>
  {about}
</div>
<div class="card admin-card">
  <h2>&#9881; User Management</h2>
  {message}
  <form method="post" action="/admin/add" style="margin-bottom: 20px;">
    <label>Add user (password will be set to <code style="color:#00205B">{default_password}</code>)</label>
    <div class="add-form">
      <input type="text" name="new_username" placeholder="firstname_lastname" required>
      <button type="submit" class="btn">Add</button>
    </div>
  </form>
  <table>
    <tr><th>Username</th><th>Admin</th><th></th></tr>
    {user_rows}
  </table>
  <p style="text-align:center;margin-top:20px">
    <a href="/" style="color:#00205B;text-decoration:none">&larr; Back to login</a>
  </p>
</div>
</body></html>"""


def check_credentials(username: str, password: str) -> bool:
    """Verify credentials against Linux PAM via su."""
    try:
        result = subprocess.run(
            ["su", "-c", "true", username],
            input=password + "\n",
            capture_output=True, text=True, timeout=5,
        )
        return result.returncode == 0
    except Exception:
        return False


def is_admin(username: str) -> bool:
    """Check if user has is_admin=true in the database."""
    if not DATABASE_URL:
        return False
    try:
        conn = psycopg2.connect(DATABASE_URL)
        with conn.cursor() as cur:
            cur.execute(
                "SELECT is_admin FROM users WHERE username = %s AND is_active = true",
                (username,),
            )
            row = cur.fetchone()
        conn.close()
        return bool(row and row[0])
    except Exception:
        return False


def get_session_user(session: Optional[str]) -> Optional[str]:
    """Return username if session is valid, else None."""
    if not session or session not in sessions:
        return None
    username, expiry = sessions[session]
    if time.time() > expiry:
        del sessions[session]
        return None
    return username


def list_workshop_users() -> list[dict]:
    """List users that have a ttyd service (workshop users)."""
    result = subprocess.run(
        ["bash", "-c", "cat /etc/biai-ports 2>/dev/null"],
        capture_output=True, text=True,
    )
    users = []
    for line in result.stdout.strip().splitlines():
        if ":" in line:
            username = line.split(":")[0]
            users.append({"username": username, "is_admin": is_admin(username)})
    return users


def add_user(username: str, password: str = DEFAULT_PASSWORD) -> tuple[bool, str]:
    """Create a Linux user and set up their workspace."""
    if not re.match(r'^[a-z][a-z0-9_]{0,31}$', username):
        return False, f"Invalid username '{username}'."
    result = subprocess.run(
        ["bash", "-c", f"""
            id '{username}' &>/dev/null && echo 'exists' && exit 0
            useradd -m -s /bin/bash -N '{username}' 2>&1 && \
            echo '{username}:{password}' | chpasswd 2>&1 && \
            bash /opt/biai-vm/setup-user.sh '{username}' 2>&1
        """],
        capture_output=True, text=True, timeout=60,
    )
    if result.returncode == 0:
        if "exists" in result.stdout:
            # User already exists — just update password
            subprocess.run(
                ["bash", "-c", f"echo '{username}:{password}' | chpasswd"],
                capture_output=True, text=True, timeout=10,
            )
            return True, f"User '{username}' already exists, password updated."
        return True, f"User '{username}' created."
    return False, f"Failed to create '{username}': {result.stdout} {result.stderr}"


def delete_user(username: str) -> tuple[bool, str]:
    """Delete a Linux user and their services."""
    result = subprocess.run(
        ["bash", "-c", f"""
            systemctl stop ttyd-{username} filebrowser-{username} 2>/dev/null
            systemctl disable ttyd-{username} filebrowser-{username} 2>/dev/null
            rm -f /etc/systemd/system/ttyd-{username}.service /etc/systemd/system/filebrowser-{username}.service
            systemctl daemon-reload
            userdel -r '{username}' 2>&1
            sed -i '/^{username}:/d' /etc/biai-ports
            bash /opt/biai-vm/generate-nginx.sh 2>&1
        """],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode == 0:
        return True, f"User '{username}' deleted."
    return False, f"Failed to delete '{username}': {result.stdout} {result.stderr}"


def render_admin(message: str = "") -> str:
    users = list_workshop_users()
    rows = ""
    for u in users:
        admin_badge = "&#9989;" if u["is_admin"] else ""
        delete_btn = f"""<form method="post" action="/admin/delete" style="display:inline;margin:0">
            <input type="hidden" name="del_username" value="{u['username']}">
            <button type="submit" class="btn-sm btn-danger"
                onclick="return confirm('Delete {u['username']}?')">Delete</button>
        </form>"""
        rows += f"<tr><td>{u['username']}</td><td>{admin_badge}</td><td>{delete_btn}</td></tr>\n"
    return ADMIN_PAGE.format(
        style=BANNER_STYLE, about=ABOUT_WIDGET, message=message,
        user_rows=rows, default_password=DEFAULT_PASSWORD,
    )


@app.get("/", response_class=HTMLResponse)
def login_form():
    return LOGIN_PAGE.format(style=BANNER_STYLE, about=ABOUT_WIDGET, error="")


@app.post("/login")
def login(username: str = Form(...), password: str = Form(...)):
    if check_credentials(username, password):
        token = secrets.token_urlsafe(32)
        sessions[token] = (username, time.time() + SESSION_HOURS * 3600)
        response = RedirectResponse("/workspace", status_code=303)
        response.set_cookie("session", token, max_age=SESSION_HOURS * 3600)
        return response
    return HTMLResponse(LOGIN_PAGE.format(
        style=BANNER_STYLE, about=ABOUT_WIDGET,
        error='<p class="error">Invalid username or password.</p>',
    ))


@app.get("/workspace", response_class=HTMLResponse)
def workspace(session: Optional[str] = Cookie(None)):
    username = get_session_user(session)
    if not username:
        return RedirectResponse("/", status_code=303)
    return WORKSPACE_PAGE.format(username=username, admin_link="")


@app.post("/provision")
def provision_user(
    username: str = Form(...),
    password: str = Form(...),
    x_provision_secret: Optional[str] = Header(None),
):
    """Provision a Linux user on the VM. Called by the biai-admin app."""
    if not PROVISION_SECRET or x_provision_secret != PROVISION_SECRET:
        raise HTTPException(status_code=403, detail="Invalid secret")
    username = username.strip().lower().replace(" ", "_")
    ok, msg = add_user(username, password)
    if ok:
        return JSONResponse({"ok": True, "message": msg})
    raise HTTPException(status_code=500, detail=msg)


@app.get("/admin", response_class=HTMLResponse)
def admin_page(session: Optional[str] = Cookie(None)):
    username = get_session_user(session)
    if not username or not is_admin(username):
        return RedirectResponse("/", status_code=303)
    return render_admin()


@app.post("/admin/add", response_class=HTMLResponse)
def admin_add_user(new_username: str = Form(...), session: Optional[str] = Cookie(None)):
    username = get_session_user(session)
    if not username or not is_admin(username):
        return RedirectResponse("/", status_code=303)
    new_username = new_username.strip().lower().replace(" ", "_")
    if not new_username:
        return render_admin('<p class="error">Username cannot be empty.</p>')
    ok, msg = add_user(new_username)
    cls = "success" if ok else "error"
    return render_admin(f'<p class="{cls}">{msg}</p>')


@app.post("/admin/delete", response_class=HTMLResponse)
def admin_delete_user(del_username: str = Form(...), session: Optional[str] = Cookie(None)):
    username = get_session_user(session)
    if not username or not is_admin(username):
        return RedirectResponse("/", status_code=303)
    if del_username == username:
        return render_admin('<p class="error">You cannot delete yourself.</p>')
    ok, msg = delete_user(del_username)
    cls = "success" if ok else "error"
    return render_admin(f'<p class="{cls}">{msg}</p>')
