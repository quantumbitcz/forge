"""Regression gate — compare current week vs frozen baseline."""
from __future__ import annotations
from dataclasses import dataclass, field


@dataclass
class GateFinding:
    category: str
    severity: str
    message: str


@dataclass
class GateResult:
    passed: bool
    findings: list[GateFinding] = field(default_factory=list)


def evaluate_gate(*, current: dict, baseline: dict | None) -> GateResult:
    if baseline is None:
        return GateResult(passed=True, findings=[
            GateFinding("BENCH-NO-BASELINE", "WARNING", "baseline.json missing; gate skipped")
        ])

    threshold_pp = baseline.get("regression_threshold_pp", 10)
    warn_pp = 5
    findings: list[GateFinding] = []
    passed = True

    for cell in current["cells"]:
        model = cell["model"]
        base = baseline["baselines"].get(model)
        if base is None:
            findings.append(GateFinding("BENCH-BASELINE-MISSING-MODEL", "WARNING",
                                        f"no baseline for model {model}"))
            continue
        for bucket in ("S", "M", "L", "overall"):
            cur = cell["solve_rate_by_complexity"].get(bucket) if bucket != "overall" else cell["solve_rate_overall"]
            if cur is None:
                continue
            delta_pp = (cur - base[bucket]) * 100
            if delta_pp <= -threshold_pp:
                passed = False
                findings.append(GateFinding(
                    "BENCH-REGRESSION", "CRITICAL",
                    f"{model} {bucket}: {cur*100:.1f}% vs baseline {base[bucket]*100:.1f}% "
                    f"(Δ {delta_pp:+.1f}pp ≤ -{threshold_pp}pp)",
                ))
            elif delta_pp <= -warn_pp:
                findings.append(GateFinding(
                    "BENCH-REGRESSION", "WARNING",
                    f"{model} {bucket}: {cur*100:.1f}% vs baseline {base[bucket]*100:.1f}% (Δ {delta_pp:+.1f}pp)",
                ))
    return GateResult(passed=passed, findings=findings)
