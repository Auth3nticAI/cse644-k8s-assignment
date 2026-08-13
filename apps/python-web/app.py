"""
CSE644 Cloud Computing - Assignment 02
Python (Flask) web application, listening on port 8888, run as a Kubernetes
Deployment. Exercises three requirements from one small app:

  * ConfigMap-driven behavior: APP_GREETING / APP_ENVIRONMENT change what the
    page says without an image rebuild (Requirement 6).
  * Secret handling: APP_SECRET_VALUE is read from an env var sourced from a
    Kubernetes Secret. Only a boolean "loaded" flag is ever exposed - the
    value itself is never logged, rendered, or returned (Requirement 6).
  * Persistent storage: /api/notes reads and appends to a file under
    DATA_DIR. When DATA_DIR is backed by a PersistentVolumeClaim, notes
    survive the Pod being deleted and replaced (Requirement 5).

Runs two ways:
  * In the container, gunicorn imports the module-level `app` object.
  * Locally for debugging:  python app.py
"""

import os
import platform
import socket
import time
from datetime import datetime, timezone

from flask import Flask, jsonify, render_template_string, request

PORT = int(os.environ.get("PORT", "8888"))

STARTED_AT = time.time()
STUDENT = os.environ.get("STUDENT", "Tray Branch")
COURSE = "CSE644 Cloud Computing"

# --- ConfigMap-controlled values (Requirement 6) ---------------------------
APP_GREETING = os.environ.get("APP_GREETING", "Hello from CSE644!")
APP_ENVIRONMENT = os.environ.get("APP_ENVIRONMENT", "unset")

# --- Secret-controlled value (Requirement 6) --------------------------------
# Deliberately never logged or returned - only whether it is present.
_APP_SECRET_VALUE = os.environ.get("APP_SECRET_VALUE", "")

# --- Persistent storage (Requirement 5) -------------------------------------
DATA_DIR = os.environ.get("DATA_DIR", "/data")
NOTES_FILE = os.path.join(DATA_DIR, "notes.log")

app = Flask(__name__)

_request_count = 0


def _data_dir_writable():
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        probe = os.path.join(DATA_DIR, ".write_probe")
        with open(probe, "w") as f:
            f.write("ok")
        os.remove(probe)
        return True
    except OSError:
        return False


def _read_notes(limit=10):
    if not os.path.exists(NOTES_FILE):
        return []
    with open(NOTES_FILE, "r") as f:
        lines = [line.rstrip("\n") for line in f.readlines()]
    return lines[-limit:]


