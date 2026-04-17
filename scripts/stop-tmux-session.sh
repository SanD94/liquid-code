#!/usr/bin/env bash

set -euo pipefail

show_usage() {
    cat <<EOF
Usage: $0 <tmux-session-name>

Stop a tmux-based Liquid Code session.

ARGUMENTS:
    tmux-session-name    The tmux session name (e.g., lcr-r-01f25d24-...)

OPTIONS:
    -h, --help           Show this help message

EXAMPLES:
    $0 lcr-r-01f25d24-8464-3440-8000-a35805b91c31
EOF
}

if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

TMUX_SESSION="$1"

if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Error: tmux session not found: $TMUX_SESSION" >&2
    exit 1
fi

tmux kill-session -t "$TMUX_SESSION"

echo "tmux session destroyed: $TMUX_SESSION"
