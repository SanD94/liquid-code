# Bridge Kit Contract

All backends should implement the same minimal HTTP surface so agents can change runtimes without relearning lifecycle behavior.

## Common Rules

- Requests and responses use JSON unless otherwise noted.
- Every response includes enough session metadata for operators to match the runtime back to its manifest.
- Stdout should be bounded. Large results should move into artifacts.
- Artifact access must be limited to files inside the session artifact directory.
- Path traversal is forbidden; all artifact paths must be relative to the artifact directory.

## `GET /health`

### Purpose

Confirm liveness, advertise session metadata, and report resilience state.

### Response

```json
{
  "ok": true,
  "stale": false,
  "seconds_since_checkpoint": 120,
  "session": {
    "id": "r-20260416-abc123",
    "backend": "r",
    "port": 8741,
    "started_at": "2026-04-16T10:15:00Z"
  }
}
```

### Notes

- `stale`: true if the server process is no longer responding (deprecated; use `/health` on the specific port).
- `seconds_since_checkpoint`: seconds elapsed since the last checkpoint was saved.

## `POST /eval`

### Purpose

Execute code inside the persistent backend environment.

### Request

```json
{
  "code": "x <- 2"
}
```

### Async Request

```json
{
  "code": "Sys.sleep(10); x <- 2",
  "async": true
}
```

### Response (Sync)

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

### Response (Async)

```json
{
  "job_id": "job-1776373500-1",
  "status": "running",
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

### Notes

- `stdout` is an array of lines to avoid newline ambiguity.
- `warnings` and `messages` are backend-specific diagnostics normalized into lists.
- `artifacts` contains metadata for any saved files created during the request.
- `truncated` describes the returned stdout slice, not whether execution was incomplete.
- When `async: true`, execution is deferred; poll `/result/<job_id>` for completion.

## `GET /jobs`

### Purpose

List all submitted async jobs with their status.

### Response

```json
{
  "ok": true,
  "jobs": [
    {
      "job_id": "job-1776373500-1",
      "status": "completed",
      "submitted_at": "2026-04-16T10:15:00Z",
      "completed_at": "2026-04-16T10:15:01Z"
    }
  ],
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

### Notes

- `status` is one of: `running`, `completed`, `failed`.

## `GET /result/<job_id>`

### Purpose

Retrieve the result of an async job. If the job is still running, it executes and returns the result.

### Response

```json
{
  "ok": true,
  "status": "completed",
  "result": {
    "ok": true,
    "stdout": ["[1] 2"],
    "warnings": [],
    "messages": [],
    "artifacts": [],
    "truncated": false,
    "total_lines": 1,
    "error": null
  },
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

## `GET /objects`

### Purpose

List objects in the backend environment with small summaries so agents can inspect shape before requesting full data.

### Response

```json
{
  "ok": true,
  "objects": [
    {
      "name": "df",
      "class": "data.frame",
      "summary": "10 rows x 4 cols"
    }
  ],
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

## `GET /artifacts`

### Purpose

List all files in the session artifact directory with metadata.

### Response

```json
{
  "ok": true,
  "artifacts": [
    {
      "path": "output.csv",
      "size": 1024,
      "mtime": "2026-04-16T10:15:00Z"
    }
  ],
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

## `GET /artifact`

### Purpose

Read a saved artifact in slices (JSON response with content).

### Query Parameters

- `path`: Relative path inside the session artifact directory (required).
- `offset`: Byte offset to start reading from. Defaults to `0`.
- `limit`: Maximum bytes to return. Backends may cap this.

### Response

```json
{
  "ok": true,
  "path": "output.csv",
  "offset": 0,
  "limit": 4096,
  "bytes_read": 120,
  "is_text": true,
  "content": "first chunk of the file",
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

## `GET /download/<path>`

### Purpose

Download an artifact as a raw file stream (non-JSON response).

### Response

- `Content-Type`: Detected based on file extension (image/*, application/pdf, or application/octet-stream).
- `Content-Disposition`: `attachment; filename="<basename>"`
- `Content-Length`: File size in bytes.
- Body: Raw file bytes.

## `POST /upload`

### Purpose

Upload a file to the session artifact directory.

### Request

```json
{
  "filename": "data.csv",
  "content": "id,name\n1,Alice",
  "encoding": "utf-8"
}
```

For binary content, use base64:

```json
{
  "filename": "image.png",
  "content": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
  "encoding": "base64"
}
```

### Response

```json
{
  "ok": true,
  "path": "data.csv",
  "size": 17,
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

## `POST /checkpoint`

### Purpose

Persist backend state to the checkpoint path recorded in the manifest.

### Response

```json
{
  "ok": true,
  "checkpoint_path": "./sessions/r-20260416-abc123/checkpoint.RData",
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

### Notes

- Backends may auto-checkpoint on a configurable interval (default 300 seconds).

## `POST /restore`

### Purpose

Load the backend checkpoint into a fresh or empty runtime environment.

### Response

```json
{
  "ok": true,
  "restored": true,
  "checkpoint_path": "./sessions/r-20260416-abc123/checkpoint.RData",
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```

## `POST /shutdown`

### Purpose

Stop the runtime gracefully while preserving the session directory.

### Response

```json
{
  "ok": true,
  "shutting_down": true,
  "session": {
    "id": "r-20260416-abc123",
    "port": 8741
  }
}
```
