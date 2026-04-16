#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_DIR="$ROOT_DIR/sessions"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_SCRIPT="$ROOT_DIR/servers/python_server.py"
LIQUID_HOME="${LIQUID_HOME:-$HOME/.liquid-code}"
OUTPUT_FORMAT="keyval"

cd "$ROOT_DIR"

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Start a new Python session.

OPTIONS:
    -p, --port PORT         Use specific port (default: auto-select)
    -t, --task-id ID        Task identifier for session tracking
    -d, --description TEXT  Human-readable task description
    -f, --files FILE,...    Comma-separated list of related files
    -r, --resume-from ID    Resume from a previous session's checkpoint
    -j, --json              Output JSON format
    -h, --help              Show this help message

EXAMPLES:
    $0 --task-id fix-login --description "Debug login flow"
    $0 --resume-from python-01f25d24-8464-3440-8000-a35805b91c31 --description "Continue analysis"
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
RESUME_FROM=""

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
    -r|--resume-from)
      RESUME_FROM="$2"
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

RESUMED_FROM_CHECKPOINT=""
if [[ -n "$RESUME_FROM" ]]; then
  OLD_SESSION_DIR="$SESSIONS_DIR/$RESUME_FROM"
  OLD_MANIFEST="$OLD_SESSION_DIR/manifest.json"
  
  if [[ ! -f "$OLD_MANIFEST" ]]; then
    echo "Error: Session not found: $RESUME_FROM" >&2
    echo "Run './scripts/list-sessions.sh --json' to see available sessions." >&2
    exit 1
  fi
  
  OLD_CHECKPOINT=$(python3 - "$OLD_MANIFEST" <<'PY'
import json
import sys
manifest_path = sys.argv[1]
with open(manifest_path) as f:
    m = json.load(f)
print(m.get("checkpoint_path", ""))
PY
)
  
  if [[ -z "$OLD_CHECKPOINT" ]]; then
    echo "Error: No checkpoint found in session: $RESUME_FROM" >&2
    exit 1
  fi
  
  OLD_CHECKPOINT_ABS="$OLD_SESSION_DIR/$(basename "$OLD_CHECKPOINT")"
  if [[ ! -f "$OLD_CHECKPOINT_ABS" ]]; then
    echo "Error: Checkpoint file not found: $OLD_CHECKPOINT_ABS" >&2
    exit 1
  fi
  
  RESUMED_FROM_CHECKPOINT="$OLD_CHECKPOINT_ABS"
  echo "Resuming from session: $RESUME_FROM (checkpoint: $OLD_CHECKPOINT_ABS)" >&2
fi

[[ -z "$PORT" ]] && PORT="$(pick_port)"

SESSION_ID="$(python3 "$SCRIPTS_DIR/uuid6.py" python)"
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
ARTIFACT_DIR="$SESSION_DIR/artifacts"
LOG_PATH="$SESSION_DIR/server.log"
MANIFEST_PATH="$SESSION_DIR/manifest.json"
CHECKPOINT_PATH="$SESSION_DIR/checkpoint.pkl"

mkdir -p "$ARTIFACT_DIR"
mkdir -p "$LIQUID_HOME"
touch "$LOG_PATH"

ensure_command python3

RELATED_FILES_JSON="[]"
if [[ -n "$RELATED_FILES" ]]; then
  RELATED_FILES_JSON="$(python3 -c "import json; print(json.dumps([f.strip() for f in '$RELATED_FILES'.split(',')]))")"
fi

python3 - "$MANIFEST_PATH" "$SESSION_ID" "$PORT" "$SESSION_DIR" "$LOG_PATH" "$CHECKPOINT_PATH" "$ARTIFACT_DIR" "$TASK_ID" "$TASK_DESCRIPTION" "$RELATED_FILES_JSON" "$RESUME_FROM" "$RESUMED_FROM_CHECKPOINT" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

manifest_path, session_id, port, session_dir, log_path, checkpoint_path, artifact_dir, task_id, task_description, related_files_json, resume_from, resumed_from_checkpoint = sys.argv[1:]

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

if task_id:
    manifest["task_id"] = task_id
if task_description:
    manifest["task_description"] = task_description
if related_files_json and related_files_json != "[]":
    manifest["related_files"] = json.loads(related_files_json)
if resume_from:
    manifest["resumed_from"] = resume_from
if resumed_from_checkpoint:
    manifest["resumed_from_checkpoint"] = os.path.relpath(resumed_from_checkpoint)

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
