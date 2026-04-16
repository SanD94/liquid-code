#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIQUID_HOME="${LIQUID_HOME:-$HOME/.liquid-code}"
OUTPUT_FORMAT="keyval"

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Get the active session and its connection details.

OPTIONS:
    -j, --json              Output JSON format
    -p, --port-only         Output only the port number
    -i, --id-only           Output only the session ID
    -h, --help              Show this help message

EXAMPLES:
    $0
    $0 --json
    $0 --port-only
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -j|--json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    -p|--port-only)
      OUTPUT_FORMAT="port"
      shift
      ;;
    -i|--id-only)
      OUTPUT_FORMAT="id"
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

ACTIVE_FILE="$LIQUID_HOME/active"
SESSIONS_DIR="$ROOT_DIR/sessions"

if [[ ! -f "$ACTIVE_FILE" ]]; then
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo '{"error": "no active session"}'
    else
        echo "No active session found" >&2
    fi
    exit 1
fi

SESSION_ID="$(cat "$ACTIVE_FILE" | tr -d '[:space:]')"
MANIFEST_FILE="$SESSIONS_DIR/$SESSION_ID/manifest.json"

if [[ ! -f "$MANIFEST_FILE" ]]; then
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{\"error\": \"session manifest not found\", \"session_id\": \"$SESSION_ID\"}"
    else
        echo "Session manifest not found for: $SESSION_ID" >&2
    fi
    exit 1
fi

python3 - "$MANIFEST_FILE" "$SESSION_ID" "$OUTPUT_FORMAT" <<'PY'
import json
import sys
import os

manifest_file = sys.argv[1]
session_id = sys.argv[2]
output_format = sys.argv[3]

with open(manifest_file, "r") as f:
    manifest = json.load(f)

port = manifest.get("port", 0)
backend = manifest.get("backend", "unknown")
pid = manifest.get("pid", 0)
task_id = manifest.get("task_id", "")
task_description = manifest.get("task_description", "")

is_running = False
if pid and pid != 0:
    try:
        os.kill(int(pid), 0)
        is_running = True
    except OSError:
        pass

if output_format == "json":
    print(json.dumps({
        "id": session_id,
        "backend": backend,
        "port": port,
        "status": "running" if is_running else "stopped",
        "pid": pid,
        "task_id": task_id,
        "task_description": task_description,
        "is_active": True,
    }, indent=2))
elif output_format == "port":
    print(port)
elif output_format == "id":
    print(session_id)
else:
    print(f"session_id={session_id}")
    print(f"port={port}")
    print(f"backend={backend}")
    print(f"status={'running' if is_running else 'stopped'}")
    print(f"pid={pid}")
    if task_id:
        print(f"task_id={task_id}")
    if task_description:
        print(f"task_description={task_description}")
PY
