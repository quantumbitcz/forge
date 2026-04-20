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

import gzip
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
