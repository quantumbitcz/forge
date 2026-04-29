"""Append-only hook-failure log + rotation.

Schema of each line (see shared/schemas/hook-failures.schema.json):
  schema, ts, hook_name, matcher, exit_code, stderr_excerpt, duration_ms, cwd

Policy:
  * Writes to .forge/.hook-failures.jsonl in the current working directory.
  * If .forge/ cannot be created, silently no-ops (hook = lossy observability).
  * rotate() gzips files older than 7d, unlinks .gz older than 30d. Invoked
    once per session by hooks/session_start.py.
"""
from __future__ import annotations

import gzip
import json
import os
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

SCHEMA_VERSION = 1
FAILURES_FILE = ".hook-failures.jsonl"
ROTATE_AFTER_S = 7 * 24 * 3600
DELETE_AFTER_S = 30 * 24 * 3600
STDERR_LIMIT = 2048


def _forge_dir(cwd: Optional[str] = None) -> Optional[Path]:
    base = Path(cwd) if cwd else Path.cwd()
    target = base / ".forge"
    try:
        target.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        sys.stderr.write(f"[failure_log] cannot create {target}: {exc}\n")
        return None
    return target


def record_failure(
    hook_name: str,
    matcher: str,
    exit_code: int,
    stderr_excerpt: str,
    duration_ms: int,
    cwd: str,
) -> None:
    """Append one JSON row. Never raises."""
    forge = _forge_dir(cwd)
    if forge is None:
        return
    now = datetime.now(timezone.utc)
    ts = now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"
    row = {
        "schema": SCHEMA_VERSION,
        "ts": ts,
        "hook_name": hook_name,
        "matcher": matcher,
        "exit_code": exit_code,
        "stderr_excerpt": (stderr_excerpt or "")[:STDERR_LIMIT],
        "duration_ms": max(0, int(duration_ms)),
        "cwd": cwd,
    }
    line = json.dumps(row, separators=(",", ":")) + "\n"
    target = forge / FAILURES_FILE
    try:
        with target.open("a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError as exc:
        sys.stderr.write(f"[failure_log] append failed: {exc}\n")


def _gzip_and_replace(src: Path, dst: Path) -> bool:
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    try:
        with src.open("rb") as src_fh, gzip.open(tmp, "wb") as dst_fh:
            shutil.copyfileobj(src_fh, dst_fh)
        os.replace(tmp, dst)
        src.unlink(missing_ok=True)
        return True
    except OSError as exc:
        sys.stderr.write(f"[failure_log] rotate failed ({src} -> {dst}): {exc}\n")
        tmp.unlink(missing_ok=True)
        return False


def rotate(now_ts: Optional[float] = None, cwd: Optional[str] = None) -> None:
    """Gzip >7d, delete gz >30d. Safe if files missing."""
    forge = _forge_dir(cwd)
    if forge is None:
        return
    now = now_ts if now_ts is not None else time.time()
    live = forge / FAILURES_FILE
    if live.exists():
        try:
            mtime = live.stat().st_mtime
        except OSError:
            mtime = now
        if (now - mtime) > ROTATE_AFTER_S:
            stamp = datetime.fromtimestamp(mtime, tz=timezone.utc).strftime("%Y%m%d")
            archive = forge / f".hook-failures-{stamp}.jsonl.gz"
            _gzip_and_replace(live, archive)
    for gz in forge.glob(".hook-failures-*.jsonl.gz"):
        try:
            if (now - gz.stat().st_mtime) > DELETE_AFTER_S:
                gz.unlink(missing_ok=True)
        except OSError:
            continue
