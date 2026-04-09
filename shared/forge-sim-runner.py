#!/usr/bin/env python3
"""Pipeline simulation runner for forge.

Reads a scenario YAML file, initializes state via forge-state.sh,
feeds each mock_event through forge-state.sh transition, captures
the trace, and compares against expected outcomes.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

import yaml


def parse_scenario(path: str) -> dict:
    """Parse a scenario YAML file."""
    with open(path) as f:
        return yaml.safe_load(f)


def run_state_cmd(state_script: str, args: list[str], forge_dir: str) -> tuple[int, str, str]:
    """Run forge-state.sh with given args, return (exit_code, stdout, stderr)."""
    cmd = ["bash", state_script] + args + ["--forge-dir", forge_dir]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def apply_fast_forward(forge_dir: str, fast_forward: dict):
    """Apply fast_forward fields directly to state.json."""
    state_file = os.path.join(forge_dir, "state.json")
    with open(state_file) as f:
        state = json.load(f)

    for key, value in fast_forward.items():
        parts = key.split(".")
        if len(parts) == 2:
            # Dotted path like convergence.phase
            parent, child = parts
            if parent not in state:
                state[parent] = {}
            # Convert types
            state[parent][child] = _convert_value(value)
        else:
            state[parts[0]] = _convert_value(value)

    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)


def _convert_value(value):
    """Convert YAML values to appropriate Python types."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        if value.lower() == "true":
            return True
        if value.lower() == "false":
            return False
        try:
            return int(value)
        except ValueError:
            try:
                return float(value)
            except ValueError:
                return value
    return value


def run_simulation(scenario: dict, state_script: str, forge_dir: str) -> dict:
    """Run a full simulation and return results."""
    name = scenario.get("name", "unnamed")
    requirement = scenario.get("requirement", "Test requirement")
    mode = scenario.get("mode", "standard")
    dry_run = scenario.get("dry_run", False)
    mock_events = scenario.get("mock_events", [])
    expected_trace = scenario.get("expected_trace", [])
    expected_counters = scenario.get("expected_counters", {})
    fast_forward = scenario.get("fast_forward", {})

    # 1. Initialize state
    init_args = ["init", "SIM-001", requirement, "--mode", mode]
    if dry_run:
        init_args.append("--dry-run")

    rc, stdout, stderr = run_state_cmd(state_script, init_args, forge_dir)
    if rc != 0:
        return {
            "pass": False,
            "name": name,
            "error": f"init failed (rc={rc}): {stderr}",
            "trace": [],
            "expected_trace": expected_trace,
        }

    # 2. Apply fast_forward if present
    if fast_forward:
        try:
            apply_fast_forward(forge_dir, fast_forward)
        except Exception as e:
            return {
                "pass": False,
                "name": name,
                "error": f"fast_forward failed: {e}",
                "trace": [],
                "expected_trace": expected_trace,
            }

    # 3. Feed each mock_event through transition
    actual_trace = []
    for i, event_spec in enumerate(mock_events):
        event = event_spec["event"]
        guards = event_spec.get("guards", {})

        trans_args = ["transition", event]
        for gk, gv in guards.items():
            trans_args.extend(["--guard", f"{gk}={gv}"])

        rc, stdout, stderr = run_state_cmd(state_script, trans_args, forge_dir)
        if rc != 0:
            return {
                "pass": False,
                "name": name,
                "error": f"event {i} ({event}) failed (rc={rc}): {stderr}\nstdout: {stdout}",
                "trace": actual_trace,
                "expected_trace": expected_trace,
            }

        # Parse transition result
        try:
            result = json.loads(stdout)
        except json.JSONDecodeError:
            return {
                "pass": False,
                "name": name,
                "error": f"event {i} ({event}) returned invalid JSON: {stdout}",
                "trace": actual_trace,
                "expected_trace": expected_trace,
            }

        prev = result.get("previous_state", "?")
        new = result.get("new_state", "?")
        actual_trace.append(f"{prev} -> {new}")

    # 4. Compare trace
    trace_match = actual_trace == expected_trace
    trace_diff = []
    if not trace_match:
        max_len = max(len(actual_trace), len(expected_trace))
        for j in range(max_len):
            actual_line = actual_trace[j] if j < len(actual_trace) else "<missing>"
            expected_line = expected_trace[j] if j < len(expected_trace) else "<extra>"
            marker = "  " if actual_line == expected_line else "!!"
            trace_diff.append(f"  {marker} [{j}] expected: {expected_line}")
            if actual_line != expected_line:
                trace_diff.append(f"  {marker} [{j}]   actual: {actual_line}")

    # 5. Compare counters
    counter_mismatches = []
    if expected_counters:
        rc, stdout, stderr = run_state_cmd(state_script, ["query"], forge_dir)
        if rc != 0:
            return {
                "pass": False,
                "name": name,
                "error": f"query failed after simulation: {stderr}",
                "trace": actual_trace,
                "expected_trace": expected_trace,
            }
        try:
            final_state = json.loads(stdout)
        except json.JSONDecodeError:
            return {
                "pass": False,
                "name": name,
                "error": f"query returned invalid JSON: {stdout}",
                "trace": actual_trace,
                "expected_trace": expected_trace,
            }

        for ck, cv in expected_counters.items():
            parts = ck.split(".")
            actual_val = final_state
            for p in parts:
                if isinstance(actual_val, dict):
                    actual_val = actual_val.get(p)
                else:
                    actual_val = None
                    break
            expected_val = _convert_value(cv)
            if actual_val != expected_val:
                counter_mismatches.append(
                    f"  {ck}: expected={expected_val}, actual={actual_val}"
                )

    # 6. Build result
    passed = trace_match and not counter_mismatches
    return {
        "pass": passed,
        "name": name,
        "trace": actual_trace,
        "expected_trace": expected_trace,
        "trace_diff": trace_diff if not trace_match else [],
        "counter_mismatches": counter_mismatches,
    }


def main():
    if len(sys.argv) < 3:
        print("Usage: forge-sim-runner.py <scenario.yaml> <state-script> [forge-dir]", file=sys.stderr)
        sys.exit(2)

    scenario_file = sys.argv[1]
    state_script = sys.argv[2]
    forge_dir_arg = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ""

    scenario = parse_scenario(scenario_file)

    # Create temp forge dir if not provided
    cleanup = False
    if forge_dir_arg:
        forge_dir = forge_dir_arg
        os.makedirs(forge_dir, exist_ok=True)
    else:
        forge_dir = tempfile.mkdtemp(prefix="forge-sim-")
        cleanup = True

    try:
        result = run_simulation(scenario, state_script, forge_dir)

        if result["pass"]:
            print(f"PASS: {result['name']}")
            print(f"  trace ({len(result['trace'])} transitions): OK")
            sys.exit(0)
        else:
            print(f"FAIL: {result['name']}")
            if result.get("error"):
                print(f"  error: {result['error']}")
            if result.get("trace_diff"):
                print("  trace mismatch:")
                for line in result["trace_diff"]:
                    print(line)
            if result.get("counter_mismatches"):
                print("  counter mismatches:")
                for line in result["counter_mismatches"]:
                    print(line)
            sys.exit(1)
    finally:
        if cleanup and os.path.isdir(forge_dir):
            shutil.rmtree(forge_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
