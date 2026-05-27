# Bug: 404 nginx Error When Submitting Forms in FastAPI Apps

## What Happened

The app loaded fine in the browser, but clicking **Optimize Schedule** produced a bare nginx 404 page instead of results.

---

## Root Cause: Absolute Paths Behind a Reverse Proxy

In this lab environment, all web apps run behind an **nginx reverse proxy**. Nginx routes traffic based on a URL prefix tied to each user:

```
https://<server>/<username>/app/   →   http://localhost:<APP_PORT>/
```

FastAPI is told about this prefix via the `--root-path` flag:

```bash
uvicorn workover_app:app --host 0.0.0.0 --port $APP_PORT --root-path /$USER/app
```

`--root-path` tells FastAPI to generate correct OpenAPI docs and redirects, but it does **not** rewrite HTML that you write yourself. Any hardcoded absolute path in your HTML is sent to the browser as-is.

### The broken form tag

```html
<form action="/optimize" method="post" ...>
```

When the user clicks Submit, the browser constructs the POST URL from the `action` attribute:

| What the browser does | Result |
|---|---|
| Sees `action="/optimize"` (starts with `/`) | Treats it as an absolute path from the server root |
| Sends POST to | `https://<server>/optimize` |
| nginx looks for a route matching `/optimize` | **No match → 404** |

The app was only reachable at `/<username>/app/optimize`, not `/optimize`.

The same problem affects the **"Back" links** in error and results pages:

```html
<a href="/">Back to input</a>   <!-- sends user to server root, not the app -->
```

---

## The Fix: Use Relative Paths

Relative paths are resolved by the browser against the current page URL, so they automatically inherit the proxy prefix — no matter which user runs the app or what port is assigned.

| Location | Broken (absolute) | Fixed (relative) |
|---|---|---|
| Form action | `action="/optimize"` | `action="optimize"` |
| Results back link | `href="/"` | `href="./"` |
| Error page back links | `href='/'` | `href='./'` |

With `action="optimize"`, when the browser is on `https://<server>/test_student/app/`, it posts to `https://<server>/test_student/app/optimize` — which nginx correctly proxies to the app.

---

## Rule for All Lab Web Apps

> **Never use absolute paths (leading `/`) in HTML `action`, `href`, `src`, or `fetch()` URLs.**  
> Always use relative paths so the proxy prefix is inherited automatically.

### Quick checklist when writing a FastAPI app for this environment

- [ ] Form `action` attributes: `action="some-route"` not `action="/some-route"`
- [ ] Anchor `href` attributes: `href="./"` not `href="/"`
- [ ] JavaScript `fetch()` calls: `fetch("api/data")` not `fetch("/api/data")`
- [ ] Image/script/CSS `src` attributes: `src="static/app.js"` not `src="/static/app.js"`

### FastAPI `url_for()` is safe

If you use FastAPI's built-in `url_for()` (e.g., with `StaticFiles` or in Jinja2 templates), it respects `root_path` automatically and generates correct absolute URLs. The problem only arises when you hardcode paths as raw strings in HTML.

---

## Affected File

`session4/data/workover_app.py` — three locations patched:

```python
# Line 370 — form action
<form action="optimize" method="post" enctype="multipart/form-data">

# Line 495 — results page back link  
<p><a href="./">Back to input</a></p>

# Lines 523, 535 — error response back links
<p><a href='./'>Back</a></p>
```
