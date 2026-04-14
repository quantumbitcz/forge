#!/usr/bin/env python3
"""Aggregate individual task results into suite-level metrics.

Takes a list of task result JSON objects and computes aggregate scores
including pass rate, breakdowns by language/difficulty/tag, and quality summary.

Usage:
    python3 aggregate-results.py --input <task-results.jsonl> [--format json|table]
    echo '[{...}, {...}]' | python3 aggregate-results.py --stdin
"""

import argparse
import json
import sys
from collections import defaultdict


def aggregate(task_results):
    """Compute aggregate metrics from a list of task results."""
    total = len(task_results)
    passed = sum(1 for t in task_results if t.get("result") == "PASS")
    failed = sum(1 for t in task_results if t.get("result") == "FAIL")
    errors = sum(1 for t in task_results if t.get("result") in ("ERROR", "TIMEOUT"))
    skipped = sum(1 for t in task_results if t.get("result") == "SKIPPED")

    scoreable = total - errors - skipped
    pass_rate = passed / scoreable if scoreable > 0 else 0.0

    # By language
    by_language = defaultdict(lambda: {"total": 0, "passed": 0, "failed": 0, "errors": 0})
    for t in task_results:
        lang = t.get("language", "unknown")
        by_language[lang]["total"] += 1
        if t["result"] == "PASS":
            by_language[lang]["passed"] += 1
        elif t["result"] == "FAIL":
            by_language[lang]["failed"] += 1
        else:
            by_language[lang]["errors"] += 1

    for lang, counts in by_language.items():
        scoreable_lang = counts["total"] - counts["errors"]
        counts["pass_rate"] = counts["passed"] / scoreable_lang if scoreable_lang > 0 else 0.0

    # By difficulty
    by_difficulty = defaultdict(lambda: {"total": 0, "passed": 0, "failed": 0, "errors": 0})
    for t in task_results:
        diff = t.get("difficulty", "unknown")
        by_difficulty[diff]["total"] += 1
        if t["result"] == "PASS":
            by_difficulty[diff]["passed"] += 1
        elif t["result"] == "FAIL":
            by_difficulty[diff]["failed"] += 1
        else:
            by_difficulty[diff]["errors"] += 1

    for diff, counts in by_difficulty.items():
        scoreable_diff = counts["total"] - counts["errors"]
        counts["pass_rate"] = counts["passed"] / scoreable_diff if scoreable_diff > 0 else 0.0

    # By tag
    by_tag = defaultdict(lambda: {"total": 0, "passed": 0})
    for t in task_results:
        for tag in t.get("tags", []):
            by_tag[tag]["total"] += 1
            if t["result"] == "PASS":
                by_tag[tag]["passed"] += 1

    # Quality summary
    scores = [t["final_score"] for t in task_results if t.get("final_score") is not None]
    iterations = [
        t["convergence"]["total_iterations"]
        for t in task_results
        if t.get("convergence", {}).get("total_iterations") is not None
    ]
    total_tokens = sum(
        t.get("tokens", {}).get("estimated_total", 0)
        for t in task_results
    )
    total_cost = sum(
        t.get("cost", {}).get("estimated_cost_usd", 0.0)
        for t in task_results
    )
    durations = [t["duration_seconds"] for t in task_results if t.get("duration_seconds")]

    quality_summary = {
        "avg_score": round(sum(scores) / len(scores), 1) if scores else None,
        "min_score": min(scores) if scores else None,
        "max_score": max(scores) if scores else None,
        "avg_iterations": round(sum(iterations) / len(iterations), 1) if iterations else None,
        "total_tokens": total_tokens,
        "total_cost_usd": round(total_cost, 2),
        "avg_duration_seconds": round(sum(durations) / len(durations)) if durations else 0,
        "total_duration_seconds": sum(durations)
    }

    return {
        "total": total,
        "passed": passed,
        "failed": failed,
        "errors": errors,
        "skipped": skipped,
        "pass_rate": round(pass_rate, 4),
        "by_language": dict(by_language),
        "by_difficulty": dict(by_difficulty),
        "by_tag": dict(by_tag),
        "quality_summary": quality_summary
    }


def main():
    parser = argparse.ArgumentParser(description="Aggregate eval task results")
    parser.add_argument("--input", help="Path to JSON file with task results array")
    parser.add_argument("--stdin", action="store_true", help="Read task results from stdin")
    parser.add_argument("--format", default="json", choices=["json", "table"],
                        help="Output format")

    args = parser.parse_args()

    if args.stdin:
        task_results = json.load(sys.stdin)
    elif args.input:
        with open(args.input, "r") as f:
            task_results = json.load(f)
    else:
        print("ERROR: Specify --input <file> or --stdin", file=sys.stderr)
        sys.exit(1)

    agg = aggregate(task_results)

    if args.format == "json":
        print(json.dumps(agg, indent=2))
    else:
        # Table format
        print("=== Eval Results ===")
        print("Total: {total}  Passed: {passed}  Failed: {failed}  Errors: {errors}".format(**agg))
        print("Pass Rate: {:.1%}".format(agg["pass_rate"]))
        print("")

        print("By Language:")
        for lang, counts in sorted(agg["by_language"].items()):
            print("  {}: {}/{} ({:.0%})".format(
                lang, counts["passed"], counts["total"], counts["pass_rate"]))

        print("")
        print("By Difficulty:")
        for diff, counts in sorted(agg["by_difficulty"].items()):
            print("  {}: {}/{} ({:.0%})".format(
                diff, counts["passed"], counts["total"], counts["pass_rate"]))

        qs = agg["quality_summary"]
        if qs["avg_score"] is not None:
            print("")
            print("Quality:")
            print("  Avg Score: {}  Min: {}  Max: {}".format(
                qs["avg_score"], qs["min_score"], qs["max_score"]))
            print("  Avg Iterations: {}".format(qs["avg_iterations"]))
            print("  Total Tokens: {:,}  Cost: ${:.2f}".format(
                qs["total_tokens"], qs["total_cost_usd"]))


if __name__ == "__main__":
    main()
