"""sc-intent-no-acs - features without ACs are unchanged from pre-F35 behavior.
living_specs.strict_mode: false (default) vacuous pass; true blocks with intent-no-acs-strict.
"""


def verify_ship_gate(state, config):
    results = state.get("intent_verification_results", [])
    findings = state.get("findings", [])
    strict = config.get("living_specs", {}).get("strict_mode", False)
    verified = sum(1 for r in results if r["verdict"] == "VERIFIED")
    partial = sum(1 for r in results if r["verdict"] == "PARTIAL")
    missed = sum(1 for r in results if r["verdict"] == "MISSED")
    unverif = sum(1 for r in results if r["verdict"] == "UNVERIFIABLE")
    denom = verified + partial + missed + unverif
    verified_pct = (verified / denom * 100) if denom > 0 else None
    open_critical = sum(
        1
        for f in findings
        if f["category"] == "INTENT-MISSED" and f["severity"] == "CRITICAL"
    )
    reasons = []
    if open_critical > 0:
        reasons.append("intent-missed")
    if verified_pct is None and strict:
        reasons.append("intent-no-acs-strict")
    elif (
        verified_pct is not None
        and verified_pct < config["intent_verification"]["strict_ac_required_pct"]
    ):
        reasons.append("intent-threshold")
    return ("BLOCK" if reasons else "SHIP"), reasons


def test_no_acs_non_strict_ships():
    state = {"intent_verification_results": [], "findings": []}
    cfg = {
        "intent_verification": {"strict_ac_required_pct": 100},
        "living_specs": {"strict_mode": False},
    }
    verdict, reasons = verify_ship_gate(state, cfg)
    assert verdict == "SHIP"
    assert reasons == []


def test_no_acs_strict_blocks():
    state = {"intent_verification_results": [], "findings": []}
    cfg = {
        "intent_verification": {"strict_ac_required_pct": 100},
        "living_specs": {"strict_mode": True},
    }
    verdict, reasons = verify_ship_gate(state, cfg)
    assert verdict == "BLOCK"
    assert "intent-no-acs-strict" in reasons
