"""sc-impl-vote-cost-skip - budget <30% remaining skips voting even on LOW confidence.

Inlines the `should_vote` helper rather than importing across scenario dirs (the
on-disk dirs use dashes which are not valid Python identifiers; inlining keeps the
two scenarios self-contained per Wave 6 guidance).
"""


def should_vote(task, state, config):
    """Re-implement the gate from fg-100-orchestrator.md for the scenario test."""
    ivcfg = config.get("impl_voting", {})
    if not ivcfg.get("enabled", False):
        return False, None
    ceiling = state.get("cost", {}).get("ceiling_usd", 0.0)
    if ceiling > 0:
        remaining = state.get("cost", {}).get("remaining_usd", ceiling)
        pct = remaining / ceiling
        if pct < ivcfg.get("skip_if_budget_remaining_below_pct", 30) / 100.0:
            return False, "cost_skip"
    if state.get("confidence", {}).get("effective_confidence", 1.0) < ivcfg.get(
        "trigger_on_confidence_below", 0.4
    ):
        return True, "confidence"
    if any(t in task.get("risk_tags", []) for t in ivcfg.get("trigger_on_risk_tags", [])):
        return True, "risk_tag"
    return False, None


def test_cost_skip_at_25pct_remaining():
    task = {"id": "t1", "risk_tags": ["high"]}
    # 75% spent => 25% remaining. Threshold: 30%. Skip fires.
    state = {
        "confidence": {"effective_confidence": 0.2},  # LOW, would trigger
        "cost": {"ceiling_usd": 100.0, "remaining_usd": 25.0},  # 25% remaining
    }
    cfg = {
        "impl_voting": {
            "enabled": True,
            "trigger_on_confidence_below": 0.4,
            "trigger_on_risk_tags": ["high"],
            "skip_if_budget_remaining_below_pct": 30,
        }
    }
    vote, trig = should_vote(task, state, cfg)
    assert vote is False
    assert trig == "cost_skip"


def test_no_cost_skip_at_35pct_remaining():
    task = {"id": "t1", "risk_tags": ["high"]}
    state = {
        "confidence": {"effective_confidence": 0.9},
        "cost": {"ceiling_usd": 100.0, "remaining_usd": 35.0},
    }
    cfg = {
        "impl_voting": {
            "enabled": True,
            "trigger_on_confidence_below": 0.4,
            "trigger_on_risk_tags": ["high"],
            "skip_if_budget_remaining_below_pct": 30,
        }
    }
    vote, trig = should_vote(task, state, cfg)
    # 35% > 30% -> no cost skip. high risk tag triggers vote.
    assert vote is True
    assert trig == "risk_tag"


def test_cost_skip_ignores_zero_ceiling():
    """cost.ceiling_usd: 0 means disabled; cost-skip never fires."""
    task = {"id": "t1", "risk_tags": ["high"]}
    state = {
        "confidence": {"effective_confidence": 0.2},
        "cost": {"ceiling_usd": 0.0, "remaining_usd": 0.0},
    }
    cfg = {
        "impl_voting": {
            "enabled": True,
            "trigger_on_confidence_below": 0.4,
            "trigger_on_risk_tags": ["high"],
            "skip_if_budget_remaining_below_pct": 30,
        }
    }
    vote, _ = should_vote(task, state, cfg)
    assert vote is True  # no skip when ceiling disabled
