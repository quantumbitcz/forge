#!/usr/bin/env python3
"""Inject `> Support tier: <tier>` below the H1 of every module file.

Tier resolution:
  1. ci-verified       — module name in CI_VERIFIED set (empty today; Phase 2).
  2. community         — module path matches a `COMMUNITY_PREFIXES` entry,
                         or has a marker file `.community` in its dir.
  3. contract-verified — default fallback for every other module.

Tier identifiers are lowercase-with-hyphen (machine-readable, grep-friendly).

`--check` mode exits non-zero if any file would be changed.
Idempotent: running twice on a clean tree produces no diff.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CI_VERIFIED: set[str] = set()  # Phase 2 populates this

# Path-prefix rules for `community` tier — layers without explicit
# CI/contract coverage. Matched against the relative path's `Path.parts`
# under the repo root. Each entry is a prefix tuple of path components.
COMMUNITY_PREFIX_PARTS: tuple[tuple[str, ...], ...] = (
    ("modules", "documentation"),
    ("modules", "ml-ops"),
    ("modules", "data-pipelines"),
    ("modules", "feature-flags"),
    ("modules", "build-systems"),
    ("modules", "code-quality"),
    ("modules", "api-protocols"),
)

# Suffix rules: framework documentation sub-bindings have no CI of their own.
# Each entry is a suffix tuple of path components matched against `Path.parts`.
COMMUNITY_SUFFIX_PARTS: tuple[tuple[str, ...], ...] = (
    ("documentation", "conventions.md"),
)

BADGE_RE = re.compile(r"^> Support tier:.*$", re.MULTILINE)
H1_RE = re.compile(r"^# .+$", re.MULTILINE)


def discover_targets(root: Path) -> list[Path]:
    """All module conventions/language/testing docs that should carry a badge.

    Includes:
      - modules/languages/*.md
      - modules/testing/*.md
      - every modules/**/conventions.md (frameworks, ml-ops, data-pipelines,
        feature-flags, build-systems, code-quality, documentation,
        api-protocols, framework documentation sub-bindings, etc.)
    """
    targets: set[Path] = set()
    targets.update((root / "modules" / "languages").glob("*.md"))
    targets.update((root / "modules" / "testing").glob("*.md"))
    targets.update((root / "modules").rglob("conventions.md"))
    return sorted(p for p in targets if p.is_file())


def tier_for(path: Path, root: Path) -> str:
    """Return the lowercase tier identifier for the given module file."""
    module_name = path.parent.name if path.name == "conventions.md" else path.stem
    if module_name in CI_VERIFIED:
        return "ci-verified"

    # Marker file opt-in for community tier.
    if (path.parent / ".community").exists():
        return "community"

    # Path-based community defaults.
    try:
        rel_parts = path.relative_to(root).parts
    except ValueError:
        rel_parts = path.parts
    for suffix in COMMUNITY_SUFFIX_PARTS:
        if rel_parts[-len(suffix):] == suffix:
            return "community"
    for prefix in COMMUNITY_PREFIX_PARTS:
        if rel_parts[: len(prefix)] == prefix:
            return "community"

    return "contract-verified"


def render_badge(tier: str) -> str:
    return f"> Support tier: {tier}"


def _trailing_newlines(text: str) -> int:
    n = 0
    while n < len(text) and text[len(text) - 1 - n] == "\n":
        n += 1
    return n


def transform(text: str, badge: str) -> str:
    """Insert (or refresh) the badge line directly below H1, with blank
    lines on both sides. Preserve the file's original trailing-newline count."""
    trailing = _trailing_newlines(text)
    body = text.rstrip("\n")

    # Remove existing badge lines (any number, anywhere).
    body = BADGE_RE.sub("", body)

    m = H1_RE.search(body)
    if not m:
        # No H1 — leave alone (other than badge purge above).
        return body + ("\n" * max(trailing, 1))

    insert_at = m.end()
    head = body[:insert_at]
    tail = body[insert_at:]

    # Collapse leading blank lines in tail so the badge has exactly one
    # blank line above it (the blank line between H1 and badge), exactly
    # one blank line below it (between badge and the next block).
    tail = re.sub(r"^\n+", "", tail)

    # Compose: H1 \n\n badge \n\n tail
    rebuilt = f"{head}\n\n{badge}\n\n{tail}" if tail else f"{head}\n\n{badge}\n"

    # Preserve original trailing-newline count (default to 1 if input had none).
    rebuilt = rebuilt.rstrip("\n") + ("\n" * max(trailing, 1))
    return rebuilt


def process(root: Path, check_only: bool) -> int:
    drift = 0
    for path in discover_targets(root):
        badge = render_badge(tier_for(path, root))
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
    ap.add_argument("--apply", action="store_true", help="apply changes (default if --check is absent)")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]), help="repo root")
    args = ap.parse_args()
    return process(Path(args.root), args.check)


if __name__ == "__main__":
    sys.exit(main())
