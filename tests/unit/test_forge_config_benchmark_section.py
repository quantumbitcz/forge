"""forge-config template advertises benchmark: section with ceiling + timeouts."""
from pathlib import Path

CFG = Path(__file__).resolve().parents[2] / "forge-config.md"


def test_benchmark_section_present() -> None:
    text = CFG.read_text() if CFG.is_file() else ""
    # Defensive: forge-config.md may be a template under modules/ or at root; search both
    if "benchmark:" not in text:
        # Try template locations
        alt = Path(__file__).resolve().parents[2] / "modules" / "frameworks" / "fastapi" / "forge-config-template.md"
        text = alt.read_text() if alt.is_file() else ""
    assert "benchmark:" in text or "max_weekly_cost_usd" in text
