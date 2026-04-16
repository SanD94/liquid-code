#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSIONS_DIR="$ROOT_DIR/sessions"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <session-id|manifest-path>" >&2
  exit 1
fi

TARGET="$1"

if [[ -f "$TARGET" ]]; then
  MANIFEST_PATH="$TARGET"
else
  MANIFEST_PATH="$SESSIONS_DIR/$TARGET/manifest.json"
fi

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "manifest not found: $MANIFEST_PATH" >&2
  exit 1
fi

read_pid() {
  python3 - "$MANIFEST_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    manifest = json.load(fh)

print(manifest.get("pid", 0))
PY
}

PID="$(read_pid)"

if [[ "$PID" == "0" ]]; then
  echo "manifest does not contain a running pid" >&2
  exit 1
fi

if kill -0 "$PID" >/dev/null 2>&1; then
  kill "$PID"
  echo "sent SIGTERM to pid=$PID"
else
  echo "pid not running: $PID"
fi
