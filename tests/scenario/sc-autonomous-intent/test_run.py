"""sc-autonomous-intent - autonomous: true must never produce AskUserQuestion from fg-540 or fg-302."""
import re
from pathlib import Path


AGENT_540 = (
    Path(__file__).parent.parent.parent.parent / "agents" / "fg-540-intent-verifier.md"
).read_text()
AGENT_302 = (
    Path(__file__).parent.parent.parent.parent / "agents" / "fg-302-diff-judge.md"
).read_text()


def test_fg540_has_ask_false():
    m = re.search(r"^ui:\s*\n(?:  .*\n)+", AGENT_540, re.MULTILINE)
    assert m
    assert "ask: false" in m.group(0)


def test_fg302_has_ask_false():
    m = re.search(r"^ui:\s*\n(?:  .*\n)+", AGENT_302, re.MULTILINE)
    assert m
    assert "ask: false" in m.group(0)


def test_fg540_body_has_no_askuserquestion():
    """The agent body itself must not invoke AskUserQuestion as part of its workflow."""
    assert "AskUserQuestion" not in AGENT_540 or "Never AskUserQuestion" in AGENT_540


def test_fg302_body_has_no_askuserquestion():
    assert "AskUserQuestion" not in AGENT_302
