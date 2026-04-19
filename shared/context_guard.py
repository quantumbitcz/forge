#!/usr/bin/env python3
"""Context degradation guard for the forge pipeline.

Phase 02.1: Python port of context-guard.sh. Uses ``hooks._py.io_utils``
for atomic state updates instead of shelling out to forge-state-write.sh.

Commands:
  check <estimated_tokens> [--forge-dir PATH]  Check size, trigger condensation if needed
  metrics [--forge-dir PATH]                   Report context metrics for this run

Exit codes:
  0  = OK (below threshold)
  1  = CONDENSED (forced condensation, proceeding)
  2  = CRITICAL (repeated exceedances, recommend task decomposition)
  10 = disabled (context_guard.enabled is false)
  11 = input error
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

# Make sibling Python modules importable when invoked directly or via -m.
_HERE = Path(__file__).resolve().parent
_PLUGIN_ROOT = _HERE.parent
if str(_PLUGIN_ROOT) not in sys.path:
    sys.path.insert(0, str(_PLUGIN_ROOT))

from hooks._py.io_utils import atomic_json_update  # noqa: E402
from shared.config_validator import extract_yaml, get_path, parse_yaml_subset  # noqa: E402

DEFAULT_CONDENSATION_THRESHOLD = 30000
DEFAULT_CRITICAL_THRESHOLD = 50000
DEFAULT_MAX_TRIGGERS = 5


def _read_state(forge_dir: Path) -> dict[str, Any] | None:
    state_path = forge_dir / "state.json"
    if not state_path.is_file():
        return None
    import json
    try:
        return json.loads(state_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def _read_context_guard_config(forge_config_dir: Path) -> dict[str, Any]:
    cfg_path = forge_config_dir / "forge-config.md"
    if not cfg_path.is_file():
        return {}
    yaml_text = extract_yaml(cfg_path)
    if not yaml_text:
        return {}
    try:
        data = parse_yaml_subset(yaml_text)
    except Exception:
        return {}
    cg = get_path(data, "context_guard")
    return cg if isinstance(cg, dict) else {}


def cmd_check(forge_dir: Path, estimated: int, forge_config_dir: Path) -> int:
    state = _read_state(forge_dir)
    if state is None:
        print("OK: no state.json")
        return 0

    cg_cfg = _read_context_guard_config(forge_config_dir)
    if cg_cfg.get("enabled") is False:
        return 10

    cond_threshold = int(cg_cfg.get("condensation_threshold", DEFAULT_CONDENSATION_THRESHOLD))
    crit_threshold = int(cg_cfg.get("critical_threshold", DEFAULT_CRITICAL_THRESHOLD))
    max_triggers = int(cg_cfg.get("max_condensation_triggers", DEFAULT_MAX_TRIGGERS))

    def _mutate(current: dict[str, Any]) -> dict[str, Any]:
        ctx = current.setdefault("context", {
            "peak_tokens": 0,
            "condensation_triggers": 0,
            "per_stage_peak": {},
            "last_estimated_tokens": 0,
            "guard_checks": 0,
        })
        ctx["guard_checks"] = ctx.get("guard_checks", 0) + 1
        ctx["last_estimated_tokens"] = estimated
        if estimated > ctx.get("peak_tokens", 0):
            ctx["peak_tokens"] = estimated

        stage = str(current.get("story_state", "unknown")).lower()
        per_stage = ctx.setdefault("per_stage_peak", {})
        if estimated > per_stage.get(stage, 0):
            per_stage[stage] = estimated

        if estimated >= crit_threshold or estimated >= cond_threshold:
            ctx["condensation_triggers"] = ctx.get("condensation_triggers", 0) + 1
        return current

    atomic_json_update(forge_dir / "state.json", _mutate, default={})

    # Re-read to compute the exit signal & message based on post-mutation state.
    state_after = _read_state(forge_dir) or {}
    triggers = state_after.get("context", {}).get("condensation_triggers", 0)

    if estimated >= crit_threshold:
        if triggers >= max_triggers:
            print(f"CRITICAL: context exceeded {crit_threshold} tokens {triggers} times")
            print("Recommend breaking work into smaller tasks")
            return 2
        print(f"CONDENSED: context at {estimated} tokens (critical: {crit_threshold})")
        return 1
    if estimated >= cond_threshold:
        if triggers >= max_triggers:
            print(f"CRITICAL: condensation triggered {triggers} times this run")
            print("Recommend breaking work into smaller tasks")
            return 2
        print(f"CONDENSED: context at {estimated} tokens (threshold: {cond_threshold})")
        return 1

    print(f"OK: context at {estimated} tokens")
    return 0


def cmd_metrics(forge_dir: Path) -> int:
    state = _read_state(forge_dir)
    if state is None:
        print("No context metrics available")
        return 0
    ctx = state.get("context", {})
    print(f"peak_tokens: {ctx.get('peak_tokens', 0)}")
    print(f"condensation_triggers: {ctx.get('condensation_triggers', 0)}")
    print(f"last_estimated_tokens: {ctx.get('last_estimated_tokens', 0)}")
    print(f"guard_checks: {ctx.get('guard_checks', 0)}")
    stages = ctx.get("per_stage_peak", {})
    if stages:
        print("per_stage_peak:")
        for s, v in stages.items():
            print(f"  {s}: {v}")
    return 0


def main(argv: list[str] | None = None) -> int:
    import os

    ap = argparse.ArgumentParser(prog="context-guard", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_check = sub.add_parser("check")
    p_check.add_argument("estimated_tokens", type=int)
    p_check.add_argument("--forge-dir", default=".forge", type=Path)

    p_metrics = sub.add_parser("metrics")
    p_metrics.add_argument("--forge-dir", default=".forge", type=Path)

    args = ap.parse_args(argv)
    forge_dir = Path(args.forge_dir)
    forge_config_dir = Path(os.environ.get("FORGE_CONFIG_DIR", "."))

    if args.cmd == "check":
        return cmd_check(forge_dir, args.estimated_tokens, forge_config_dir)
    if args.cmd == "metrics":
        return cmd_metrics(forge_dir)
    return 11


if __name__ == "__main__":
    sys.exit(main())
