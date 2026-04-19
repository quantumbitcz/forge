# Phase 14 — Time-Travel Checkpoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship backward rewind to any prior checkpoint mid-run via `/forge-recover rewind --to=<id>`, atomically restoring the (state, worktree, events, memory) four-tuple from a content-addressable checkpoint store.

**Architecture:** Content-addressable storage under `.forge/runs/<run_id>/checkpoints/by-hash/<sha256>/` (per-run to avoid sprint-mode collisions) with a DAG index, atomic restore through a staging directory (`.forge/runs/<run_id>/.rewind-tx/`), and git-native worktree snapshotting (store commit SHA, not contents). A new Python module `hooks/_py/checkpoint_cas.py` is the single implementation surface; the orchestrator dispatches to it via `recovery_op: rewind | list-checkpoints`. Breaking state-schema bump 1.7.0 → 1.8.0 invalidates the old linear `.forge/checkpoint-*.json` layout (no back-compat).

**Tech Stack:** Python 3.10+ stdlib (hashlib, json, tarfile, gzip; zstandard optional), bash 4+, git, bats-core for tests.

---

## File Structure

**New files:**
- `hooks/_py/checkpoint_cas.py` — implementation module (CAS write/read, DAG, atomic rewind, GC, tx repair).
- `hooks/_py/__init__.py` — package marker (empty; directory does not yet exist).
- `hooks/_py/rewound_event.py` — `RewoundEvent` dataclass + canonical JSON serialization (isolated so golden-file tests import one place).
- `shared/recovery/time-travel.md` — full protocol spec + GC policy + tx semantics.
- `tests/unit/py/checkpoint_cas/__init__.py` — package marker.
- `tests/unit/py/checkpoint_cas/test_cas_write_read.py` — round-trip CAS unit tests.
- `tests/unit/py/checkpoint_cas/test_rewound_event.py` — RewoundEvent schema + golden-file test.
- `tests/unit/py/checkpoint_cas/test_gc_policy.py` — GC edge cases (active run protection, orphans, HEAD-path).
- `tests/unit/py/checkpoint_cas/test_rewind_tx_repair.py` — crash-recovery subroutine.
- `tests/unit/py/checkpoint_cas/fixtures/rewound-event.golden.json` — golden JSON.
- `tests/evals/time-travel/round-trip.bats`
- `tests/evals/time-travel/rewind-convergence.bats`
- `tests/evals/time-travel/dedup-storage.bats`
- `tests/evals/time-travel/dirty-worktree-abort.bats`
- `tests/evals/time-travel/crash-mid-rewind.bats`
- `tests/evals/time-travel/tree-dag.bats`
- `tests/evals/time-travel/fixtures/tree-dag.golden.txt` — golden `list-checkpoints` output.
- `tests/evals/time-travel/helpers/scenario.bash` — shared scenario bootstrap.

**Modified files:**
- `skills/forge-recover/SKILL.md` — add `rewind`, `list-checkpoints` subcommands, flags, examples, exit codes.
- `agents/fg-100-orchestrator.md` §Recovery op dispatch — wire the two new recovery_op values.
- `shared/state-schema.md` — bump 1.7.0 → 1.8.0, replace §Checkpoints, add `checkpoints[]` + `head_checkpoint` fields.
- `shared/state-transitions.md` — add `REWINDING` pseudo-state transitions.
- `CHANGELOG.md` (or top-level `CHANGELOG`) — breaking-change note.
- `.claude/forge-config.md` (template under `modules/` if present) and/or docs — document the new `recovery.time_travel` config block.

**Responsibility split:**
- `checkpoint_cas.py` is the ONLY code that touches `by-hash/`, `index.json`, `tree.json`, `HEAD`, and `.rewind-tx/`. Other components call it via subprocess `python3 hooks/_py/checkpoint_cas.py <op> …`.
- `rewound_event.py` owns the event schema exclusively; `checkpoint_cas.py` imports from it.
- Shared md docs describe contracts, not code.

---

## Task 1: Python package scaffolding + RewoundEvent schema

**Files:**
- Create: `hooks/_py/__init__.py`
- Create: `hooks/_py/rewound_event.py`
- Create: `tests/unit/py/__init__.py`
- Create: `tests/unit/py/checkpoint_cas/__init__.py`
- Create: `tests/unit/py/checkpoint_cas/test_rewound_event.py`
- Create: `tests/unit/py/checkpoint_cas/fixtures/rewound-event.golden.json`

Resolves review Issue #1.

- [ ] **Step 1: Create empty package markers**

```bash
mkdir -p hooks/_py tests/unit/py/checkpoint_cas/fixtures
: > hooks/_py/__init__.py
: > tests/unit/py/__init__.py
: > tests/unit/py/checkpoint_cas/__init__.py
```

- [ ] **Step 2: Write the golden fixture**

Write `tests/unit/py/checkpoint_cas/fixtures/rewound-event.golden.json`:

```json
{
  "type": "REWOUND",
  "schema_version": 1,
  "timestamp": "2026-04-19T12:00:00Z",
  "run_id": "run-abc123",
  "from_sha": "a1b2c3d4e5f60718293a4b5c6d7e8f901122334455667788aabbccddeeff0011",
  "to_sha": "deadbeefcafe0102030405060708090a0b0c0d0e0f1011121314151617181920",
  "to_human_id": "PLAN.-.003",
  "triggered_by": "user",
  "forced": false,
  "dirty_paths": []
}
```

- [ ] **Step 3: Write the failing test**

Write `tests/unit/py/checkpoint_cas/test_rewound_event.py`:

```python
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))

from hooks._py.rewound_event import RewoundEvent

FIXTURE = pathlib.Path(__file__).parent / "fixtures" / "rewound-event.golden.json"


def test_rewound_event_matches_golden():
    ev = RewoundEvent(
        timestamp="2026-04-19T12:00:00Z",
        run_id="run-abc123",
        from_sha="a1b2c3d4e5f60718293a4b5c6d7e8f901122334455667788aabbccddeeff0011",
        to_sha="deadbeefcafe0102030405060708090a0b0c0d0e0f1011121314151617181920",
        to_human_id="PLAN.-.003",
        triggered_by="user",
        forced=False,
        dirty_paths=[],
    )
    encoded = json.loads(ev.to_canonical_json())
    expected = json.loads(FIXTURE.read_text())
    assert encoded == expected


def test_rewound_event_forced_with_dirty_paths():
    ev = RewoundEvent(
        timestamp="2026-04-19T12:00:00Z",
        run_id="run-abc123",
        from_sha="a" * 64,
        to_sha="b" * 64,
        to_human_id="IMPLEMENT.T1.004",
        triggered_by="auto",
        forced=True,
        dirty_paths=["src/a.py", "src/b.py"],
    )
    d = json.loads(ev.to_canonical_json())
    assert d["forced"] is True
    assert d["dirty_paths"] == ["src/a.py", "src/b.py"]
    assert d["triggered_by"] == "auto"


def test_canonical_json_is_sorted_and_compact():
    ev = RewoundEvent(
        timestamp="2026-04-19T12:00:00Z",
        run_id="r",
        from_sha="a" * 64,
        to_sha="b" * 64,
        to_human_id="X.-.001",
        triggered_by="user",
        forced=False,
        dirty_paths=[],
    )
    out = ev.to_canonical_json()
    assert " " not in out
    assert out.index('"dirty_paths"') < out.index('"forced"') < out.index('"from_sha"')
```

- [ ] **Step 4: Run test to verify it fails**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_rewound_event.py -v`
Expected: FAIL with `ModuleNotFoundError: hooks._py.rewound_event`.

- [ ] **Step 5: Implement the module**

Write `hooks/_py/rewound_event.py`:

```python
"""RewoundEvent schema for Phase 14 time-travel checkpoints.

Appended to .forge/runs/<run_id>/events.jsonl after every successful rewind.
Schema is versioned (schema_version) so future migrations are explicit.
"""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import List, Literal

SCHEMA_VERSION = 1
EVENT_TYPE = "REWOUND"


@dataclass(frozen=True)
class RewoundEvent:
    timestamp: str                      # ISO 8601 UTC, e.g. 2026-04-19T12:00:00Z
    run_id: str                         # matches .forge/runs/<run_id>/
    from_sha: str                       # 64-hex previous HEAD checkpoint sha
    to_sha: str                         # 64-hex target checkpoint sha
    to_human_id: str                    # e.g. "PLAN.-.003"
    triggered_by: Literal["user", "auto"]
    forced: bool                        # True iff --force overrode require_clean_worktree
    dirty_paths: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["type"] = EVENT_TYPE
        d["schema_version"] = SCHEMA_VERSION
        return d

    def to_canonical_json(self) -> str:
        """Sorted-keys, no-whitespace JSON — stable across platforms for hashing / golden-file comparison."""
        return json.dumps(self.to_dict(), sort_keys=True, separators=(",", ":"))
```

- [ ] **Step 6: Run test to verify it passes**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_rewound_event.py -v`
Expected: 3 passed.

- [ ] **Step 7: Commit**

```bash
git add hooks/_py/__init__.py hooks/_py/rewound_event.py \
        tests/unit/py/__init__.py tests/unit/py/checkpoint_cas/__init__.py \
        tests/unit/py/checkpoint_cas/test_rewound_event.py \
        tests/unit/py/checkpoint_cas/fixtures/rewound-event.golden.json
git commit -m "feat(phase14): add RewoundEvent schema + golden-file test"
```

---

## Task 2: CAS write + read round-trip (minimum viable module)

**Files:**
- Create: `hooks/_py/checkpoint_cas.py`
- Create: `tests/unit/py/checkpoint_cas/test_cas_write_read.py`

- [ ] **Step 1: Write the failing test**

Write `tests/unit/py/checkpoint_cas/test_cas_write_read.py`:

