#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_DIR="$ROOT_DIR/sessions"

if [[ ! -d "$SESSIONS_DIR" ]]; then
    echo "No sessions directory found"
    exit 0
fi

echo "ID                  BACKEND  STATUS    PORT    PID     STARTED_AT"
echo "------------------  -------  --------  ------  ------  ------------------"

for manifest_path in "$SESSIONS_DIR"/*/manifest.json; do
    if [[ ! -f "$manifest_path" ]]; then
        continue
    fi

    python3 - "$manifest_path" <<'PY'
import json
import os
import sys
from datetime import datetime

manifest_path = sys.argv[1]
session_dir = os.path.dirname(manifest_path)

with open(manifest_path, "r") as f:
    m = json.load(f)

session_id = m.get("id", "unknown")
backend = m.get("backend", "unknown")
port = m.get("port", "-")
pid = m.get("pid", 0)
started_at = m.get("started_at", "-")[:19]

if pid and pid != 0:
    try:
        os.kill(int(pid), 0)
        status = "running"
    except OSError:
        status = "stopped"
else:
    status = "stopped"

print(f"{session_id:<19}  {backend:<7}  {status:<8}  {port:<6}  {pid:<6}  {started_at}")
PY
done
