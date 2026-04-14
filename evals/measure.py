#!/usr/bin/env python3
"""Offline analysis of cached eval results.

Reads eval-results.json (from run-evals.py) and generates summary tables
comparing accuracy and token usage across arms.

Usage:
    python3 measure.py
    python3 measure.py --input results/eval-results.json
    python3 measure.py --output results/summary.md
"""

import argparse
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_INPUT = os.path.join(SCRIPT_DIR, "results", "eval-results.json")
DEFAULT_OUTPUT = os.path.join(SCRIPT_DIR, "results", "summary.md")


def load_results(path: str) -> dict:
    """Load JSON results file."""
    if not os.path.isfile(path):
        print(f"ERROR: Results file not found: {path}", file=sys.stderr)
        print("Run 'python3 run-evals.py' first to generate results.", file=sys.stderr)
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def analyze(results: dict) -> str:
    """Generate markdown summary from results."""
    meta = results.get("meta", {})
    tasks = results.get("tasks", {})
    arms = meta.get("arms", [])

    lines = [
        "# Eval Results Summary",
        "",
        f"Model: **{meta.get('model', 'unknown')}**",
        f"Timestamp: {meta.get('timestamp', 'unknown')}",
        f"Tasks: {meta.get('task_count', len(tasks))}",
        f"Arms: {', '.join(arms)}",
        "",
    ]

    # --- Accuracy table ---
    lines.extend([
        "## Accuracy (required_facts substring match)",
        "",
        "| Task | " + " | ".join(arms) + " |",
        "|------" + "|--------:" * len(arms) + "|",
    ])

    arm_acc_sums = {a: 0.0 for a in arms}
    task_count = 0

    for task_name in sorted(tasks.keys()):
        task_data = tasks[task_name]
        row = f"| {task_name} |"
        for arm in arms:
            arm_data = task_data.get("arms", {}).get(arm, {})
            acc = arm_data.get("accuracy", 0.0)
            arm_acc_sums[arm] += acc
            row += f" {acc:.0%} |"
        lines.append(row)
        task_count += 1

    # Average row
    row = "| **Average** |"
    for arm in arms:
        avg = arm_acc_sums[arm] / task_count if task_count else 0
        row += f" **{avg:.0%}** |"
    lines.append(row)

    # --- Token usage table ---
    lines.extend([
        "",
        "## Output Tokens (API-reported)",
        "",
        "| Task | " + " | ".join(arms) + " |",
        "|------" + "|--------:" * len(arms) + "|",
    ])

    arm_token_sums = {a: 0 for a in arms}

    for task_name in sorted(tasks.keys()):
        task_data = tasks[task_name]
        row = f"| {task_name} |"
        for arm in arms:
            arm_data = task_data.get("arms", {}).get(arm, {})
            tokens = arm_data.get("output_tokens", 0)
            arm_token_sums[arm] += tokens
            row += f" {tokens} |"
        lines.append(row)

    # Total row
    row = "| **TOTAL** |"
    for arm in arms:
        row += f" **{arm_token_sums[arm]}** |"
    lines.append(row)

    # Savings row
    verbose_total = arm_token_sums.get("verbose", 0) or 1
    row = "| **Savings vs verbose** |"
    for arm in arms:
        if arm == "verbose":
            row += " -- |"
        else:
            savings = (1 - arm_token_sums[arm] / verbose_total) * 100
            row += f" {savings:.0f}% |"
    lines.append(row)

    # --- Per-task detail: missed facts ---
    lines.extend([
        "",
        "## Missed Facts Detail",
        "",
    ])

    for task_name in sorted(tasks.keys()):
        task_data = tasks[task_name]
        has_misses = False
        for arm in arms:
            arm_data = task_data.get("arms", {}).get(arm, {})
            misses = arm_data.get("misses", [])
            if misses:
                has_misses = True
                break

        if not has_misses:
            continue

        lines.append(f"### {task_name}")
        lines.append("")
        for arm in arms:
            arm_data = task_data.get("arms", {}).get(arm, {})
            misses = arm_data.get("misses", [])
            if misses:
                lines.append(f"- **{arm}**: missed {', '.join(misses)}")
        lines.append("")

    # --- Summary statistics ---
    lines.extend([
        "## Key Findings",
        "",
    ])

    if task_count > 0:
        verbose_avg = arm_acc_sums.get("verbose", 0) / task_count
        for arm in arms:
            if arm == "verbose":
                continue
            arm_avg = arm_acc_sums[arm] / task_count
            token_savings = (1 - arm_token_sums[arm] / verbose_total) * 100 if verbose_total > 0 else 0
            acc_delta = arm_avg - verbose_avg
            lines.append(
                f"- **{arm}**: {token_savings:.0f}% token savings, "
                f"{acc_delta:+.0%} accuracy vs verbose"
            )

    lines.extend([
        "",
        "## Notes",
        "",
        "- Accuracy is substring-match-based, not semantic similarity",
        "- Token counts from Anthropic API usage (actual, not estimated)",
        "- Estimated cost: ~$0.50/run with Sonnet",
        "- This is a local-only eval. Not run in CI.",
        "",
    ])

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Offline analysis of cached eval results"
    )
    parser.add_argument(
        "--input",
        default=DEFAULT_INPUT,
        help=f"Path to eval-results.json (default: {DEFAULT_INPUT})",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help=f"Path to write summary.md (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print to stdout instead of writing file",
    )
    args = parser.parse_args()

    results = load_results(args.input)
    summary = analyze(results)

    if args.stdout:
        print(summary)
    else:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(summary)
        print(f"Summary written to: {args.output}")


if __name__ == "__main__":
    main()
