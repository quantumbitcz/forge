from datetime import datetime, timezone

from hooks._py.handoff.config import HandoffConfig
from hooks._py.handoff.triggers import (
    TriggerContext,
    TriggerDecision,
    decide_trigger,
)


def _ctx(**over) -> TriggerContext:
    defaults = dict(
        autonomous=False,
        background=False,
        model_window_tokens=200_000,
        estimated_tokens=50_000,
        last_written_at=None,
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    defaults.update(over)
    return TriggerContext(**defaults)


def test_below_soft_no_trigger():
    d = decide_trigger(_ctx(estimated_tokens=80_000), HandoffConfig())
    assert d.level is None


def test_exactly_soft_triggers_soft():
    d = decide_trigger(_ctx(estimated_tokens=100_000), HandoffConfig())  # 50% of 200K
    assert d.level == "soft"


def test_hard_triggers_hard():
    d = decide_trigger(_ctx(estimated_tokens=145_000), HandoffConfig())  # 72.5% > 70%
    assert d.level == "hard"


def test_autonomous_hard_no_pause_flag():
    d = decide_trigger(_ctx(estimated_tokens=145_000, autonomous=True), HandoffConfig())
    assert d.level == "hard"
    assert d.should_pause is False


def test_interactive_hard_requests_pause():
    d = decide_trigger(_ctx(estimated_tokens=145_000), HandoffConfig())
    assert d.should_pause is True


def test_disabled_never_triggers():
    d = decide_trigger(_ctx(estimated_tokens=180_000), HandoffConfig(enabled=False))
    assert d.level is None


def test_autonomous_mode_disabled_skips_soft_and_hard():
    cfg = HandoffConfig(autonomous_mode="disabled")
    d = decide_trigger(_ctx(estimated_tokens=180_000, autonomous=True), cfg)
    assert d.level is None


def test_autonomous_mode_milestone_only_skips_threshold_triggers():
    cfg = HandoffConfig(autonomous_mode="milestone_only")
    d = decide_trigger(_ctx(estimated_tokens=180_000, autonomous=True), cfg)
    assert d.level is None
