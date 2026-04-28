"""BenchmarkResult dataclass — one JSON file per entry per matrix cell."""
from __future__ import annotations
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class BenchmarkResult:
    schema_version: int
    entry_id: str
    run_date: str
    os: str
    model: str
    complexity: str  # "S" | "M" | "L" — copied from corpus metadata.yaml at run time
    started_at: str
    ended_at: str
    duration_s: int
    solved: bool
    partial_ac_pct: float
    ac_breakdown: dict[str, str]
    unverifiable_count: int
    cost_usd: float
    pipeline_verdict: str  # SHIP | CONCERNS | FAIL | ERROR | DRY_RUN
    score: int
    convergence_iterations: int
    critical_findings: int
    warning_findings: int
    timeout: bool
    must_not_touch_violations: list[str] = field(default_factory=list)
    touched_files_actual: list[str] = field(default_factory=list)
    hook_failures_count: int = 0
    error: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def dry_run(cls, *, entry_id: str, os: str, model: str, complexity: str) -> "BenchmarkResult":
        now = _iso_now()
        today = now[:10]
        return cls(
            schema_version=1, entry_id=entry_id, run_date=today,
            os=os, model=model, complexity=complexity,
            started_at=now, ended_at=now, duration_s=0,
            solved=False, partial_ac_pct=0.0, ac_breakdown={},
            unverifiable_count=0, cost_usd=0.0, pipeline_verdict="DRY_RUN", score=0,
            convergence_iterations=0, critical_findings=0, warning_findings=0,
            timeout=False, error=None,
        )
