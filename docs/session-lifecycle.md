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
