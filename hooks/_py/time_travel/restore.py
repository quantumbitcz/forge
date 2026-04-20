"""Atomic rewind protocol for Phase 14 time-travel.

Module-level functions operate on a CheckpointStore instance. Per the
plan-review IMPORTANT issue #1, this module deliberately uses functions
rather than methods on CheckpointStore — the rewind transaction is a
discrete protocol that reads/writes through a CheckpointStore but is
easier to test as standalone callables, and keeps cas.py focused on
storage primitives.

Protocol (5 stages, see shared/recovery/time-travel.md when published):
  1. Pre-flight  — resolve sha; abort if unknown (exit 6) or worktree
                   dirty without --force (exit 5); abort if a tx dir
                   already exists from a prior crashed run (exit 7).
  2. Stage       — write target state, events slice, worktree sha,
                   metadata, and memory tree under <run>/.rewind-tx/.
  3-5. Commit    — atomically swap live files, run git reset --hard,
                   unpack memory, update HEAD, append RewoundEvent,
                   remove tx dir.

Crash repair: if .rewind-tx/ is found at orchestrator startup, the
'stage' marker file selects roll-forward (committing) or rollback
(staged).
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
from datetime import datetime, timezone
from typing import List

from .cas import CheckpointStore, _canonical
from .events import RewoundEvent


class RewindAbort(Exception):
    """Raised by rewind() to signal aborted operation with a CLI-level exit code."""

    def __init__(self, msg: str, exit_code: int):
        super().__init__(msg)
        self.exit_code = exit_code


def tx_dir(store: CheckpointStore) -> pathlib.Path:
    """Per-run transaction dir; sprint-safe (each run owns its own)."""
    return store.run_dir / ".rewind-tx"


def _worktree_dirty(store: CheckpointStore) -> List[str]:
    out = subprocess.check_output(
        ["git", "-C", str(store.worktree_dir), "status", "--porcelain"]
    ).decode()
    return [line[3:] for line in out.splitlines() if line.strip()]


def rewind(
    store: CheckpointStore,
    to_sha: str,
    run_id: str,
    triggered_by: str = "user",
    force: bool = False,
) -> None:
    """Atomic 5-step restore. Raises RewindAbort on failure with exit codes:
        5 = dirty worktree (require_clean_worktree),
        6 = unknown id,
        7 = tx collision (prior crashed rewind not yet repaired).
    """
    # Step 1: pre-flight
    bundle_dir = store.ck_dir / "by-hash" / to_sha[:2] / to_sha[2:]
    if not (bundle_dir / "manifest.json").exists():
        raise RewindAbort(f"unknown checkpoint sha {to_sha}", exit_code=6)
    dirty = _worktree_dirty(store)
    if dirty and not force:
        raise RewindAbort(f"worktree dirty ({len(dirty)} paths): {dirty[:5]}", exit_code=5)
    tx = tx_dir(store)
    if tx.exists():
        raise RewindAbort(f"rewind tx in progress: {tx}", exit_code=7)

    head_before = ""
    head_path = store.ck_dir / "HEAD"
    if head_path.exists():
        head_before = head_path.read_text().strip()

    bundle = store.read_checkpoint(to_sha)

    # Step 2: stage
    tx.mkdir()
    try:
        (tx / "state.json").write_bytes(_canonical(bundle["state"]))
        (tx / "events.jsonl.new").write_text(
            "\n".join(
                json.dumps(e, sort_keys=True, separators=(",", ":"))
                for e in bundle["events_slice"]
            )
            + ("\n" if bundle["events_slice"] else "")
        )
        (tx / "target.sha").write_text(to_sha + "\n")
        (tx / "worktree.sha").write_text(bundle["worktree_sha"] + "\n")
        (tx / "head_before.sha").write_text(head_before + "\n")
        (tx / "run_id").write_text(run_id + "\n")
        (tx / "forced").write_text("1" if force else "0")
        (tx / "dirty_paths.json").write_text(json.dumps(dirty))
        (tx / "triggered_by").write_text(triggered_by)
        # Write memory files into tx/memory/ (deferred unpack)
        (tx / "memory").mkdir()
        for path, data in bundle["memory_files"].items():
            dest = tx / "memory" / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        (tx / "stage").write_text("committing\n")
    except Exception:
        # stage failure: remove tx dir, zero side effects
        shutil.rmtree(tx, ignore_errors=True)
        raise

    # Step 3-5: commit
    _commit_tx(store, tx, run_id=run_id)


def _commit_tx(store: CheckpointStore, tx: pathlib.Path, run_id: str) -> None:
    target = (tx / "target.sha").read_text().strip()
    worktree_sha = (tx / "worktree.sha").read_text().strip()
    head_before = (tx / "head_before.sha").read_text().strip()
    forced = (tx / "forced").read_text().strip() == "1"
    dirty = json.loads((tx / "dirty_paths.json").read_text())
    triggered_by = (tx / "triggered_by").read_text().strip() or "user"
    human_id = "?"
    tree = json.loads((store.ck_dir / "tree.json").read_text())
    if target in tree:
        human_id = tree[target].get("human_id", "?")

    # Step 3: commit state.json + events.jsonl + git reset + memory unpack
    os.replace(tx / "state.json", store.run_dir / "state.json")

    # Replace events.jsonl with slice, then append RewoundEvent
    os.replace(tx / "events.jsonl.new", store.run_dir / "events.jsonl")
    subprocess.run(
        ["git", "-C", str(store.worktree_dir), "reset", "--hard", worktree_sha],
        check=True,
        capture_output=True,
    )
    # Unpack memory (overwrite)
    mem_root = tx / "memory"
    if mem_root.exists():
        for src in mem_root.rglob("*"):
            if src.is_file():
                rel = src.relative_to(mem_root)
                dst = store.run_dir / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)

    # Step 4: update HEAD + append RewoundEvent
    store._write_head(target)
    ev = RewoundEvent(
        timestamp=datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        run_id=run_id,
        from_sha=head_before,
        to_sha=target,
        to_human_id=human_id,
        triggered_by=triggered_by,  # type: ignore[arg-type]
        forced=forced,
        dirty_paths=dirty,
    )
    with (store.run_dir / "events.jsonl").open("a") as fh:
        fh.write(ev.to_canonical_json() + "\n")

    # Step 5: cleanup tx
    shutil.rmtree(tx, ignore_errors=True)


def repair_rewind_tx(store: CheckpointStore, run_id: str) -> None:
    """Called at orchestrator start if .rewind-tx/ exists from a crashed rewind.

    If stage file says "committing" we roll forward; otherwise we discard
    and restore nothing.
    """
    tx = tx_dir(store)
    if not tx.exists():
        return
    stage_file = tx / "stage"
    if stage_file.exists() and stage_file.read_text().strip() == "committing":
        _commit_tx(store, tx, run_id=run_id)
    else:
        shutil.rmtree(tx, ignore_errors=True)