```python
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))

from hooks._py.checkpoint_cas import CheckpointStore


def _init_git(dir_: pathlib.Path) -> str:
    subprocess.run(["git", "init", "-q", str(dir_)], check=True)
    subprocess.run(["git", "-C", str(dir_), "config", "user.email", "a@b"], check=True)
    subprocess.run(["git", "-C", str(dir_), "config", "user.name", "a"], check=True)
    (dir_ / "f.txt").write_text("v1\n")
    subprocess.run(["git", "-C", str(dir_), "add", "."], check=True)
    subprocess.run(["git", "-C", str(dir_), "commit", "-q", "-m", "init"], check=True)
    sha = subprocess.check_output(["git", "-C", str(dir_), "rev-parse", "HEAD"]).decode().strip()
    return sha


def test_write_then_read_round_trip(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "run1"
    forge.mkdir(parents=True)
    worktree = tmp_path / "wt"
    worktree.mkdir()
    sha = _init_git(worktree)

    store = CheckpointStore(run_dir=forge, worktree_dir=worktree)
    cp_hash = store.write_checkpoint(
        human_id="PLAN.-.003",
        stage="PLANNING",
        task="-",
        state={"story_state": "PLANNING", "score": 0},
        events_slice=[{"type": "STAGE_TRANSITION", "id": 1}],
        memory_files={"stage_notes/plan.md": b"hello"},
    )
    assert len(cp_hash) == 64
    bundle = store.read_checkpoint(cp_hash)
    assert bundle["state"]["story_state"] == "PLANNING"
    assert bundle["worktree_sha"] == sha
    assert bundle["events_slice"][0]["type"] == "STAGE_TRANSITION"
    assert bundle["memory_files"]["stage_notes/plan.md"] == b"hello"
    assert (forge / "checkpoints" / "HEAD").read_text().strip() == cp_hash
    assert json.loads((forge / "checkpoints" / "index.json").read_text())["PLAN.-.003"] == cp_hash


def test_identical_checkpoints_dedup(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "run1"
    forge.mkdir(parents=True)
    worktree = tmp_path / "wt"
    worktree.mkdir()
    _init_git(worktree)
    store = CheckpointStore(run_dir=forge, worktree_dir=worktree)
    h1 = store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    h2 = store.write_checkpoint("A.-.002", "PLANNING", "-", {"x": 1}, [], {})
    assert h1 == h2
    by_hash = forge / "checkpoints" / "by-hash"
    dirs = [p for p in by_hash.rglob("manifest.json")]
    assert len(dirs) == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_cas_write_read.py -v`
Expected: FAIL with `ModuleNotFoundError: hooks._py.checkpoint_cas`.

- [ ] **Step 3: Implement the module**

Write `hooks/_py/checkpoint_cas.py`:

```python
"""Content-addressable checkpoint store for Phase 14 time-travel.

Layout under <run_dir>/checkpoints/:
    by-hash/<aa>/<sha256-tail>/manifest.json  -- {state_hash, worktree_sha, events_hash, memory_hash, parent_ids}
    by-hash/<aa>/<sha256-tail>/state.json
    by-hash/<aa>/<sha256-tail>/events.slice.jsonl
    by-hash/<aa>/<sha256-tail>/memory.tar.(zst|gz)
    index.json       -- {"<human-id>": "<sha>", ...}
    tree.json        -- {"<sha>": {parents, children, created_at, stage, task, human_id}}
    HEAD             -- active checkpoint sha

CAS-INPUT-v1 = sha256(
    canonical_state_json_bytes + b"\\0" +
    worktree_sha.encode() + b"\\0" +
    sorted_events_bytes + b"\\0" +
    memory_tar_bytes
)
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import pathlib
import subprocess
import tarfile
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Mapping, Optional

try:
    import zstandard as _zstd  # type: ignore
except ImportError:
    _zstd = None
import gzip

CAS_INPUT_VERSION = 1


def _canonical(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _sorted_events(events: Iterable[Mapping[str, Any]]) -> bytes:
    rendered = [json.dumps(e, sort_keys=True, separators=(",", ":")) for e in events]
    rendered.sort()
    return ("\n".join(rendered)).encode("utf-8")


def _pack_memory(files: Mapping[str, bytes], compression: str) -> bytes:
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w") as tar:
        for path, data in sorted(files.items()):
            info = tarfile.TarInfo(name=path)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    payload = raw.getvalue()
    if compression == "zstd" and _zstd is not None:
        return _zstd.ZstdCompressor(level=3).compress(payload)
    if compression == "none":
        return payload
    return gzip.compress(payload)


def _unpack_memory(blob: bytes, compression: str) -> Dict[str, bytes]:
    if compression == "zstd" and _zstd is not None:
        payload = _zstd.ZstdDecompressor().decompress(blob)
    elif compression == "none":
        payload = blob
    else:
        payload = gzip.decompress(blob)
    out: Dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r") as tar:
        for info in tar.getmembers():
            f = tar.extractfile(info)
            if f is not None:
                out[info.name] = f.read()
    return out


def _git_head(worktree: pathlib.Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(worktree), "rev-parse", "HEAD"]
    ).decode().strip()


@dataclass
class CheckpointStore:
    run_dir: pathlib.Path
    worktree_dir: pathlib.Path
    compression: str = "gzip"

    def __post_init__(self) -> None:
        self.ck_dir = self.run_dir / "checkpoints"
        self.ck_dir.mkdir(parents=True, exist_ok=True)
        (self.ck_dir / "by-hash").mkdir(exist_ok=True)
        if not (self.ck_dir / "index.json").exists():
            (self.ck_dir / "index.json").write_text("{}")
        if not (self.ck_dir / "tree.json").exists():
            (self.ck_dir / "tree.json").write_text("{}")

    # -------- write --------
    def write_checkpoint(
        self,
        human_id: str,
        stage: str,
        task: str,
        state: Mapping[str, Any],
        events_slice: Iterable[Mapping[str, Any]],
        memory_files: Mapping[str, bytes],
        parents: Optional[List[str]] = None,
    ) -> str:
        worktree_sha = _git_head(self.worktree_dir)
        state_bytes = _canonical(state)
        events_bytes = _sorted_events(events_slice)
        memory_blob = _pack_memory(memory_files, self.compression)
        h = hashlib.sha256()
        h.update(state_bytes); h.update(b"\0")
        h.update(worktree_sha.encode()); h.update(b"\0")
        h.update(events_bytes); h.update(b"\0")
        h.update(memory_blob)
        sha = h.hexdigest()

        bundle_dir = self.ck_dir / "by-hash" / sha[:2] / sha[2:]
        bundle_dir.mkdir(parents=True, exist_ok=True)
        if not (bundle_dir / "manifest.json").exists():
            (bundle_dir / "state.json").write_bytes(state_bytes)
            (bundle_dir / "events.slice.jsonl").write_bytes(events_bytes)
            ext = "zst" if (self.compression == "zstd" and _zstd) else ("raw" if self.compression == "none" else "gz")
            (bundle_dir / f"memory.tar.{ext}").write_bytes(memory_blob)
            manifest = {
                "cas_input_version": CAS_INPUT_VERSION,
                "state_hash": hashlib.sha256(state_bytes).hexdigest(),
                "worktree_sha": worktree_sha,
                "events_hash": hashlib.sha256(events_bytes).hexdigest(),
                "memory_hash": hashlib.sha256(memory_blob).hexdigest(),
                "compression": self.compression,
                "parent_ids": parents or [],
            }
            (bundle_dir / "manifest.json").write_text(
                json.dumps(manifest, sort_keys=True, indent=2)
            )

        # index + tree + HEAD (write-and-rename for atomicity)
        self._update_index(human_id, sha)
        self._update_tree(sha, human_id, stage, task, parents or self._current_head_as_parent_list())
        self._write_head(sha)
        return sha

    # -------- read --------
    def read_checkpoint(self, sha: str) -> Dict[str, Any]:
        bundle_dir = self.ck_dir / "by-hash" / sha[:2] / sha[2:]
        manifest = json.loads((bundle_dir / "manifest.json").read_text())
        state = json.loads((bundle_dir / "state.json").read_bytes())
        events_text = (bundle_dir / "events.slice.jsonl").read_text().strip()
        events = [json.loads(line) for line in events_text.split("\n") if line]
        mem_file = next(bundle_dir.glob("memory.tar.*"))
        memory_files = _unpack_memory(mem_file.read_bytes(), manifest["compression"])
        return {
            "manifest": manifest,
            "state": state,
            "worktree_sha": manifest["worktree_sha"],
            "events_slice": events,
            "memory_files": memory_files,
        }

    # -------- helpers --------
    def _atomic_write(self, path: pathlib.Path, data: str) -> None:
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(data)
        os.replace(tmp, path)

    def _update_index(self, human_id: str, sha: str) -> None:
        idx_path = self.ck_dir / "index.json"
        idx = json.loads(idx_path.read_text())
        idx[human_id] = sha
        self._atomic_write(idx_path, json.dumps(idx, sort_keys=True, indent=2))

    def _update_tree(self, sha: str, human_id: str, stage: str, task: str, parents: List[str]) -> None:
        tree_path = self.ck_dir / "tree.json"
        tree = json.loads(tree_path.read_text())
        from datetime import datetime, timezone
        now = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        tree.setdefault(sha, {"parents": parents, "children": [], "created_at": now,
                              "stage": stage, "task": task, "human_id": human_id})
        for p in parents:
            node = tree.setdefault(p, {"parents": [], "children": [], "created_at": now,
                                       "stage": "?", "task": "?", "human_id": "?"})
            if sha not in node["children"]:
                node["children"].append(sha)
        self._atomic_write(tree_path, json.dumps(tree, sort_keys=True, indent=2))

    def _current_head_as_parent_list(self) -> List[str]:
        head = self.ck_dir / "HEAD"
        if head.exists() and head.read_text().strip():
            return [head.read_text().strip()]
        return []

    def _write_head(self, sha: str) -> None:
        self._atomic_write(self.ck_dir / "HEAD", sha + "\n")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_cas_write_read.py -v`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/checkpoint_cas.py tests/unit/py/checkpoint_cas/test_cas_write_read.py
