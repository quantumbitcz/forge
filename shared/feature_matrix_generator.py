#!/usr/bin/env python3
"""Regenerate shared/feature-matrix.md from .forge/run-history.db.

Usage:
    python shared/feature_matrix_generator.py

Exit codes:
    0 — success (matrix regenerated; may be no-op if already current)
    1 — DB present but corrupted (sqlite3.Error mid-query)
    2 — sentinel comments missing from feature-matrix.md

Cross-platform: pathlib.Path, no shell invocation. Tested on Linux, macOS,
Windows CI runners.
"""
from __future__ import annotations

import sqlite3
import sys
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterator

# Authoritative feature list. Source of truth for the matrix. Cross-reference:
# CLAUDE.md §Features table. Add a row here and regenerate to update the matrix.
FEATURES: list[tuple[str, str, str]] = [
    ("F05", "Living specifications", "conditional (living_specs.enabled)"),
    ("F07", "Event-sourced log", "conditional (events.enabled)"),
    ("F08", "Context condensation", "conditional (condensation.enabled)"),
    ("F09", "Active knowledge base", "conditional (active_knowledge.enabled)"),
    ("F10", "Enhanced security", "conditional (security.enabled)"),
    ("F11", "Playbooks", "conditional (playbooks.enabled)"),
    ("F12", "Spec inference", "conditional (spec_inference.enabled)"),
    ("F13", "Property-based testing", "conditional (property_testing.enabled)"),
    ("F14", "Flaky test management", "conditional (flaky_tests.enabled)"),
    ("F15", "Dynamic accessibility", "conditional (accessibility.enabled)"),
    ("F16", "i18n validation", "enabled (i18n.enabled default true)"),
    ("F17", "Performance regression", "conditional (performance_tracking.enabled)"),
    ("F18", "Next-task prediction", "conditional (predictions.enabled)"),
    ("F19", "DX metrics", "conditional (dx_metrics.enabled)"),
    ("F20", "Monorepo tooling", "conditional (monorepo.enabled)"),
    ("F21", "A2A HTTP transport", "conditional (a2a.enabled)"),
    ("F22", "AI/ML pipelines", "conditional (ml_ops.enabled)"),
    ("F23", "Feature flags", "conditional (feature_flags.enabled)"),
    ("F24", "Deployment strategies", "conditional (deployment.enabled)"),
    ("F25", "Consumer-driven contracts", "conditional (contract_testing.enabled)"),
    ("F26", "Output compression", "conditional (output_compression.enabled)"),
    ("F27", "AI quality", "conditional (ai_quality.enabled)"),
    ("F28", "Cross-project learnings", "conditional (cross_project.enabled)"),
    ("F29", "Run history store", "conditional (run_history.enabled)"),
    ("F30", "MCP server", "conditional (mcp_server.enabled)"),
    ("F31", "Self-improving playbooks", "conditional (playbooks.refinement.enabled)"),
    ("F32", "Implementer reflection", "conditional (implementer.reflection.enabled)"),
    ("F33", "Self-consistency voting", "conditional (consistency.enabled)"),
    ("F34", "Session handoff", "conditional (handoff.enabled)"),
    ("F35", "Speculative plan branches", "conditional (speculation.enabled)"),
]

START_SENTINEL = "<!-- FEATURE_MATRIX_START -->"
END_SENTINEL = "<!-- FEATURE_MATRIX_END -->"
FLAGGED_MARKER = "<!-- FLAGGED -->"

REPO_ROOT = Path(__file__).resolve().parent.parent
MATRIX_PATH = REPO_ROOT / "shared" / "feature-matrix.md"
DB_PATH = REPO_ROOT / ".forge" / "run-history.db"


@contextmanager
def _with_feature_usage_table(db_path: Path) -> Iterator[sqlite3.Cursor | None]:
    """Open run-history.db; yield a cursor if `feature_usage` exists, else None.

    Centralises the missing-DB / missing-table probe so the two callers below
    don't duplicate the boilerplate. Caller decides whether sqlite3.Error is
    fatal (load_usage_counts) or silent (load_flagged_features).
    """
    if not db_path.exists():
        yield None
        return
    conn = sqlite3.connect(str(db_path))
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='feature_usage'"
        )
        if cur.fetchone() is None:
            yield None
        else:
            yield cur
    finally:
        conn.close()


def load_usage_counts(window_days: int = 30) -> dict[str, int | None]:
    """Return {feature_id: count}. Missing DB or table → all values None."""
    counts: dict[str, int | None] = {fid: None for fid, _, _ in FEATURES}
    try:
        with _with_feature_usage_table(DB_PATH) as cur:
            if cur is None:
                return counts
            cutoff = (
                datetime.now(timezone.utc) - timedelta(days=window_days)
            ).isoformat()
            cur.execute(
                "SELECT feature_id, COUNT(*) FROM feature_usage "
                "WHERE ts >= ? GROUP BY feature_id",
                (cutoff,),
            )
            for fid, count in cur.fetchall():
                counts[fid] = int(count)
            # Features with no row in the window → 0 (not None);
            # None means DB/table missing.
            for fid in counts:
                if counts[fid] is None:
                    counts[fid] = 0
    except sqlite3.Error as exc:
        print(f"feature_matrix_generator: sqlite error: {exc}", file=sys.stderr)
        sys.exit(1)
    return counts


def load_flagged_features(window_days: int = 90) -> set[str]:
    """Feature IDs with zero usage in last `window_days`."""
    try:
        with _with_feature_usage_table(DB_PATH) as cur:
            if cur is None:
                return set()
            cutoff = (
                datetime.now(timezone.utc) - timedelta(days=window_days)
            ).isoformat()
            cur.execute(
                "SELECT DISTINCT feature_id FROM feature_usage WHERE ts >= ?",
                (cutoff,),
            )
            active = {row[0] for row in cur.fetchall()}
    except sqlite3.Error:
        return set()
    all_ids = {fid for fid, _, _ in FEATURES}
    return all_ids - active


def render_matrix(counts: dict[str, int | None], flagged: set[str]) -> str:
    lines: list[str] = []
    lines.append("| ID | Feature | Default | Last-30d Usage |")
    lines.append("|----|---------|---------|----------------|")
    for fid, name, default in sorted(FEATURES, key=lambda f: f[0]):
        count_val = counts.get(fid)
        usage = "unknown" if count_val is None else str(count_val)
        if fid in flagged and count_val is not None:
            usage = f"{usage} {FLAGGED_MARKER}"
        lines.append(f"| {fid} | {name} | {default} | {usage} |")
    return "\n".join(lines)


def rewrite_matrix_file(rendered: str) -> None:
    text = MATRIX_PATH.read_text(encoding="utf-8")
    if START_SENTINEL not in text or END_SENTINEL not in text:
        print(
            f"feature_matrix_generator: missing sentinel in {MATRIX_PATH}",
            file=sys.stderr,
        )
        sys.exit(2)
    start = text.index(START_SENTINEL) + len(START_SENTINEL)
    end = text.index(END_SENTINEL)
    new_text = text[:start] + "\n" + rendered + "\n" + text[end:]
    MATRIX_PATH.write_text(new_text, encoding="utf-8")


def main() -> int:
    counts = load_usage_counts(window_days=30)
    flagged = load_flagged_features(window_days=90)
    rendered = render_matrix(counts, flagged)
    rewrite_matrix_file(rendered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
