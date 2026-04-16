#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_DIR="$ROOT_DIR/sessions"
SERVER_SCRIPT="$ROOT_DIR/servers/python_server.py"

cd "$ROOT_DIR"

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

pick_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

ensure_command python3

PORT="${1:-$(pick_port)}"
STAMP="$(date -u +%Y%m%d%H%M%S)"
RAND="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(3))
PY
)"
SESSION_ID="py-${STAMP}-${RAND}"
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
ARTIFACT_DIR="$SESSION_DIR/artifacts"
LOG_PATH="$SESSION_DIR/server.log"
MANIFEST_PATH="$SESSION_DIR/manifest.json"
CHECKPOINT_PATH="$SESSION_DIR/checkpoint.pkl"

mkdir -p "$ARTIFACT_DIR"
touch "$LOG_PATH"

python3 - "$MANIFEST_PATH" "$SESSION_ID" "$PORT" "$SESSION_DIR" "$LOG_PATH" "$CHECKPOINT_PATH" "$ARTIFACT_DIR" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

manifest_path, session_id, port, session_dir, log_path, checkpoint_path, artifact_dir = sys.argv[1:]
manifest = {
    "id": session_id,
    "backend": "python",
    "pid": 0,
    "port": int(port),
    "started_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "session_dir": os.path.relpath(session_dir),
    "log_path": os.path.relpath(log_path),
    "checkpoint_path": os.path.relpath(checkpoint_path),
    "artifact_dir": os.path.relpath(artifact_dir),
}

with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY

python3 "$SERVER_SCRIPT" "$MANIFEST_PATH" >>"$LOG_PATH" 2>&1 &
PID=$!

python3 - "$MANIFEST_PATH" "$PID" <<'PY'
import json
import sys

manifest_path, pid = sys.argv[1:]
with open(manifest_path, "r", encoding="utf-8") as fh:
    manifest = json.load(fh)

manifest["pid"] = int(pid)

with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY

echo "session_id=$SESSION_ID"
echo "port=$PORT"
echo "pid=$PID"
echo "manifest=$MANIFEST_PATH"
