"""Phase 7 F36 — risk_tags producer/consumer contract documentation."""
from pathlib import Path

DOC = (Path(__file__).parent.parent.parent / "shared" / "agent-communication.md").read_text()


def test_risk_tags_producer_consumer_documented():
    assert "risk_tags Contract" in DOC
    assert "fg-200-planner" in DOC and "emits" in DOC
    assert "fg-100-orchestrator" in DOC and "reads" in DOC
    assert "impl_voting.trigger_on_risk_tags" in DOC
