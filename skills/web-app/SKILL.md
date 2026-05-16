---
name: web-app
description: Build and run FastAPI web apps on the AI Lab server. This skill should be used when creating web applications, APIs, dashboards, or any app that runs in a browser. Covers the reverse proxy path rules, correct uvicorn command, and HTML/JS patterns required for apps to work behind the /<user>/app/ proxy.
---

# Web App — AI Lab Server

## How Apps Are Served

Apps run on a per-user port (`$APP_PORT`) and are proxied through nginx at:

```
https://ai-lab.rice-business.org/<username>/app/
```

Nginx strips the `/<username>/app/` prefix before forwarding to the app, so the app itself sees requests at `/`, `/chat`, `/submit`, etc. — standard paths work on the server side.

**The critical issue is on the client side (browser).** The browser's base URL is `/<username>/app/`, so all paths in HTML, JavaScript, and CSS must be **relative** (no leading `/`).

## Rules

### 1. Always use relative paths in frontend code

```javascript
// WRONG — resolves to https://ai-lab.rice-business.org/chat
fetch("/chat")

// CORRECT — resolves to https://ai-lab.rice-business.org/<user>/app/chat
fetch("chat")
```

This applies everywhere in HTML and JavaScript:

```html
<!-- WRONG -->
<link rel="stylesheet" href="/static/style.css">
<script src="/static/app.js"></script>
<a href="/about">About</a>
<form action="/submit">

<!-- CORRECT -->
<link rel="stylesheet" href="static/style.css">
<script src="static/app.js"></script>
<a href="about">About</a>
<form action="submit">

<!-- To link back to the app root, use "./" not "/" -->
<a href="./">Back to home</a>
```

**Checklist for every app:**
- Form `action` attributes: `action="optimize"` not `action="/optimize"`
- Anchor `href` attributes: `href="./"` not `href="/"` (for back-to-home links)
- JavaScript `fetch()` calls: `fetch("api/data")` not `fetch("/api/data")`
- Image/script/CSS `src` attributes: `src="static/app.js"` not `src="/static/app.js"`

**Note:** FastAPI's `url_for()` (e.g., in Jinja2 templates or with `StaticFiles`) respects `root_path` automatically and generates correct absolute URLs. The problem only arises with hardcoded path strings in HTML.

### 2. Mount static files with a relative-friendly path

```python
from fastapi.staticfiles import StaticFiles

# Mount static files at "static" (no leading slash issues —
# the browser will request "static/..." relative to the app URL)
app.mount("/static", StaticFiles(directory="static"), name="static")
```

In templates, reference them with relative paths:

```html
<link rel="stylesheet" href="static/style.css">
```

### 3. Use the correct uvicorn command

```bash
uvicorn app:app --host 0.0.0.0 --port $APP_PORT --root-path /$USER/app
```

The `--root-path` flag tells FastAPI about the proxy prefix so that:
- OpenAPI docs (`/docs`) generate correct URLs
- FastAPI redirects (e.g., `/docs` → `/docs/`) include the prefix

### 4. For WebSocket connections

```javascript
// WRONG
const ws = new WebSocket("ws://host/ws");

// CORRECT — use relative WebSocket URL
const protocol = location.protocol === "https:" ? "wss:" : "ws:";
const ws = new WebSocket(`${protocol}//${location.host}${location.pathname}ws`);
```

### 5. For Streamlit apps

Streamlit doesn't need path adjustments — run with:

```bash
streamlit run app.py --server.port $APP_PORT --server.address 0.0.0.0 --server.baseUrlPath /$USER/app
```

### 6. Long-running computations (avoiding 504 timeouts)

Nginx has a 60-second proxy timeout. Any request that takes longer returns a 504 Gateway Timeout. This commonly happens with optimization, ML training, or large data processing.

**Fix: run the computation in a background thread and poll for results.**

```python
import uuid
import threading
from fastapi import FastAPI
from fastapi.responses import JSONResponse

app = FastAPI()
jobs = {}  # job_id -> {"status": "running" | "done" | "error", "result": ...}

def run_job(job_id, params):
    try:
        result = expensive_computation(params)  # your slow function
        jobs[job_id] = {"status": "done", "result": result}
    except Exception as e:
        jobs[job_id] = {"status": "error", "result": str(e)}

@app.post("submit")
def submit(params: dict):
    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "running"}
    threading.Thread(target=run_job, args=(job_id, params)).start()
    return {"job_id": job_id}

@app.get("status/{job_id}")
def status(job_id: str):
    return jobs.get(job_id, {"status": "not_found"})
```

Frontend polls until done:

```javascript
async function submitAndPoll(params) {
    const resp = await fetch("submit", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(params)
    });
    const {job_id} = await resp.json();

    while (true) {
        await new Promise(r => setTimeout(r, 1000));  // poll every 1s
        const status = await fetch(`status/${job_id}`).then(r => r.json());
        if (status.status === "done") return status.result;
        if (status.status === "error") throw new Error(status.result);
    }
}
```

IMPORTANT: Any app with computations that could take more than 30 seconds MUST use this pattern. Do not try to return results directly from a slow POST handler.

### 7. CPU-bound background threads: avoid `copy.deepcopy` and yield the GIL

When running CPU-bound code (e.g., simulated annealing, genetic algorithms) in a background thread:

**Never use `copy.deepcopy` in tight loops.** It is extremely slow due to Python's object introspection. For simple nested lists, use a shallow copy instead:

```python
# WRONG — 20-50x slower than needed
neighbor = copy.deepcopy(current)

# CORRECT — for List[List[int]] or List[List[object]]
neighbor = [list(r) for r in current]
```

**Yield the GIL periodically** so uvicorn's event loop can serve poll requests:

```python
import time

for i in range(n_iterations):
    if i % 1000 == 0:
        time.sleep(0)  # releases GIL, lets event loop handle requests
    # ... rest of loop
```

Without this, a tight CPU loop can starve the event loop and make poll responses feel stuck.

## Quick Start Template

```python
from fastapi import FastAPI
from fastapi.responses import HTMLResponse

app = FastAPI()

@app.get("/", response_class=HTMLResponse)
def home():
    return """
    <!DOCTYPE html>
    <html>
    <head><title>My App</title></head>
    <body>
        <h1>Hello!</h1>
        <div id="result"></div>
        <button onclick="fetchData()">Get Data</button>
        <script>
        async function fetchData() {
            const resp = await fetch("api/data");
            const data = await resp.json();
            document.getElementById("result").innerText = JSON.stringify(data);
        }
        </script>
    </body>
    </html>
    """

@app.get("/api/data")
def get_data():
    return {"message": "It works!"}
```

Run with:
```bash
uvicorn app:app --host 0.0.0.0 --port $APP_PORT --root-path /$USER/app
```

Then click the **App** tab in the left pane to view it.
