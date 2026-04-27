"""Phase 7 Wave 1 Task 4 — preflight-constraints.md documents intent_verification + impl_voting."""

from __future__ import annotations

from pathlib import Path

SRC_PATH = (
    Path(__file__).parent.parent.parent
    / "shared"
    / "preflight-constraints.md"
)
SRC = SRC_PATH.read_text(encoding="utf-8")


def test_intent_verification_keys_documented():
    for key in (
        "strict_ac_required_pct",
        "max_probes_per_ac",
        "probe_timeout_seconds",
        "probe_tier",
        "allow_runtime_probes",
        "forbidden_probe_hosts",
    ):
        assert f"intent_verification.{key}" in SRC, (
            f"missing intent_verification.{key} in preflight-constraints.md"
        )


def test_impl_voting_keys_documented():
    for key in (
        "trigger_on_confidence_below",
        "trigger_on_risk_tags",
        "trigger_on_regression_history_days",
        "samples",
        "tiebreak_required",
        "skip_if_budget_remaining_below_pct",
    ):
        assert f"impl_voting.{key}" in SRC, (
            f"missing impl_voting.{key} in preflight-constraints.md"
        )
