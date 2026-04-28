"""Render SCORECARD.md from trends.jsonl.

Sections (enforced order, idempotent by HTML marker):
  - header (metadata + hook failures + incomplete-cells banner)
  - this-week (overall, by complexity, by language, by model)
  - last-12-weeks (sparklines per bucket)
  - regressions (entries that flipped solved→failed)
  - cost-per-solve (median USD sparkline)
  - vs-peers (placeholder — never fabricate)
  - appendix (per-entry raw solve booleans)
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Sequence
from pathlib import Path

_BLOCKS = "▁▂▃▄▅▆▇█"


def sparkline(values: Sequence[float | None]) -> str:
    if not values:
        return "▁" * 12
    rendered = []
    for v in values:
        if v is None:
            rendered.append(_BLOCKS[0])
        else:
            clamped = max(0.0, min(1.0, float(v)))
            # truncate (not round) so 0.5 → ▄ (test-locked behavior).
            idx = min(len(_BLOCKS) - 1, int(clamped * (len(_BLOCKS) - 1)))
            rendered.append(_BLOCKS[idx])
    return "".join(rendered)


def _section(marker: str, body: str) -> str:
    return f"<!-- section:{marker} -->\n{body}\n"


def render(*, trends_lines: list[dict], baseline: dict | None, hook_failures_total: int) -> str:
    parts: list[str] = []
    # Header
    if not trends_lines:
        parts.append(_section("header", "# Forge Scorecard\n\n> awaiting first weekly run\n"))
        parts.append(_section("this-week", "_no data_\n"))
        parts.append(_section("last-12-weeks", "_no data_\n"))
        parts.append(_section("regressions", "_none_\n"))
        parts.append(_section("cost-per-solve", "_no data_\n"))
        parts.append(_section("vs-peers", _peers_placeholder(None)))
        parts.append(_section("appendix", "_no data_\n"))
        return "\n".join(parts)

    latest = trends_lines[-1]
    header = "# Forge Scorecard\n\n"
    header += f"- generated: {latest['week_of']}\n"
    header += f"- commit: {latest['commit_sha']}\n"
    header += f"- forge version: {latest['forge_version']}\n"
    header += f"- hook failures this week: {hook_failures_total}\n"
    if latest.get("cost_truncated"):
        header += "- **cost-truncated**: weekly cost ceiling tripped; partial data only\n"
    cells_ran = len(latest.get("cells", []))
    if cells_ran < 6:
        header += f"- incomplete: {cells_ran}/6 cells ran\n"
    parts.append(_section("header", header))

    # This week
    tw = _render_this_week(latest)
    parts.append(_section("this-week", tw))

    # Sparklines over last 12
    last_12 = trends_lines[-12:]
    sp = _render_sparklines(last_12)
    parts.append(_section("last-12-weeks", sp))

    # Regressions
    regs = latest.get("regressions", [])
    if regs:
        body = (
            "| entry | last week | this week |\n|---|---|---|\n"
            + "\n".join(
                f"| `{r['entry_id']}` | {r['last_status']} | {r['this_status']} |" for r in regs
            )
            + "\n"
        )
    else:
        body = "_none this week_\n"
    parts.append(_section("regressions", body))

    # Cost-per-solve
    cps = _render_cost_per_solve(last_12)
    parts.append(_section("cost-per-solve", cps))

    # Peers
    parts.append(_section("vs-peers", _peers_placeholder(latest)))

    # Appendix
    parts.append(_section("appendix", _render_appendix(latest)))

    return "\n".join(parts)


def _render_this_week(line: dict) -> str:
    rows = []
    rows.append(
        "| os | model | solved / total | overall | S | M | L | median $/solve | UNVERIFIABLE |"
    )
    rows.append("|---|---|---|---|---|---|---|---|---|")
    for c in line.get("cells", []):
        by = c["solve_rate_by_complexity"]
        rows.append(
            f"| {c['os']} | {c['model']} | {c['entries_solved']} / {c['entries_total']} | "
            f"{c['solve_rate_overall'] * 100:.0f}% | "
            f"{by.get('S', 0) * 100:.0f}% | {by.get('M', 0) * 100:.0f}% | {by.get('L', 0) * 100:.0f}% | "
            f"${c['median_cost_per_solve_usd']:.2f} | "
            f"{c.get('unverifiable_total', 0)} |"
        )
    return "\n".join(rows) + "\n"


def _render_sparklines(lines: list[dict]) -> str:
    by_cell: dict[tuple[str, str], list[float | None]] = {}
    for ln in lines:
        for c in ln.get("cells", []):
            by_cell.setdefault((c["os"], c["model"]), []).append(c["solve_rate_overall"])
    out = ["## Last 12 weeks\n"]
    for (os_name, model), vals in sorted(by_cell.items()):
        padded = [None] * (12 - len(vals)) + list(vals)
        first = next((v for v in vals if v is not None), 0.0)
        last = vals[-1] if vals else 0.0
        out.append(
            f"- `{os_name}` × `{model}`: {sparkline(padded)} ({first * 100:.0f}% → {last * 100:.0f}%)"
        )
    return "\n".join(out) + "\n"


def _render_cost_per_solve(lines: list[dict]) -> str:
    by_model: dict[str, list[float | None]] = {}
    for ln in lines:
        for c in ln.get("cells", []):
            by_model.setdefault(c["model"], []).append(c["median_cost_per_solve_usd"])
    if not by_model:
        return "_no data_\n"
    # Normalize: sparkline expects 0..1, so scale by max observed
    out = ["## Cost-per-solve (median USD)\n"]
    max_cost = (
        max(
            (max(v for v in vals if v is not None) for vals in by_model.values() if vals),
            default=1.0,
        )
        or 1.0
    )
    for model, vals in sorted(by_model.items()):
        padded = [None] * (12 - len(vals)) + [v / max_cost if v is not None else None for v in vals]
        last_raw = vals[-1] if vals else 0.0
        out.append(f"- `{model}`: {sparkline(padded)} (latest: ${last_raw:.2f})")
    return "\n".join(out) + "\n"


def _peers_placeholder(_latest: dict | None) -> str:
    return (
        "## Peer comparison (manual update — never auto-scraped)\n"
        "\n"
        "| benchmark | solve rate | link |\n"
        "|---|---|---|\n"
        "| forge (this repo) | — | [SCORECARD.md](./SCORECARD.md) |\n"
        "| SWE-bench Verified | — | https://www.swebench.com/ |\n"
        "| OpenHands | — | https://github.com/All-Hands-AI/OpenHands |\n"
        "| SWE-agent | — | https://github.com/SWE-agent/SWE-agent |\n"
    )


def _render_appendix(line: dict) -> str:
    rows = ["## Appendix — per-entry solve matrix\n"]
    rows.append("| os | model | entries solved/total |")
    rows.append("|---|---|---|")
    for c in line.get("cells", []):
        rows.append(f"| {c['os']} | {c['model']} | {c['entries_solved']} / {c['entries_total']} |")
    return "\n".join(rows) + "\n"


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.benchmark.render_scorecard")
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--baseline", type=Path, default=None)
    p.add_argument("--hook-failures-total", type=int, default=0)
    p.add_argument("--output", type=Path, default=Path("SCORECARD.md"))
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    lines: list[dict] = []
    if args.trends.is_file():
        for raw in args.trends.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                lines.append(json.loads(raw))
    baseline = (
        json.loads(args.baseline.read_text(encoding="utf-8"))
        if args.baseline and args.baseline.is_file()
        else None
    )
    doc = render(
        trends_lines=lines, baseline=baseline, hook_failures_total=args.hook_failures_total
    )
    args.output.write_text(doc, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
