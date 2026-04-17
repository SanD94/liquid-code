# Agent Guidance

This document has two parts: **Implementation** guidance for developers building the bridge kit, and **Usage** guidance for agents operating through it.

---

## Part 1: Implementation

### Priorities

1. Preserve predictable session lifecycle behavior before adding features.
2. Prefer bounded output and saved artifacts over verbose inline responses.
3. Keep the protocol stable across backends.
4. Treat manifests, checkpoints, and logs as first-class product artifacts.

### Implementation Style

- Favor small, inspectable scripts and server templates.
- Keep backend-specific behavior behind the shared contract in `protocol/CONTRACT.md`.
- Session directories must be self-contained enough to inspect failures after the runtime exits.
- Build incrementally following milestones in `docs/liquid-code-bdd.md`.

### Milestone Workflow (jj)

After completing each milestone and verifying against BDD scenarios:

1. **Describe the changes:**

   ```bash
   jj describe -m "<verb> <short description>
   
   - <key change 1>
   - <key change 2>
   
   "
   ```

2. **Create the next milestone branch:**

   ```bash
   jj new
   ```

3. **Verification checklist before describing:**

   - All BDD scenarios pass
   - Both R and Python backends tested
   - Protocol contract updated (if applicable)
   - Documentation updated
   - No regressions in existing functionality

### Failure Recovery

- Missing checkpoint → Not a silent success, investigate logs
- Startup failure → Inspect `manifest.json` and `server.log`
- Stale process → Use `/restore` to recover from last checkpoint

---

## Part 2: Usage (For Agents)

You are operating through the Liquid Code Bridge Kit. Treat the runtime as a bounded session service, not as an unlimited terminal dump.

### Session Discovery (Empty Slate Problem)

When you start fresh, you need to find or create your session:

```bash
# Step 1: Check for active session
./scripts/get-active-session.sh --json

# Step 2: If no active session, check for running sessions
./scripts/list-sessions.sh --json --status running

# Step 3: If sessions exist, pick the right one
# Look at task_id, task_description, started_at in the manifest

# Step 4: If no suitable session, create one
./scripts/start-r-session.sh \
    --task-id "my-task-123" \
    --description "Analyze Q1 sales data" \
    --files "sales.csv,report.md"

# Step 5: Alternatively, resume from an old session's checkpoint
./scripts/start-r-session.sh \
    --resume-from "<old-session-id>" \
    --task-id "my-task-123" \
    --description "Continue previous analysis"
```

### Session Resume Workflow

```bash
# Get active session port
PORT=$(./scripts/get-active-session.sh --port-only 2>/dev/null)

if [[ -z "$PORT" ]]; then
    # No active session, create one
    ./scripts/start-r-session.sh --task-id "$TASK_ID" --description "$DESCRIPTION"
    PORT=$(./scripts/get-active-session.sh --port-only)
fi

# Verify session is alive
curl http://127.0.0.1:$PORT/health

# Resume work...
```

### Cross-Session Restore (Resume from Old Checkpoint)

To continue from a previous session's checkpoint:

```bash
# Step 1: Find old sessions with checkpoints
./scripts/list-sessions.sh --json --status stopped

# Step 2: Start new session with --resume-from
./scripts/start-r-session.sh \
    --resume-from "<old-session-id>" \
    --task-id "continue-analysis" \
    --description "Continue from previous work"

# Step 3: Call /restore to load the checkpoint state
PORT=$(./scripts/get-active-session.sh --port-only)
curl -X POST http://127.0.0.1:$PORT/restore

# Step 4: Verify variables are restored
curl -X POST http://127.0.0.1:$PORT/eval \
    -H "Content-Type: application/json" \
    -d '{"code":"print(ls())"}'
```

The new session has independent lifecycle - its checkpoints save to its own directory.

### Rules

