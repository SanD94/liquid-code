#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_DIR="$ROOT_DIR/sessions"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT="$ROOT_DIR/servers/r_server.R"
LIQUID_HOME="${LIQUID_HOME:-$HOME/.liquid-code}"
OUTPUT_FORMAT="keyval"

cd "$ROOT_DIR"

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Start a new R session.

OPTIONS:
    -p, --port PORT         Use specific port (default: auto-select)
    -t, --task-id ID        Task identifier for session tracking
    -d, --description TEXT  Human-readable task description
    -f, --files FILE,...    Comma-separated list of related files
    -j, --json              Output JSON format
    -h, --help              Show this help message

EXAMPLES:
    $0 --task-id fix-login --description "Debug login flow"
    $0 --json
    $0 -p 8080
EOF
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

ensure_r_package() {
  local package_name="$1"
  if ! Rscript -e "if (!requireNamespace('${package_name}', quietly = TRUE)) quit(status = 1)" >/dev/null 2>&1; then
    echo "missing required R package: ${package_name}" >&2
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

TASK_ID=""
TASK_DESCRIPTION=""
RELATED_FILES=""
PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    -t|--task-id)
      TASK_ID="$2"
      shift 2
      ;;
    -d|--description)
      TASK_DESCRIPTION="$2"
      shift 2
      ;;
    -f|--files)
      RELATED_FILES="$2"
      shift 2
      ;;
    -j|--json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

[[ -z "$PORT" ]] && PORT="$(pick_port)"

SESSION_ID="$(python3 "$SCRIPTS_DIR/uuid6.py" r)"
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
ARTIFACT_DIR="$SESSION_DIR/artifacts"
LOG_PATH="$SESSION_DIR/server.log"
MANIFEST_PATH="$SESSION_DIR/manifest.json"
CHECKPOINT_PATH="$SESSION_DIR/checkpoint.RData"

mkdir -p "$ARTIFACT_DIR"
mkdir -p "$LIQUID_HOME"
touch "$LOG_PATH"

ensure_command python3
ensure_command Rscript
ensure_r_package httpuv
ensure_r_package jsonlite

RELATED_FILES_JSON="[]"
if [[ -n "$RELATED_FILES" ]]; then
  RELATED_FILES_JSON="$(python3 -c "import json; print(json.dumps([f.strip() for f in '$RELATED_FILES'.split(',')]))")"
fi

python3 - "$MANIFEST_PATH" "$SESSION_ID" "$PORT" "$SESSION_DIR" "$LOG_PATH" "$CHECKPOINT_PATH" "$ARTIFACT_DIR" "$TASK_ID" "$TASK_DESCRIPTION" "$RELATED_FILES_JSON" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

manifest_path, session_id, port, session_dir, log_path, checkpoint_path, artifact_dir, task_id, task_description, related_files_json = sys.argv[1:]

manifest = {
    "id": session_id,
    "backend": "r",
    "pid": 0,
    "port": int(port),
    "started_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "session_dir": os.path.relpath(session_dir),
    "log_path": os.path.relpath(log_path),
    "checkpoint_path": os.path.relpath(checkpoint_path),
    "artifact_dir": os.path.relpath(artifact_dir),
}

if task_id:
    manifest["task_id"] = task_id
if task_description:
    manifest["task_description"] = task_description
if related_files_json and related_files_json != "[]":
    manifest["related_files"] = json.loads(related_files_json)

with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY

Rscript "$SERVER_SCRIPT" "$MANIFEST_PATH" >>"$LOG_PATH" 2>&1 &
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

echo "$SESSION_ID" > "$LIQUID_HOME/active"

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  python3 - "$MANIFEST_PATH" <<PY
import json
import sys

manifest_path = sys.argv[1]
with open(manifest_path, "r") as f:
    manifest = json.load(f)

manifest["status"] = "running"
print(json.dumps(manifest, indent=2))
PY
else
  echo "session_id=$SESSION_ID"
  echo "port=$PORT"
  echo "pid=$PID"
  echo "manifest=$MANIFEST_PATH"
fi
