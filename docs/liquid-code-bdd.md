# Liquid Code BDD

This document defines milestone-based behavior so the bridge kit can be implemented incrementally without losing the core product shape.

## Milestone 1: Reliable R Bridge

### Scenario: Start an R session

- Given an operator runs `scripts/start-r-session.sh`
- When the script completes
- Then a new session directory exists under `sessions/<id>/`
- And `manifest.json` records the session metadata
- And `server.log` exists for later inspection

### Scenario: Health check reports liveness

- Given a running R session
- When a client calls `GET /health`
- Then the response has `ok: true`
- And the response includes the session ID and port

### Scenario: Eval preserves state

- Given a running R session
- When a client posts `x <- 2` to `POST /eval`
- And the client later posts `x + 1`
- Then the second response prints `3`

### Scenario: Shutdown is graceful

- Given a running R session
- When a client posts to `POST /shutdown`
- Then the server exits without leaving a corrupt manifest or partial checkpoint

## Milestone 2: Output And Artifact Discipline

### Scenario: Oversized stdout is truncated

- Given a running session
- When eval produces more than the configured output limit
- Then the response includes only the first limit-sized slice of stdout
- And `truncated` is `true`
- And `total_lines` reports the untruncated count

### Scenario: Artifacts are returned by reference

- Given a running session
- When eval writes a plot or file into the session artifact directory
- Then the response includes artifact metadata instead of embedding the full file contents

### Scenario: Artifacts are readable in slices

- Given a session artifact larger than one response page
- When a client calls `GET /artifact` with offset and limit
- Then the server returns only the requested slice

## Milestone 3: Recovery

### Scenario: Checkpoint saves state

- Given a running session with objects in memory
- When a client posts to `POST /checkpoint`
- Then the runtime writes a checkpoint file at the manifest checkpoint path

### Scenario: Restore recovers state

- Given a saved checkpoint from a previous session
- When a fresh process posts to `POST /restore`
- Then previously saved variables reappear in the backend environment

### Scenario: Failures remain inspectable

- Given a startup or runtime failure
- When an operator inspects the session directory
- Then the manifest, logs, and checkpoint path explain what happened

## Milestone 4: Agent Guidance

### Scenario: Agent asks for shape before full data

- Given a large table exists in the backend
- When an agent needs to understand it
- Then the agent first asks for dimensions, columns, and a preview
- And only requests the full data as an artifact when necessary

### Scenario: Agent prefers artifacts for large outputs

- Given a task would produce thousands of output lines
- When an agent evaluates code
- Then it instructs the runtime to save a file in the artifact directory
- And the agent retrieves slices or summaries instead of inline dumps

## Milestone 5: Python Backend Consistency

### Scenario: Python matches the shared contract

- Given a running Python session
- When a client calls the shared endpoints
- Then the JSON response envelope matches the R backend contract
- And the manifest fields keep the same meaning

## Verification Checklist

1. Review the manifest shape before implementation changes.
2. Start an R session and verify `/health` and `/eval` manually.
3. Force output truncation and verify the contract fields.
4. Checkpoint, restart, restore, and verify state persistence.
5. Repeat the same checks against the Python backend template.
