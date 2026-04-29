"""CLI dispatcher for /forge-admin handoff subcommands."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from hooks._py.handoff.resumer import ResumeRequest, resume_from_handoff
from hooks._py.handoff.writer import WriteRequest, write_handoff
from hooks._py.platform_support import forge_dir


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    ap = argparse.ArgumentParser(prog="forge-handoff")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_write = sub.add_parser("write")
    p_write.add_argument("--level", default="manual", choices=["manual", "soft", "hard", "milestone", "terminal"])
    p_write.add_argument("--variant", default="full", choices=["light", "full"])
    p_write.add_argument("--reason", default="manual")

    p_list = sub.add_parser("list")
    p_list.add_argument("--run", default=None)

    p_show = sub.add_parser("show")
    p_show.add_argument("target", help="path or 'latest'")

    p_resume = sub.add_parser("resume")
    p_resume.add_argument("path", nargs="?", default=None)
    p_resume.add_argument("--autonomous", action="store_true")
    p_resume.add_argument("--force", action="store_true")

    p_search = sub.add_parser("search")
    p_search.add_argument("query")

    args = ap.parse_args(argv)
    fdir = forge_dir()

    if args.cmd == "write":
        return _cmd_write(fdir, args)
    if args.cmd == "list":
        return _cmd_list(fdir, args)
    if args.cmd == "show":
        return _cmd_show(fdir, args)
    if args.cmd == "resume":
        return _cmd_resume(fdir, args)
    if args.cmd == "search":
        return _cmd_search(fdir, args)
    return 2


def _cmd_write(fdir: Path, args) -> int:
    state = _read_state(fdir)
    if state is None or not state.get("run_id"):
        print("error: no active forge run", file=sys.stderr)
        return 1
    req = WriteRequest(
        run_id=state["run_id"],
        level=args.level,
        reason=args.reason,
        variant=args.variant,
        now=datetime.now(timezone.utc),
    )
    result = write_handoff(req, forge_dir=fdir)
    if result.suppressed:
        print(f"suppressed: {result.reason}", file=sys.stderr)
        return 2
    print(str(result.path))
    return 0


def _cmd_list(fdir: Path, args) -> int:
    state = _read_state(fdir)
    if args.run is None:
        # Default: current run via state.json
        if state is None:
            return 1
        run_id = state.get("run_id")
        if not run_id:
            return 1
        chain = (state.get("handoff") or {}).get("chain", [])
        for entry in chain:
            print(entry)
        return 0

    # Explicit --run: filesystem glob (state.json only tracks current run)
    run_id = args.run
    handoff_dir = fdir / "runs" / run_id / "handoffs"
    if not handoff_dir.is_dir():
        print(f"error: no handoffs directory for run {run_id}", file=sys.stderr)
        return 1
    files = sorted(handoff_dir.glob("*.md"))
    for f in files:
        print(str(f))
    return 0


def _cmd_show(fdir: Path, args) -> int:
    if args.target == "latest":
        state = _read_state(fdir)
        if state is None:
            return 1
        run_id = state.get("run_id")
        if not run_id:
            return 1
        handoff_dir = fdir / "runs" / run_id / "handoffs"
        files = sorted(handoff_dir.glob("*.md"))
        if not files:
            print(f"error: no handoffs found for run {run_id}", file=sys.stderr)
            return 1
        path = files[-1]
    else:
        path = Path(args.target)
    if not path.is_file():
        print(f"error: {path} not found", file=sys.stderr)
        return 1
    print(path.read_text())
    return 0


def _cmd_resume(fdir: Path, args) -> int:
    if args.path is None:
        # Auto-pick: latest handoff across all runs
        runs = sorted((fdir / "runs").glob("*/handoffs/*.md"))
        if not runs:
            print("error: no handoffs found", file=sys.stderr)
            return 1
        path = runs[-1]
    else:
        path = Path(args.path)
    req = ResumeRequest(handoff_path=path, autonomous=args.autonomous, force=args.force)
    result = resume_from_handoff(req, forge_dir=fdir)
    print(json.dumps({"status": result.status, "run_id": result.run_id, "reason": result.reason}))
    return 0 if result.status in ("ok", "ok_forced") else 1


def _cmd_search(fdir: Path, args) -> int:
    # Delegate to run-history.db FTS5; placeholder until Phase 7 wires indexing.
    db = fdir / "run-history.db"
    if not db.exists():
        print("error: run-history.db not available", file=sys.stderr)
        return 1
    import sqlite3
    conn = sqlite3.connect(str(db))
    try:
        rows = conn.execute(
            "SELECT path, snippet(handoff_fts, 0, '[', ']', '...', 12) FROM handoff_fts WHERE handoff_fts MATCH ? LIMIT 20",
            (args.query,),
        ).fetchall()
        for path, snip in rows:
            print(f"{path}\n  {snip}\n")
    except sqlite3.OperationalError:
        print("error: handoff_fts table missing — search unavailable", file=sys.stderr)
        return 1
    return 0


def _read_state(fdir: Path) -> dict | None:
    p = fdir / "state.json"
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return None


if __name__ == "__main__":
    sys.exit(main())
