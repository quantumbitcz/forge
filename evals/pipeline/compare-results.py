#!/usr/bin/env python3
"""Compare two eval result files and detect regressions.

Matches tasks by ID, computes per-task status changes, and produces
a comparison report with verdict (STABLE/IMPROVEMENT/REGRESSION).

Usage:
    python3 compare-results.py --baseline <file> --current <file> [--format json|table|markdown]
    python3 compare-results.py --baseline <file> --results-dir <dir> [--suite <name>]
"""

import argparse
import glob
import json
import os
import sys


def find_latest_result(results_dir, suite_name=None):
    """Find the latest result file, optionally filtered by suite name."""
    pattern = "*-{}.json".format(suite_name) if suite_name else "*.json"
    files = sorted(glob.glob(os.path.join(results_dir, pattern)))
    return files[-1] if files else None


def compare(baseline_data, current_data):
    """Compare baseline and current results, return comparison report."""
    baseline_tasks = {t["id"]: t for t in baseline_data.get("results", {}).get("tasks", [])}
    current_tasks = {t["id"]: t for t in current_data.get("results", {}).get("tasks", [])}

    all_ids = sorted(set(list(baseline_tasks.keys()) + list(current_tasks.keys())))

    task_comparisons = []
    regressions = []
    improvements = []
    stable = []
    new_tasks = []
    removed = []

    for tid in all_ids:
        bt = baseline_tasks.get(tid)
        ct = current_tasks.get(tid)

        if bt and not ct:
            removed.append(tid)
            task_comparisons.append({
                "id": tid, "status": "REMOVED",
                "baseline_result": bt.get("result"), "current_result": None
            })
        elif ct and not bt:
            new_tasks.append(tid)
            task_comparisons.append({
                "id": tid, "status": "NEW",
                "baseline_result": None, "current_result": ct.get("result")
            })
        else:
            br = bt.get("result", "UNKNOWN")
            cr = ct.get("result", "UNKNOWN")

            if br == "PASS" and cr != "PASS":
                status = "REGRESSION"
                regressions.append(tid)
            elif br != "PASS" and cr == "PASS":
                status = "IMPROVEMENT"
                improvements.append(tid)
            else:
                status = "STABLE"
                stable.append(tid)

            # Score comparison
            bs = bt.get("final_score")
            cs = ct.get("final_score")
            score_delta = None
            if bs is not None and cs is not None:
                score_delta = cs - bs

            task_comparisons.append({
                "id": tid, "status": status,
                "baseline_result": br, "current_result": cr,
                "baseline_score": bs, "current_score": cs,
                "score_delta": score_delta,
                "baseline_duration": bt.get("duration_seconds"),
                "current_duration": ct.get("duration_seconds")
            })

    # Aggregate comparison
    b_agg = baseline_data.get("results", {}).get("aggregate", {})
    c_agg = current_data.get("results", {}).get("aggregate", {})
    pass_rate_delta = c_agg.get("pass_rate", 0) - b_agg.get("pass_rate", 0)

    verdict = "REGRESSION" if regressions else ("IMPROVEMENT" if improvements else "STABLE")

    return {
        "verdict": verdict,
        "regression_count": len(regressions),
        "improvement_count": len(improvements),
        "stable_count": len(stable),
        "new_count": len(new_tasks),
        "removed_count": len(removed),
        "aggregate": {
            "baseline_pass_rate": b_agg.get("pass_rate", 0),
            "current_pass_rate": c_agg.get("pass_rate", 0),
            "pass_rate_delta": round(pass_rate_delta, 4),
            "regressions": regressions,
            "improvements": improvements,
            "stable": stable,
            "new": new_tasks,
            "removed": removed
        },
        "tasks": task_comparisons
    }


