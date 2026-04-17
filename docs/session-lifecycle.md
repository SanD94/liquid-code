# Session Lifecycle

This document describes the session states owned by the Bridge Kit and the expectations around their transitions.

## Lifecycle States

### Requested

The operator or agent asks the Bridge Kit to create a new session. No runtime process exists yet.

### Prepared

The Bridge Kit allocates a session ID, a port, and a session directory. It writes an initial manifest and creates the log and artifact paths.

### Running

The backend runtime is alive and serving the shared HTTP contract. The manifest should now contain the runtime PID and the port in use.

### Checkpointed

The backend has written a checkpoint file that can be used by a later session. The running process may continue to serve requests after the checkpoint is written.

### Restoring

A fresh runtime starts with the intent to load a prior checkpoint. During this state, the server may be alive but should not claim the restore is complete until the checkpoint loads successfully.

### Shutting Down

The runtime has accepted a shutdown request and is draining outstanding work. The session directory remains intact for inspection.

### Stopped

The runtime process has exited. The manifest, logs, checkpoint, and artifacts remain the durable record.

## Directory Expectations

Each session directory should contain:

- `manifest.json`
- `server.log`
- `artifacts/`
- A backend checkpoint file such as `checkpoint.RData` or `checkpoint.pkl`

## Operational Notes

- Manifests should be written before the runtime starts so operators can inspect failed launches.
- Logs should be streamed into the session directory from process start until exit.
- Artifact paths should be relative to the session artifact directory to keep retrieval simple and safe.
- Shutdown should preserve the session directory even when the process exits cleanly.
- Active session file (`~/.liquid-code/active`) tracks the current session for agent resumption.

## Agent Session Discovery

For agents resuming from an empty slate:

1. Check `~/.liquid-code/active` for the current session ID
2. If exists, verify it's still running via `/health`
3. If not running or no active session, query `scripts/list-sessions.sh --json --status running`
4. Select appropriate session based on `task_id` or `task_description`
5. If no suitable session, create new with `scripts/start-*-session.sh --task-id <id> --description <desc>`

## Cross-Session Restore

Agents can resume from a previous session's checkpoint:

1. List stopped sessions: `scripts/list-sessions.sh --json --status stopped`
2. Start new session with `--resume-from <old-session-id>`
3. Call `POST /restore` to load the checkpoint into the new session
4. The new session has independent lifecycle - its checkpoints save to its own directory

The new session manifest includes `resumed_from` (old session ID) and `resumed_from_checkpoint` (path to old checkpoint). After `/restore`, these fields are removed and `checkpoint_path` points to the new session's directory.

## Manual Verification

1. Start a session and inspect `manifest.json` before calling any endpoint.
2. Confirm `/health` reflects the same session ID and port.
3. Create state, checkpoint it, and confirm the checkpoint file appears in the session directory.
4. Restore into a fresh process and confirm the state is available again.
5. Shut the process down and confirm logs and artifacts remain on disk.

## tmux Backend Mode (PoC)

As an alternative to embedding HTTP servers in the runtime process, the tmux backend
runs the R/Python REPL inside a tmux session. The HTTP wrapper is a separate process
that uses libtmux to control the REPL.

### Session Directory Expectations (tmux mode)

Each tmux session directory should contain:

- `manifest.json` (includes `tmux_session` field)
- `server.log`
- `artifacts/`
- A backend checkpoint file such as `checkpoint.RData` or `checkpoint.pkl`

### tmux Session Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                      HTTP Wrapper Process                           │
│  - Stateless - implements protocol endpoints                        │
│  - Uses libtmux to interact with tmux sessions                     │
│  - Can restart independently of tmux session                        │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ libtmux
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  tmux session: lcr-<session-id>                                    │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  R/Python REPL (interactive, persistent)                      │ │
│  │  - stdin/stdout attached to tmux pane                         │ │
│  │  - State lives in REPL's memory                               │ │
│  │  - Controlled via tmux send-keys                              │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### tmux Session Naming

- Session name format: `lcr-<session-id>` (e.g., `lcr-r-01f25d24-8464-3440-8000`)
- The `lcr-` prefix avoids conflicts with other tmux sessions
- Operators can attach manually: `tmux attach -t <session-name>`

### tmux vs Embedded Server Comparison

| Aspect | Embedded Server | tmux Backend |
|--------|-----------------|--------------|
| Session persistence | Tied to server process | Independent of wrapper |
| Manual interaction | Not directly | `tmux attach` to see REPL |
| Wrapper crash recovery | Full restart | Just restart wrapper |
| Architecture complexity | Simpler | Requires libtmux |
| Output capture | Direct stdout | Pane capture via tmux |

### Manual Verification (tmux mode)

1. Start tmux session: `./scripts/start-r-tmux.sh`
2. Verify tmux session exists: `tmux list-sessions`
3. Attach to REPL: `tmux attach -t lcr-<id>` (Ctrl-d to detach)
4. Confirm `/health` returns expected envelope
5. Test eval: `POST /eval` with `x <- 2` then `x + 1` returns `3`
6. Test checkpoint/restore via HTTP
7. Kill wrapper process, restart, verify session alive
8. Shutdown and verify tmux session destroyed
