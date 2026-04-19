#!/usr/bin/env python3
"""Budget ceiling alerting for the forge pipeline.

Phase 02.1: Python port of cost-alerting.sh. Uses ``hooks._py.io_utils``
for atomic state updates instead of shelling out to forge-state-write.sh.

Commands:
  init [--forge-dir PATH]                  Initialize budget tracking for run
  check [--forge-dir PATH]                 Check budget status, return alert level
  stage-report <stage> [--iteration N] [--forge-dir PATH]
                                           Emit per-stage cost summary line
  summary [--forge-dir PATH]               Full budget summary for forge-status
  apply-downgrade [--forge-dir PATH]       Write model tier override to state.json

Exit codes:
  0  = OK (below first threshold)
  1  = INFO (crossed first threshold)
  2  = WARNING (crossed second threshold)
  3  = CRITICAL (crossed third threshold)
  4  = EXCEEDED (above 100%)
  10 = disabled (cost_alerting.enabled is false)
  11 = input error
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
_PLUGIN_ROOT = _HERE.parent
if str(_PLUGIN_ROOT) not in sys.path:
    sys.path.insert(0, str(_PLUGIN_ROOT))

from hooks._py.io_utils import atomic_json_update  # noqa: E402
from shared.config_validator import extract_yaml, get_path, parse_yaml_subset  # noqa: E402

DEFAULT_BUDGET = 2_000_000
DEFAULT_THRESHOLDS = (0.50, 0.75, 0.90)

STAGE_PROPORTIONS = {
    "preflight": 0.03, "exploring": 0.07, "planning": 0.10, "validating": 0.05,
    "implementing": 0.30, "verifying": 0.15, "reviewing": 0.15,
    "documenting": 0.05, "shipping": 0.05, "learning": 0.05,
}

STAGE_ABBREV = {
    "preflight": "PRE", "exploring": "EXPL", "planning": "PLAN",
    "validating": "VALID", "implementing": "IMPL", "verifying": "VERIFY",
    "reviewing": "REVIEW", "documenting": "DOCS", "shipping": "SHIP",
    "learning": "LEARN",
}

COST_DOWNGRADE_ROUTING = {
    "fg-200-planner": "sonnet",
    "fg-300-implementer": "sonnet",
    "fg-320-frontend-polisher": "sonnet",
    "fg-412-architecture-reviewer": "sonnet",
    "fg-350-docs-generator": "haiku",
    "fg-600-pr-builder": "haiku",
    "fg-700-retrospective": "haiku",
    "fg-710-post-run": "haiku",
}


def _read_state(forge_dir: Path) -> dict[str, Any] | None:
    p = forge_dir / "state.json"
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def _read_cost_alerting_config(forge_config_dir: Path) -> dict[str, Any]:
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
    ca = get_path(data, "cost_alerting")
    return ca if isinstance(ca, dict) else {}


def cmd_init(forge_dir: Path, forge_config_dir: Path) -> int:
    if not (forge_dir / "state.json").is_file():
        print(f"ERROR: state.json not found in {forge_dir}", file=sys.stderr)
        return 11

    cfg = _read_cost_alerting_config(forge_config_dir)
    budget = int(cfg.get("budget_ceiling_tokens", DEFAULT_BUDGET))
    thresholds_raw = cfg.get("alert_thresholds")
    if isinstance(thresholds_raw, list) and len(thresholds_raw) == 3:
        thresholds = [float(x) for x in thresholds_raw]
    else:
        thresholds = list(DEFAULT_THRESHOLDS)

    per_stage_limits_cfg = cfg.get("per_stage_limits", "auto")
    if per_stage_limits_cfg == "auto" or not isinstance(per_stage_limits_cfg, dict):
        per_stage_limits: dict[str, int] = {
            stage: int(budget * proportion)
            for stage, proportion in STAGE_PROPORTIONS.items()
        }
    else:
        per_stage_limits = {k: int(v) for k, v in per_stage_limits_cfg.items()}

    def _mutate(state: dict[str, Any]) -> dict[str, Any]:
        tokens = state.setdefault("tokens", {
            "estimated_total": 0, "budget_ceiling": 0, "by_stage": {}, "by_agent": {},
        })
        tokens["budget_ceiling"] = budget
        state["cost_alerting"] = {
            "enabled": True,
            "thresholds": thresholds,
            "per_stage_limits": per_stage_limits,
            "alerts_issued": [],
            "last_alert_level": "OK",
            "routing_override": None,
        }
        return state

    atomic_json_update(forge_dir / "state.json", _mutate, default={})
    return 0


def cmd_check(forge_dir: Path) -> int:
    state = _read_state(forge_dir)
    if state is None:
        print("OK: no state.json, nothing to check")
        return 0

    ca = state.get("cost_alerting", {})
    if not ca.get("enabled", True):
        return 10

    tokens = state.get("tokens", {})
    total = int(tokens.get("estimated_total", 0))
    ceiling = int(tokens.get("budget_ceiling", 0))

    if ceiling <= 0:
        print("OK: no budget ceiling set")
        return 0

    ratio = total / ceiling
    thresholds = ca.get("thresholds", list(DEFAULT_THRESHOLDS))

    if ratio >= 1.0:
        level, exit_code = "EXCEEDED", 4
    elif len(thresholds) >= 3 and ratio >= thresholds[2]:
        level, exit_code = "CRITICAL", 3
    elif len(thresholds) >= 2 and ratio >= thresholds[1]:
        level, exit_code = "WARNING", 2
    elif len(thresholds) >= 1 and ratio >= thresholds[0]:
        level, exit_code = "INFO", 1
    else:
        level, exit_code = "OK", 0

    alerts_issued = list(ca.get("alerts_issued", []))
    new_alert = level not in alerts_issued and level != "OK"

    if new_alert:
        def _mutate(s: dict[str, Any]) -> dict[str, Any]:
            sca = s.setdefault("cost_alerting", {})
            issued = list(sca.get("alerts_issued", []))
            if level not in issued:
                issued.append(level)
            sca["alerts_issued"] = issued
            sca["last_alert_level"] = level
            return s
        atomic_json_update(forge_dir / "state.json", _mutate, default={})

    pct = int(ratio * 100)
    print(f"{level}: {pct}% of token budget used ({total:,} / {ceiling:,})")
    if new_alert:
        print(f"NEW_ALERT:{level}")
    return exit_code


def cmd_stage_report(forge_dir: Path, stage: str, iteration: str | None) -> int:
    state = _read_state(forge_dir)
    if state is None:
        print(f"[COST] {stage}: no state data")
        return 0

    stage = stage.lower()
    tokens = state.get("tokens", {})
    by_stage = tokens.get("by_stage", {})
    stage_data = by_stage.get(stage, {"input": 0, "output": 0})
    stage_tokens = int(stage_data.get("input", 0)) + int(stage_data.get("output", 0))
    total_tokens = int(tokens.get("estimated_total", 0))
    ceiling = int(tokens.get("budget_ceiling", 0))

    cost = state.get("cost", {})
    cost_usd = float(cost.get("estimated_cost_usd", 0.0))

    ca = state.get("cost_alerting", {})
    per_stage_limits = ca.get("per_stage_limits", {})
    stage_limit = int(per_stage_limits.get(stage, 0))

    budget_note = ""
    if stage_limit > 0:
        ratio = stage_tokens / stage_limit
        if ratio >= 1.5:
            budget_note = " [STAGE_OVER_BUDGET: 150%+ of expected]"
        elif ratio >= 1.0:
            budget_note = " [STAGE_AT_LIMIT]"

    if ceiling > 0:
        budget_str = f"{int(total_tokens / ceiling * 100)}% of budget"
    else:
        budget_str = "no budget set"

    label = STAGE_ABBREV.get(stage, stage.upper())

    if iteration:
        print(
            f"[COST] {label} iteration {iteration}: {stage_tokens:,} tokens "
            f"(${cost_usd:.2f}) | {budget_str} | Run total: {total_tokens:,} tokens"
            f"{budget_note}"
        )
    else:
        print(
            f"[COST] {label}: {stage_tokens:,} tokens (${cost_usd:.2f}) | "
            f"{budget_str} | Run total: {total_tokens:,} tokens{budget_note}"
        )
    return 0


def cmd_summary(forge_dir: Path) -> int:
    state = _read_state(forge_dir)
    if state is None:
        print("No state file")
        return 1

    tokens = state.get("tokens", {})
    cost = state.get("cost", {})
    ca = state.get("cost_alerting", {})

    ceiling = int(tokens.get("budget_ceiling", DEFAULT_BUDGET))
    total = int(tokens.get("estimated_total", 0))
    pct = round(total / ceiling * 100, 1) if ceiling > 0 else 0.0
    cost_usd = float(cost.get("estimated_cost_usd", 0.0))

    print(f"Budget: {total:,} / {ceiling:,} tokens ({pct}%) — Est. ${cost_usd:.2f}")
    alerts = ca.get("alerts_issued", [])
    if alerts:
        print(f"Alerts triggered: {', '.join(alerts)}")

    by_stage = tokens.get("by_stage", {})
    if by_stage:
        per_stage_costs = cost.get("per_stage", {})
        print("Per-stage:")
        for stage, data in sorted(by_stage.items()):
            stokens = int(data.get("input", 0)) + int(data.get("output", 0))
            entry = per_stage_costs.get(stage, {})
            stage_cost = float(entry.get("cost_usd", 0.0)) if isinstance(entry, dict) else 0.0
            print(f"  {stage}: {stokens:,} tokens (${stage_cost:.2f})")
    return 0


def cmd_apply_downgrade(forge_dir: Path) -> int:
    if not (forge_dir / "state.json").is_file():
        print("ERROR: state.json not found", file=sys.stderr)
        return 11

    def _mutate(state: dict[str, Any]) -> dict[str, Any]:
        ca = state.setdefault("cost_alerting", {})
        ca["routing_override"] = dict(COST_DOWNGRADE_ROUTING)
        return state

    atomic_json_update(forge_dir / "state.json", _mutate, default={})
    print("Applied cost downgrade routing override for remaining stages")
    return 0


def main(argv: list[str] | None = None) -> int:
    import os

    # Match the bash original: missing command prints "Usage: ..." (capital U)
    # to stderr and exits 11. argparse's default would be lowercase "usage:" + 2.
    args = sys.argv[1:] if argv is None else argv
    if not args:
        print(
            "Usage: cost-alerting.sh {init|check|stage-report|summary|apply-downgrade} ...",
            file=sys.stderr,
        )
        return 11

    ap = argparse.ArgumentParser(prog="cost-alerting", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    for name in ("init", "check", "summary", "apply-downgrade"):
        sp = sub.add_parser(name)
        sp.add_argument("--forge-dir", default=".forge", type=Path)

    p_stage = sub.add_parser("stage-report")
    p_stage.add_argument("stage")
    p_stage.add_argument("--iteration", default=None)
    p_stage.add_argument("--forge-dir", default=".forge", type=Path)

    args = ap.parse_args(argv)
    forge_dir = Path(args.forge_dir)
    forge_config_dir = Path(os.environ.get("FORGE_CONFIG_DIR", "."))

    if args.cmd == "init":
        return cmd_init(forge_dir, forge_config_dir)
    if args.cmd == "check":
        return cmd_check(forge_dir)
    if args.cmd == "stage-report":
        return cmd_stage_report(forge_dir, args.stage, args.iteration)
    if args.cmd == "summary":
        return cmd_summary(forge_dir)
    if args.cmd == "apply-downgrade":
        return cmd_apply_downgrade(forge_dir)
    return 11


if __name__ == "__main__":
    sys.exit(main())
