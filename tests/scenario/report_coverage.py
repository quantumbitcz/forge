#!/usr/bin/env python3
"""Scenario coverage reporter for shared/state-transitions.md.

Parses:
  - The three transition tables in state-transitions.md (normal flow, error,
    convergence). Reads the ACTUAL row numbers present — today the normal
    flow has a gap at row 20, so denominator = count-of-present-rows, not
    max(id).
  - `# Covers: T-01, T-37, C-09, ...` headers in tests/scenario/*.bats.

Produces:
  tests/scenario/COVERAGE.md — row-by-row coverage table, plus a split
  scope section:
    - T-* (pipeline) rows: subject to the 60% hard gate.
    - E-*, R-*, D-* rows: tracked separately, no hard gate (recovery paths
      initially have low scenario coverage by design).

CI modes:
  default  — regenerate COVERAGE.md in-place
  --check  — regenerate and diff against committed file; exit 1 on drift
  --gate   — also apply the 60% T-* hard gate and 80% warning gate

Exit:
  0 — green (coverage >= 80% on T-*, committed file up-to-date)
  1 — hard gate violated (T-* coverage < 60% OR committed file stale)
  2 — internal error (malformed table, etc.)
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TABLE = REPO / "shared" / "state-transitions.md"
SCENARIO_DIR = REPO / "tests" / "scenario"
COVERAGE_MD = REPO / "tests" / "scenario" / "COVERAGE.md"

HARD_GATE_PCT = 60.0
SOFT_WARN_PCT = 80.0


@dataclass(frozen=True)
class TxRow:
    row_id: str  # T-01, E-3, R-1, D-1, C-9
    description: str


@dataclass
class CoverageRow:
    row: TxRow
    covered_by: list[str] = field(default_factory=list)

    @property
    def covered(self) -> bool:
        return bool(self.covered_by)


# Matches a markdown transition-table row. Row ID can be bare digits (normal
# flow), or prefixed letter+digits (E3, R1, D1, C9, C10a).
ROW_RE = re.compile(
    r"^\|\s*(?P<id>[A-Z]?\d+[a-z]?)\s*\|"
    r"\s*(?P<cur>[^|]+?)\s*\|"
    r"\s*(?P<evt>[^|]+?)\s*\|"
    r"\s*(?P<grd>[^|]*?)\s*\|"
    r"\s*(?P<nxt>[^|]+?)\s*\|"
    r"\s*(?P<act>[^|]*?)\s*\|\s*$"
)
COVERS_RE = re.compile(r"^\s*#\s*Covers:\s*(?P<ids>.+?)\s*$")


def _prefix_for(raw_id: str) -> str:
    """Map raw row ID to canonical form.

    - Normal flow: bare digits → T-NN (zero-padded when <10 for sort stability)
    - E1..E9 → E-1..E-9
    - C1..C13a → C-1..C-13a
    - R1..R3 → R-1..R-3
    - D1 → D-1
    """
    if raw_id.isdigit():
        return f"T-{int(raw_id):02d}"
    m = re.fullmatch(r"([A-Z])(\d+)([a-z]?)", raw_id)
    if not m:
        return raw_id
    letter, digits, suffix = m.groups()
    return f"{letter}-{int(digits):02d}{suffix}"


def parse_rows(md: Path) -> list[TxRow]:
    """Return rows from all four transition tables in file order."""
    out: list[TxRow] = []
    for raw in md.read_text(encoding="utf-8").splitlines():
        m = ROW_RE.match(raw.rstrip())
        if not m:
            continue
        rid = _prefix_for(m["id"])
        desc = f"{m['cur'].strip(' `')} + {m['evt'].strip(' `')}"
        grd = m["grd"].strip(" `")
        if grd and grd != "—":
            desc += f" [{grd}]"
        out.append(TxRow(row_id=rid, description=desc))
    if not out:
        raise RuntimeError(f"no rows parsed from {md}")
    return out


def parse_coverage_headers(scenario_dir: Path) -> dict[str, list[str]]:
    """Return {row_id: [scenario_filename, ...]} from `# Covers:` headers."""
    out: dict[str, list[str]] = {}
    for path in sorted(scenario_dir.glob("*.bats")):
        for line in path.read_text(encoding="utf-8").splitlines():
            m = COVERS_RE.match(line)
            if not m:
                continue
            for rid in [x.strip() for x in m["ids"].split(",") if x.strip()]:
                # Normalise bare "T-1" / "T-01" / "T1" / "1" all to T-01 form.
                if rid.isdigit():
                    rid = f"T-{int(rid):02d}"
                elif re.fullmatch(r"T-\d+", rid):
                    num = int(rid[2:])
                    rid = f"T-{num:02d}"
                elif re.fullmatch(r"[A-Z]\d+[a-z]?", rid):
                    letter = rid[0]
                    num_suffix = rid[1:]
                    m2 = re.fullmatch(r"(\d+)([a-z]?)", num_suffix)
                    rid = f"{letter}-{int(m2[1]):02d}{m2[2]}" if m2 else rid
                out.setdefault(rid, []).append(path.name)
    return out


def compute_coverage(rows: list[TxRow],
                     headers: dict[str, list[str]]) -> list[CoverageRow]:
    return [CoverageRow(row=r, covered_by=headers.get(r.row_id, [])) for r in rows]


def render(results: list[CoverageRow]) -> str:
    def scope_of(rid: str) -> str:
        match rid[0]:
            case "T":
                return "T"
            case "E":
                return "E"
            case "R":
                return "R"
            case "D":
                return "D"
            case "C":
                return "C"
            case _:
                return "?"

    t_rows = [r for r in results if scope_of(r.row.row_id) == "T"]
    recovery_rows = [r for r in results if scope_of(r.row.row_id) in {"E", "R", "D"}]
    conv_rows = [r for r in results if scope_of(r.row.row_id) == "C"]

    def pct(rs: list[CoverageRow]) -> float:
        if not rs:
            return 100.0
        return 100.0 * sum(1 for r in rs if r.covered) / len(rs)

    t_pct = pct(t_rows)
    recovery_pct = pct(recovery_rows)
    conv_pct = pct(conv_rows)

    lines = ["# Scenario Coverage — shared/state-transitions.md",
             "",
             "Regenerated by `tests/scenario/report_coverage.py`. CI fails on drift.",
             "",
             f"- **Pipeline (T-\\*) coverage: {sum(1 for r in t_rows if r.covered)} / {len(t_rows)} rows ({t_pct:.1f}%)** "
             f"— hard gate: {HARD_GATE_PCT}%. Warning below: {SOFT_WARN_PCT}%.",
             f"- Recovery & Rewind (E-\\*, R-\\*, D-\\*) coverage: "
             f"{sum(1 for r in recovery_rows if r.covered)} / {len(recovery_rows)} rows ({recovery_pct:.1f}%) "
             "— tracked, not gated.",
             f"- Convergence (C-\\*) coverage: "
             f"{sum(1 for r in conv_rows if r.covered)} / {len(conv_rows)} rows ({conv_pct:.1f}%) "
             "— tracked, not gated.",
             ""]

    def emit_section(title: str, rs: list[CoverageRow]) -> None:
        lines.append(f"## {title}")
        lines.append("")
        lines.append("| row_id | description | covered_by | covered? |")
        lines.append("| --- | --- | --- | --- |")
        for r in rs:
            cov = ", ".join(r.covered_by) if r.covered_by else "—"
            mark = "YES" if r.covered else "NO"
            lines.append(f"| {r.row.row_id} | {r.row.description} | {cov} | {mark} |")
        lines.append("")

    emit_section("Pipeline (T-*)", t_rows)
    emit_section("Recovery & Rewind (E-*, R-*, D-*)", recovery_rows)
    emit_section("Convergence (C-*)", conv_rows)
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="report-coverage")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--gate", action="store_true")
    args = ap.parse_args(argv)

    try:
        rows = parse_rows(TABLE)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    headers = parse_coverage_headers(SCENARIO_DIR)
    results = compute_coverage(rows, headers)
    rendered = render(results)

    if args.check:
        old = COVERAGE_MD.read_text(encoding="utf-8") if COVERAGE_MD.is_file() else ""
        if old != rendered:
            print("[ERROR] tests/scenario/COVERAGE.md is stale; "
                  "run `python tests/scenario/report_coverage.py` and commit.",
                  file=sys.stderr)
            return 1
    else:
        COVERAGE_MD.write_text(rendered, encoding="utf-8")

    if args.gate:
        t_rows = [r for r in results if r.row.row_id.startswith("T-")]
        t_pct = 100.0 * sum(1 for r in t_rows if r.covered) / max(1, len(t_rows))
        if t_pct < HARD_GATE_PCT:
            print(f"::error::T-* coverage {t_pct:.1f}% < {HARD_GATE_PCT}% hard gate",
                  file=sys.stderr)
            return 1
        if t_pct < SOFT_WARN_PCT:
            print(f"::warning::T-* coverage {t_pct:.1f}% < {SOFT_WARN_PCT}% soft gate",
                  file=sys.stderr)

    print(f"[PASS] coverage report regenerated ({len(results)} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