def _append_note(text):
    os.makedirs(DATA_DIR, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    with open(NOTES_FILE, "a") as f:
        f.write(f"{stamp} | pod={socket.gethostname()} | {text}\n")


def _facts():
    return {
        "student": STUDENT,
        "course": COURSE,
        "assignment": "02 - Kubernetes",
        "hostname": socket.gethostname(),
        "pid": os.getpid(),
        "python_version": platform.python_version(),
        "listening_port": PORT,
        "uptime_seconds": round(time.time() - STARTED_AT, 1),
        "server_time_utc": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "requests_served": _request_count,
        "greeting": APP_GREETING,
        "environment": APP_ENVIRONMENT,
        "secret_loaded": bool(_APP_SECRET_VALUE),
        "data_dir": DATA_DIR,
        "notes_count": len(_read_notes(limit=10_000)),
        "recent_notes": _read_notes(limit=5),
    }


PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CSE644 &middot; Python Web App on :{{ f.listening_port }}</title>
<style>
  :root {
    --bg:#0d1117; --panel:#161b22; --line:#30363d;
    --ink:#e6edf3; --dim:#8b949e; --accent:#58a6ff; --py:#ffd343;
  }
  * { box-sizing:border-box; }
  body {
    margin:0; min-height:100vh; background:var(--bg); color:var(--ink);
    font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
    display:flex; align-items:center; justify-content:center; padding:2rem;
  }
  .card {
    width:100%; max-width:680px; background:var(--panel);
    border:1px solid var(--line); border-radius:12px; overflow:hidden;
  }
  .bar { height:4px; background:linear-gradient(90deg,var(--py),var(--accent)); }
  .inner { padding:2.25rem; }
  .badge {
    display:inline-block; font:600 11px/1 ui-monospace,Menlo,Consolas,monospace;
    letter-spacing:.12em; text-transform:uppercase; color:var(--py);
    border:1px solid var(--py); border-radius:999px; padding:.45rem .7rem;
    margin-bottom:1.25rem;
  }
  h1 { margin:0 0 .3rem; font-size:1.85rem; letter-spacing:-.02em; }
  .greeting { margin:0 0 1.75rem; color:var(--accent); font-weight:600; }
  code { font-family:ui-monospace,Menlo,Consolas,monospace; color:var(--accent); }
  dl {
    margin:0; display:grid; grid-template-columns:auto 1fr; gap:.6rem 1.25rem;
    padding-top:1.5rem; border-top:1px solid var(--line);
    font:13px/1.5 ui-monospace,Menlo,Consolas,monospace;
  }
  dt { color:var(--dim); white-space:nowrap; }
  dd { margin:0; word-break:break-all; }
  ul.notes { margin:.5rem 0 0; padding-left:1.1rem; font:12px/1.6 ui-monospace,Menlo,Consolas,monospace; color:var(--dim); }
  footer {
    margin-top:1.75rem; padding-top:1.25rem; border-top:1px solid var(--line);
    color:var(--dim); font-size:13px;
  }
</style>
</head>
<body>
  <main class="card">
    <div class="bar"></div>
    <div class="inner">
      <span class="badge">Assignment 02 &middot; Python / Flask on :{{ f.listening_port }}</span>
      <h1>Python Web App in Kubernetes</h1>
      <p class="greeting">{{ f.greeting }} &middot; environment: {{ f.environment }}</p>

      <dl>
        <dt>Student</dt>        <dd>{{ f.student }}</dd>
        <dt>Pod hostname</dt>   <dd>{{ f.hostname }}</dd>
        <dt>Worker PID</dt>     <dd>{{ f.pid }}</dd>
        <dt>Python</dt>         <dd>{{ f.python_version }}</dd>
        <dt>Uptime</dt>         <dd>{{ f.uptime_seconds }}s</dd>
        <dt>Server time</dt>    <dd>{{ f.server_time_utc }}</dd>
        <dt>Requests</dt>       <dd>{{ f.requests_served }}</dd>
        <dt>Secret loaded</dt>  <dd>{{ f.secret_loaded }}</dd>
        <dt>Data dir</dt>       <dd>{{ f.data_dir }}</dd>
        <dt>Notes stored</dt>   <dd>{{ f.notes_count }}</dd>
      </dl>

      {% if f.recent_notes %}
      <ul class="notes">
        {% for n in f.recent_notes %}<li>{{ n }}</li>{% endfor %}
      </ul>
      {% endif %}

      <footer>
        JSON: <code>/api/info</code> &middot;
        Notes: <code>GET/POST /api/notes</code> &middot;
        Liveness: <code>/healthz</code> &middot; Readiness: <code>/readyz</code>
      </footer>
    </div>
  </main>
</body>
</html>
"""


@app.after_request
def _count(response):
    global _request_count
    if not response.direct_passthrough:
        _request_count += 1
    return response


@app.get("/")
def index():
    return render_template_string(PAGE, f=_facts())


@app.get("/api/info")
def api_info():
    """Machine-readable facts. Never includes the raw secret value."""
    return jsonify(_facts())


@app.get("/api/notes")
def get_notes():
    return jsonify({"notes": _read_notes(limit=50)})


@app.post("/api/notes")
def post_notes():
    body = request.get_json(silent=True) or {}
    text = str(body.get("note", "")).strip()
    if not text:
        return jsonify({"error": "note field is required"}), 400
    _append_note(text)
    return jsonify({"notes": _read_notes(limit=50)}), 201


@app.get("/healthz")
def healthz():
    """Liveness: is the process itself still able to serve a request?
    Deliberately has no external dependency - a slow disk or missing
    Secret should not cause Kubernetes to kill and restart this Pod."""
    return "ok\n", 200, {"Content-Type": "text/plain"}


@app.get("/readyz")
def readyz():
    """Readiness: are this Pod's dependencies actually in place?
    Fails (503) until the data directory is writable (PVC mounted) and the
    ConfigMap/Secret values have been injected - so Kubernetes won't send
    it traffic before it can serve a correct response."""
    checks = {
        "data_dir_writable": _data_dir_writable(),
        "greeting_configured": APP_GREETING != "",
        "secret_loaded": bool(_APP_SECRET_VALUE),
    }
    ready = all(checks.values())
    return jsonify({"ready": ready, "checks": checks}), (200 if ready else 503)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