def format_table(comparison):
    """Format comparison as plain text table."""
    lines = []
    lines.append("Verdict: {}".format(comparison["verdict"]))
    agg = comparison["aggregate"]
    lines.append("Pass Rate: {:.1%} -> {:.1%} ({:+.1%})".format(
        agg["baseline_pass_rate"], agg["current_pass_rate"], agg["pass_rate_delta"]))
    lines.append("")

    if comparison["regression_count"] > 0:
        lines.append("Regressions ({}):".format(comparison["regression_count"]))
        for tid in agg["regressions"]:
            lines.append("  - {}".format(tid))
        lines.append("")

    if comparison["improvement_count"] > 0:
        lines.append("Improvements ({}):".format(comparison["improvement_count"]))
        for tid in agg["improvements"]:
            lines.append("  - {}".format(tid))
        lines.append("")

    lines.append("Task Details:")
    lines.append("{:<25} {:<12} {:<12} {:<10}".format("Task", "Baseline", "Current", "Status"))
    lines.append("-" * 60)
    for tc in comparison["tasks"]:
        lines.append("{:<25} {:<12} {:<12} {:<10}".format(
            tc["id"],
            tc.get("baseline_result") or "-",
            tc.get("current_result") or "-",
            tc["status"]
        ))

    return "\n".join(lines)


def format_markdown(comparison):
    """Format comparison as markdown."""
    lines = []
    lines.append("## Eval Comparison")
    lines.append("")
    lines.append("**Verdict: {}**".format(comparison["verdict"]))
    lines.append("")

    agg = comparison["aggregate"]
    lines.append("| Metric | Baseline | Current | Delta |")
    lines.append("|--------|----------|---------|-------|")
    lines.append("| Pass Rate | {:.1%} | {:.1%} | {:+.1%} |".format(
        agg["baseline_pass_rate"], agg["current_pass_rate"], agg["pass_rate_delta"]))
    lines.append("| Regressions | - | {} | - |".format(comparison["regression_count"]))
    lines.append("| Improvements | - | {} | - |".format(comparison["improvement_count"]))
    lines.append("")

    if comparison["regression_count"] > 0:
        lines.append("### Regressions")
        for tid in agg["regressions"]:
            lines.append("- {}".format(tid))
        lines.append("")

    if comparison["improvement_count"] > 0:
        lines.append("### Improvements")
        for tid in agg["improvements"]:
            lines.append("- {}".format(tid))
        lines.append("")

    lines.append("### Task Details")
    lines.append("")
    lines.append("| Task | Baseline | Current | Status | Score Delta |")
    lines.append("|------|----------|---------|--------|-------------|")
    for tc in comparison["tasks"]:
        sd = tc.get("score_delta")
        sd_str = "{:+d}".format(sd) if sd is not None else "-"
        lines.append("| {} | {} | {} | {} | {} |".format(
            tc["id"],
            tc.get("baseline_result") or "-",
            tc.get("current_result") or "-",
            tc["status"],
            sd_str
        ))

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Compare eval results against baseline")
    parser.add_argument("--baseline", required=True, help="Baseline result file")
    parser.add_argument("--current", help="Current result file")
    parser.add_argument("--results-dir", help="Results directory (auto-detect latest)")
    parser.add_argument("--suite", help="Suite name for result filtering")
    parser.add_argument("--format", default="table", choices=["json", "table", "markdown", "csv"],
                        help="Output format")

    args = parser.parse_args()

    # Load baseline
    with open(args.baseline, "r") as f:
        baseline_data = json.load(f)

    # Resolve current
    current_path = args.current
    if not current_path and args.results_dir:
        current_path = find_latest_result(args.results_dir, args.suite)
    if not current_path:
        print("ERROR: No current result file found. Specify --current or --results-dir.", file=sys.stderr)
        sys.exit(1)

    with open(current_path, "r") as f:
        current_data = json.load(f)

    comparison = compare(baseline_data, current_data)

    if args.format == "json":
        print(json.dumps({"comparison": comparison}, indent=2))
    elif args.format == "markdown":
        print(format_markdown(comparison))
    elif args.format == "csv":
        print("task_id,baseline_result,current_result,status,score_delta")
        for tc in comparison["tasks"]:
            sd = tc.get("score_delta", "")
            print("{},{},{},{},{}".format(
                tc["id"],
                tc.get("baseline_result", ""),
                tc.get("current_result", ""),
                tc["status"],
                sd if sd is not None else ""
            ))
    else:
        print(format_table(comparison))

    # Exit code 3 on regression
    sys.exit(3 if comparison["verdict"] == "REGRESSION" else 0)


if __name__ == "__main__":
    main()
