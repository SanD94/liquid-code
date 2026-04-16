# Agent Guidance

## Priorities

1. Preserve predictable session lifecycle behavior before adding features.
2. Prefer bounded output and saved artifacts over verbose inline responses.
3. Keep the protocol stable across backends.
4. Treat manifests, checkpoints, and logs as first-class product artifacts.

## Implementation Style

- Favor small, inspectable scripts and server templates.
- Keep backend-specific behavior behind the shared contract in `protocol/CONTRACT.md`.
- Session directories must be self-contained enough to inspect failures after the runtime exits.
- Build incrementally following milestones in `docs/liquid-code-bdd.md`.

## Session Lifecycle

### Creating Sessions

```text
POST /eval {"code":"..."}  # Always check health first
GET /health
```

### State Management

```text
POST /checkpoint {}        # Save before risky work
POST /restore {}           # Recover after restart
```

### Large Outputs

```text
POST /eval {"code":"write.csv(df, file.path(manifest$artifact_dir, 'data.csv'))"}
GET /artifact?path=data.csv&offset=0&limit=4096
```

### Async Long-Running Tasks

```text
POST /eval {"code":"expensive_computation()", "async": true}  # Returns job_id
GET /jobs                  # Check job statuses
GET /result/<job_id>        # Get result when ready
```

## Protocol Reference

See `protocol/CONTRACT.md` for the complete endpoint specification.

## Failure Recovery

- Missing checkpoint → Not a silent success, investigate logs
- Startup failure → Inspect `manifest.json` and `server.log`
- Stale process → Use `/restore` to recover from last checkpoint
