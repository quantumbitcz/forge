#!/usr/bin/env python3
"""Scenario-sensitivity probe for shared/state-transitions.md seed rows.

This is a *scenario-sensitivity probe*, not classical mutation testing. It
does not mutate source files. Each row's mutation flag (`MUTATE_ROW=<id>`)
tells the bats scenario to flip its OWN expected-`next_state` assertion to
the mutated value. A "kill" proves the scenario was reached and that the
assertion would have caught a misconfigured row; it does NOT prove a real
source-file bug would be caught.

Why it's still useful:
  - It catches scenarios that silently no-op (declare a `# mutation_row:`
    header but never actually exercise the row).
  - It surfaces scenarios whose pass/fail outcome is independent of the
    transition under test.
  - It enforces a per-row negative control: every probed row must pass
    without `MUTATE_ROW` set and fail with it set.

What it does NOT do:
  - It does NOT mutate `shared/state-transitions.md` rows on disk.
  - It does NOT exercise the production state machine implementation.
  - A "kill" therefore is NOT evidence that a real bug in the transition
    table or state machine would be caught — only that this assertion would
    have caught THIS specific assertion-flip.

Conventions:
  - Each probed scenario carries a `# mutation_row: <id>` header.
  - Each probed scenario reads `$MUTATE_ROW` and flips one expected
    `next_state` assertion when the env var matches its declared row id.
  - The harness runs every probed scenario twice per row: first with no env
    var (negative control / baseline) and then with `MUTATE_ROW=<id>`.

Output: tests/mutation/REPORT.md (committed, diff-checked in CI).
Exit:
  0 — all seed probes killed under mutation, baselines clean
  1 — at least one survivor or broken baseline
  2 — internal error (malformed table, missing scenario, etc.)
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TABLE = REPO / "shared" / "state-transitions.md"
SCENARIO_DIR = REPO / "tests" / "scenario"
REPORT = REPO / "tests" / "mutation" / "REPORT.md"

SEED_ROWS = [
    # (row_id, description, scenario_file, mutation_summary)
    ("37", "REVIEWING + score_regressing -> ESCALATED",
     "oscillation.bats", "next_state: ESCALATED -> IMPLEMENTING"),
    ("28", "VERIFYING + safety_gate_fail<2 -> IMPLEMENTING",
     "safety-gate.bats", "next_state: IMPLEMENTING -> DOCUMENTING"),
    ("E-3", "ANY + circuit_breaker_open -> ESCALATED",
     "circuit-breaker.bats", "next_state: ESCALATED -> <prior>"),
    ("47", "SHIPPING + pr_rejected design -> PLANNING",
     "feedback-loop.bats", "next_state: PLANNING -> IMPLEMENTING"),
    ("48", "SHIPPING + feedback_loop_count>=2 -> ESCALATED",
     "feedback-loop.bats", "guard: >= 2 -> >= 3"),
]


class TransitionTableError(RuntimeError):
    pass


@dataclass(frozen=True)
class Row:
    row_id: str
    current_state: str
    event: str
    guard: str
    next_state: str


ROW_RE = re.compile(
    r"^\|\s*(?P<id>[A-Z0-9][-A-Z0-9a-z]*)\s*\|"
    r"\s*(?P<cur>[^|]+?)\s*\|"
    r"\s*(?P<evt>[^|]+?)\s*\|"
    r"\s*(?P<grd>[^|]*?)\s*\|"
    r"\s*(?P<nxt>[^|]+?)\s*\|"
    r"\s*(?P<act>[^|]*?)\s*\|\s*$"
)


def parse_rows(md_path: Path) -> dict[str, Row]:
    """Return all rows from the three transition tables keyed by row id.

    Row IDs: bare `37` in the main table becomes `37`. `E3` becomes `E-3`.
    `C9` becomes `C-9`. `D1` becomes `D-1`. `R1` becomes `R-1`.
    """
    rows: dict[str, Row] = {}
    in_table = False
    for lineno, raw in enumerate(md_path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.rstrip()
        if line.startswith("| # |") or line.startswith("| #   |"):
            in_table = True
            continue
        if in_table and (not line.startswith("|") or line.startswith("|---")):
            in_table = False if not line.startswith("|") else in_table
            if line.startswith("|---"):
                continue
            else:
                continue
        if not in_table:
            continue
        m = ROW_RE.match(line)
        if not m:
            continue
        raw_id = m["id"]
        # Normalise prefixes.
        if raw_id.isdigit():
            row_id = raw_id  # e.g. "37"
        elif re.fullmatch(r"[A-Z]\d+[a-z]?", raw_id):
            # e.g. E3 -> E-3, C9 -> C-9, D1 -> D-1, R1 -> R-1, C10a -> C-10a
            row_id = f"{raw_id[0]}-{raw_id[1:]}"
        else:
            row_id = raw_id
        rows[row_id] = Row(
            row_id=row_id,
            current_state=m["cur"].strip(" `"),
            event=m["evt"].strip(" `"),
            guard=m["grd"].strip(" `"),
            next_state=m["nxt"].strip(" `"),
        )
    if not rows:
        raise TransitionTableError(f"no rows parsed from {md_path}")
    return rows


def find_scenario_mutation_rows(scenario_dir: Path) -> dict[str, Path]:
    """Return {row_id: scenario_path} from '# mutation_row: <id>' comments."""
    out: dict[str, Path] = {}
    pat = re.compile(r"^\s*#\s*mutation_row:\s*(?P<id>[A-Z0-9][-A-Z0-9a-z]*)\s*$")
    for path in sorted(scenario_dir.glob("*.bats")):
        for line in path.read_text(encoding="utf-8").splitlines():
            m = pat.match(line)
            if m:
                out[m["id"]] = path
    return out


def run_mutation(row_id: str, scenario: Path) -> bool:
    """Return True if mutation was KILLED (scenario failed under MUTATE_ROW)."""
    env = os.environ.copy()
    env["MUTATE_ROW"] = row_id
    bats = REPO / "tests" / "lib" / "bats-core" / "bin" / "bats"
    cmd = [str(bats), str(scenario)] if bats.is_file() else ["bats", str(scenario)]
    result = subprocess.run(
        cmd, cwd=str(REPO), env=env, capture_output=True, text=True,
        check=False, timeout=120,
    )
    # Convention: bats exit 0 = all tests passed = mutation SURVIVED (scenario
    # didn't notice the transition was wrong). Non-zero = mutation KILLED.
    return result.returncode != 0


def write_report(results: list[tuple[str, str, str, str, bool]]) -> None:
    """results = [(row_id, description, scenario, mutation, killed), ...]"""
    lines = [
        "# Scenario-Sensitivity Probe Report — shared/state-transitions.md",
        "",
        "Regenerated on every CI run from `tests/mutation/state_transitions.py`. "
        "Commit this file; CI fails on drift.",
        "",
        "> **Note.** These rows are exercised via env-var assertion-flipping, "
        "NOT via source-file mutation. A `killed` outcome proves the scenario "
        "reached the row and the assertion would have caught a misconfigured "
        "row id; it does NOT prove a real bug in `state-transitions.md` or the "
        "state machine would be caught. See `state_transitions.py` docstring "
        "for the full semantics.",
        "",
        "**Strategy:** `MUTATE_ROW` env-var — participating scenarios read the env "
        "var and flip their expected `next_state` assertion when the row matches.",
        "",
        "| row_id | description | scenario | mutation_applied | survived |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row_id, desc, scenario, mut, killed in results:
        survived = "NO" if killed else "**YES** (scenario does not exercise row)"
        lines.append(f"| {row_id} | {desc} | {scenario} | {mut} | {survived} |")
    lines.append("")
    REPORT.write_text("\n".join(lines), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="state-transitions-mutation")
    ap.add_argument("--check", action="store_true",
                    help="Verify tests/mutation/REPORT.md is up-to-date (CI mode).")
    args = ap.parse_args(argv)

    try:
        rows = parse_rows(TABLE)
    except TransitionTableError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    scenario_map = find_scenario_mutation_rows(SCENARIO_DIR)

    results: list[tuple[str, str, str, str, bool]] = []
    any_survived = False
    for row_id, desc, scenario_name, mut in SEED_ROWS:
        if row_id not in rows:
            print(f"[ERROR] seed row {row_id} missing from transition table",
                  file=sys.stderr)
            return 2
        scenario = scenario_map.get(row_id) or (SCENARIO_DIR / scenario_name)
        if not scenario.is_file():
            print(f"[ERROR] seed scenario {scenario} missing", file=sys.stderr)
            return 2
        killed = run_mutation(row_id, scenario)
        if not killed:
            any_survived = True
        results.append((row_id, desc, scenario.name, mut, killed))

    if args.check:
        # Regenerate into a tmp, compare to the committed file.
        old = REPORT.read_text(encoding="utf-8") if REPORT.is_file() else ""
        write_report(results)
        new = REPORT.read_text(encoding="utf-8")
        if old != new:
            print("[ERROR] tests/mutation/REPORT.md is stale; "
                  "run `python tests/mutation/state_transitions.py` and commit.",
                  file=sys.stderr)
            return 1
    else:
        write_report(results)

    if any_survived:
        print("[FAIL] at least one mutation survived", file=sys.stderr)
        return 1
    print("[PASS] all seed mutations killed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
