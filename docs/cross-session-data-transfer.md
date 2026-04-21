# Cross-Session Data Transfer Proposal

This document proposes a protocol extension for sending data between REPL sessions, enabling visualization in one session (e.g., R) of data produced in another (e.g., Python/PyTorch).

## Motivation

Current sessions operate independently. There is no mechanism to:
1. Serialize data from session A (Python/PyTorch tensors)
2. Transfer to session B (R for visualization)
3. Render or process in session B

## Use Cases

- **Python → R**: Render PyTorch tensor batches using R's ggplot2 or plotly
- **R → Python**: Transfer processed dataframes back for ML pipelines
- **Python → Python**: Pipeline stages across different environments
- **Any → Any**: Arbitrary data exchange via standardized serialization

## Design Principles

1. **Artifacts as transfer medium**: Use existing `/upload` and `/artifact` endpoints
2. **Session-aware upload**: Allow direct upload to a specific target session
3. **Format negotiation**: Support multiple serialization formats
4. **Bounded transfer**: Cap data sizes to prevent abuse
5. **Metadata tracking**: Include provenance for debugging

## Schema Language: Protocol Buffers

We use protobuf as the canonical schema language for cross-session data types, providing:
- Language-neutral type definitions
- Compact binary wire format option
- Schema evolution support
- Code generation for Python and R

### Proto Definition

```protobuf
// liquid-code/transfer.proto

syntax = "proto3";

package liquidcode.transfer;

message Tensor {
  repeated int64 shape = 1;
  string dtype = 2;
  bytes data = 3;  // flatten row-major
  DataLayout layout = 4;

  enum DataLayout {
    ROW_MAJOR = 0;
    COL_MAJOR = 1;
  }
}

message DataFrame {
  message Column {
    string name = 1;
    string dtype = 2;
    oneof payload {
      Tensor tensor = 3;
      bytes raw = 4;
    }
  }

  repeated Column columns = 1;
  repeated int64 indices = 2;  // optional row index
}

message TransferRequest {
  string target_session = 1;
  string object_name = 2;
  string format = 3;        // "protobuf", "numpy", "json", "base64"
  oneof payload {
    Tensor tensor = 4;
    DataFrame dataframe = 5;
    bytes raw = 6;
  }
  map<string, string> metadata = 7;
}

message TransferResponse {
  bool ok = 1;
  string transferred_to = 2;
  string object_name = 3;
  uint64 size_bytes = 4;
  SessionInfo source_session = 5;
}

message SessionInfo {
  string id = 1;
  string backend = 2;
  uint32 port = 3;
}
```

### Format Options

| Format | Description | Wire |
|--------|-------------|------|
| `protobuf` | Binary protobuf (this schema) | `application/x-protobuf` |
| `numpy` | NumPy-compatible flattened + shape | JSON or base64 |
| `json` | JSON representation | `application/json` |
| `base64` | Raw base64 for images/large tensors | text/plain |

### Protobuf Advantages

1. **Schema evolution**: Add fields without breaking old clients
2. **Typed payloads**: Tensor/DataFrame vs generic "blob"
3. **Efficient encoding**: 3-10x smaller than JSON for numeric arrays
4. **Generated code**: Type-safe in each language

## Proposed Protocol Extensions

### 1. `POST /send` - Direct Cross-Session Transfer

Send data directly from one session to another. Supports both JSON and binary protobuf.

#### JSON Request

```json
{
  "target_session": "r-20260416-def456",
  "object_name": "batch_data",
  "format": "protobuf",
  "tensor": {
    "shape": [4, 3, 32, 32],
    "dtype": "float32",
    "data": "base64-encoded-bytes...",
    "layout": "ROW_MAJOR"
  },
  "metadata": {
    "source_session": "python-20260416-abc123",
    "dataset": "CIFAR-10"
  }
}
```

#### Protobuf Request

```
Content-Type: application/x-protobuf

TransferRequest {
  target_session: "r-20260416-def456"
  object_name: "batch_data"
  format: "protobuf"
  tensor {
    shape: [4, 3, 32, 32]
    dtype: "float32"
    data: <binary>
    layout: ROW_MAJOR
  }
}
```

#### Response

```json
{
  "ok": true,
  "transferred_to": "r-20260416-def456",
  "object_name": "batch_data",
  "size_bytes": 16384,
  "session": {
    "id": "python-20260416-abc123",
    "port": 8741
  }
}
```

#### Notes

- `target_session` must be a running session (verified via `/health`)
- `format` is `"protobuf"` for binary, `"json"` for JSON representation
- Content-Type header determines parsing path

