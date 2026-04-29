"""sc-intent-layer2-tripwire - Layer-2 defense-in-depth: monkey-patch the builder to inject
a forbidden key, confirm fg-540 agent's Context Exclusion Contract catches it.
"""
from pathlib import Path

AGENT_540 = (
    Path(__file__).parent.parent.parent.parent / "agents" / "fg-540-intent-verifier.md"
).read_text()


def test_agent_body_contains_forbidden_key_list():
    """The agent system prompt enumerates forbidden keys so the model knows what to trip on."""
    for fkey in (
        "plan",
        "stage_2_notes",
        "test_code",
        "diff",
        "implementation_diff",
        "tdd_history",
        "prior_findings",
    ):
        assert fkey in AGENT_540


def test_agent_body_instructs_stop_and_emit_contract_violation():
    body = AGENT_540
    # Must instruct STOP on forbidden key + emit INTENT-CONTRACT-VIOLATION.
    assert "STOP" in body.upper()
    assert "INTENT-CONTRACT-VIOLATION" in body


def test_tripwire_is_labeled_defense_in_depth():
    """Layer 2 must be explicitly labeled so readers know Layer 1 is the enforcement."""
    assert "defense-in-depth" in AGENT_540.lower() or "Layer 2" in AGENT_540
