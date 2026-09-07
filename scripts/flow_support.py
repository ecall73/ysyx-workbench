#!/usr/bin/env python3

"""Runtime helpers for the repeatable functional and scoring flows."""

from __future__ import annotations

import os
import pathlib
import re
import selectors
import shlex
import shutil
import signal
import subprocess
import time
from dataclasses import asdict, dataclass


ANSI_RE = re.compile(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
BAD_OUTPUT_RE = re.compile(
    r"(?:HIT BAD TRAP|npc:\s+ABORT\b|assert(?:ion)?(?:\s+failed|ion failed)"
    r"|(?:diff(?:erential)?test|diff\s*test).*(?:mismatch|fail)"
    r"|\*\*\*FAIL\*\*\*|segmentation fault|core dumped|fatal error)",
    re.IGNORECASE,
)


@dataclass
class ProcessResult:
    command: list[str]
    returncode: int | None
    elapsed_seconds: float
    timed_out: bool
    stopped_on_success: bool
    log: str
    output: str
    error_lines: list[str]

    def as_dict(self) -> dict:
        data = asdict(self)
        data.pop("output", None)
        return data


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def find_bad_output(text: str) -> list[str]:
    lines: list[str] = []
    for line in strip_ansi(text).splitlines():
        if BAD_OUTPUT_RE.search(line) and line not in lines:
            lines.append(line)
    return lines


def workbench_env(workbench: pathlib.Path) -> dict[str, str]:
    """Return an environment pointing all AM/NPC dependencies at this checkout."""

    workbench = workbench.expanduser().resolve()
    env = os.environ.copy()
    defaults = {
        "YSYX_HOME": workbench,
        "NEMU_HOME": workbench / "nemu",
        "AM_HOME": workbench / "abstract-machine",
        "NPC_HOME": workbench / "npc",
        "YSYX_SOC_HOME": workbench / "ysyxSoC",
        "NVBOARD_HOME": workbench / "nvboard",
        "RTT_ROOT": workbench / "rt-thread-am",
    }
    for key, value in defaults.items():
        env[key] = str(value)
    return env


def _signal_process_group(process: subprocess.Popen, sig: signal.Signals, pgid: int | None = None) -> None:
    try:
        os.killpg(pgid if pgid is not None else os.getpgid(process.pid), sig)
    except ProcessLookupError:
        pass


def _stop_process_group(process: subprocess.Popen, sig: signal.Signals, wait_seconds: float) -> None:
    # The make leader may exit immediately after forwarding SIGINT while its
    # Verilator child still owns the pipe.  The leader's PID is also the
    # process-group ID because run_logged starts a new session.
    pgid = process.pid
    _signal_process_group(process, sig, pgid)
    try:
        process.wait(timeout=wait_seconds)
        return
    except subprocess.TimeoutExpired:
        pass
    _signal_process_group(process, signal.SIGTERM, pgid)
    try:
        process.wait(timeout=wait_seconds)
        return
    except subprocess.TimeoutExpired:
        pass
    _signal_process_group(process, signal.SIGKILL, pgid)
    process.wait()


def _drain_process(process: subprocess.Popen, timeout: float = 2.0) -> bytes:
    try:
        remaining, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _stop_process_group(process, signal.SIGTERM, timeout)
        remaining, _ = process.communicate()
    return remaining or b""


def run_logged(
    command: list[str],
    *,
    cwd: pathlib.Path,
    env: dict[str, str],
    log_path: pathlib.Path,
    timeout_seconds: float,
    success_patterns: tuple[str, ...] = (),
) -> ProcessResult:
    """Run a command while logging it and optionally stop on output markers.

    The selector waits for output or the timeout; it does not spin while a
    resident simulator is idle.  A process group is used because the make
    target starts a nested make and the Verilator executable.
    """

    log_path = log_path.expanduser().resolve()
    log_path.parent.mkdir(parents=True, exist_ok=True)
    launch_command = list(command)
    stdbuf = shutil.which("stdbuf")
    if stdbuf:
        launch_command = [stdbuf, "-oL", "-eL", *launch_command]

    process = subprocess.Popen(
        launch_command,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    chunks: list[bytes] = []
    started = time.monotonic()
    timed_out = False
    stopped_on_success = False

    def append(data: bytes, fp) -> None:
        if not data:
            return
        chunks.append(data)
        fp.write(data.decode(errors="replace"))
        fp.flush()

    with log_path.open("w", encoding="utf-8") as log_fp:
        while True:
            remaining = timeout_seconds - (time.monotonic() - started)
            if remaining <= 0:
                timed_out = True
                _stop_process_group(process, signal.SIGTERM, 2.0)
                break

            events = selector.select(timeout=min(0.25, remaining))
            if events:
                data = os.read(process.stdout.fileno(), 64 * 1024)
                if not data:
                    selector.unregister(process.stdout)
                    break
                append(data, log_fp)
                if success_patterns:
                    normalized = strip_ansi(b"".join(chunks).decode(errors="replace"))
                    if all(re.search(pattern, normalized, re.MULTILINE | re.DOTALL) for pattern in success_patterns):
                        stopped_on_success = True
                        _stop_process_group(process, signal.SIGINT, 2.0)
                        break
            elif process.poll() is not None:
                break

        # Read data already buffered in the pipe after natural completion or
        # intentional termination.  It is not part of the marker decision.
        append(_drain_process(process), log_fp)

    selector.close()
    if process.poll() is None:
        _stop_process_group(process, signal.SIGTERM, 2.0)
    elapsed = time.monotonic() - started
    output = b"".join(chunks).decode(errors="replace")
    return ProcessResult(
        command=command,
        returncode=process.returncode,
        elapsed_seconds=elapsed,
        timed_out=timed_out,
        stopped_on_success=stopped_on_success,
        log=str(log_path),
        output=output,
        error_lines=find_bad_output(output),
    )


def command_text(command: list[str]) -> str:
    return shlex.join(command)