git commit -m "feat(phase14): add CAS checkpoint write/read with dedup"
```

---

## Task 3: Atomic restore via per-run `.rewind-tx/` + crash repair

**Files:**
- Modify: `hooks/_py/checkpoint_cas.py`
- Create: `tests/unit/py/checkpoint_cas/test_rewind_tx_repair.py`

Resolves review Issue #3 (per-run tx dir).

- [ ] **Step 1: Write the failing test**

Write `tests/unit/py/checkpoint_cas/test_rewind_tx_repair.py`:

```python
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))

from hooks._py.checkpoint_cas import CheckpointStore, RewindAbort


def _init_git(d: pathlib.Path, content: str = "v1\n") -> str:
    subprocess.run(["git", "init", "-q", str(d)], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.email", "a@b"], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.name", "a"], check=True)
    (d / "f.txt").write_text(content)
    subprocess.run(["git", "-C", str(d), "add", "."], check=True)
    subprocess.run(["git", "-C", str(d), "commit", "-q", "-m", "c"], check=True)
    return subprocess.check_output(["git", "-C", str(d), "rev-parse", "HEAD"]).decode().strip()


def _setup(tmp_path):
    run = tmp_path / ".forge" / "runs" / "runX"
    run.mkdir(parents=True)
    wt = tmp_path / "wt"; wt.mkdir()
    sha0 = _init_git(wt, "v1\n")
    store = CheckpointStore(run_dir=run, worktree_dir=wt)
    h1 = store.write_checkpoint("PLAN.-.001", "PLANNING", "-",
                                {"s": 1}, [{"type": "X", "id": 1}],
                                {"stage_notes/plan.md": b"plan1"})
    (wt / "f.txt").write_text("v2\n")
    subprocess.run(["git", "-C", str(wt), "add", "."], check=True)
    subprocess.run(["git", "-C", str(wt), "commit", "-q", "-m", "c2"], check=True)
    h2 = store.write_checkpoint("IMPLEMENT.T1.002", "IMPLEMENTING", "T1",
                                {"s": 2}, [{"type": "X", "id": 2}],
                                {"stage_notes/impl.md": b"impl"})
    return store, run, wt, h1, h2


def test_rewind_restores_state_worktree_events_memory(tmp_path):
    store, run, wt, h1, h2 = _setup(tmp_path)
    # Pretend live state.json and events.jsonl sit here
    (run / "state.json").write_text(json.dumps({"s": 2, "head_checkpoint": h2}))
    (run / "events.jsonl").write_text(json.dumps({"type": "X", "id": 2}) + "\n")

    store.rewind(to_sha=h1, run_id="runX", triggered_by="user")

    assert (run / "checkpoints" / "HEAD").read_text().strip() == h1
    assert json.loads((run / "state.json").read_text())["s"] == 1
    events = [json.loads(l) for l in (run / "events.jsonl").read_text().splitlines()]
    assert events[-1]["type"] == "REWOUND"
    assert events[-1]["to_sha"] == h1
    assert (wt / "f.txt").read_text() == "v1\n"


def test_rewind_aborts_on_dirty_worktree(tmp_path):
    store, run, wt, h1, _ = _setup(tmp_path)
    (wt / "f.txt").write_text("dirty\n")
    try:
        store.rewind(to_sha=h1, run_id="runX", triggered_by="user")
    except RewindAbort as e:
        assert e.exit_code == 5
        assert "dirty" in str(e).lower()
    else:
        raise AssertionError("expected RewindAbort")
    # zero side effects: HEAD, state.json unchanged
    assert (wt / "f.txt").read_text() == "dirty\n"


def test_rewind_aborts_on_unknown_id(tmp_path):
    store, run, wt, h1, _ = _setup(tmp_path)
    try:
        store.rewind(to_sha="f" * 64, run_id="runX", triggered_by="user")
    except RewindAbort as e:
        assert e.exit_code == 6
    else:
        raise AssertionError("expected RewindAbort")


def test_tx_dir_is_per_run(tmp_path):
    store, run, _, _, _ = _setup(tmp_path)
    tx = store._tx_dir()
    assert tx.parent == run
    assert tx.name == ".rewind-tx"


def test_repair_rewind_tx_rolls_back_partial(tmp_path):
    store, run, wt, h1, h2 = _setup(tmp_path)
    (run / "state.json").write_text(json.dumps({"s": 2}))
    (run / "events.jsonl").write_text(json.dumps({"type": "X", "id": 2}) + "\n")
    # simulate crash between stage 2 (stage) and stage 3 (commit): tx dir populated, live files untouched
    tx = store._tx_dir()
    tx.mkdir()
    (tx / "state.json").write_text(json.dumps({"s": 1}))
    (tx / "events.jsonl.new").write_text("{}\n")
    (tx / "target.sha").write_text(h1 + "\n")
    (tx / "stage").write_text("staged\n")  # not "committing"

    store.repair_rewind_tx(run_id="runX")
    assert not tx.exists()
    # live files unchanged
    assert json.loads((run / "state.json").read_text())["s"] == 2


def test_repair_rewind_tx_replays_when_committing(tmp_path):
    store, run, wt, h1, _ = _setup(tmp_path)
    (run / "state.json").write_text(json.dumps({"s": 2}))
    (run / "events.jsonl").write_text("")
    tx = store._tx_dir()
    tx.mkdir()
    (tx / "state.json").write_text(json.dumps({"s": 1}))
    (tx / "events.jsonl.new").write_text("")
    (tx / "target.sha").write_text(h1 + "\n")
    (tx / "stage").write_text("committing\n")

    store.repair_rewind_tx(run_id="runX")
    assert not tx.exists()
    assert json.loads((run / "state.json").read_text())["s"] == 1
    assert (run / "checkpoints" / "HEAD").read_text().strip() == h1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_rewind_tx_repair.py -v`
Expected: FAIL with `ImportError: cannot import name 'RewindAbort'` and missing `rewind` / `repair_rewind_tx` methods.

- [ ] **Step 3: Extend `checkpoint_cas.py` with rewind + repair**

Append to `hooks/_py/checkpoint_cas.py`:

```python
class RewindAbort(Exception):
    def __init__(self, msg: str, exit_code: int):
        super().__init__(msg)
        self.exit_code = exit_code


# Extend CheckpointStore (method additions, same class):

def _tx_dir(self) -> pathlib.Path:
    """Per-run transaction dir; sprint-safe (each run owns its own)."""
    return self.run_dir / ".rewind-tx"


def _worktree_dirty(self) -> List[str]:
    out = subprocess.check_output(
        ["git", "-C", str(self.worktree_dir), "status", "--porcelain"]
    ).decode()
    return [line[3:] for line in out.splitlines() if line.strip()]


def rewind(self, to_sha: str, run_id: str, triggered_by: str = "user",
           force: bool = False) -> None:
    """Atomic 5-step restore. Raises RewindAbort on failure with exit codes:
        5 = dirty worktree (require_clean_worktree), 6 = unknown id, 7 = tx collision.
    """
    from .rewound_event import RewoundEvent
    from datetime import datetime, timezone

    # Step 1: pre-flight
    bundle_dir = self.ck_dir / "by-hash" / to_sha[:2] / to_sha[2:]
    if not (bundle_dir / "manifest.json").exists():
        raise RewindAbort(f"unknown checkpoint sha {to_sha}", exit_code=6)
    dirty = self._worktree_dirty()
    if dirty and not force:
        raise RewindAbort(f"worktree dirty ({len(dirty)} paths): {dirty[:5]}", exit_code=5)

    tx = self._tx_dir()
    if tx.exists():
        raise RewindAbort(f"rewind tx in progress: {tx}", exit_code=7)

    head_before = ""
    head_path = self.ck_dir / "HEAD"
    if head_path.exists():
        head_before = head_path.read_text().strip()

    bundle = self.read_checkpoint(to_sha)

    # Step 2: stage
    tx.mkdir()
    try:
        (tx / "state.json").write_bytes(_canonical(bundle["state"]))
        (tx / "events.jsonl.new").write_text(
            "\n".join(json.dumps(e, sort_keys=True, separators=(",", ":"))
                     for e in bundle["events_slice"]) + ("\n" if bundle["events_slice"] else "")
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
        import shutil
        shutil.rmtree(tx, ignore_errors=True)
        raise

    # Step 3-5: commit
    self._commit_tx(tx, run_id=run_id)


def _commit_tx(self, tx: pathlib.Path, run_id: str) -> None:
    from .rewound_event import RewoundEvent
    from datetime import datetime, timezone
    import shutil

    target = (tx / "target.sha").read_text().strip()
    worktree_sha = (tx / "worktree.sha").read_text().strip()
    head_before = (tx / "head_before.sha").read_text().strip()
    forced = (tx / "forced").read_text().strip() == "1"
    dirty = json.loads((tx / "dirty_paths.json").read_text())
    triggered_by = (tx / "triggered_by").read_text().strip() or "user"
    human_id = "?"
    tree = json.loads((self.ck_dir / "tree.json").read_text())
    if target in tree:
        human_id = tree[target].get("human_id", "?")

    # Step 3: commit state.json + events.jsonl + git reset + memory unpack
    os.replace(tx / "state.json", self.run_dir / "state.json")

    # Replace events.jsonl with slice, then append RewoundEvent
    os.replace(tx / "events.jsonl.new", self.run_dir / "events.jsonl")
    subprocess.run(
        ["git", "-C", str(self.worktree_dir), "reset", "--hard", worktree_sha],
        check=True, capture_output=True,
    )
    # Unpack memory (overwrite)
    mem_root = tx / "memory"
    if mem_root.exists():
        for src in mem_root.rglob("*"):
            if src.is_file():
                rel = src.relative_to(mem_root)
                dst = self.run_dir / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)

    # Step 4: update HEAD + append RewoundEvent
    self._write_head(target)
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
    with (self.run_dir / "events.jsonl").open("a") as fh:
        fh.write(ev.to_canonical_json() + "\n")

    # Step 5: cleanup tx
    shutil.rmtree(tx, ignore_errors=True)


def repair_rewind_tx(self, run_id: str) -> None:
    """Called at orchestrator start if .rewind-tx/ exists from a crashed rewind.

    If stage file says "committing" we roll forward; otherwise we discard and restore nothing.
    """
    import shutil
    tx = self._tx_dir()
    if not tx.exists():
        return
    stage_file = tx / "stage"
    if stage_file.exists() and stage_file.read_text().strip() == "committing":
        self._commit_tx(tx, run_id=run_id)
    else:
        shutil.rmtree(tx, ignore_errors=True)
