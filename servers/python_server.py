#!/usr/bin/env python3

import io
import json
import pickle
import sys
import threading
import warnings
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


if len(sys.argv) != 2:
    raise SystemExit("usage: python_server.py <manifest-path>")


manifest_path = Path(sys.argv[1]).resolve()
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
runtime = {}
output_limit = 50
shutdown_event = threading.Event()
auto_checkpoint_interval = 300
last_checkpoint_time = 0


def session_payload():
    return {
        "id": manifest["id"],
        "backend": manifest["backend"],
        "port": manifest["port"],
        "started_at": manifest["started_at"],
    }


def trim_stdout(lines):
    total = len(lines)
    if total > output_limit:
        return lines[:output_limit], True, total
    return lines, False, total


def artifact_path(rel_path):
    artifact_root = Path(manifest["artifact_dir"]).resolve()
    candidate = (artifact_root / rel_path).resolve()
    if artifact_root not in (candidate, *candidate.parents):
        raise ValueError("artifact path escapes artifact_dir")
    return candidate


def detect_artifacts(before):
    artifact_root = Path(manifest["artifact_dir"])
    after = {str(p) for p in artifact_root.rglob("*") if p.is_file()}
    new_files = after - before
    artifacts = []
    for f in new_files:
        path = Path(f)
        artifacts.append(
            {
                "path": str(path.relative_to(artifact_root)),
                "size": path.stat().st_size,
                "mtime": str(path.stat().st_mtime),
            }
        )
    return artifacts


