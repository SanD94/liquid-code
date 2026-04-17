#!/usr/bin/env python3

import json
import os
import sys
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

try:
    from . import tmux_repl
except ImportError:
    import tmux_repl


class TmuxServer:
    def __init__(self, manifest_path: str):
        self.manifest_path = manifest_path
        with open(manifest_path, "r") as f:
            self.manifest = json.load(f)

        self.session_id = self.manifest["id"]
        self.session_dir = self.manifest["session_dir"]
        self.backend = self.manifest["backend"].replace("-tmux", "")
        self.port = self.manifest["port"]
        self.checkpoint_path = self.manifest["checkpoint_path"]
        self.artifact_dir = self.manifest["artifact_dir"]
        self.output_limit = 50
        self.resumed_from_checkpoint = self.manifest.get("resumed_from_checkpoint", "")

        self.repl = tmux_repl.TmuxREPL(self.session_id, self.backend)
        self.last_checkpoint_time = time.time()
        self.shutdown_event = threading.Event()

    def resolve_checkpoint_path(self, path: str = None) -> str:
        if path:
            return path
        if self.resumed_from_checkpoint:
            sessions_dir = os.path.dirname(self.session_dir)
            checkpoint_basename = os.path.basename(self.resumed_from_checkpoint)
            old_session_id = os.path.basename(
                os.path.dirname(self.resumed_from_checkpoint)
            )
            resolved = os.path.join(sessions_dir, old_session_id, checkpoint_basename)
            if os.path.exists(resolved):
                return resolved
        return self.checkpoint_path

    def start(self):
        self.repl.create()
        print(f"tmux server ready for session {self.session_id}")
        print(f"tmux session: {self.repl.tmux_session_name}")
        print(f"Attach with: tmux attach -t {self.repl.tmux_session_name}")

    def session_info(self):
        return {
            "id": self.session_id,
            "backend": self.manifest["backend"],
            "port": self.port,
            "started_at": self.manifest["started_at"],
        }


server: TmuxServer = None
shutdown_event = threading.Event()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json(self, status: int, data: dict):
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def parse_body(self):
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            return {}
        body = self.rfile.read(content_length)
        return json.loads(body.decode("utf-8"))

    def do_GET(self):
        global server
        if server is None:
            self.send_json(500, {"error": "server not initialized"})
            return

        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/health":
            seconds_since_checkpoint = int(time.time() - server.last_checkpoint_time)
            self.send_json(
                200,
                {
                    "ok": True,
                    "stale": False,
                    "seconds_since_checkpoint": seconds_since_checkpoint,
                    "session": server.session_info(),
                },
            )
            return

        if path == "/objects":
            try:
                if server.backend == "r":
                    code = "paste0(names(.GlobalEnv), collapse=', ')"
                else:
                    code = "print(list(globals().keys()))"
                result = server.repl.send_code(code)
                objects = [{"name": n.strip()} for n in result.split(",") if n.strip()]
                self.send_json(
                    200,
                    {
                        "ok": True,
                        "objects": objects,
                        "session": server.session_info(),
                    },
                )
            except Exception as e:
                self.send_json(
                    500,
                    {
                        "ok": False,
                        "error": str(e),
                        "session": server.session_info(),
                    },
                )
            return

        self.send_json(
            404,
            {
                "ok": False,
                "error": f"no route for GET {path}",
                "session": server.session_info(),
            },
        )

    def do_POST(self):
        global server, shutdown_event
        if server is None:
            self.send_json(500, {"error": "server not initialized"})
            return

        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/eval":
            body = self.parse_body()
            code = body.get("code", "")

            try:
                stdout = server.repl.send_code(code)
                lines = stdout.split("\n") if stdout else []
                lines = [
                    l for l in lines if l.strip() and not l.strip().startswith(">")
                ]
                total = len(lines)
                truncated = total > server.output_limit
                if truncated:
                    lines = lines[: server.output_limit]

                self.send_json(
                    200,
                    {
                        "ok": True,
                        "stdout": lines,
                        "warnings": [],
                        "messages": [],
                        "artifacts": [],
                        "truncated": truncated,
                        "total_lines": total,
                        "error": None,
                        "session": server.session_info(),
                    },
                )
            except Exception as e:
                self.send_json(
                    200,
                    {
                        "ok": False,
                        "stdout": [],
                        "warnings": [],
                        "messages": [],
                        "artifacts": [],
                        "truncated": False,
                        "total_lines": 0,
                        "error": str(e),
                        "session": server.session_info(),
                    },
                )
            return

        if path == "/checkpoint":
            try:
                server.repl.checkpoint(server.checkpoint_path)
                server.last_checkpoint_time = time.time()
                self.send_json(
                    200,
                    {
                        "ok": True,
                        "checkpoint_path": server.checkpoint_path,
                        "session": server.session_info(),
                    },
                )
            except Exception as e:
                self.send_json(
                    500,
                    {
                        "ok": False,
                        "error": str(e),
                        "session": server.session_info(),
                    },
                )
            return

        if path == "/restore":
            try:
                restore_path = server.resolve_checkpoint_path()
                server.repl.restore(restore_path)
                self.send_json(
                    200,
                    {
                        "ok": True,
                        "restored": True,
                        "checkpoint_path": restore_path,
                        "session": server.session_info(),
                    },
                )
            except Exception as e:
                self.send_json(
                    500,
                    {
                        "ok": False,
                        "restored": False,
                        "error": str(e),
                        "session": server.session_info(),
                    },
                )
            return

        if path == "/shutdown":
            self.send_json(
                200,
                {
                    "ok": True,
                    "shutting_down": True,
                    "session": server.session_info(),
                },
            )
            shutdown_event.set()
            return

        self.send_json(
            404,
            {
                "ok": False,
                "error": f"no route for POST {path}",
                "session": server.session_info(),
            },
        )


def run_server(manifest_path: str, host: str = "127.0.0.1"):
    global server, shutdown_event

    server = TmuxServer(manifest_path)
    server.start()
    shutdown_event = threading.Event()

    http_server = ThreadingHTTPServer((host, server.port), Handler)
    http_server.timeout = 0.25

    print(f"HTTP server listening on http://{host}:{server.port}")

    while not shutdown_event.is_set():
        http_server.handle_request()

    server.stop()
    http_server.server_close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: tmux_server.py <manifest-path>")
        sys.exit(1)
    run_server(sys.argv[1])
