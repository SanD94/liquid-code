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
   jj describe -m "feat(milestone-N): <short description>
   
   - <key change 1>
   - <key change 2>
   
   Milestone N: <milestone name>"
   ```

2. **Create the next milestone branch:**

   ```bash
   jj new
   ```

3. **Verification checklist before describing:**

   - [ ] All BDD scenarios pass
   - [ ] Both R and Python backends tested
   - [ ] Protocol contract updated (if applicable)
   - [ ] Documentation updated
   - [ ] No regressions in existing functionality

### Failure Recovery

- Missing checkpoint → Not a silent success, investigate logs
- Startup failure → Inspect `manifest.json` and `server.log`
- Stale process → Use `/restore` to recover from last checkpoint

---

## Part 2: Usage (For Agents)

You are operating through the Liquid Code Bridge Kit. Treat the runtime as a bounded session service, not as an unlimited terminal dump.

### Rules

1. Check `GET /health` before assuming the session is alive.
2. Keep `POST /eval` requests targeted and incremental.
3. Ask for object shape before requesting full data.
4. Prefer saving large results into artifacts and then reading them in slices.
5. Use checkpoints deliberately when the task depends on state continuity.
6. Shut sessions down when the task is complete.

### Session Lifecycle

**Creating Sessions:**

```text
GET /health
POST /checkpoint {}        # Save initial state if needed
```

**State Management:**

```text
POST /checkpoint {}        # Save before risky work
POST /restore {}           # Recover after restart
```

**Large Outputs:**

```text
POST /eval {"code":"write.csv(df, file.path(manifest$artifact_dir, 'data.csv'))"}
GET /artifact?path=data.csv&offset=0&limit=4096
```

**Async Long-Running Tasks:**

```text
POST /eval {"code":"expensive_computation()", "async": true}  # Returns job_id
GET /jobs                  # Check job statuses
GET /result/<job_id>       # Get result when ready
```

**File Upload/Download:**

```text
POST /upload {"filename":"data.csv", "content":"...", "encoding":"utf-8"}
GET /download/data.csv     # Stream as file
```

### Output Strategy

- For data frames or tables, inspect dimensions, columns, and a preview first.
- For plots, reports, and long outputs, write files into the artifact directory.
- If a response is truncated, do not retry with a larger stdout dump by default. Switch to artifacts.

### Failure Strategy

- Inspect `manifest.json` and `server.log` when startup fails.
- Treat missing checkpoints as recoverable operational errors, not silent success.
- Keep protocol usage consistent across R and Python backends.

### Protocol Reference

See `protocol/CONTRACT.md` for the complete endpoint specification.
