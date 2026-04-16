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

## Milestone 6: Session Management CLI

### Scenario: List all sessions

- Given multiple session directories exist under `sessions/`
- When an operator runs `scripts/list-sessions.sh`
- Then the output shows each session's ID, backend, status, and port
- And stopped sessions show their exit time

### Scenario: Session status from manifest

- Given a session directory with a valid manifest
- When an operator queries session status
- Then the response includes pid, backend, started_at, and checkpoint_path
- And if the pid is not running, the status shows as "stopped"

### Scenario: Start Python session via script

- Given an operator runs `scripts/start-python-session.sh`
- When the script completes
- Then a new session directory exists under `sessions/<id>/`
- And `manifest.json` records backend as "python"
- And the Python server is listening on the allocated port

## Milestone 7: File Operations

### Scenario: Upload file to session

- Given a running session
- When an operator posts a file to `POST /upload`
- Then the file appears in the session artifact directory
- And the response confirms the uploaded path and size

### Scenario: Download artifact from session

- Given a running session with artifacts
- When an operator requests `GET /download/<artifact-path>`
- Then the response streams the raw file contents
- And Content-Disposition header suggests a filename

### Scenario: List session artifacts

- Given a running session with files in its artifact directory
- When a client calls `GET /artifacts`
- Then the response includes a list of files with path, size, and mtime

## Milestone 8: Session Resilience

### Scenario: Auto-checkpoint on interval

- Given a running session with state
- When the configured checkpoint interval elapses
- Then the server automatically calls `/checkpoint`
- And the checkpoint file is updated without client request

### Scenario: Crash recovery restarts session

- Given a session directory with a valid checkpoint
- When the server process dies unexpectedly
- When a new server starts with the same manifest
- Then the new server can call `/restore` to recover state
- And the agent receives the same variables as before the crash

### Scenario: Health check reports checkpoint status

- Given a running session
- When a client calls `GET /health`
- Then the response includes `seconds_since_checkpoint`
- And the response includes session metadata for recovery

## Milestone 9: Async Eval

### Scenario: Eval returns immediately with job ID

- Given a running session
- When a client posts `{"code": "...", "async": true}` to `POST /eval`
- Then the response returns a job_id immediately
- And the actual result is available at `GET /result/<job_id>`

### Scenario: List pending jobs

- Given a running session with submitted jobs
- When a client calls `GET /jobs`
- Then the response includes all jobs with their status
- And each job shows submitted_at and completed_at timestamps

## Milestone 10: Agent Session Discovery

### Scenario: Session IDs use UUIDv6 format

- Given an operator starts a new session
- When the session is created
- Then the session ID is a valid UUIDv6 format
- And the timestamp is embedded in the UUID for sorting

### Scenario: Active session file tracks current session

- Given a running session
- When the session starts
- Then `~/.liquid-code/active` contains the session ID
- And an agent can read this file to resume the session

### Scenario: Manifest includes task metadata

- Given an agent creates a session with task context
- When the session is created with task_id and description
- Then the manifest includes `task_id`, `task_description`, and `related_files`
- And these fields are queryable via session listing

### Scenario: Session listing with JSON output

- Given multiple sessions exist
- When an agent queries `scripts/list-sessions.sh --json`
- Then the output is valid JSON for machine parsing
- And includes all manifest fields for each session

### Scenario: Agent resumes session from active file

- Given a previous session was marked as active
- When an agent starts with an empty slate
- Then the agent can read `~/.liquid-code/active`
- And query the corresponding session to verify it's still valid

## Milestone 11: Cross-Session Restore

### Scenario: Resume from old session checkpoint

- Given a stopped session with a saved checkpoint at `sessions/<old-id>/checkpoint.*`
- When an operator starts a new session with `--resume-from <old-session-id>`
- Then the new session's manifest references the old checkpoint path
- And `POST /restore` loads the checkpoint from the old session
- And previously saved variables reappear in the backend environment

### Scenario: New session has independent lifecycle after resume

- Given a new session created via `--resume-from <old-session-id>`
- When the new session checkpoints its state
- Then the checkpoint is written to the new session's directory
- And the old session's checkpoint remains unchanged

### Scenario: Resume with task metadata

- Given an old session with task metadata
- When resuming from that session
- Then the new session's manifest includes `task_id` and `task_description`
- And the session listing shows the resumed session with its own status

### Scenario: Resume fails gracefully for invalid checkpoint

- Given an invalid or missing checkpoint path
- When an operator attempts to resume
- Then the script reports an error without creating a broken session
- And logs indicate the checkpoint was not found

## Verification Checklist

1. Review the manifest shape before implementation changes.
2. Start an R session and verify `/health` and `/eval` manually.
3. Force output truncation and verify the contract fields.
4. Checkpoint, restart, restore, and verify state persistence.
5. Repeat the same checks against the Python backend template.
6. Run `scripts/list-sessions.sh` and verify output format.
7. Upload a file and verify it appears in the artifact directory.
8. Verify auto-checkpoint triggers on configured interval.
9. Submit async job and retrieve result via `/result/<job_id>`.
10. Verify `/jobs` lists all submitted async jobs.
11. Verify session IDs are valid UUIDv6 format.
12. Verify `~/.liquid-code/active` contains current session ID.
13. Verify manifest includes task metadata when provided.
14. Verify `list-sessions.sh --json` outputs valid JSON.
15. Resume from old session checkpoint and verify state loads correctly.
16. Verify new session creates its own checkpoint after resume.
17. Verify resume fails gracefully for invalid checkpoint path.
