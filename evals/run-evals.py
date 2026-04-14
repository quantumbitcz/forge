#!/usr/bin/env python3
"""Three-arm eval runner: verbose, terse, caveman-full.

Runs each of the 10 eval tasks through three output compression arms
and measures accuracy via substring matching against required_facts.

Requires ANTHROPIC_API_KEY environment variable. Estimated cost: ~$0.50/run
with Sonnet (30 API calls).

LOCAL-ONLY eval. Not run in CI.

Arms:
  1. verbose -- no compression instructions
  2. terse -- terse mode compression
  3. caveman-full -- full caveman mode compression

Usage:
    export ANTHROPIC_API_KEY=sk-ant-...
    python3 run-evals.py
    python3 run-evals.py --tasks 01,02,03
    python3 run-evals.py --model claude-sonnet-4-20250514
    python3 run-evals.py --dry-run
"""

import argparse
import json
import os
import re
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TASKS_DIR = os.path.join(SCRIPT_DIR, "tasks")
RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")

MULTIPLIER = 1.3

# Three-arm design
ARMS = {
    "verbose": "",
    "terse": (
        "OUTPUT COMPRESSION -- TERSE MODE\n\n"
        "Drop: articles (a/an/the), filler (just/really/basically/simply), "
        "pleasantries (sure/certainly/I'd be happy to), hedging (perhaps/might/"
        "you could consider), restated context, transition phrases.\n"
        "Keep: technical terms exact, code blocks unchanged, error messages "
        "verbatim, file paths, line numbers, finding categories, severity levels.\n"
        "Pattern: [subject] [action] [reason]. [next step].\n\n"
    ),
    "caveman-full": (
        "CAVEMAN MODE -- FULL COMPRESSION\n\n"
        "U talk like caveman. Short word only. No article. No filler.\n"
        "Drop: a/an/the, just/really/basically, sure/certainly, "
        "however/furthermore/additionally.\n"
        "Keep: code exact, technical term exact, number exact.\n"
        "Pattern: [thing] [do] [why]. No fluff.\n\n"
    ),
}

FORGE_CONTEXT = (
    "You are a forge pipeline agent. Forge is a 10-stage autonomous development "
    "pipeline with 41 agents, quality scoring (score = max(0, 100 - 20*CRITICAL - "
    "5*WARNING - 2*INFO)), convergence engine, and recovery system. "
    "PASS >= 80, CONCERNS 60-79, FAIL < 60. "
    "Recovery: 7 strategies, budget ceiling 5.5. "
    "MCP failures degrade gracefully (INFO, not blocking). "
    "Flaky tests: auto-quarantine via flip_rate detection."
)


def load_tasks(task_filter: list = None) -> list:
    """Load task definitions from tasks/*.md."""
    tasks = []
    for filename in sorted(os.listdir(TASKS_DIR)):
        if not filename.endswith(".md"):
            continue

        path = os.path.join(TASKS_DIR, filename)
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        fm_match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
        if not fm_match:
            continue

        fm_text = fm_match.group(1)
        task = {"file": filename}

        for line in fm_text.split("\n"):
            line = line.strip()
            if line.startswith("id:"):
                task["id"] = line.split(":", 1)[1].strip().strip('"')
            elif line.startswith("name:"):
                task["name"] = line.split(":", 1)[1].strip()
            elif line.startswith("prompt:"):
                task["prompt"] = line.split(":", 1)[1].strip().strip('"')
            elif line.startswith("  - "):
                task.setdefault("required_facts", []).append(
                    line.lstrip("  - ").strip().strip('"')
                )

        if task_filter:
            if task.get("name") not in task_filter and task.get("id") not in task_filter:
                continue

        if "prompt" in task and "required_facts" in task:
            tasks.append(task)

    return tasks


def check_accuracy(response: str, required_facts: list) -> dict:
    """Check substring matches for required facts (case-insensitive)."""
    response_lower = response.lower()
    matches = []
    misses = []
    for fact in required_facts:
        if fact.lower() in response_lower:
            matches.append(fact)
        else:
            misses.append(fact)
    return {
        "matches": matches,
        "misses": misses,
        "accuracy": len(matches) / len(required_facts) if required_facts else 0.0,
    }


def call_api(prompt: str, system: str, model: str) -> dict:
    """Call Anthropic API."""
    try:
        import anthropic
    except ImportError:
        print(
            "ERROR: anthropic package required. Install with: pip install anthropic",
            file=sys.stderr,
        )
        sys.exit(1)

    client = anthropic.Anthropic()
    start = time.time()
    response = client.messages.create(
        model=model,
        max_tokens=2000,
        system=system,
        messages=[{"role": "user", "content": prompt}],
    )
    elapsed = time.time() - start

    text = response.content[0].text if response.content else ""
    return {
        "text": text,
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens,
        "words": len(text.split()),
        "elapsed_seconds": round(elapsed, 2),
        "model": response.model,
    }


