#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_DIR="$ROOT_DIR/sessions"
LIQUID_HOME="${LIQUID_HOME:-$HOME/.liquid-code}"
OUTPUT_FORMAT="table"
FILTER_BACKEND=""
FILTER_STATUS=""
FILTER_TASK_ID=""

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

List all Liquid Code sessions.

OPTIONS:
    -j, --json              Output JSON format (machine-readable)
    -b, --backend BACKEND   Filter by backend (r, python)
    -s, --status STATUS     Filter by status (running, stopped)
    -t, --task-id ID        Filter by task ID
    -h, --help              Show this help message

EXAMPLES:
    $0
    $0 --json
    $0 --backend python --status running
    $0 --task-id fix-login
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -j|--json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    -b|--backend)
      FILTER_BACKEND="$2"
      shift 2
      ;;
    -s|--status)
      FILTER_STATUS="$2"
      shift 2
      ;;
    -t|--task-id)
      FILTER_TASK_ID="$2"
      shift 2
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

if [[ ! -d "$SESSIONS_DIR" ]]; then
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "[]"
    else
        echo "No sessions directory found"
    fi
    exit 0
fi

list_sessions() {
    python3 - "$SESSIONS_DIR" "$LIQUID_HOME/active" <<'PY'
import json
import os
import sys
from datetime import datetime

sessions_dir, active_file = sys.argv[1:]

active_session_id = ""
if os.path.exists(active_file):
    with open(active_file, "r") as f:
        active_session_id = f.read().strip()

sessions = []
for session_path in sorted(os.listdir(sessions_dir)):
    manifest_file = os.path.join(sessions_dir, session_path, "manifest.json")
    if not os.path.isfile(manifest_file):
        continue
    
    with open(manifest_file, "r") as f:
        manifest = json.load(f)
    
    session_id = manifest.get("id", session_path)
    backend = manifest.get("backend", "unknown")
    pid = manifest.get("pid", 0)
    port = manifest.get("port", "-")
    started_at = manifest.get("started_at", "-")
    task_id = manifest.get("task_id", "")
    task_description = manifest.get("task_description", "")
    related_files = manifest.get("related_files", [])
    
    if pid and pid != 0:
        try:
            os.kill(int(pid), 0)
            status = "running"
        except OSError:
            status = "stopped"
    else:
        status = "stopped"
    
    sessions.append({
        "id": session_id,
        "backend": backend,
        "status": status,
        "port": port,
        "pid": pid,
        "started_at": started_at,
        "task_id": task_id,
        "task_description": task_description,
        "related_files": related_files,
        "is_active": session_id == active_session_id,
    })

if "--json" in sys.argv:
    print(json.dumps(sessions, indent=2))
else:
    for s in sessions:
        print(json.dumps(s))
PY
}

FILTER_BACKEND="$FILTER_BACKEND"
FILTER_STATUS="$FILTER_STATUS"
FILTER_TASK_ID="$FILTER_TASK_ID"

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    python3 - "$SESSIONS_DIR" "$LIQUID_HOME/active" <<'PY'
import json
import os
import sys

sessions_dir, active_file = sys.argv[1:]

active_session_id = ""
if os.path.exists(active_file):
    with open(active_file, "r") as f:
        active_session_id = f.read().strip()

sessions = []
for session_path in sorted(os.listdir(sessions_dir)):
    manifest_file = os.path.join(sessions_dir, session_path, "manifest.json")
    if not os.path.isfile(manifest_file):
        continue
    
    with open(manifest_file, "r") as f:
        manifest = json.load(f)
    
    session_id = manifest.get("id", session_path)
    backend = manifest.get("backend", "unknown")
    pid = manifest.get("pid", 0)
    port = manifest.get("port", "-")
    started_at = manifest.get("started_at", "-")
    task_id = manifest.get("task_id", "")
    task_description = manifest.get("task_description", "")
    related_files = manifest.get("related_files", [])
    
    if pid and pid != 0:
        try:
            os.kill(int(pid), 0)
            status = "running"
        except OSError:
            status = "stopped"
    else:
        status = "stopped"
    
    sessions.append({
        "id": session_id,
        "backend": backend,
        "status": status,
        "port": port,
        "pid": pid,
        "started_at": started_at,
        "task_id": task_id,
        "task_description": task_description,
        "related_files": related_files,
        "is_active": session_id == active_session_id,
    })

print(json.dumps(sessions, indent=2))
PY
else
    python3 - "$SESSIONS_DIR" "$LIQUID_HOME/active" "$FILTER_BACKEND" "$FILTER_STATUS" "$FILTER_TASK_ID" <<'PY'
import json
import os
import sys

sessions_dir, active_file, filter_backend, filter_status, filter_task_id = sys.argv[1:]

active_session_id = ""
if os.path.exists(active_file):
    with open(active_file, "r") as f:
        active_session_id = f.read().strip()

sessions = []
for session_path in sorted(os.listdir(sessions_dir)):
    manifest_file = os.path.join(sessions_dir, session_path, "manifest.json")
    if not os.path.isfile(manifest_file):
        continue
    
    with open(manifest_file, "r") as f:
        manifest = json.load(f)
    
    session_id = manifest.get("id", session_path)
    backend = manifest.get("backend", "unknown")
    pid = manifest.get("pid", 0)
    port = manifest.get("port", "-")
    started_at = manifest.get("started_at", "-")[:19]
    task_id = manifest.get("task_id", "")
    task_description = manifest.get("task_description", "")
    is_active = session_id == active_session_id
    
    if pid and pid != 0:
        try:
            os.kill(int(pid), 0)
            status = "running"
        except OSError:
            status = "stopped"
    else:
        status = "stopped"
    
    if filter_backend and filter_backend != backend:
        continue
    if filter_status and filter_status != status:
        continue
    if filter_task_id and filter_task_id not in task_id:
        continue
    
    active_marker = "*" if is_active else " "
    desc = task_description[:30] + "..." if len(task_description) > 30 else task_description
    tid = f"[{task_id}]" if task_id else ""
    
    print(f"{active_marker}{session_id:<42}  {backend:<7}  {status:<8}  {port:<6}  {pid:<6}  {started_at}  {tid} {desc}")
PY
fi