### 2. `POST /send-artifact` - Send Artifact to Another Session

Transfer an existing artifact file to another session's artifact directory.

#### Request

```json
{
  "artifact_path": "batch.npy",
  "target_session": "r-20260416-def456",
  "target_name": "input_batch"
}
```

#### Response

```json
{
  "ok": true,
  "transferred_to": "r-20260416-def456",
  "artifact_path": "batch.npy",
  "target_path": "input_batch.npy",
  "size_bytes": 16384,
  "session": {
    "id": "python-20260416-abc123",
    "port": 8741
  }
}
```

### 3. `GET /objects` - Enhanced Object Listing

Include provenance metadata for transferred objects.

#### Response

```json
{
  "ok": true,
  "objects": [
    {
      "name": "batch_data",
      "class": "numpy.ndarray",
      "summary": "shape=(4, 3, 32, 32), dtype=float32",
      "provenance": {
        "source_session": "python-20260416-abc123",
        "received_at": "2026-04-16T10:20:00Z",
        "original_format": "numpy"
      }
    }
  ],
  "session": {
    "id": "r-20260421-def456",
    "port": 8742
  }
}
```

## Serialization Formats

| Format | Description | Content-Type |
|--------|-------------|--------------|
| `protobuf` | Binary protobuf (schema above) | `application/x-protobuf` |
| `numpy` | NumPy-compatible flattened + shape | `application/json` or `base64` |
| `json` | Standard JSON arrays/objects | `application/json` |
| `base64` | Raw base64 for images/large tensors | `text/plain` |
| `pickle` | Python pickle (session-specific) | Python → Python only |

### Format Handlers by Backend

| Backend | Supports | Libraries |
|---------|-----------|-----------|
| Python | `protobuf`, `numpy`, `json`, `base64`, `pickle` | `protobuf`, `numpy` |
| R | `protobuf`, `json`, `base64` | `RProtoBuf`, `jsonlite`, `base64` |

### Protobuf Code Generation

```bash
# Python
protoc --python_out=. liquid-code/transfer.proto

# R
protoc --proto_path=. --_r_out=. liquid-code/transfer.proto
```

Generated code provides type-safe serializers/deserializers for each language.

## Workflow Example

### Python Session (Data Producer)

```python
import torch
import torchvision

# Load CIFAR-10 batch
trainset = torchvision.datasets.CIFAR10(root='./data', train=True, download=True, transform=transform)
trainloader = torch.utils.data.DataLoader(trainset, batch_size=4, shuffle=True)
images, labels = next(iter(trainloader))

# Convert to numpy and save as artifact
import numpy as np
images_np = images.numpy()  # shape: (4, 3, 32, 32)

# Save to artifacts for transfer
np.save('artifacts/batch.npy', images_np)
```

### Cross-Session Transfer

```bash
# From Python session, send to R session
curl -X POST http://127.0.0.1:8741/send-artifact \
  -H "Content-Type: application/json" \
  -d '{
    "artifact_path": "batch.npy",
    "target_session": "r-20260421-def456",
    "target_name": "cifar_batch"
  }'
```

### R Session (Visualization Consumer)

```r
# Receive batch from Python session
batch <- readRDS("artifacts/cifar_batch.rds")

# Or load numpy array via reticulate
library(reticulate)
np <- import("numpy")
batch <- np$load("artifacts/cifar_batch.npy")

# Visualize using ggplot2 or base graphics
# ... visualization code ...
```

## Implementation Path

### Phase 1: Artifact-Based Transfer (MVP)

1. Add `session` field to `/upload` request (optional target session)
2. If `session` specified, copy artifact to target session's artifacts directory
3. Add provenance metadata to target session's object tracking

### Phase 2: Direct Transfer Protocol

1. Add `/send` endpoint with target session validation
2. Implement format handlers for each backend
3. Add provenance tracking to `/objects` response

### Phase 3: Advanced Features

1. Streaming transfers for large datasets
2. Format conversion (numpy → RDS automatically)
3. Transfer history and audit logs

## Security Considerations

1. **Session isolation**: Verify source/target sessions are owned by same operator
2. **Size limits**: Cap transfer sizes (default 100MB)
3. **Format validation**: Reject malicious pickle payloads
4. **Audit trail**: Log all transfers to session logs

## Backward Compatibility

- New fields are optional; existing code works unchanged
- `/send` and `/send-artifact` return 404 if target doesn't exist
- Format negotiation fails gracefully with helpful error messages