"""Contract: handoff config defaults and validation."""
from __future__ import annotations

import pytest

from hooks._py.handoff.config import (
    HandoffConfig,
    load_handoff_config,
    validate_handoff_config,
)


def test_defaults_match_preflight_table():
    cfg = HandoffConfig()
    assert cfg.enabled is True
    assert cfg.soft_threshold_pct == 50
    assert cfg.hard_threshold_pct == 70
    assert cfg.min_interval_minutes == 15
    assert cfg.autonomous_mode == "auto"
    assert cfg.auto_on_ship is True
    assert cfg.auto_on_escalation is True
    assert cfg.chain_limit == 50
    assert cfg.auto_memory_promotion is True
    assert cfg.mcp_expose is True


def test_hard_must_exceed_soft_by_ten():
    cfg = HandoffConfig(soft_threshold_pct=60, hard_threshold_pct=65)
    errs = validate_handoff_config(cfg)
    assert any("hard_threshold_pct" in e for e in errs)


def test_soft_below_30_rejected():
    cfg = HandoffConfig(soft_threshold_pct=25)
    errs = validate_handoff_config(cfg)
    assert any("soft_threshold_pct" in e for e in errs)


def test_autonomous_mode_enum_enforced():
    cfg = HandoffConfig(autonomous_mode="sometimes")  # type: ignore[arg-type]
    errs = validate_handoff_config(cfg)
    assert any("autonomous_mode" in e for e in errs)


def test_load_from_missing_file_returns_defaults():
    cfg = load_handoff_config(forge_config_path=None)
    assert cfg.soft_threshold_pct == 50
