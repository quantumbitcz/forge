"""Cost ceiling guard for the weekly benchmark workflow.

Phase 6 contract: reads state.cost.estimated_cost_usd (field-name: pct_consumed).
Default ceiling: $200 (conservative; user DB empty at commit time — see plan header).
"""
from __future__ import annotations
from dataclasses import dataclass


class CostLimitExceeded(RuntimeError):
    pass


@dataclass
class CostGuard:
    max_weekly_cost_usd: float
    total_usd: float = 0.0

    def record(self, usd: float) -> None:
        self.total_usd += max(0.0, float(usd))

    def within_limit(self) -> bool:
        return self.total_usd < self.max_weekly_cost_usd

    def assert_within(self) -> None:
        if not self.within_limit():
            raise CostLimitExceeded(
                f"BENCH-COST-CEILING: ${self.total_usd:.2f} ≥ ${self.max_weekly_cost_usd:.2f}"
            )
