"""Phase 7 Wave 5 Task 25 — mode-overlay frontmatter for intent + voting."""
import re
from pathlib import Path

MODES_DIR = Path(__file__).parent.parent.parent / "shared" / "modes"


def _load_frontmatter(name: str) -> str:
    text = (MODES_DIR / name).read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    assert m, f"no frontmatter in {name}"
    return m.group(1)


def test_bootstrap_disables_intent_and_voting():
    fm = _load_frontmatter("bootstrap.md")
    assert "intent_verification:" in fm
    assert "enabled: false" in fm.split("intent_verification:")[1][:80]
    assert "impl_voting:" in fm


def test_migration_disables_intent():
    fm = _load_frontmatter("migration.md")
    assert "intent_verification:" in fm


def test_bugfix_extends_risk_tags():
    fm = _load_frontmatter("bugfix.md")
    assert "\"bugfix\"" in fm or "'bugfix'" in fm
    assert "trigger_on_risk_tags" in fm