```

Attach the method definitions to the class (move them into `class CheckpointStore:` as methods — in practice, write them directly inside the class body above the final line). Ensure `from __future__ import annotations` is present (already at top).

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_rewind_tx_repair.py -v`
Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/checkpoint_cas.py tests/unit/py/checkpoint_cas/test_rewind_tx_repair.py
git commit -m "feat(phase14): atomic rewind with per-run tx dir + crash repair"
```

---

## Task 4: GC policy (active-run protection, orphans, HEAD-path)

**Files:**
- Modify: `hooks/_py/checkpoint_cas.py`
- Create: `tests/unit/py/checkpoint_cas/test_gc_policy.py`

Resolves review Issue #2.

- [ ] **Step 1: Write the failing test**

Write `tests/unit/py/checkpoint_cas/test_gc_policy.py`:

```python
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))

from hooks._py.checkpoint_cas import CheckpointStore, GCPolicy


def _init_git(d):
    subprocess.run(["git", "init", "-q", str(d)], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.email", "a@b"], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.name", "a"], check=True)
    (d / "f.txt").write_text("x")
    subprocess.run(["git", "-C", str(d), "add", "."], check=True)
    subprocess.run(["git", "-C", str(d), "commit", "-q", "-m", "c"], check=True)


def _mk_store(tmp, run_id="r1"):
    run = tmp / ".forge" / "runs" / run_id
    run.mkdir(parents=True)
    wt = tmp / f"wt-{run_id}"; wt.mkdir()
    _init_git(wt)
    return CheckpointStore(run_dir=run, worktree_dir=wt), run


def test_gc_refuses_to_delete_checkpoint_on_path_to_active_head(tmp_path):
    store, run = _mk_store(tmp_path)
    h1 = store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    h2 = store.write_checkpoint("A.-.002", "PLANNING", "-", {"x": 2}, [], {})  # HEAD = h2
    # mark run as RUNNING
    (run / "state.json").write_text(json.dumps({"status": "RUNNING", "head_checkpoint": h2}))
    removed = store.gc(GCPolicy(retention_days=0, max_per_run=100,
                                runs_root=tmp_path / ".forge" / "runs"))
    # h1 is on path to HEAD -> protected; h2 is HEAD -> protected
    assert removed == []


def test_gc_reclaims_orphan_subtree_when_ttl_expired(tmp_path):
    store, run = _mk_store(tmp_path)
    h1 = store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    h2 = store.write_checkpoint("A.-.002", "PLANNING", "-", {"x": 2}, [], {})
    # simulate rewind: HEAD back to h1
    (store.ck_dir / "HEAD").write_text(h1 + "\n")
    # run marked COMPLETE and TTL expired
    (run / "state.json").write_text(json.dumps({"status": "COMPLETE", "head_checkpoint": h1}))
    # Force created_at to ancient
    tree = json.loads((store.ck_dir / "tree.json").read_text())
    tree[h2]["created_at"] = "2000-01-01T00:00:00Z"
    (store.ck_dir / "tree.json").write_text(json.dumps(tree))
    removed = store.gc(GCPolicy(retention_days=7, max_per_run=100,
                                runs_root=tmp_path / ".forge" / "runs"))
    assert h2 in removed
    assert h1 not in removed


def test_gc_skips_active_runs_entirely(tmp_path):
    store_a, run_a = _mk_store(tmp_path, "runA")
    ha = store_a.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    (run_a / "state.json").write_text(json.dumps({"status": "RUNNING", "head_checkpoint": ha}))

    store_b, run_b = _mk_store(tmp_path, "runB")
    hb1 = store_b.write_checkpoint("B.-.001", "PLANNING", "-", {"y": 1}, [], {})
    hb2 = store_b.write_checkpoint("B.-.002", "PLANNING", "-", {"y": 2}, [], {})
    (store_b.ck_dir / "HEAD").write_text(hb1 + "\n")
    (run_b / "state.json").write_text(json.dumps({"status": "COMPLETE", "head_checkpoint": hb1}))
    tree = json.loads((store_b.ck_dir / "tree.json").read_text())
    tree[hb2]["created_at"] = "2000-01-01T00:00:00Z"
    (store_b.ck_dir / "tree.json").write_text(json.dumps(tree))

    removed = store_b.gc(GCPolicy(retention_days=7, max_per_run=100,
                                  runs_root=tmp_path / ".forge" / "runs"))
    assert hb2 in removed  # only runB's orphan
    assert ha not in removed  # runA untouched


def test_gc_enforces_max_per_run_cap(tmp_path):
    store, run = _mk_store(tmp_path)
    hashes = []
    for i in range(5):
        hashes.append(store.write_checkpoint(f"A.-.{i:03d}", "PLANNING", "-",
                                             {"x": i}, [], {}))
    (run / "state.json").write_text(json.dumps({"status": "COMPLETE",
                                                "head_checkpoint": hashes[-1]}))
    removed = store.gc(GCPolicy(retention_days=365, max_per_run=3,
                                runs_root=tmp_path / ".forge" / "runs"))
    # oldest 2 collected; HEAD path preserved
    assert len(removed) == 2
    assert hashes[-1] not in removed
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_gc_policy.py -v`
Expected: FAIL with `ImportError: cannot import name 'GCPolicy'`.

- [ ] **Step 3: Implement GC**

Append to `hooks/_py/checkpoint_cas.py`:

```python
from dataclasses import dataclass as _dc


@_dc
class GCPolicy:
    retention_days: int = 7
    max_per_run: int = 100
    runs_root: Optional[pathlib.Path] = None  # .forge/runs


# Add to CheckpointStore:

def _path_to_head(self) -> set:
    """Set of all checkpoints on path from ROOT to current HEAD (inclusive)."""
    tree = json.loads((self.ck_dir / "tree.json").read_text())
    head_path = self.ck_dir / "HEAD"
    if not head_path.exists():
        return set()
    cur = head_path.read_text().strip()
    out = set()
    while cur and cur not in out:
        out.add(cur)
        parents = tree.get(cur, {}).get("parents", [])
        cur = parents[0] if parents else ""
    return out


def _run_is_active(self, run_dir: pathlib.Path) -> bool:
    state_path = run_dir / "state.json"
    if not state_path.exists():
        return False
    try:
        st = json.loads(state_path.read_text())
    except Exception:
        return False
    return st.get("status") in ("RUNNING", "PAUSED", "ESCALATED")


