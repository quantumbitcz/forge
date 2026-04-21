"""Pure decision function: given context + config, what trigger level (if any)?"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from hooks._py.handoff.config import HandoffConfig

TriggerLevel = Literal["soft", "hard"]


@dataclass
class TriggerContext:
    autonomous: bool
    background: bool
    model_window_tokens: int
    estimated_tokens: int
    last_written_at: datetime | None
    now: datetime


@dataclass
class TriggerDecision:
    level: TriggerLevel | None
    should_pause: bool
    reason: str
    utilisation_pct: float


def decide_trigger(ctx: TriggerContext, cfg: HandoffConfig) -> TriggerDecision:
    if not cfg.enabled:
        return TriggerDecision(None, False, "disabled", 0.0)
    if ctx.autonomous and cfg.autonomous_mode in ("disabled", "milestone_only"):
        return TriggerDecision(None, False, f"autonomous_mode={cfg.autonomous_mode}", 0.0)

    util = (ctx.estimated_tokens / ctx.model_window_tokens) * 100 if ctx.model_window_tokens else 0.0

    if util >= cfg.hard_threshold_pct:
        should_pause = not ctx.autonomous  # autonomous never pauses
        return TriggerDecision("hard", should_pause, f"context_hard_{cfg.hard_threshold_pct}pct", util)
    if util >= cfg.soft_threshold_pct:
        return TriggerDecision("soft", False, f"context_soft_{cfg.soft_threshold_pct}pct", util)
    return TriggerDecision(None, False, "below_threshold", util)
