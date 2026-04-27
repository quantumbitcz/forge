"""sc-intent-missed - fg-590 must BLOCK when INTENT-MISSED is open.

Executed by tests/scenario/harness or directly via pytest.
"""
import json
from pathlib import Path


def run_scenario(fixture: dict) -> dict:
    """Simulate the fg-590 verdict logic from agents/fg-590-pre-ship-verifier.md Step 6."""
    results = fixture["intent_verification_results"]
    findings = fixture["findings"]
    iv_cfg = fixture["config"]["intent_verification"]

    verified = sum(1 for r in results if r["verdict"] == "VERIFIED")
    missed = sum(1 for r in results if r["verdict"] == "MISSED")
    partial = sum(1 for r in results if r["verdict"] == "PARTIAL")
    unverif = sum(1 for r in results if r["verdict"] == "UNVERIFIABLE")
    denom = verified + missed + partial + unverif
    verified_pct = (verified / denom * 100) if denom > 0 else None
    open_critical = sum(
        1
        for f in findings
        if f["category"] == "INTENT-MISSED" and f["severity"] == "CRITICAL"
    )

    verdict = "SHIP"
    reasons = []
    if open_critical > 0:
        verdict = "BLOCK"
        reasons.append(f"intent-missed: {open_critical} open CRITICAL INTENT-MISSED findings")
    if verified_pct is not None and verified_pct < iv_cfg["strict_ac_required_pct"]:
        verdict = "BLOCK"
        reasons.append(
            f"intent-threshold: verified {verified_pct:.2f}% < required {iv_cfg['strict_ac_required_pct']}%"
        )
    return {"verdict": verdict, "block_reasons": reasons}


def test_sc_intent_missed_blocks():
    fx = json.loads((Path(__file__).parent / "fixture.json").read_text())
    result = run_scenario(fx)
    assert result["verdict"] == "BLOCK"
    assert any("intent-missed" in r for r in result["block_reasons"])
