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

## Durable Responsibilities

The Bridge Kit should own:

- Session ID generation.
- Port allocation.
- Session directory creation.
- Manifest writing and updates.
- Log routing.
- Startup and shutdown orchestration.
- Checkpoint and restore workflows.
- Protocol documentation and shared expectations.

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

- `GET /health`: Liveness and session metadata.
- `POST /eval`: Execute code with bounded output.
- `GET /objects`: List current objects with summaries.
- `GET /artifact`: Read saved artifacts in slices.
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
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

## Session Manifest

Every session directory should contain a `manifest.json` shaped like this:

```json
{
  "id": "r-20260416-abc123",
  "backend": "r",
  "pid": 12345,
  "port": 8741,
  "started_at": "2026-04-16T10:15:00Z",
  "session_dir": "./sessions/r-20260416-abc123",
  "log_path": "./sessions/r-20260416-abc123/server.log",
  "checkpoint_path": "./sessions/r-20260416-abc123/checkpoint.RData",
  "artifact_dir": "./sessions/r-20260416-abc123/artifacts"
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

## Verification Targets

1. Start a session and confirm `manifest.json` appears under `sessions/<id>/`.
2. Call `/health` and confirm session metadata matches the manifest.
3. Call `/eval` twice and confirm state persists between calls.
4. Produce more than the output limit and confirm the response sets `truncated: true`.
5. Save a checkpoint, restart, restore, and confirm state survives the handoff.
