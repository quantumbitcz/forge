"""write_overrides pins all three tiers to the matrix-cell model ID."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from tests.evals.benchmark.write_forge_model_overrides import write_overrides


def test_writes_three_tier_override(tmp_path: Path) -> None:
    written = write_overrides(tmp_path, "claude-opus-4-7")
    assert written.samefile(tmp_path / ".claude" / "forge.local.md")
    raw = written.read_text(encoding="utf-8")
    # Extract YAML block from the markdown fragment
    yaml_block = raw.split("```yaml")[1].split("```")[0]
    doc = yaml.safe_load(yaml_block)
    assert doc["model_routing"]["overrides"]["fast"] == "claude-opus-4-7"
    assert doc["model_routing"]["overrides"]["standard"] == "claude-opus-4-7"
    assert doc["model_routing"]["overrides"]["premium"] == "claude-opus-4-7"


def test_refuses_to_write_in_forge_repo(tmp_path: Path) -> None:
    """Safety: must not write into the plugin's own tree or an ancestor."""
    forge_root = Path(__file__).resolve().parents[2]
    with pytest.raises(ValueError, match="refusing to write"):
        write_overrides(forge_root, "claude-sonnet-4-6")
    with pytest.raises(ValueError, match="refusing to write"):
        write_overrides(forge_root.parent, "claude-sonnet-4-6")


def test_rejects_unknown_model_id() -> None:
    with pytest.raises(ValueError, match="unknown model id"):
        write_overrides(Path("/tmp"), "not-a-real-model")
