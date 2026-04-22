"""Handoff configuration loading and validation."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

from shared.config_validator import extract_yaml, get_path, parse_yaml_subset

AutonomousMode = Literal["auto", "milestone_only", "disabled"]


@dataclass
class HandoffConfig:
    enabled: bool = True
    soft_threshold_pct: int = 50
    hard_threshold_pct: int = 70
    min_interval_minutes: int = 15
    autonomous_mode: AutonomousMode = "auto"
    auto_on_ship: bool = True
    auto_on_escalation: bool = True
    chain_limit: int = 50
    auto_memory_promotion: bool = True
    mcp_expose: bool = True


def validate_handoff_config(cfg: HandoffConfig) -> list[str]:
    errs: list[str] = []
    if not (30 <= cfg.soft_threshold_pct <= 80):
        errs.append(f"soft_threshold_pct must be 30-80, got {cfg.soft_threshold_pct}")
    if cfg.hard_threshold_pct > 95:
        errs.append(f"hard_threshold_pct must be <=95, got {cfg.hard_threshold_pct}")
    if cfg.hard_threshold_pct < cfg.soft_threshold_pct + 10:
        errs.append(
            f"hard_threshold_pct ({cfg.hard_threshold_pct}) must exceed "
            f"soft_threshold_pct ({cfg.soft_threshold_pct}) by at least 10"
        )
    if not (1 <= cfg.min_interval_minutes <= 60):
        errs.append(f"min_interval_minutes must be 1-60, got {cfg.min_interval_minutes}")
    if cfg.autonomous_mode not in ("auto", "milestone_only", "disabled"):
        errs.append(f"autonomous_mode must be auto|milestone_only|disabled, got {cfg.autonomous_mode!r}")
    if not (5 <= cfg.chain_limit <= 500):
        errs.append(f"chain_limit must be 5-500, got {cfg.chain_limit}")
    return errs


def load_handoff_config(forge_config_path: Path | None) -> HandoffConfig:
    if forge_config_path is None or not forge_config_path.is_file():
        return HandoffConfig()
    yaml_text = extract_yaml(forge_config_path)
    if not yaml_text:
        return HandoffConfig()
    try:
        data = parse_yaml_subset(yaml_text)
    except Exception:
        return HandoffConfig()
    raw: Any = get_path(data, "handoff")
    if not isinstance(raw, dict):
        return HandoffConfig()
    defaults = HandoffConfig()
    return HandoffConfig(
        enabled=bool(raw.get("enabled", defaults.enabled)),
        soft_threshold_pct=int(raw.get("soft_threshold_pct", defaults.soft_threshold_pct)),
        hard_threshold_pct=int(raw.get("hard_threshold_pct", defaults.hard_threshold_pct)),
        min_interval_minutes=int(raw.get("min_interval_minutes", defaults.min_interval_minutes)),
        autonomous_mode=raw.get("autonomous_mode", defaults.autonomous_mode),
        auto_on_ship=bool(raw.get("auto_on_ship", defaults.auto_on_ship)),
        auto_on_escalation=bool(raw.get("auto_on_escalation", defaults.auto_on_escalation)),
        chain_limit=int(raw.get("chain_limit", defaults.chain_limit)),
        auto_memory_promotion=bool(raw.get("auto_memory_promotion", defaults.auto_memory_promotion)),
        mcp_expose=bool(raw.get("mcp_expose", defaults.mcp_expose)),
    )
