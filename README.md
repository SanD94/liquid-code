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
- `~/.liquid-code/` is where agent state is persisted (active session).

## All Milestones Complete

See `docs/liquid-code-bdd.md` for the full BDD specification.

| # | Milestone | Description |
|---|-----------|-------------|
| 1 | Reliable R Bridge | Start, health, eval, shutdown |
| 2 | Output And Artifact Discipline | Truncation, artifact references, slicing |
| 3 | Recovery | Checkpoint save and restore |
| 4 | Agent Guidance | Prompts for shape-first workflow |
| 5 | Python Backend Consistency | Both backends match the shared contract |
| 6 | Session Management CLI | List sessions, multi-backend scripts |
| 7 | File Operations | Upload, download, artifact listing |
| 8 | Session Resilience | Auto-checkpoint, crash recovery, health monitoring |
| 9 | Async Eval | Non-blocking eval with job IDs |
| 10 | Agent Session Discovery | UUIDv6, task metadata, active session tracking |
| 11 | Cross-Session Restore | Resume from checkpoint in old session |

## Session Manifest

Each session owns a `manifest.json` with lifecycle and task metadata:

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
  "artifact_dir": "./sessions/.../artifacts",
  "resumed_from": "r-01f25d23-...",
  "resumed_from_checkpoint": "./sessions/.../checkpoint.RData"
}
```

The `resumed_from` and `resumed_from_checkpoint` fields are only present in sessions created with `--resume-from`.

## Quick Start

**R Session:**

```bash
./scripts/start-r-session.sh --task-id my-task --description "My analysis"
```

**Python Session:**

```bash
./scripts/start-python-session.sh --task-id my-task --description "Data processing"
```

**Session Management:**

```bash
./scripts/list-sessions.sh           # List all sessions
./scripts/list-sessions.sh --json     # JSON output for agents
./scripts/list-sessions.sh --status running
./scripts/get-active-session.sh       # Get current session info
./scripts/get-active-session.sh --port-only
./scripts/stop-session.sh <session-id>
```

**Resume from Old Session:**

```bash
# List stopped sessions to find one with checkpoint
./scripts/list-sessions.sh --json --status stopped

# Start new session that loads checkpoint from old session
./scripts/start-r-session.sh --resume-from <old-session-id> --description "Continue analysis"

# Load the checkpoint state into the new session
curl -X POST http://127.0.0.1:<port>/restore
```

The new session writes its own checkpoints to its own directory, keeping the old session's checkpoint unchanged.

**For Agents:**

```bash
# Resume from empty slate
ACTIVE=$(./scripts/get-active-session.sh --port-only 2>/dev/null)
if [[ -z "$ACTIVE" ]]; then
    ./scripts/start-r-session.sh --task-id my-task --description "New task"
    ACTIVE=$(./scripts/get-active-session.sh --port-only)
fi
curl http://127.0.0.1:$ACTIVE/health
```

## Protocol Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Liveness, session metadata, checkpoint status |
| `POST /eval` | Execute code (sync or async with `async: true`) |
| `GET /jobs` | List async job statuses |
| `GET /result/<job_id>` | Get async job result |
| `GET /objects` | List runtime objects with summaries |
| `GET /artifacts` | List artifact directory |
| `GET /artifact` | Read artifact in slices |
| `GET /download/<path>` | Stream artifact as file |
| `POST /upload` | Upload file to artifacts |
| `POST /checkpoint` | Save runtime state |
| `POST /restore` | Restore from checkpoint |
| `POST /shutdown` | Graceful shutdown |
