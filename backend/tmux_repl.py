import time
import re
from typing import Optional

import libtmux


class TmuxREPL:
    def __init__(
        self,
        session_id: str,
        backend: str = "r",
        socket_name: Optional[str] = None,
    ):
        self.session_id = session_id
        self.backend = backend
        self.server = libtmux.Server(socket_name=socket_name)
        self._session: Optional[libtmux.Session] = None
        self._pane: Optional[libtmux.Pane] = None
        self._initial_line_count: int = 0

    @property
    def tmux_session_name(self) -> str:
        return f"lcr-{self.session_id}"

    @property
    def prompt_pattern(self) -> re.Pattern:
        if self.backend == "r":
            return re.compile(r"^>\s*$", re.MULTILINE)
        elif self.backend == "python":
            return re.compile(r"^>>>\s*$", re.MULTILINE)
        else:
            raise ValueError(f"Unknown backend: {self.backend}")

    @property
    def startup_command(self) -> str:
        if self.backend == "r":
            return "R --vanilla --quiet"
        elif self.backend == "python":
            return "python3"
        else:
            raise ValueError(f"Unknown backend: {self.backend}")

    def create(self, window_name: str = "repl") -> None:
        self._session = self.server.new_session(
            session_name=self.tmux_session_name,
            window_name=window_name,
            attach=False,
        )
        window = self._session.active_window
        self._pane = window.active_pane
        self._pane.send_keys(self.startup_command)
        self._wait_for_prompt()
        self._initial_line_count = self._get_line_count()

    def is_alive(self) -> bool:
        if self._session is None:
            return False
        try:
            self._session.cmd("display-message", "ping")
            return True
        except libtmux.exc.LibTmuxException:
            return False

    def _get_line_count(self) -> int:
        if self._pane is None:
            return 0
        capture = self._pane.capture_pane()
        return len(capture)

    def _wait_for_prompt(self, timeout: float = 5.0) -> None:
        start = time.time()
        while time.time() - start < timeout:
            capture = self._pane.capture_pane()
            pane_text = "\n".join(capture)
            if self.prompt_pattern.search(pane_text):
                return
            time.sleep(0.1)
        raise TimeoutError(f"Prompt did not appear within {timeout} seconds")

    def _clear_and_send(self, code: str) -> None:
        if self._pane is None:
            raise RuntimeError("REPL not initialized")
        self._input_line_count = 0
        lines = code.split("\n")
        for i, line in enumerate(lines):
            self._pane.send_keys(line, enter=(i == len(lines) - 1))
            self._input_line_count += 1

    def _capture_output(self, timeout: float = 30.0) -> str:
        if self._pane is None:
            raise RuntimeError("REPL not initialized")

        output_lines = []
        seen_prompt = False
        start = time.time()
        while time.time() - start < timeout:
            capture = self._pane.capture_pane()
            pane_text = "\n".join(capture)

            if self.prompt_pattern.search(pane_text):
                for line in capture:
                    line_stripped = line.strip()
                    if line_stripped.startswith(">"):
                        seen_prompt = True
                        continue
                    if seen_prompt and line_stripped:
                        output_lines.append(line)
                return "\n".join(output_lines)

            time.sleep(0.05)

        raise TimeoutError(f"Output capture timed out after {timeout} seconds")

    def send_code(self, code: str, timeout: float = 30.0) -> str:
        if self._pane is None:
            raise RuntimeError("REPL not initialized")

        self._clear_and_send(code)
        return self._capture_output(timeout)

    def checkpoint(self, path: str) -> None:
        if self.backend == "r":
            cmd = f'save.image("{path}")'
        elif self.backend == "python":
            cmd = f"import dill; dill.dump_session('{path}')"
        else:
            raise ValueError(f"Unknown backend: {self.backend}")

        self.send_code(cmd)

    def restore(self, path: str) -> None:
        if self.backend == "r":
            cmd = f'load("{path}")'
        elif self.backend == "python":
            cmd = f"import dill; dill.load_session('{path}')"
        else:
            raise ValueError(f"Unknown backend: {self.backend}")

        self.send_code(cmd)

    def destroy(self) -> None:
        if self._session is not None:
            try:
                self._session.kill_session()
            except libtmux.exc.LibTmuxException:
                pass
            self._session = None
            self._pane = None

    def __del__(self):
        self.destroy()
