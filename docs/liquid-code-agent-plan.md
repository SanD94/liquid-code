# Liquid Code Agent Plan

## Product Shape

Liquid Code should be built as a durable Bridge Kit that owns lifecycle, observability, and contract enforcement for ephemeral runtime bridges. The bridge kit is the product surface. R, Python, and other backends are replaceable session implementations behind that surface.

```text
Agent -> Bridge Kit (durable) -> Session Bridge (ephemeral) -> Target Runtime
```

## Why This Shape

- Agents need a predictable control plane more than they need a single immortal REPL process.
- Durable manifests and logs make failures inspectable from outside the runtime.
- A stable protocol lets multiple backends behave the same way.
- Session-local artifacts provide a place for large outputs, plots, and saved state.
- UUIDv6 session IDs enable time-ordered sorting across distributed agents.
- Active session tracking enables seamless resumption from empty slate.

## Durable Responsibilities

The Bridge Kit should own:

- Session ID generation (UUIDv6 for time-ordering).
- Port allocation.
- Session directory creation.
- Manifest writing and updates (including task metadata).
- Log routing.
- Startup and shutdown orchestration.
- Checkpoint and restore workflows.
- Protocol documentation and shared expectations.
- Active session tracking (`~/.liquid-code/active`).

## Ephemeral Responsibilities

Each session bridge should own:

- Backend runtime startup.
- Eval execution inside a persistent backend environment.
- Object inspection.
- Artifact creation and retrieval.
- Checkpoint save and restore for that runtime.
- Graceful shutdown.

## Protocol Endpoints

All backends should converge on the following endpoints:

- `GET /health`: Liveness, session metadata, checkpoint status.
- `POST /eval`: Execute code with bounded output (sync or async).
- `GET /jobs`: List async job statuses.
- `GET /result/<job_id>`: Get async job result.
- `GET /objects`: List current objects with summaries.
- `GET /artifacts`: List artifact directory contents.
- `GET /artifact`: Read saved artifacts in slices.
- `GET /download/<path>`: Stream artifact as file.
- `POST /upload`: Upload file to artifacts.
- `POST /checkpoint`: Save state.
- `POST /restore`: Restore state.
- `POST /shutdown`: Graceful teardown.

## Eval Response Contract

`POST /eval` should return a transport-safe JSON envelope that can represent success, truncation, diagnostics, and artifact references:

```json
{
  "ok": true,
  "stdout": ["[1] 2"],
  "warnings": [],
  "messages": [],
  "artifacts": [],
  "truncated": false,
  "total_lines": 1,
  "error": null,
  "session": {
    "id": "r-01f25d24-8464-3440-8000-a35805b91c31",
    "port": 8741
  }
}
```

## Session Manifest

Every session directory should contain a `manifest.json` shaped like this:

```json
{
  "id": "r-01f25d24-8464-3440-8000-a35805b91c31",
  "backend": "r",
  "pid": 12345,
  "port": 8741,
  "started_at": "2026-04-16T10:15:00Z",
  "task_id": "fix-login-bug",
  "task_description": "Debug the authentication flow",
  "related_files": ["auth.py", "login.html"],
  "session_dir": "./sessions/r-01f25d24-8464-3440-8000-a35805b91c31",
  "log_path": "./sessions/.../server.log",
  "checkpoint_path": "./sessions/.../checkpoint.RData",
  "artifact_dir": "./sessions/.../artifacts"
}
```

## Milestones

### Milestone 1: Reliable R Bridge

- Start a session from a script.
- Expose `GET /health`.
- Support `POST /eval` against persistent state.
- Shut down cleanly.

### Milestone 2: Output And Artifact Discipline

- Truncate oversized stdout.
- Return artifact references instead of flooding responses.
- Read artifacts in slices with `GET /artifact`.

### Milestone 3: Recovery

- Persist checkpoints explicitly.
- Restore state into a fresh process.
- Keep enough logs to reconstruct failures.

### Milestone 4: Agent Guidance

- Teach agents to inspect object shape before asking for full data.
- Teach agents to prefer files and artifacts for large results.
- Keep prompts aligned with the contract.

### Milestone 5: Python Backend Consistency

- Bring Python onto the same endpoint surface.
- Match response envelope semantics.
- Keep session manifests and lifecycle parallel to R.

### Milestone 6: Session Management CLI

- Add `scripts/list-sessions.sh` for session listing.
- Add `scripts/start-python-session.sh` for Python sessions.

### Milestone 7: File Operations

- Add `POST /upload` for uploading files.
- Add `GET /download/<path>` for streaming files.
- Add `GET /artifacts` for listing artifact directory.

### Milestone 8: Session Resilience

- Auto-checkpoint on configurable interval.
- Add `seconds_since_checkpoint` to health response.
- Improve crash recovery story.

### Milestone 9: Async Eval

- Add `async: true` option to `POST /eval`.
- Add `GET /jobs` for listing job statuses.
- Add `GET /result/<job_id>` for retrieving results.

### Milestone 10: Agent Session Discovery

- Use UUIDv6 for time-ordered session IDs.
- Add task metadata to manifests (task_id, task_description, related_files).
- Track active session in `~/.liquid-code/active`.
- Add JSON output to list-sessions for machine parsing.
- Add filter options (--backend, --status, --task-id).

## Verification Targets

1. Start a session and confirm `manifest.json` appears under `sessions/<id>/`.
2. Call `/health` and confirm session metadata matches the manifest.
3. Call `/eval` twice and confirm state persists between calls.
4. Produce more than the output limit and confirm the response sets `truncated: true`.
5. Save a checkpoint, restart, restore, and confirm state survives the handoff.
6. Verify session IDs are UUIDv6 format.
7. Verify `~/.liquid-code/active` contains current session.
8. Create session with task metadata, verify it appears in manifest.
9. Query sessions with filters, verify correct results.
10. Resume from empty slate using active session file.
