#!/usr/bin/env python3
"""Extract eval metrics from .forge/state.json after a task run.

Reads state.json and produces a structured JSON result for a single task.
Called by eval-runner.sh after each task execution.

Usage:
    python3 collect-result.py --state <path> --task-id <id> --language <lang> \
        --difficulty <diff> --result <PASS|FAIL|ERROR|TIMEOUT> --duration <seconds>
"""

import argparse
import json
import os
import subprocess
import sys


def collect_result(state_path, task_id, language, difficulty, result, duration, workdir=None):
    """Extract metrics from state.json and build a task result object."""
    task_result = {
        "id": task_id,
        "language": language,
        "difficulty": difficulty,
        "result": result,
        "duration_seconds": duration,
        "final_score": None,
        "convergence": {},
        "tokens": {},
        "files_changed": [],
        "validation_output": ""
    }

    # Read state.json if available
    if state_path and os.path.isfile(state_path):
        try:
            with open(state_path, "r") as f:
                state = json.load(f)

            # Extract final score from score_history
            score_history = state.get("score_history", [])
            if score_history:
                task_result["final_score"] = score_history[-1]

            # Extract convergence data
            conv = state.get("convergence", {})
            task_result["convergence"] = {
                "total_iterations": conv.get("total_iterations", 0),
                "phase_iterations": conv.get("phase_iterations", 0),
                "convergence_state": conv.get("convergence_state", "UNKNOWN"),
                "phase": conv.get("phase", "unknown"),
                "plateau_count": conv.get("plateau_count", 0),
                "safety_gate_passed": conv.get("safety_gate_passed", False),
                "safety_gate_failures": conv.get("safety_gate_failures", 0)
            }

            # Extract token data
            tokens = state.get("tokens", {})
            task_result["tokens"] = {
                "estimated_total": tokens.get("estimated_total", 0),
                "by_stage": tokens.get("by_stage", {}),
                "by_agent": tokens.get("by_agent", {}),
                "model_distribution": tokens.get("model_distribution", {})
            }

            # Extract cost
            cost = state.get("cost", {})
            task_result["cost"] = {
                "wall_time_seconds": cost.get("wall_time_seconds", 0),
                "stages_completed": cost.get("stages_completed", 0),
                "estimated_cost_usd": cost.get("estimated_cost_usd", 0.0)
            }

        except (json.JSONDecodeError, KeyError, TypeError) as e:
            task_result["state_parse_error"] = str(e)

    # Get files changed via git diff if workdir is available
    if workdir and os.path.isdir(os.path.join(workdir, ".git")):
        try:
            proc = subprocess.run(
                ["git", "diff", "--name-only", "HEAD"],
                cwd=workdir, capture_output=True, text=True, timeout=10
            )
            if proc.returncode == 0:
                task_result["files_changed"] = [
                    f.strip() for f in proc.stdout.strip().split("\n") if f.strip()
                ]
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    return task_result


def main():
    parser = argparse.ArgumentParser(description="Collect eval result from state.json")
    parser.add_argument("--state", required=True, help="Path to .forge/state.json")
    parser.add_argument("--task-id", required=True, help="Task identifier")
    parser.add_argument("--language", required=True, help="Programming language")
    parser.add_argument("--difficulty", required=True, help="Task difficulty")
    parser.add_argument("--result", required=True, choices=["PASS", "FAIL", "ERROR", "TIMEOUT"],
                        help="Task result status")
    parser.add_argument("--duration", required=True, type=int, help="Duration in seconds")
    parser.add_argument("--workdir", default=None, help="Task working directory for git diff")

    args = parser.parse_args()

    result = collect_result(
        args.state, args.task_id, args.language,
        args.difficulty, args.result, args.duration, args.workdir
    )

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
