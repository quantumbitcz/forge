"""CLI entry point for the Phase 14 time-travel checkpoint store.

Invoked by the orchestrator and ``/forge-recover`` via
``python3 -m hooks._py.time_travel <op> <args...>``. Exit codes are the
contract surfaced to the user:

    0 = success
    2 = usage error (missing required flag)
    5 = rewind aborted: dirty worktree (use ``--force`` to override)
    6 = rewind aborted: unknown checkpoint id
    7 = rewind aborted: another rewind transaction in progress

See skills/forge-recover/SKILL.md §Exit Codes and shared/recovery/time-travel.md
for the full protocol.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import List, Optional

from .cas import CheckpointStore
from .gc import GCPolicy, gc
from .restore import RewindAbort, repair_rewind_tx, rewind


def _cmd_list(args: argparse.Namespace) -> int:
    store = CheckpointStore(
        run_dir=pathlib.Path(args.run_dir),
        worktree_dir=pathlib.Path(args.worktree),
    )
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
    """Render the checkpoint DAG as an indented tree with HEAD marker."""
    roots = [sha for sha, meta in tree.items() if not meta.get("parents")]

    def render(sha: str, depth: int) -> None:
        meta = tree.get(sha, {})
        marker = " <-- HEAD" if sha == head else ""
        print(f"{'  ' * depth}+-- {meta.get('human_id', '?')} [{sha[:8]}]{marker}")
        for child in meta.get("children", []):
            render(child, depth + 1)

    for root in roots:
        render(root, 0)


def _cmd_rewind(args: argparse.Namespace) -> int:
    store = CheckpointStore(
        run_dir=pathlib.Path(args.run_dir),
        worktree_dir=pathlib.Path(args.worktree),
    )
    try:
        rewind(
            store,
            to_sha=args.to,
            run_id=args.run_id,
            triggered_by=args.triggered_by,
            force=args.force,
        )
    except RewindAbort as e:
        print(f"rewind aborted: {e}", file=sys.stderr)
        return e.exit_code
    print(f"rewound to {args.to}")
    return 0


def _cmd_repair(args: argparse.Namespace) -> int:
    store = CheckpointStore(
        run_dir=pathlib.Path(args.run_dir),
        worktree_dir=pathlib.Path(args.worktree),
    )
    repair_rewind_tx(store, run_id=args.run_id)
    return 0


def _cmd_gc(args: argparse.Namespace) -> int:
    store = CheckpointStore(
        run_dir=pathlib.Path(args.run_dir),
        worktree_dir=pathlib.Path(args.worktree),
    )
    policy = GCPolicy(
        retention_days=args.retention_days,
        max_per_run=args.max_per_run,
        runs_root=pathlib.Path(args.runs_root) if args.runs_root else None,
    )
    removed = gc(store, policy)
    print(json.dumps({"removed": removed}))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="checkpoint_cas")
    parser.add_argument("op", choices=["list-checkpoints", "rewind", "repair", "gc"])
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--to")
    parser.add_argument("--run-id")
    parser.add_argument("--triggered-by", default="user")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--retention-days", type=int, default=7)
    parser.add_argument("--max-per-run", type=int, default=100)
    parser.add_argument("--runs-root")
    args = parser.parse_args(argv)

    if args.op == "list-checkpoints":
        return _cmd_list(args)
    if args.op == "rewind":
        if not args.to or not args.run_id:
            print("rewind requires --to and --run-id", file=sys.stderr)
            return 2
        return _cmd_rewind(args)
    if args.op == "repair":
        if not args.run_id:
            print("repair requires --run-id", file=sys.stderr)
            return 2
        return _cmd_repair(args)
    if args.op == "gc":
        return _cmd_gc(args)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
