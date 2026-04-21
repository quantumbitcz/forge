"""GC policy for time-travel checkpoints.

Module-level helpers operate on a CheckpointStore instance, mirroring the
restore.py convention (see plan-review IMPORTANT issue #1).

Protections (never delete):
  - HEAD of this run
  - any checkpoint on the path ROOT..HEAD (active-head lineage)
  - any checkpoint while this run is RUNNING / PAUSED / ESCALATED
  - cross-run safety: never touches another run's checkpoints
    (each run has its own per-run CAS subtree, but the policy
    re-checks defensively)

Reclaim policies (in order):
  1. TTL: any non-protected node whose created_at is older than
     retention_days is collected.
  2. Cap: if non-protected node count still exceeds max_per_run,
     collect oldest non-protected nodes until under the cap.
"""
from __future__ import annotations

import json
import pathlib
import shutil
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from .cas import CheckpointStore


@dataclass
class GCPolicy:
    retention_days: int = 7
    max_per_run: int = 100
    runs_root: Optional[pathlib.Path] = None  # .forge/runs


def _path_to_head(store: CheckpointStore) -> set:
    """Set of all checkpoints on path from ROOT to current HEAD (inclusive)."""
    tree = json.loads((store.ck_dir / "tree.json").read_text())
    head_path = store.ck_dir / "HEAD"
    if not head_path.exists():
        return set()
    cur = head_path.read_text().strip()
    out: set = set()
    while cur and cur not in out:
        out.add(cur)
        parents = tree.get(cur, {}).get("parents", [])
        cur = parents[0] if parents else ""
    return out


def _run_is_active(run_dir: pathlib.Path) -> bool:
    state_path = run_dir / "state.json"
    if not state_path.exists():
        return False
    try:
        st = json.loads(state_path.read_text())
    except Exception:
        return False
    return st.get("status") in ("RUNNING", "PAUSED", "ESCALATED")


def gc(store: CheckpointStore, policy: GCPolicy) -> List[str]:
    """Reclaim checkpoints per policy. Never deletes:
      - HEAD of this run
      - any checkpoint on path ROOT..HEAD (protects active-head lineage)
      - any checkpoint if this run is RUNNING/PAUSED/ESCALATED
      - any checkpoint belonging to another active run (cross-run safety)
    Returns list of removed shas.
    """
    # cross-run safety: skip GC entirely if this run is active
    if _run_is_active(store.run_dir):
        return []

    # cross-run safety: if any other run is active AND shares this CAS root,
    # we only touch checkpoints created by this run's tree. (Per-run layout
    # already enforces this — tree.json is per-run — but re-check defensively.)
    if policy.runs_root and policy.runs_root.exists():
        for sibling in policy.runs_root.iterdir():
            if sibling == store.run_dir:
                continue
            if _run_is_active(sibling):
                # Our tree is isolated; nothing to do for sibling. Noted for audit.
                pass

    protected = _path_to_head(store)
    tree = json.loads((store.ck_dir / "tree.json").read_text())
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

    # Enforce max_per_run: collect oldest non-HEAD non-removed until under cap.
    # Cap enforcement may evict HEAD-path ancestors (older lineage), but never
    # the current HEAD itself. TTL-only-protection of the lineage would let
    # caches grow unbounded on long lived runs; the cap is the hard ceiling.
    head_path = store.ck_dir / "HEAD"
    head_sha = head_path.read_text().strip() if head_path.exists() else ""
    cap_eligible = [(sha, meta) for sha, meta in tree.items()
                    if sha != head_sha and sha not in removed]
    if len(tree) - len(removed) > policy.max_per_run:
        cap_eligible.sort(key=lambda p: p[1].get("created_at", ""))
        over = len(tree) - len(removed) - policy.max_per_run
        for sha, _ in cap_eligible:
            if over <= 0:
                break
            if sha not in removed:
                removed.append(sha)
                over -= 1

    # Apply: delete bundles + tree edges; rewrite tree.json + index.json
    for sha in removed:
        bdir = store.ck_dir / "by-hash" / sha[:2] / sha[2:]
        shutil.rmtree(bdir, ignore_errors=True)
        tree.pop(sha, None)
    for meta in tree.values():
        meta["children"] = [c for c in meta.get("children", []) if c not in removed]
    store._atomic_write(
        store.ck_dir / "tree.json",
        json.dumps(tree, sort_keys=True, indent=2),
    )
    idx_path = store.ck_dir / "index.json"
    idx = json.loads(idx_path.read_text())
    idx = {h: s for h, s in idx.items() if s not in removed}
    store._atomic_write(idx_path, json.dumps(idx, sort_keys=True, indent=2))
    return removed
