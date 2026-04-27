#!/usr/bin/env python3
"""Inject `> Support tier: <tier>` below the H1 of every module file.

Tier resolution:
  1. CI-verified    — module name in CI_VERIFIED set (empty today; Phase 2).
  2. Community      — module has a marker file `.community` in its dir.
  3. Contract-verified — default fallback for every other module.

`--check` mode exits non-zero if any file would be changed.
Idempotent: running twice on a clean tree produces no diff.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CI_VERIFIED: set[str] = set()  # Phase 2 populates this
BADGE_RE = re.compile(r"^> Support tier:.*$", re.MULTILINE)
H1_RE = re.compile(r"^# .+$", re.MULTILINE)


def discover_targets(root: Path) -> list[Path]:
    targets: list[Path] = []
    targets.extend(sorted((root / "modules" / "languages").glob("*.md")))
    targets.extend(sorted((root / "modules" / "frameworks").glob("*/conventions.md")))
    targets.extend(sorted((root / "modules" / "testing").glob("*.md")))
    return [p for p in targets if p.is_file()]


def tier_for(path: Path) -> str:
    module_name = path.parent.name if path.name == "conventions.md" else path.stem
    if module_name in CI_VERIFIED:
        return "CI-verified"
    if (path.parent / ".community").exists():
        return "Community"
    return "contract-verified"


def render_badge(tier: str) -> str:
    return f"> Support tier: {tier}"


def transform(text: str, badge: str) -> str:
    # Remove existing badge lines (any number, anywhere).
    text = BADGE_RE.sub("", text)
    # Re-insert directly after H1.
    m = H1_RE.search(text)
    if not m:
        return text  # no H1 — leave alone
    insert_at = m.end()
    # Skip a single trailing newline so the badge lands on its own line.
    tail = text[insert_at:]
    # Collapse leading blank lines in tail (prevents stacking).
    tail = re.sub(r"^\n+", "\n", tail)
    return text[:insert_at] + "\n" + badge + "\n" + tail.lstrip("\n").rstrip() + ("\n" if not text.endswith("\n") else "\n")


def process(root: Path, check_only: bool) -> int:
    drift = 0
    for path in discover_targets(root):
        badge = render_badge(tier_for(path))
        original = path.read_text(encoding="utf-8")
        updated = transform(original, badge)
        if updated != original:
            drift += 1
            if check_only:
                sys.stdout.write(f"drift: {path}\n")
            else:
                path.write_text(updated, encoding="utf-8")
    if check_only and drift:
        sys.stderr.write(f"{drift} file(s) out of date. Run derive_support_tiers.py without --check.\n")
        return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Inject support-tier badges in module docs.")
    ap.add_argument("--check", action="store_true", help="exit non-zero on drift")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]), help="repo root")
    args = ap.parse_args()
    return process(Path(args.root), args.check)


if __name__ == "__main__":
    sys.exit(main())
