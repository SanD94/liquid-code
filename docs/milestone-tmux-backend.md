# Milestone 12: tmux-Based Backend (PoC)

## Overview

This milestone explores running R/Python REPLs inside tmux sessions as an alternative
to embedding HTTP servers in the runtime process. The HTTP protocol contract remains
the same; only the backend execution model changes.

## Motivation

**Advantages:**
- Manual REPL inspection: `tmux attach` to see live session
- Wrapper crash resilience: tmux session persists independently of wrapper
- Simpler debugging: can attach to session to see what's happening
- Potential for multi-pane setups (REPL + logging + debugging)

**Trade-offs:**
- Requires tmux installation
- More complex output capture (tmux is pull-based, not push-based)
- Additional dependency: libtmux

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  HTTP Wrapper (tmux_server.py)                             │
│  - Stateless - implements protocol endpoints                 │
│  - Uses libtmux to interact with tmux sessions             │
│  - No runtime state in wrapper process                     │
└────────────────────────┬──────────────────────────────────┘
                         │ libtmux / tmux control socket
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  tmux session: lcr-<session-id>                            │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  R/Python REPL (interactive, persistent)             │ │
│  │  - stdin/stdout attached to tmux pane               │ │
│  │  - State lives in REPL's memory                     │ │
│  │  - Controlled via tmux send-keys                    │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Components

| Component | File | Responsibility |
|-----------|------|----------------|
| tmux REPL Control | `backend/tmux_repl.py` | libtmux wrapper for REPL control |
| HTTP Server | `backend/tmux_server.py` | Protocol endpoints, routes to tmux_repl |
| Session Starter | `scripts/start-r-tmux.sh` | Creates session + starts wrapper |
| Session Stopper | `scripts/stop-tmux-session.sh` | Destroys tmux session gracefully |

## Files to Create

```
liquid-code/
├── backend/
│   ├── __init__.py
│   ├── tmux_repl.py      # Core tmux REPL control
│   └── tmux_server.py    # HTTP server
├── scripts/
│   ├── start-r-tmux.sh   # R tmux session starter
│   └── stop-tmux-session.sh  # Session destroyer
```

## Files Modified

```
liquid-code/
├── docs/
│   ├── liquid-code-bdd.md      # Added Milestone 12
│   └── session-lifecycle.md    # Added tmux mode notes
├── README.md                   # Added tmux milestone
└── AGENTS.md                   # Added tmux usage guidance
```

## Output Capture Strategy

tmux is pull-based (not push-based), so output capture requires polling:

1. **Line tracking**: Track pane history line count before sending code
2. **Send code**: Use `tmux send-keys` to inject code + Enter
3. **Wait for prompt**: Poll pane, looking for REPL prompt to reappear
4. **Capture output**: Use `capture-pane` to get stdout lines

### Prompt Detection

| Backend | Prompt Pattern |
|---------|----------------|
| R | `> ` (at start of line) |
| Python | `>>> ` or `... ` |

### Edge Cases

- Multi-line input: May need to send line-by-line or wrap in braces
- Error output: May appear on stderr, captured separately
- Warnings/messages: Platform-dependent, may need extra handling
- Empty output: Prompt reappears immediately

## tmux_repl.py API

```python
class TmuxREPL:
    def __init__(self, session_id: str, backend: str = "r"):
        """
        Initialize tmux REPL controller.
        
        Args:
            session_id: Liquid code session ID (used for naming tmux session)
            backend: 'r' or 'python'
        """
        
    def create(self) -> None:
        """Create detached tmux session with REPL."""
        
    def is_alive(self) -> bool:
        """Check if REPL is responsive."""
        
    def send_code(self, code: str, timeout: float = 30.0) -> str:
        """
        Execute code and return stdout.
        
        Args:
            code: R/Python code to execute
            timeout: Max seconds to wait for result
            
        Returns:
            stdout text from REPL
        """
        
    def checkpoint(self, path: str) -> None:
        """Save session state to checkpoint file."""
        
    def restore(self, path: str) -> None:
        """Load checkpoint file into session."""
        
    def destroy(self) -> None:
        """Kill tmux session."""
```

## Manifest Fields (tmux mode)

```json
{
  "id": "r-01f25d24-8464-3440-8000-a35805b91c31",
  "backend": "r-tmux",
  "tmux_session": "lcr-r-01f25d24-8464-3440-8000-a35805b91c31",
  "pid": 12345,
  "port": 8741,
  "started_at": "2026-04-16T10:15:00Z",
  "session_dir": "./sessions/...",
  "log_path": "./sessions/.../server.log",
  "checkpoint_path": "./sessions/.../checkpoint.RData",
  "artifact_dir": "./sessions/.../artifacts"
}
```

Note: `backend` uses `-tmux` suffix for tmux-mode sessions.

## Checkpoint/Restore Commands

### R

```r
# Checkpoint
save.image("/path/to/checkpoint.RData")

# Restore
load("/path/to/checkpoint.RData")
```

### Python (requires dill)

```python
# Checkpoint
import dill
dill.dump_session("/path/to/checkpoint.pkl")

# Restore
import dill
dill.load_session("/path/to/checkpoint.pkl")
```

## Testing Approach

1. **Manual libtmux test:**
   ```bash
   pip install libtmux
   python3 -c "
   import libtmux
   server = libtmux.Server()
   session = server.new_session('test', detach=True)
   pane = session.attached_window.attached_pane
   pane.send_keys('R --vanilla')
   print(pane.capture pane())
   "
   ```

2. **tmux_repl.py standalone test:**
   ```bash
   python3 -c "
   from backend.tmux_repl import TmuxREPL
   repl = TmuxREPL('test-001', 'r')
   repl.create()
   print(repl.send_code('x <- 2'))
   print(repl.send_code('x + 1'))
   repl.destroy()
   "
   ```

3. **Full protocol test:**
   ```bash
   ./scripts/start-r-tmux.sh
   PORT=$(./scripts/get-active-session.sh --port-only)
   curl http://127.0.0.1:$PORT/health
   curl -X POST http://127.0.0.1:$PORT/eval -d '{"code":"x <- 2"}'
   ```

## Success Criteria

- [x] tmux session starts with R REPL
- [x] libtmux can send code and capture output
- [x] HTTP wrapper serves /health, /eval, /checkpoint, /restore
- [x] State persists across /eval calls (x <- 2; x + 1 = 3)
- [x] /checkpoint saves state to disk
- [x] /restore loads checkpoint into fresh session
- [x] tmux session can be destroyed cleanly

## Future Extensions (Post-PoC)

1. **Python support**: Same pattern as R, uses `python3` instead of `R`
2. **Multi-pane setup**: REPL + logging pane
3. **Async job support**: Background tmux process polls for completion
4. **Artifact detection**: Monitor pane for file creation patterns
5. **Objects inspection**: Send `ls()` or `str()` and parse output
