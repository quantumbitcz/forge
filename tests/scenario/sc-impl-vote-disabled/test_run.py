"""sc-impl-vote-disabled - impl_voting.enabled: false = no extra dispatches."""


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


def test_disabled_no_vote_on_low_confidence():
    task = {"id": "t1", "risk_tags": ["high"]}
    state = {
        "confidence": {"effective_confidence": 0.2},
        "cost": {"ceiling_usd": 100.0, "remaining_usd": 80.0},
    }
    cfg = {
        "impl_voting": {
            "enabled": False,
            "trigger_on_confidence_below": 0.4,
            "trigger_on_risk_tags": ["high"],
        }
    }
    vote, trig = should_vote(task, state, cfg)
    assert vote is False
    assert trig is None


def test_disabled_no_vote_on_high_risk():
    task = {"id": "t1", "risk_tags": ["high", "payment"]}
    state = {
        "confidence": {"effective_confidence": 0.9},
        "cost": {"ceiling_usd": 100.0, "remaining_usd": 80.0},
    }
    cfg = {"impl_voting": {"enabled": False, "trigger_on_risk_tags": ["high"]}}
    vote, _ = should_vote(task, state, cfg)
    assert vote is False