1. Check `GET /health` before assuming the session is alive.
2. Keep `POST /eval` requests targeted and incremental.
3. Ask for object shape before requesting full data.
4. Prefer saving large results into artifacts and then reading them in slices.
5. Use checkpoints deliberately when the task depends on state continuity.
6. Shut sessions down when the task is complete.

### Session Lifecycle

**Creating Sessions:**

```bash
./scripts/start-r-session.sh --task-id "fix-login" --description "Debug auth flow"
PORT=$(./scripts/get-active-session.sh --port-only)
curl http://127.0.0.1:$PORT/health
```

**State Management:**

```bash
curl -X POST http://127.0.0.1:$PORT/checkpoint
curl -X POST http://127.0.0.1:$PORT/restore
```

**Large Outputs:**

```bash
curl -X POST http://127.0.0.1:$PORT/eval \
    -H "Content-Type: application/json" \
    -d '{"code":"write.csv(df, file.path(manifest$artifact_dir, \"data.csv\"))"}'
curl "http://127.0.0.1:$PORT/artifact?path=data.csv&offset=0&limit=4096"
```

**Async Long-Running Tasks:**

```bash
curl -X POST http://127.0.0.1:$PORT/eval \
    -H "Content-Type: application/json" \
    -d '{"code":"expensive_computation()", "async": true}'
# Returns job_id, poll until done
curl http://127.0.0.1:$PORT/result/<job_id>
```

**File Upload/Download:**

```bash
curl -X POST http://127.0.0.1:$PORT/upload \
    -H "Content-Type: application/json" \
    -d '{"filename":"data.csv", "content":"...", "encoding":"utf-8"}'
curl http://127.0.0.1:$PORT/download/data.csv -o data.csv
```

### Output Strategy

- For data frames or tables, inspect dimensions, columns, and a preview first.
- For plots, reports, and long outputs, write files into the artifact directory.
- If a response is truncated, do not retry with a larger stdout dump by default. Switch to artifacts.

### Failure Strategy

- Missing checkpoint → Not a silent success, investigate logs
- Startup failure → Inspect `manifest.json` and `server.log`
- Stale process → Use `/restore` to recover from last checkpoint
- Session not found → Create new session or query list for alternatives

### Protocol Reference

See `protocol/CONTRACT.md` for the complete endpoint specification.

---

## Part 3: tmux Backend Mode (PoC)

The tmux backend runs R/Python REPLs inside tmux sessions. This provides:
- Manual REPL inspection: `tmux attach -t <session-name>`
- Wrapper crash resilience: tmux session persists independently
- Same HTTP protocol contract as embedded servers

### Requirements

- `tmux` must be installed
- `libtmux` Python package: `pip install libtmux`

### tmux Session Naming

- Format: `lcr-<session-id>` (e.g., `lcr-r-01f25d24-8464-3440-8000`)
- Prefix `lcr-` avoids conflicts with other tmux sessions

### tmux Session Discovery

```bash
# List all liquid-code tmux sessions
tmux list-sessions

# Check if specific session exists
tmux has-session -t lcr-<session-id>

# Attach to see live REPL (Ctrl-d to detach)
tmux attach -t lcr-<session-id>
```

### tmux Session Workflow

```bash
# Start tmux-based session
./scripts/start-r-tmux.sh \
    --task-id "my-task-123" \
    --description "Analyze data"

# Verify tmux session is running
tmux list-sessions

# Attach to see REPL directly (optional)
tmux attach -t lcr-<session-id>

# Work via HTTP as usual
PORT=$(./scripts/get-active-session.sh --port-only)
curl http://127.0.0.1:$PORT/health

# Stop session
./scripts/stop-tmux-session.sh lcr-<session-id>
```

### tmux vs Embedded Comparison

| Aspect | Embedded Server | tmux Backend |
|--------|-----------------|--------------|
| Manual REPL access | No | Yes (`tmux attach`) |
| Wrapper crash | Full restart | Just restart wrapper |
| Complexity | Simpler | Requires libtmux |
| Protocol | Same | Same |
