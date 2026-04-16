# Bridge Kit Contract

All backends should implement the same minimal HTTP surface so agents can change runtimes without relearning lifecycle behavior.

## Common Rules

- Requests and responses use JSON unless otherwise noted.
- Every response includes enough session metadata for operators to match the runtime back to its manifest.
- Stdout should be bounded. Large results should move into artifacts.
- Artifact access must be limited to files inside the session artifact directory.

## `GET /health`

### Purpose

Confirm liveness and advertise session metadata.

### Response

```json
{
  "ok": true,
  "session": {
    "id": "r-20260416-abc123",
    "backend": "r",
    "port": 8741,
    "started_at": "2026-04-16T10:15:00Z"
  }
}
```

## `POST /eval`

### Purpose

Execute code inside the persistent backend environment.

### Request

```json
{
  "code": "x <- 2"
}
```

### Response

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

### Notes

- `stdout` is an array of lines to avoid newline ambiguity.
- `warnings` and `messages` are backend-specific diagnostics normalized into lists.
- `artifacts` contains metadata for any saved files created during the request.
- `truncated` describes the returned stdout slice, not whether execution was incomplete.

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

## `GET /artifact`

### Purpose

Read a saved artifact in slices.

### Query Parameters

- `path`: Relative path inside the session artifact directory.
- `offset`: Byte offset to start reading from. Defaults to `0`.
- `limit`: Maximum bytes to return. Backends may cap this.

### Response

```json
{
  "ok": true,
  "path": "plot.txt",
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
