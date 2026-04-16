# Liquid Code

Liquid Code packages a durable "Bridge Kit" that can spin up ephemeral runtime sessions for tool-using agents. The durable layer owns lifecycle, manifests, logs, and protocol guarantees. Each session bridge owns a single backend runtime such as R or Python.

The working model is:

```text
Agent -> Bridge Kit (durable) -> Session Bridge (ephemeral) -> Target Runtime
```

## Repository Layout

- `docs/` contains the product plan, BDD milestones, and lifecycle notes.
- `protocol/` defines the HTTP contract shared by all backends.
- `scripts/` contains operator-facing session start and stop helpers.
- `servers/` contains backend server templates.
- `templates/` contains starter assets for new session bridges.
- `prompts/` contains agent guidance for using the bridge safely.
- `sessions/` is where runtime session directories are created.

## Milestones

Milestones 1-5 are complete. See `docs/liquid-code-bdd.md` for the full BDD specification.

### Completed
1. **Reliable R Bridge** - Start, health, eval, shutdown
2. **Output And Artifact Discipline** - Truncation, artifact references, slicing
3. **Recovery** - Checkpoint save and restore
4. **Agent Guidance** - Prompts for shape-first workflow
5. **Python Backend Consistency** - Both backends match the shared contract

### In Progress
6. **Session Management CLI** - List sessions, status, multi-backend scripts

### Planned
7. **File Operations** - Upload/download, artifact listing
8. **Session Resilience** - Auto-checkpoint, crash recovery, stale detection
9. **Async Eval** - Non-blocking eval with job IDs

## Session Manifest

Each session owns a `manifest.json` with the minimum lifecycle metadata:

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

## Quick Start

Use the R starter script to create a session directory, write a manifest, and launch the server template:

```bash
./scripts/start-r-session.sh
curl http://127.0.0.1:<port>/health
```

Use `./scripts/stop-session.sh <session-id>` to shut down a running session.
