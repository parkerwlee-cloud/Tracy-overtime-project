#!/usr/bin/env bash
set -euo pipefail
APPDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$APPDIR"

echo "== venv =="
python3 -m venv .venv
source .venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt

echo "== init db =="
python init_db.py

echo "== endpoint scan (url_for targets) =="
python - <<'PY'
import re,glob,sys,os
app = open("app.py","r",encoding="utf-8").read()
defs = set(re.findall(r"@app\.(?:route|get|post)\([^)]*\)\s*def\s+([A-Za-z_]\w*)", app))
targets=set()
for p in glob.glob("templates/*.html"):
    s=open(p,encoding="utf-8").read()
    targets.update(re.findall(r"url_for\(\s*['\"]([^'\"]+)['\"]", s))
missing=[t for t in sorted(targets) if t not in defs]
print("routes:", len(defs), "targets:", len(targets))
if missing:
    print("MISSING:", missing); sys.exit(1)
print("OK: all url_for targets resolved.")
PY

echo "== launch dev server (quick probe) =="
python - <<'PY'
import os, threading, time, requests
from app import app, socketio
import logging
logging.getLogger('werkzeug').setLevel(logging.ERROR)
port = 5055
t = threading.Thread(target=lambda: socketio.run(app, host="127.0.0.1", port=port), daemon=True)
t.start()
time.sleep(1.2)
for path in ["/", "/display", "/admin", "/health", "/healthz"]:
    try:
        r = requests.get(f"http://127.0.0.1:{port}{path}", timeout=2)
        print(path, r.status_code)
    except Exception as e:
        print(path, "ERR", e); raise
print("OK")
PY
echo "✅ self-test passed"
