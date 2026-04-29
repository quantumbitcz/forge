"""Phase 7 Wave 5 Task 24 — shared/intent-verification.md architectural doc."""
from pathlib import Path

DOC = Path(__file__).parent.parent.parent / "shared" / "intent-verification.md"


def test_doc_exists():
    assert DOC.exists()


def test_two_layer_isolation_explained():
    txt = DOC.read_text(encoding="utf-8")
    assert "Layer 1" in txt
    assert "Layer 2" in txt
    assert "defense-in-depth" in txt.lower()


def test_voting_gate_thresholds_present():
    txt = DOC.read_text(encoding="utf-8")
    assert "30" in txt  # cost-skip pct
    assert "trigger_on_risk_tags" in txt