def checkpoint_state():
    return {name: value for name, value in runtime.items() if not name.startswith("__")}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def send_json(self, status, payload):
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            import time

            seconds_since_checkpoint = int(time.time() - last_checkpoint_time)
            self.send_json(
                200,
                {
                    "ok": True,
                    "stale": False,
                    "seconds_since_checkpoint": seconds_since_checkpoint,
                    "session": session_payload(),
                },
            )
            return

        if parsed.path == "/objects":
            objects = []
            for name, value in runtime.items():
                if name.startswith("__"):
                    continue
                objects.append(
                    {
                        "name": name,
                        "class": type(value).__name__,
                        "summary": repr(value)[:160],
                    }
                )
            self.send_json(
                200,
                {
                    "ok": True,
                    "objects": objects,
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            return

        if parsed.path == "/artifact":
            params = parse_qs(parsed.query)
            rel_path = params.get("path", [""])[0]
            if not rel_path:
                self.send_json(
                    400,
                    {
                        "ok": False,
                        "error": "missing artifact path",
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return
            offset = int(params.get("offset", ["0"])[0])
            limit = int(params.get("limit", ["4096"])[0])
            try:
                path = artifact_path(rel_path)
            except ValueError as err:
                self.send_json(
                    400,
                    {
                        "ok": False,
                        "error": str(err),
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return
            if not path.exists():
                self.send_json(
                    404,
                    {
                        "ok": False,
                        "error": "artifact not found",
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return

            with path.open("rb") as fh:
                fh.seek(offset)
                chunk = fh.read(limit)

            self.send_json(
                200,
                {
                    "ok": True,
                    "path": rel_path,
                    "offset": offset,
                    "limit": limit,
                    "bytes_read": len(chunk),
                    "is_text": True,
                    "content": chunk.decode("utf-8", errors="replace"),
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            return

        if parsed.path == "/artifacts":
            artifact_root = Path(manifest["artifact_dir"])
            artifacts = []
            for p in artifact_root.rglob("*"):
                if p.is_file():
                    artifacts.append(
                        {
                            "path": str(p.relative_to(artifact_root)),
                            "size": p.stat().st_size,
                            "mtime": str(p.stat().st_mtime),
                        }
                    )
            self.send_json(
                200,
                {
                    "ok": True,
                    "artifacts": artifacts,
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            return

        if parsed.path.startswith("/download/"):
            rel_path = parsed.path[10:]
            try:
                path = artifact_path(rel_path)
            except ValueError as err:
                self.send_json(
                    400,
                    {
                        "ok": False,
                        "error": str(err),
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return
            if not path.exists():
                self.send_json(
                    404,
                    {
                        "ok": False,
                        "error": "artifact not found",
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return

            content_type = "application/octet-stream"
            if path.suffix in (".png", ".jpg", ".jpeg", ".gif", ".webp"):
                content_type = "image/png"
            elif path.suffix == ".pdf":
                content_type = "application/pdf"

            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header(
                "Content-Disposition", f'attachment; filename="{path.name}"'
            )
            self.send_header("Content-Length", str(path.stat().st_size))
            self.end_headers()
            self.wfile.write(path.read_bytes())
            return

        self.send_json(
            404,
            {
                "ok": False,
                "error": f"no route for GET {parsed.path}",
                "session": {"id": manifest["id"], "port": manifest["port"]},
            },
        )

    def do_POST(self):
        parsed = urlparse(self.path)

        if parsed.path == "/eval":
            payload = self.read_json()
            code = payload.get("code", "")
            buffer = io.StringIO()
            caught_warnings = []
            artifact_root = Path(manifest["artifact_dir"])
            before_artifacts = {str(p) for p in artifact_root.rglob("*") if p.is_file()}

            try:
                with warnings.catch_warnings(record=True) as warning_records:
                    warnings.simplefilter("always")
                    with redirect_stdout(buffer):
                        exec(code, runtime, runtime)
                caught_warnings = [str(item.message) for item in warning_records]
                ok = True
                error = None
            except Exception as exc:
                ok = False
                error = str(exc)

            stdout_lines = buffer.getvalue().splitlines()
            stdout_lines, truncated, total_lines = trim_stdout(stdout_lines)
            after_artifacts = {str(p) for p in artifact_root.rglob("*") if p.is_file()}
            artifacts = []
            for f in after_artifacts - before_artifacts:
                path = Path(f)
                artifacts.append(
                    {
                        "path": str(path.relative_to(artifact_root)),
                        "size": path.stat().st_size,
                        "mtime": str(path.stat().st_mtime),
                    }
                )
            self.send_json(
                200,
                {
                    "ok": ok,
                    "stdout": stdout_lines,
                    "warnings": caught_warnings,
                    "messages": [],
                    "artifacts": artifacts,
                    "truncated": truncated,
                    "total_lines": total_lines,
                    "error": error,
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            return

        if parsed.path == "/upload":
            import base64

            payload = self.read_json()
            filename = payload.get("filename", "")
            content = payload.get("content", "")
            encoding = payload.get("encoding", "utf-8")

            if not filename:
                self.send_json(
                    400,
                    {
                        "ok": False,
                        "error": "missing filename",
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return

            try:
                path = artifact_path(filename)
            except ValueError as err:
                self.send_json(
                    400,
                    {
                        "ok": False,
                        "error": str(err),
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return

            if encoding == "base64":
                data = base64.b64decode(content)
            else:
                data = content.encode("utf-8")

            path.write_bytes(data)
            self.send_json(
                200,
                {
                    "ok": True,
                    "path": filename,
                    "size": path.stat().st_size,
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            return

        if parsed.path == "/checkpoint":
            import time

            checkpoint_path = Path(manifest["checkpoint_path"])
            with checkpoint_path.open("wb") as fh:
                pickle.dump(checkpoint_state(), fh)
            globals()["last_checkpoint_time"] = time.time()
            self.send_json(
                200,
                {
                    "ok": True,
                    "checkpoint_path": manifest["checkpoint_path"],
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            return

        if parsed.path == "/restore":
            checkpoint_path = Path(manifest["checkpoint_path"])
            if not checkpoint_path.exists():
                self.send_json(
                    404,
                    {
                        "ok": False,
                        "restored": False,
                        "checkpoint_path": manifest["checkpoint_path"],
                        "error": "checkpoint not found",
                        "session": {"id": manifest["id"], "port": manifest["port"]},
                    },
                )
                return
            with checkpoint_path.open("rb") as fh:
                runtime.clear()
                runtime["__builtins__"] = __builtins__
                runtime.update(pickle.load(fh))
            self.send_json(
                200,
                {
                    "ok": True,
                    "restored": True,
                    "checkpoint_path": manifest["checkpoint_path"],
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            return

        if parsed.path == "/shutdown":
            self.send_json(
                200,
                {
                    "ok": True,
                    "shutting_down": True,
                    "session": {"id": manifest["id"], "port": manifest["port"]},
                },
            )
            shutdown_event.set()
            return

        self.send_json(
            404,
            {
                "ok": False,
                "error": f"no route for POST {parsed.path}",
                "session": {"id": manifest["id"], "port": manifest["port"]},
            },
        )


server = ThreadingHTTPServer(("127.0.0.1", int(manifest["port"])), Handler)
server.timeout = 0.25

import time

if last_checkpoint_time == 0:
    globals()["last_checkpoint_time"] = time.time()

print(f"python server listening on http://127.0.0.1:{manifest['port']}")

while not shutdown_event.is_set():
    server.handle_request()

    elapsed = time.time() - last_checkpoint_time
    if elapsed >= auto_checkpoint_interval:
        state_to_save = checkpoint_state()
        if state_to_save:
            checkpoint_path = Path(manifest["checkpoint_path"])
            with checkpoint_path.open("wb") as fh:
                pickle.dump(state_to_save, fh)
            globals()["last_checkpoint_time"] = time.time()

server.server_close()
