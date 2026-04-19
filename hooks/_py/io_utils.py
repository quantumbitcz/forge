"""TOOL_INPUT parsing, atomic JSON update, cross-platform file locks."""
from __future__ import annotations

import contextlib
import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, IO

IS_WINDOWS = sys.platform.startswith("win")

if IS_WINDOWS:
    import msvcrt  # type: ignore[import-not-found]
else:
    import fcntl


@dataclass
class ToolInput:
    file_path: str | None
    tool_name: str | None
    raw: dict[str, Any]


def parse_tool_input(stream: IO[str] | None = None) -> ToolInput:
    """Parse the TOOL_INPUT JSON document Claude Code pipes on stdin.

    Returns a ToolInput even when the stream is empty or malformed — hooks
    must never crash on unexpected input; they short-circuit.
    """
    stream = stream or sys.stdin
    try:
        payload = json.loads(stream.read() or "{}")
    except json.JSONDecodeError:
        payload = {}
    tool_input = payload.get("tool_input", {}) if isinstance(payload, dict) else {}
    return ToolInput(
        file_path=tool_input.get("file_path"),
        tool_name=payload.get("tool_name") if isinstance(payload, dict) else None,
        raw=payload if isinstance(payload, dict) else {},
    )


@contextlib.contextmanager
def _locked(fp):
    if IS_WINDOWS:
        # Lock a single byte — semantics match flock(LOCK_EX) closely enough
        # for JSON-update serialization. fp must be a writable binary handle.
        while True:
            try:
                msvcrt.locking(fp.fileno(), msvcrt.LK_LOCK, 1)
                break
            except OSError:
                continue
        try:
            yield
        finally:
            try:
                fp.seek(0)
                msvcrt.locking(fp.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
    else:
        fcntl.flock(fp.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fp.fileno(), fcntl.LOCK_UN)


def atomic_json_update(
    path: Path,
    mutate: Callable[[dict], dict],
    *,
    default: dict | None = None,
) -> None:
    """Read-modify-write a JSON file under an exclusive lock, atomically."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(path.suffix + ".lock")

    # Serialize concurrent writers on a sibling lock file (works on every FS).
    with open(lock_path, "a+b") as lock_fp:
        with _locked(lock_fp):
            try:
                current = json.loads(path.read_text()) if path.exists() else (
                    default if default is not None else {}
                )
            except json.JSONDecodeError:
                current = default if default is not None else {}
            updated = mutate(current)
            # Atomic rename — works on POSIX always, on Windows requires that
            # the target is not open elsewhere in the same process.
            tmp_fd, tmp_name = tempfile.mkstemp(
                dir=str(path.parent), prefix=path.name + ".", suffix=".tmp"
            )
            try:
                with os.fdopen(tmp_fd, "w") as tmp:
                    json.dump(updated, tmp, indent=2, sort_keys=True)
                os.replace(tmp_name, path)
            except BaseException:
                with contextlib.suppress(FileNotFoundError):
                    os.unlink(tmp_name)
                raise


def normalize_path(p: str | Path) -> str:
    """Return a POSIX-style string for cross-platform state files."""
    return str(Path(p).as_posix())