def run_evals(tasks: list, model: str, dry_run: bool = False) -> dict:
    """Run all tasks across three arms."""
    results = {
        "meta": {
            "model": model,
            "arms": list(ARMS.keys()),
            "task_count": len(tasks),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "token_method": "word_count * 1.3 (estimated) + API usage (actual)",
        },
        "tasks": {},
    }

    total_calls = len(tasks) * len(ARMS)
    call_num = 0

    for task in tasks:
        task_name = task["name"]
        task_results = {
            "prompt": task["prompt"],
            "required_facts": task["required_facts"],
            "arms": {},
        }

        for arm_name, arm_prefix in ARMS.items():
            call_num += 1
            system = arm_prefix + FORGE_CONTEXT
            prompt = task["prompt"]

            print(f"  [{call_num}/{total_calls}] {task_name} / {arm_name}", end="", flush=True)

            if dry_run:
                est_input = round(len((system + prompt).split()) * MULTIPLIER)
                task_results["arms"][arm_name] = {
                    "text": "(dry-run)",
                    "input_tokens": est_input,
                    "output_tokens": 0,
                    "words": 0,
                    "elapsed_seconds": 0,
                    "accuracy": 0.0,
                    "matches": [],
                    "misses": task["required_facts"],
                }
                print(f" (dry-run, ~{est_input} input tokens)")
                continue

            try:
                api_result = call_api(prompt, system, model)
                accuracy = check_accuracy(api_result["text"], task["required_facts"])

                task_results["arms"][arm_name] = {
                    "text": api_result["text"],
                    "input_tokens": api_result["input_tokens"],
                    "output_tokens": api_result["output_tokens"],
                    "words": api_result["words"],
                    "elapsed_seconds": api_result["elapsed_seconds"],
                    "accuracy": accuracy["accuracy"],
                    "matches": accuracy["matches"],
                    "misses": accuracy["misses"],
                }
                print(
                    f" -- {api_result['output_tokens']} out tokens, "
                    f"accuracy {accuracy['accuracy']:.0%}, "
                    f"{api_result['elapsed_seconds']}s"
                )
            except Exception as e:
                print(f" ERROR: {e}")
                task_results["arms"][arm_name] = {
                    "text": f"ERROR: {e}",
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "words": 0,
                    "elapsed_seconds": 0,
                    "accuracy": 0.0,
                    "matches": [],
                    "misses": task["required_facts"],
                    "error": str(e),
                }

        results["tasks"][task_name] = task_results

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Three-arm eval runner: verbose, terse, caveman-full"
    )
    parser.add_argument(
        "--model",
        default="claude-sonnet-4-20250514",
        help="Anthropic model (default: claude-sonnet-4-20250514)",
    )
    parser.add_argument(
        "--tasks",
        default=None,
        help="Comma-separated task IDs or names (default: all)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Estimate costs without API calls",
    )
    args = parser.parse_args()

    if not args.dry_run and not os.environ.get("ANTHROPIC_API_KEY"):
        print("ERROR: ANTHROPIC_API_KEY required", file=sys.stderr)
        print("Set: export ANTHROPIC_API_KEY=sk-ant-...", file=sys.stderr)
        sys.exit(1)

    task_filter = args.tasks.split(",") if args.tasks else None
    tasks = load_tasks(task_filter)

    if not tasks:
        print("ERROR: No tasks found.", file=sys.stderr)
        sys.exit(1)

    os.makedirs(RESULTS_DIR, exist_ok=True)

    print("Forge Eval Runner (3-arm)")
    print(f"Model: {args.model}")
    print(f"Tasks: {len(tasks)}")
    print(f"Arms: {', '.join(ARMS.keys())}")
    print(f"Total API calls: {len(tasks) * len(ARMS)}")
    if args.dry_run:
        print("Mode: DRY RUN")
    else:
        est_cost = len(tasks) * len(ARMS) * 0.015
        print(f"Estimated cost: ~${est_cost:.2f}")
    print()

    results = run_evals(tasks, args.model, args.dry_run)

    # Save JSON results
    json_path = os.path.join(RESULTS_DIR, "eval-results.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to: {json_path}")
    print(f"Run 'python3 measure.py' to generate summary.")


if __name__ == "__main__":
    main()