def gc(self, policy: GCPolicy) -> List[str]:
    """Reclaim checkpoints per policy. Never deletes:
      - HEAD of this run
      - any checkpoint on path ROOT..HEAD (protects active-head lineage)
      - any checkpoint if this run is RUNNING/PAUSED
      - any checkpoint belonging to another active run (cross-run safety)
    Returns list of removed shas.
    """
    import shutil
    from datetime import datetime, timedelta, timezone

    # cross-run safety: skip GC entirely if this run is active
    if self._run_is_active(self.run_dir):
        return []

    # cross-run safety: if any other run is active AND shares this CAS root,
    # we only touch checkpoints created by this run's tree. (Per-run layout
    # already enforces this — tree.json is per-run — but re-check defensively.)
    if policy.runs_root and policy.runs_root.exists():
        for sibling in policy.runs_root.iterdir():
            if sibling == self.run_dir:
                continue
            if self._run_is_active(sibling):
                # Our tree is isolated; nothing to do for sibling. Noted for audit.
                pass

    protected = self._path_to_head()
    tree = json.loads((self.ck_dir / "tree.json").read_text())
    now = datetime.now(tz=timezone.utc)
    ttl = timedelta(days=policy.retention_days)
    removed: List[str] = []

    # TTL-based orphan reclaim
    for sha, meta in list(tree.items()):
        if sha in protected:
            continue
        created_s = meta.get("created_at", "1970-01-01T00:00:00Z")
        try:
            created = datetime.strptime(created_s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except ValueError:
            created = now
        if now - created >= ttl:
            removed.append(sha)

    # Enforce max_per_run: collect oldest non-protected non-removed until under cap
    non_protected = [(sha, meta) for sha, meta in tree.items() if sha not in protected]
    if len(tree) - len(removed) > policy.max_per_run:
        non_protected.sort(key=lambda p: p[1].get("created_at", ""))
        over = len(tree) - len(removed) - policy.max_per_run
        for sha, _ in non_protected:
            if over <= 0:
                break
            if sha not in removed:
                removed.append(sha)
                over -= 1

    # Apply: delete bundles + tree edges; rewrite tree.json + index.json
    for sha in removed:
        bdir = self.ck_dir / "by-hash" / sha[:2] / sha[2:]
        shutil.rmtree(bdir, ignore_errors=True)
        tree.pop(sha, None)
    for meta in tree.values():
        meta["children"] = [c for c in meta.get("children", []) if c not in removed]
    self._atomic_write(self.ck_dir / "tree.json",
                       json.dumps(tree, sort_keys=True, indent=2))
    idx_path = self.ck_dir / "index.json"
    idx = json.loads(idx_path.read_text())
    idx = {h: s for h, s in idx.items() if s not in removed}
    self._atomic_write(idx_path, json.dumps(idx, sort_keys=True, indent=2))
    return removed
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_gc_policy.py -v`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/checkpoint_cas.py tests/unit/py/checkpoint_cas/test_gc_policy.py
git commit -m "feat(phase14): GC with HEAD-path protection + active-run + orphan reclaim"
```

---

## Task 5: CLI entry point for orchestrator dispatch

**Files:**
- Modify: `hooks/_py/checkpoint_cas.py`

The orchestrator invokes `python3 hooks/_py/checkpoint_cas.py <op> <args...>`. Exit codes are the contract.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/py/checkpoint_cas/test_cas_write_read.py`:

```python
def test_cli_list_checkpoints_json(tmp_path, monkeypatch):
    forge = tmp_path / ".forge" / "runs" / "r1"; forge.mkdir(parents=True)
    wt = tmp_path / "wt"; wt.mkdir()
    _init_git(wt)
    store = CheckpointStore(run_dir=forge, worktree_dir=wt)
    store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    import subprocess, sys as _sys
    result = subprocess.run(
        [_sys.executable, "-m", "hooks._py.checkpoint_cas",
         "list-checkpoints", "--run-dir", str(forge), "--worktree", str(wt), "--json"],
        check=True, capture_output=True, text=True, cwd=str(ROOT),
    )
    payload = json.loads(result.stdout)
    assert payload["HEAD"]
    assert len(payload["nodes"]) == 1


def test_cli_rewind_unknown_id_returns_exit_6(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "r1"; forge.mkdir(parents=True)
    wt = tmp_path / "wt"; wt.mkdir()
    _init_git(wt)
    store = CheckpointStore(run_dir=forge, worktree_dir=wt)
    store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    import subprocess, sys as _sys
    result = subprocess.run(
        [_sys.executable, "-m", "hooks._py.checkpoint_cas", "rewind",
         "--run-dir", str(forge), "--worktree", str(wt),
         "--to", "f" * 64, "--run-id", "r1"],
        capture_output=True, text=True, cwd=str(ROOT),
    )
    assert result.returncode == 6
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/test_cas_write_read.py::test_cli_list_checkpoints_json -v`
Expected: FAIL (`__main__` missing).

- [ ] **Step 3: Add `__main__` block**

Append to `hooks/_py/checkpoint_cas.py`:

```python
def _cmd_list(args) -> int:
    store = CheckpointStore(run_dir=pathlib.Path(args.run_dir),
                            worktree_dir=pathlib.Path(args.worktree))
    tree = json.loads((store.ck_dir / "tree.json").read_text())
    head_path = store.ck_dir / "HEAD"
    head = head_path.read_text().strip() if head_path.exists() else ""
    payload = {"HEAD": head, "nodes": tree}
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        _print_dag(tree, head)
    return 0


def _print_dag(tree: dict, head: str) -> None:
    # roots = nodes with empty parents
    roots = [sha for sha, m in tree.items() if not m.get("parents")]

    def render(sha: str, depth: int) -> None:
        m = tree.get(sha, {})
        marker = " <-- HEAD" if sha == head else ""
        print(f"{'  ' * depth}+-- {m.get('human_id','?')} [{sha[:8]}]{marker}")
        for ch in m.get("children", []):
            render(ch, depth + 1)

    for r in roots:
        render(r, 0)


def _cmd_rewind(args) -> int:
    store = CheckpointStore(run_dir=pathlib.Path(args.run_dir),
                            worktree_dir=pathlib.Path(args.worktree))
    try:
        store.rewind(to_sha=args.to, run_id=args.run_id,
                     triggered_by=args.triggered_by, force=args.force)
    except RewindAbort as e:
        print(f"rewind aborted: {e}", file=sys.stderr)
        return e.exit_code
    print(f"rewound to {args.to}")
    return 0


def _cmd_repair(args) -> int:
    store = CheckpointStore(run_dir=pathlib.Path(args.run_dir),
                            worktree_dir=pathlib.Path(args.worktree))
    store.repair_rewind_tx(run_id=args.run_id)
    return 0


def _cmd_gc(args) -> int:
    store = CheckpointStore(run_dir=pathlib.Path(args.run_dir),
                            worktree_dir=pathlib.Path(args.worktree))
    policy = GCPolicy(retention_days=args.retention_days,
                      max_per_run=args.max_per_run,
                      runs_root=pathlib.Path(args.runs_root) if args.runs_root else None)
    removed = store.gc(policy)
    print(json.dumps({"removed": removed}))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    import argparse
    import sys as _sys
    p = argparse.ArgumentParser(prog="checkpoint_cas")
    p.add_argument("op", choices=["list-checkpoints", "rewind", "repair", "gc"])
    p.add_argument("--run-dir", required=True)
    p.add_argument("--worktree", required=True)
    p.add_argument("--to")
    p.add_argument("--run-id")
    p.add_argument("--triggered-by", default="user")
    p.add_argument("--force", action="store_true")
    p.add_argument("--json", action="store_true")
    p.add_argument("--retention-days", type=int, default=7)
    p.add_argument("--max-per-run", type=int, default=100)
    p.add_argument("--runs-root")
    args = p.parse_args(argv)
    if args.op == "list-checkpoints":
        return _cmd_list(args)
    if args.op == "rewind":
        if not args.to or not args.run_id:
            print("rewind requires --to and --run-id", file=_sys.stderr)
            return 2
        return _cmd_rewind(args)
    if args.op == "repair":
        if not args.run_id:
            print("repair requires --run-id", file=_sys.stderr)
            return 2
        return _cmd_repair(args)
    if args.op == "gc":
        return _cmd_gc(args)
    return 2


if __name__ == "__main__":
    import sys as _sys
    _sys.exit(main(_sys.argv[1:]))
```

Ensure `import sys` is present at the top of the file (add if missing).

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/ -v`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/checkpoint_cas.py tests/unit/py/checkpoint_cas/test_cas_write_read.py
git commit -m "feat(phase14): CLI entry point for orchestrator dispatch"
```

---

## Task 6: Skill surface — `forge-recover rewind` + `list-checkpoints`

**Files:**
- Modify: `skills/forge-recover/SKILL.md`

- [ ] **Step 1: Read the current SKILL.md**

Run: `cat skills/forge-recover/SKILL.md`
Locate the subcommand table, flags section, exit-codes references, examples, and migration table.

- [ ] **Step 2: Edit the description string**

Find the top-level `description:` YAML value (currently ends with `...rollback worktree commits.`).

Replace with:

```yaml
description: "[writes] Diagnose or fix pipeline state — read-only diagnose (default), repair counters/locks, reset clearing state while preserving caches, resume from checkpoint, rollback worktree commits, rewind to any prior checkpoint (time-travel), or list the checkpoint DAG. Use when pipeline stuck, failed with state errors, or you need to explore alternate execution paths. Trigger: /forge-recover, diagnose state, repair pipeline, reset state, resume from checkpoint, rollback commits, rewind checkpoint, time travel, list checkpoints"
```

- [ ] **Step 3: Extend the subcommand table**

Find the table that starts `| Subcommand | …` and add two rows at the bottom (preserving the existing `rollback` row above):

```markdown
| `rewind --to=<id> [--force]` | writes | Time-travel to any checkpoint. Atomic four-tuple restore (state, worktree, events, memory). Aborts on dirty worktree unless `--force`. |
| `list-checkpoints [--json]` | read-only | Render the checkpoint DAG with current HEAD marked. |
```

- [ ] **Step 4: Extend the Flags section**

In the Flags section, add:

```markdown
- **--to <id>**: (rewind only) target checkpoint human id (e.g. `PLAN.-.003`) or sha256. Required.
- **--force**: (rewind only) proceed even if worktree is dirty. Destructive — loses uncommitted changes.
```

- [ ] **Step 5: Add exit codes block**

Below the Flags section, add (or extend the existing exit-codes note):

```markdown
## Exit Codes

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | generic failure |
| 2 | usage error (missing --to, etc.) |
| 5 | rewind aborted: dirty worktree (use `--force` to override) |
| 6 | rewind aborted: unknown checkpoint id |
| 7 | rewind aborted: another rewind transaction in progress |
```

- [ ] **Step 6: Extend the Examples section**

Append to the example block:

```bash
/forge-recover list-checkpoints             # show DAG with HEAD marked
/forge-recover list-checkpoints --json      # machine-readable
/forge-recover rewind --to=PLAN.-.003       # time-travel restore
/forge-recover rewind --to=a3f9c1 --force   # override dirty worktree guard
```

- [ ] **Step 7: Extend the dispatch note**

Find the sentence "Dispatches `fg-100-orchestrator` with `recovery_op: diagnose|repair|reset|resume|rollback`" and change it to:

```markdown
Dispatches `fg-100-orchestrator` with `recovery_op: diagnose|repair|reset|resume|rollback|rewind|list-checkpoints` on its input payload. See `agents/fg-100-orchestrator.md` §Recovery op dispatch and `shared/state-schema.md` for the payload schema. Rewind and list-checkpoints are backed by `hooks/_py/checkpoint_cas.py` (see `shared/recovery/time-travel.md`).
```

- [ ] **Step 8: Commit**

```bash
git add skills/forge-recover/SKILL.md
git commit -m "feat(phase14): /forge-recover rewind + list-checkpoints subcommands"
```

---

## Task 7: Orchestrator routing for `rewind` + `list-checkpoints`

**Files:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Open §Recovery op dispatch**

Open `agents/fg-100-orchestrator.md` around the "§ Recovery op dispatch" heading (near line 1329).

- [ ] **Step 2: Edit the routing prose line**

Find: `recovery_op: diagnose|repair|reset|resume|rollback`

Replace with: `recovery_op: diagnose|repair|reset|resume|rollback|rewind|list-checkpoints`

- [ ] **Step 3: Extend the routing table**

Find the `| recovery_op | Dispatch action |` table and add two rows under `rollback`:

```markdown
| `rewind` | Resolve `--to=<id>` via `hooks/_py/checkpoint_cas.py resolve` (human-id → sha), then invoke `python3 hooks/_py/checkpoint_cas.py rewind --run-dir <run_dir> --worktree <worktree> --to <sha> --run-id <run_id> [--force]`. On success: set `state.status = REWINDING` briefly, then restore to the checkpoint's `story_state` (pseudo-state; never persists). Emit `StateTransitionEvent` + consume `RewoundEvent` already appended by the Python tool. On abort codes 5/6/7: surface to user via `AskUserQuestion` with remediation options. |
| `list-checkpoints` | Read-only: invoke `python3 hooks/_py/checkpoint_cas.py list-checkpoints --run-dir <run_dir> --worktree <worktree> [--json]`. Stream stdout to user. No TaskCreate; no state write. |
```

- [ ] **Step 4: Add the crash-repair contract note**

At the bottom of §Recovery op dispatch, add:

```markdown
**Crash recovery:** On every orchestrator start for an active run, invoke `python3 hooks/_py/checkpoint_cas.py repair --run-dir <run_dir> --worktree <worktree> --run-id <run_id>`. This is a no-op when `.forge/runs/<run_id>/.rewind-tx/` does not exist and a safe replay-or-rollback when it does (see `shared/recovery/time-travel.md` §Crash Recovery).
```

- [ ] **Step 5: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat(phase14): orchestrator routes rewind + list-checkpoints"
```

---

## Task 8: State schema bump 1.7.0 → 1.8.0

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Bump the version header**

Find the top-of-file version marker (e.g. `**Version:** 1.7.0` or similar) and change to `**Version:** 1.8.0`.

Find any in-body `v1.7.0` references and update to `v1.8.0`.

- [ ] **Step 2: Replace the §Checkpoints section**

Locate the §Checkpoints section (the one currently describing `.forge/checkpoint-{storyId}.json`) and replace it in full with:

```markdown
## § Checkpoints

**Breaking change in v1.8.0:** the old `.forge/checkpoint-{storyId}.json` linear file layout is **removed**. Checkpoints now live under `.forge/runs/<run_id>/checkpoints/` in a content-addressable DAG:

```
.forge/runs/<run_id>/checkpoints/
├── by-hash/<aa>/<sha256-tail>/
│   ├── manifest.json            # {state_hash, worktree_sha, events_hash, memory_hash, parent_ids[], compression}
│   ├── state.json               # canonical JSON snapshot
│   ├── events.slice.jsonl       # events since parent
│   └── memory.tar.<gz|zst>      # stage_notes + PREEMPT + forge-log excerpt
├── index.json                   # {"<human-id>": "<sha256>", ...}
├── tree.json                    # {"<sha>": {parents, children, created_at, stage, task, human_id}}
└── HEAD                         # active checkpoint sha
```

See `shared/recovery/time-travel.md` for the full protocol, atomic restore semantics, and GC policy.

### state.json additions

```json
{
  "checkpoints": [
    {
      "id": "IMPLEMENT.T1.004",
      "hash": "a3f9c1...",
      "stage": "IMPLEMENTING",
      "task": "T1",
      "created_at": "2026-04-19T10:14:22Z",
      "parents": ["a1b2f0..."]
    }
  ],
  "head_checkpoint": "a3f9c1..."
}
```

- `checkpoints` is append-only within a run. Pre-rewind entries are retained for audit.
- `head_checkpoint` mirrors `.forge/runs/<run_id>/checkpoints/HEAD`.

### Refusal behavior

Orchestrator at startup reads `state.json.version`. If < `1.8.0`, refuses to proceed with error:
`state.json v<detected> detected; v1.8.0 required (Phase 14). Run /forge-recover reset to start fresh.`

No automatic migration — the checkpoint format is incompatible. Legacy `.forge/checkpoint-*.json` files are deleted by `hooks/_py/checkpoint_cas.py` at first Phase-14 write unless `recovery.time_travel.preserve_legacy: true` (moves to `.forge/runs/<run_id>/checkpoints/legacy-trash/`).
```

- [ ] **Step 3: Add `recovery.time_travel` config block reference**

Find the Config section of `state-schema.md` (or an adjacent section referencing `forge-config.md`). Add:

```markdown
### recovery.time_travel (new in 1.8.0)

```yaml
recovery:
  time_travel:
    enabled: true                # master switch
    retention_days: 7            # GC TTL post-SHIP
    max_checkpoints_per_run: 100 # hard cap; oldest non-critical GC'd when exceeded
    require_clean_worktree: true # abort rewind if worktree dirty (safety)
    compression: zstd            # zstd | gzip | none (zstd falls back to gzip if stdlib-only)
    preserve_legacy: false       # archive pre-1.8.0 checkpoints to legacy-trash/ instead of deleting
```
```

- [ ] **Step 4: Commit**

```bash
git add shared/state-schema.md
git commit -m "feat(phase14)!: bump state-schema to 1.8.0 with CAS checkpoints"
```

---

## Task 9: State transitions — `REWINDING` pseudo-state

**Files:**
- Modify: `shared/state-transitions.md`

- [ ] **Step 1: Add REWINDING to the state list**

Find the enumeration of pipeline states (near the top of `state-transitions.md`). Add:

```markdown
- **REWINDING** *(pseudo-state, non-persistent)* — in effect only during the atomic rewind transaction. `state.story_state` is NOT written as `REWINDING`; this name appears only in `events.jsonl` `StateTransitionEvent` pairs that bracket the rewind op.
```

- [ ] **Step 2: Add the transitions**

Find the transitions table. Add rows:

```markdown
| `*` | `REWINDING` | `recovery_op: rewind` dispatched by orchestrator | Entered transiently at the start of rewind. |
| `REWINDING` | `<checkpoint.story_state>` | Atomic restore succeeded | Whichever story_state the target checkpoint captured. |
| `REWINDING` | `<prior story_state>` | Atomic restore failed (exit 5/6/7) | Zero side effects; pipeline returns to state before rewind. |
```

- [ ] **Step 3: Add a §Rewind section**

Near the bottom (or adjacent to §Recovery transitions), add:

```markdown
## § Rewind transitions

Rewind is the only transition type that can originate from ANY pipeline state. It is also the only one with a pseudo-state (`REWINDING`) that never persists to `state.story_state`. The sequence is:

1. Orchestrator receives `recovery_op: rewind` with `--to=<id>`.
2. `StateTransitionEvent { from: <current>, to: "REWINDING" }` logged.
3. `hooks/_py/checkpoint_cas.py rewind` runs (atomic protocol, see `shared/recovery/time-travel.md`).
4a. On success: `StateTransitionEvent { from: "REWINDING", to: <checkpoint.story_state> }` logged; `state.story_state` is set to the target's story_state.
4b. On abort: `StateTransitionEvent { from: "REWINDING", to: <prior story_state> }` logged; `state.story_state` reverts.

Subsequent forward progress is normal. The next `/forge-recover resume` continues from the rewound head.
```

- [ ] **Step 4: Commit**

```bash
git add shared/state-transitions.md
git commit -m "feat(phase14): add REWINDING pseudo-state transitions"
```

---

## Task 10: `shared/recovery/time-travel.md` — full protocol spec

**Files:**
- Create: `shared/recovery/time-travel.md`

- [ ] **Step 1: Write the file**

Write `shared/recovery/time-travel.md`:

```markdown
# Time-Travel Checkpoints (Phase 14)

**Status:** Active (since state-schema 1.8.0, forge 3.1.0)
**Owner:** forge plugin maintainers
**Implementation:** `hooks/_py/checkpoint_cas.py`

## 1. Purpose

Atomic backward rewind to any prior checkpoint in a run, restoring the full four-tuple (state, worktree, events, memory).

## 2. On-disk layout

```
.forge/runs/<run_id>/
├── state.json
├── events.jsonl
├── .rewind-tx/                       # present only during an in-flight rewind
│   ├── stage                         # "staged" | "committing"
│   ├── state.json                    # target state snapshot
│   ├── events.jsonl.new              # events slice since parent
│   ├── target.sha / worktree.sha / head_before.sha / run_id / forced / dirty_paths.json / triggered_by
│   └── memory/                       # unpacked memory files staged for copy
└── checkpoints/
    ├── by-hash/<aa>/<sha256-tail>/
    │   ├── manifest.json
    │   ├── state.json
    │   ├── events.slice.jsonl
    │   └── memory.tar.(gz|zst)
    ├── index.json
    ├── tree.json
    └── HEAD
```

The tx dir is **per-run** — this is the critical sprint-mode safety invariant. Two concurrent sprint orchestrators cannot collide because their tx dirs live under separate `<run_id>` subtrees.

## 3. CAS key (CAS-INPUT-v1)

```
sha256(
    canonical_state_json_bytes  || 0x00 ||
    worktree_sha_hex_40         || 0x00 ||
    sorted_events_jsonl_bytes   || 0x00 ||
    memory_tar_bytes
)
```

- `canonical_state_json_bytes` = `json.dumps(state, sort_keys=True, separators=(",", ":"))` UTF-8 bytes.
- `sorted_events_jsonl_bytes` = each event canonicalized (sort_keys, compact), lines lexicographically sorted, `\n`-joined.
- `memory_tar_bytes` = compressed tar (gzip default, zstd if installed, none if configured).

## 4. Atomic restore protocol

Five steps. Any failure before step 3 is a no-op for the live pipeline.

| Step | Action | Persists if killed? |
|---|---|---|
| 1 | Pre-flight: resolve id→sha (abort 6 if unknown); check `git status --porcelain` (abort 5 if dirty && !force); check `.rewind-tx/` absent (abort 7 if present). | — |
| 2 | Populate `.rewind-tx/`: target state.json, new events.jsonl.new, memory/ tree, metadata files. Last write: `stage = committing`. | Yes, recovered as replay. |
| 3 | `os.replace(tx/state.json, run/state.json)`; `os.replace(tx/events.jsonl.new, run/events.jsonl)`; `git -C worktree reset --hard <worktree_sha>`; copy `tx/memory/*` onto live paths. | Yes, partial — replay finishes. |
| 4 | `os.replace(tx/HEAD.new, checkpoints/HEAD)`; append `RewoundEvent` to `events.jsonl`. | Yes. |
| 5 | `shutil.rmtree(tx)`. | — |

## 5. Crash recovery (`repair_rewind_tx`)

Orchestrator invokes `checkpoint_cas.py repair --run-id <id>` at every start. Algorithm:

- If `.rewind-tx/` missing: no-op.
- Else if `.rewind-tx/stage == "committing"`: roll forward (re-run steps 3–5).
- Else: discard `.rewind-tx/` (no live files were touched yet — steps 1–2 only).

## 6. DAG semantics

`tree.json` is a directed acyclic graph. Each node:

```json
"<sha>": {
  "parents": ["<sha>", ...],          // len=1 today; list for future merge/fork
  "children": ["<sha>", ...],
  "created_at": "2026-04-19T10:14:22Z",
  "stage": "IMPLEMENTING",
  "task": "T1",
  "human_id": "IMPLEMENT.T1.004"
}
```

After a rewind, the next checkpoint write creates a new child of the rewind target — producing a branch. Dead branches (leaves with no `complete: true` attached run) are GC candidates after TTL.

## 7. RewoundEvent

Appended to live `events.jsonl` after every successful rewind. Schema defined in `hooks/_py/rewound_event.py`; canonical form:

```json
{
  "type": "REWOUND",
  "schema_version": 1,
  "timestamp": "2026-04-19T12:00:00Z",
  "run_id": "run-abc123",
  "from_sha": "<64-hex>",
  "to_sha": "<64-hex>",
  "to_human_id": "PLAN.-.003",
  "triggered_by": "user",
  "forced": false,
  "dirty_paths": []
}
```

## 8. GC policy

Invoked post-SHIP and (optionally) by cron. See `hooks/_py/checkpoint_cas.py::gc`.

**Hard protections (never deleted):**
1. `HEAD` of this run.
2. Every checkpoint on the path ROOT..HEAD.
3. Any checkpoint if this run's `state.status ∈ {RUNNING, PAUSED, ESCALATED}` — entire run is skipped.
4. Any checkpoint owned by another active run — enforced by per-run CAS subtree isolation.

**Reclamation criteria:**
- TTL expired (`now - created_at >= retention_days`).
- Over the `max_checkpoints_per_run` cap — oldest non-protected checkpoints reclaimed first.

**Orphan subtrees:** after a rewind, unreferenced children of the rewind target are dead branches. They are reclaimable under TTL. If a run crashes (stale PID, status stuck RUNNING), treat as active for `retention_days`; then reclaim. Manual `/forge-recover reset` clears the run's entire subtree.

**Cross-run safety:** GC reads `.forge/runs/*/state.json` to identify active runs but only ever mutates its own `checkpoints/` subtree. Parallel sprint runs cannot delete each other's checkpoints.

## 9. Configuration

See `shared/state-schema.md §Config.recovery.time_travel`.

## 10. Failure modes

| Mode | Detection | Response |
|---|---|---|
| Dirty worktree | `git status --porcelain` non-empty | Exit 5, no side effects. `--force` overrides. |
| Unknown checkpoint id | id not in `index.json` and not a valid sha in `by-hash/` | Exit 6. |
| Concurrent rewind tx | `.rewind-tx/` exists | Exit 7. Run `repair` to clear or complete. |
| zstandard not installed | ImportError | Transparent fallback to gzip. INFO logged. |
| Corrupt bundle (hash mismatch) | Manifest hash ≠ recomputed | Exit 1; bundle quarantined under `by-hash/.quarantine/`. |

## 11. Testing

Unit: `tests/unit/py/checkpoint_cas/`. Eval: `tests/evals/time-travel/`. CI gates per spec §8 (dedup ratio ≥ 1.25×; storage ≤ 50 MB/run; rewind wall-time < 2 s for 50 checkpoints).
```

- [ ] **Step 2: Commit**

```bash
git add shared/recovery/time-travel.md
git commit -m "docs(phase14): add time-travel protocol spec"
```

---

## Task 11: Eval harness — round-trip, dedup, dirty-abort

**Files:**
- Create: `tests/evals/time-travel/helpers/scenario.bash`
- Create: `tests/evals/time-travel/round-trip.bats`
- Create: `tests/evals/time-travel/dedup-storage.bats`
- Create: `tests/evals/time-travel/dirty-worktree-abort.bats`

- [ ] **Step 1: Write the shared scenario helper**

Write `tests/evals/time-travel/helpers/scenario.bash`:

```bash
# shellcheck shell=bash
# Shared helpers for Phase-14 eval bats.

scenario_setup() {
    TMP_ROOT="$(mktemp -d)"
    export TMP_ROOT
    export RUN_ID="run-$(basename "$TMP_ROOT")"
    export RUN_DIR="$TMP_ROOT/.forge/runs/$RUN_ID"
    export WT="$TMP_ROOT/wt"
    mkdir -p "$RUN_DIR" "$WT"
    git -C "$WT" init -q
    git -C "$WT" config user.email a@b
    git -C "$WT" config user.name a
    echo v1 > "$WT/f.txt"
    git -C "$WT" add . && git -C "$WT" commit -q -m c0
    export CAS_PY="python3 -m hooks._py.checkpoint_cas"
}

scenario_teardown() {
    rm -rf "$TMP_ROOT"
}

cas_write() {
    local human_id="$1" stage="$2" state_json="$3"
    python3 - <<PY
import json, pathlib, sys
sys.path.insert(0, "$PWD")
from hooks._py.checkpoint_cas import CheckpointStore
s = CheckpointStore(run_dir=pathlib.Path("$RUN_DIR"), worktree_dir=pathlib.Path("$WT"))
sha = s.write_checkpoint("$human_id", "$stage", "-", json.loads('$state_json'), [], {})
print(sha)
PY
}
```

- [ ] **Step 2: Write the round-trip bats**

Write `tests/evals/time-travel/round-trip.bats`:

```bash
#!/usr/bin/env bats

load '../../lib/bats-core/bin/bats'
load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "round-trip: write then read preserves state + worktree_sha" {
    sha=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    [ "${#sha}" -eq 64 ]
    run python3 -m hooks._py.checkpoint_cas list-checkpoints \
        --run-dir "$RUN_DIR" --worktree "$WT" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"$sha"* ]]
}
```

- [ ] **Step 3: Write the dedup-storage bats**

Write `tests/evals/time-travel/dedup-storage.bats`:

```bash
#!/usr/bin/env bats

load '../../lib/bats-core/bin/bats'
load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "dedup: 10 writes w/ 3 identical states yield 8 unique bundles" {
    for i in 0 1 2 3 4 5 6 7 8 9; do
        # entries 3, 5, 7 all have state {x:99}; others distinct
        state='{"x":'"$i"'}'
        case "$i" in 3|5|7) state='{"x":99}';; esac
        cas_write "A.-.$(printf %03d "$i")" "PLANNING" "$state" >/dev/null
    done
    count=$(find "$RUN_DIR/checkpoints/by-hash" -name manifest.json | wc -l | tr -d ' ')
    [ "$count" -eq 8 ]
}
```

- [ ] **Step 4: Write the dirty-worktree-abort bats**

Write `tests/evals/time-travel/dirty-worktree-abort.bats`:

```bash
#!/usr/bin/env bats

load '../../lib/bats-core/bin/bats'
load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "dirty worktree aborts rewind with exit 5; zero side effects" {
    sha=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    # dirty the worktree
    echo dirty > "$WT/f.txt"
    run python3 -m hooks._py.checkpoint_cas rewind \
        --run-dir "$RUN_DIR" --worktree "$WT" --to "$sha" --run-id "$RUN_ID"
    [ "$status" -eq 5 ]
    # worktree still dirty with our change (unchanged)
    run cat "$WT/f.txt"
    [ "$output" = "dirty" ]
    # HEAD still points at the latest-written sha (unchanged)
    run cat "$RUN_DIR/checkpoints/HEAD"
    [[ "$output" == "$sha"* ]]
}
```

- [ ] **Step 5: Commit**

```bash
git add tests/evals/time-travel/helpers/scenario.bash \
        tests/evals/time-travel/round-trip.bats \
        tests/evals/time-travel/dedup-storage.bats \
        tests/evals/time-travel/dirty-worktree-abort.bats
git commit -m "test(phase14): eval harness — round-trip, dedup, dirty-abort"
```

---

## Task 12: Eval harness — crash-mid-rewind, tree-dag golden, rewind-convergence

**Files:**
- Create: `tests/evals/time-travel/crash-mid-rewind.bats`
- Create: `tests/evals/time-travel/tree-dag.bats`
- Create: `tests/evals/time-travel/rewind-convergence.bats`
- Create: `tests/evals/time-travel/fixtures/tree-dag.golden.txt`

- [ ] **Step 1: Write crash-mid-rewind**

Write `tests/evals/time-travel/crash-mid-rewind.bats`:

```bash
#!/usr/bin/env bats

load '../../lib/bats-core/bin/bats'
load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "crash after staging (before committing) -> full rollback" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    echo v2 > "$WT/f.txt"
    git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2=$(cas_write "A.-.002" "IMPLEMENTING" '{"x":2}')
    # simulate partial tx: stage only
    tx="$RUN_DIR/.rewind-tx"
    mkdir -p "$tx/memory"
    cp "$RUN_DIR/checkpoints/by-hash/${sha1:0:2}/${sha1:2}/state.json" "$tx/state.json"
    : > "$tx/events.jsonl.new"
    echo "$sha1" > "$tx/target.sha"
    echo "$(git -C "$WT" rev-parse HEAD~1)" > "$tx/worktree.sha"
    echo "$sha2" > "$tx/head_before.sha"
    echo "$RUN_ID" > "$tx/run_id"
    echo 0 > "$tx/forced"
    echo "[]" > "$tx/dirty_paths.json"
    echo user > "$tx/triggered_by"
    echo staged > "$tx/stage"

    run python3 -m hooks._py.checkpoint_cas repair \
        --run-dir "$RUN_DIR" --worktree "$WT" --run-id "$RUN_ID"
    [ "$status" -eq 0 ]
    [ ! -e "$tx" ]
    run cat "$RUN_DIR/checkpoints/HEAD"
    [[ "$output" == "$sha2"* ]]   # unchanged: rollback succeeded
}

@test "crash during commit -> roll forward" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    echo v2 > "$WT/f.txt"
    git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2=$(cas_write "A.-.002" "IMPLEMENTING" '{"x":2}')
    tx="$RUN_DIR/.rewind-tx"
    mkdir -p "$tx/memory"
    cp "$RUN_DIR/checkpoints/by-hash/${sha1:0:2}/${sha1:2}/state.json" "$tx/state.json"
    : > "$tx/events.jsonl.new"
    echo "$sha1" > "$tx/target.sha"
    echo "$(git -C "$WT" rev-parse HEAD~1)" > "$tx/worktree.sha"
    echo "$sha2" > "$tx/head_before.sha"
    echo "$RUN_ID" > "$tx/run_id"
    echo 0 > "$tx/forced"
    echo "[]" > "$tx/dirty_paths.json"
    echo user > "$tx/triggered_by"
    echo committing > "$tx/stage"

    run python3 -m hooks._py.checkpoint_cas repair \
        --run-dir "$RUN_DIR" --worktree "$WT" --run-id "$RUN_ID"
    [ "$status" -eq 0 ]
    [ ! -e "$tx" ]
    run cat "$RUN_DIR/checkpoints/HEAD"
    [[ "$output" == "$sha1"* ]]   # rolled forward to target
}
```

- [ ] **Step 2: Write the tree-dag golden fixture**

Write `tests/evals/time-travel/fixtures/tree-dag.golden.txt`:

```
+-- A.-.001 [<SHA1>]
  +-- A.-.002 [<SHA2>] <-- HEAD
```

(The bats test below substitutes `<SHA1>`/`<SHA2>` with actual prefixes at runtime before comparing.)

- [ ] **Step 3: Write tree-dag bats**

Write `tests/evals/time-travel/tree-dag.bats`:

```bash
#!/usr/bin/env bats

load '../../lib/bats-core/bin/bats'
load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "tree-dag: 2 linear checkpoints render golden output" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    sha2=$(cas_write "A.-.002" "PLANNING" '{"x":2}')
    run python3 -m hooks._py.checkpoint_cas list-checkpoints \
        --run-dir "$RUN_DIR" --worktree "$WT"
    [ "$status" -eq 0 ]
    golden="$(cat "$BATS_TEST_DIRNAME/fixtures/tree-dag.golden.txt")"
    golden="${golden//<SHA1>/${sha1:0:8}}"
    golden="${golden//<SHA2>/${sha2:0:8}}"
    [ "$output" = "$golden" ]
}
```

- [ ] **Step 4: Write rewind-convergence bats**

This is the hardest test. It uses the unit-level API rather than real LLM calls (deterministic), proving "rewind then same-write produces identical HEAD".

Write `tests/evals/time-travel/rewind-convergence.bats`:

```bash
#!/usr/bin/env bats

load '../../lib/bats-core/bin/bats'
load 'helpers/scenario.bash'

setup() { scenario_setup; }
teardown() { scenario_teardown; }

@test "rewind then replay identical writes converges to same HEAD" {
    sha1=$(cas_write "A.-.001" "PLANNING" '{"x":1}')
    echo v2 > "$WT/f.txt"; git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2=$(cas_write "A.-.002" "IMPLEMENTING" '{"x":2}')

    # Fake a live state.json + events.jsonl
    echo '{"x":2,"head_checkpoint":"'"$sha2"'"}' > "$RUN_DIR/state.json"
    : > "$RUN_DIR/events.jsonl"

    run python3 -m hooks._py.checkpoint_cas rewind \
        --run-dir "$RUN_DIR" --worktree "$WT" --to "$sha1" --run-id "$RUN_ID"
    [ "$status" -eq 0 ]
    # Replay the same write as before
    echo v2 > "$WT/f.txt"; git -C "$WT" add . && git -C "$WT" commit -q -m c2
    sha2b=$(cas_write "A.-.002b" "IMPLEMENTING" '{"x":2}')

    # CAS dedup: sha2b must equal sha2 (identical state, worktree, events, memory)
    [ "$sha2b" = "$sha2" ]
}
```

- [ ] **Step 5: Commit**

```bash
git add tests/evals/time-travel/crash-mid-rewind.bats \
        tests/evals/time-travel/tree-dag.bats \
        tests/evals/time-travel/rewind-convergence.bats \
        tests/evals/time-travel/fixtures/tree-dag.golden.txt
git commit -m "test(phase14): crash-repair, tree-dag golden, convergence eval"
```

---

## Task 13: Wire eval harness into CI + plugin validator

**Files:**
- Modify: `tests/run-all.sh`
- Modify: `tests/validate-plugin.sh` (only if structural check for `tests/evals/` subdirs exists)

- [ ] **Step 1: Open `tests/run-all.sh`**

Run: `cat tests/run-all.sh | head -80`
Identify the block that enumerates bats subdirectories under `tests/` (structural / unit / contract / scenario / evals).

- [ ] **Step 2: Add the time-travel eval dir to the enumeration**

If the script loops over `tests/evals/*/*.bats` already: no change needed. Otherwise, add:

```bash
# Phase 14 time-travel evals
if [ -d "$ROOT/tests/evals/time-travel" ]; then
    bats_files+=("$ROOT"/tests/evals/time-travel/*.bats)
fi
```

adjacent to the existing evals-discovery logic. If `run-all.sh` uses a mode dispatch (`structural|unit|contract|scenario`), add a `time-travel` mode OR include it under the existing `evals` / `scenario` mode — match the current idiom.

- [ ] **Step 3: Verify `validate-plugin.sh` doesn't need updates**

Run: `grep -n "tests/evals" tests/validate-plugin.sh` (via Grep tool)
If it already enumerates `tests/evals/*` structurally: no change. If it expects a fixed list, append `time-travel` to that list.

- [ ] **Step 4: Commit**

```bash
git add tests/run-all.sh
# and tests/validate-plugin.sh only if actually modified
git commit -m "test(phase14): register time-travel evals with run-all"
```

---

## Task 14: CHANGELOG + config template propagation

**Files:**
- Modify: top-level `CHANGELOG.md` (create if absent)
- Modify: any `forge-config-template.md` under `modules/frameworks/*/` that already ships a `recovery:` block (grep first; only touch those that already have recovery config, to avoid bloating unrelated templates)

- [ ] **Step 1: Append to `CHANGELOG.md`**

If the file does not exist, create it with a standard header. Append a new entry:

```markdown
## [Unreleased] — Phase 14: Time-Travel Checkpoints

### BREAKING

- `state.json.version` bumped `1.7.0 → 1.8.0`. Runs with older state are refused by the orchestrator. Remediation: `/forge-recover reset`.
- Old `.forge/checkpoint-{storyId}.json` layout removed; replaced by content-addressable store under `.forge/runs/<run_id>/checkpoints/`.

### Added

- `/forge-recover rewind --to=<id> [--force]` — atomic time-travel to any prior checkpoint (restores state + worktree + events + memory).
- `/forge-recover list-checkpoints` — render the checkpoint DAG with HEAD marked.
- `hooks/_py/checkpoint_cas.py` — CAS store, atomic rewind with crash recovery, GC.
- `shared/recovery/time-travel.md` — full protocol spec.
- `recovery.time_travel.*` config block (see `shared/state-schema.md`).
- Eval harness under `tests/evals/time-travel/`.
```

- [ ] **Step 2: Find framework templates that need the new config**

Run (via Grep tool):
- Pattern: `recovery:` in `modules/frameworks/*/forge-config-template.md`

For each matching template, insert the `recovery.time_travel` block under the existing `recovery:` key. Exact block to insert:

```yaml
  time_travel:
    enabled: true
    retention_days: 7
    max_checkpoints_per_run: 100
    require_clean_worktree: true
    compression: zstd
    preserve_legacy: false
```

Only touch templates that already have a `recovery:` section — do not add `recovery:` to templates lacking it (out of scope).

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md modules/frameworks/*/forge-config-template.md
git commit -m "docs(phase14)!: changelog + template propagation for time_travel config"
```

---

## Task 15: Final validation pass

**Files:** (none — validation only)

- [ ] **Step 1: Run unit tests**

Run: `python3 -m pytest tests/unit/py/checkpoint_cas/ -v`
Expected: all tests pass.

- [ ] **Step 2: Run evals**

Run: `./tests/run-all.sh` (or whatever subset runs the new `tests/evals/time-travel/` group).
Expected: all bats scenarios pass.

- [ ] **Step 3: Run the plugin structural validator**

Run: `./tests/validate-plugin.sh`
Expected: all 73+ checks pass.

- [ ] **Step 4: Smoke-test CLI entrypoints**

Run:
```bash
python3 -m hooks._py.checkpoint_cas list-checkpoints --help
python3 -m hooks._py.checkpoint_cas rewind --help
```
Expected: argparse help output, exit 0.

- [ ] **Step 5: Commit any validation-found fixes**

If no code changes were required: skip commit.
Otherwise: `git commit -m "fix(phase14): <specific fix>"`.

---

## Self-Review Results

**Spec coverage check:**

| Spec §  | Covered by tasks |
|---|---|
| §3 Scope (CAS, DAG, human IDs, tx, GC) | 2, 3, 4 |
| §4.1 CAS layout | 2, 10 |
| §4.2 DAG | 2, 12 |
| §4.3 Atomic protocol | 3, 10, 12 |
| §5 Components | 2, 3, 4, 5 (Python); 6 (SKILL); 7 (orchestrator); 8 (state-schema); 9 (transitions); 10 (protocol doc) |
| §6 Config | 8, 14 |
| §7 Compatibility / state version bump | 8, 14 |
| §8 Testing (6 scenarios) | 11 (round-trip, dedup, dirty-abort), 12 (crash-mid, tree-dag, convergence) |
| §9 Rollout single PR | all tasks converge to one branch |
| §10 Risks | §4 GC + §3 per-run tx + clean-worktree gate in Task 3, 4 |
| §11 Success criteria | covered by unit + eval tests (Task 15 validates) |

**Review-Issue resolution:**

| Issue | Resolved by |
|---|---|
| #1 `RewoundEvent` schema | Task 1 (schema + golden file + tests) |
| #2 GC edge cases | Task 4 (unit tests cover active-run skip, orphans, HEAD-path protection, cap) |
| #3 Sprint-parallel tx collision | Task 3 uses per-run `<run_dir>/.rewind-tx/`; `test_tx_dir_is_per_run` locks the invariant |

**Placeholder scan:** none — every code, command, and JSON block is concrete.

**Type/name consistency:** `CheckpointStore` / `RewindAbort` / `GCPolicy` / `RewoundEvent` — used identically across all tasks. CLI subcommand names (`list-checkpoints`, `rewind`, `repair`, `gc`) consistent between SKILL.md, orchestrator.md, and `checkpoint_cas.py`.
