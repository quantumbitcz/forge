from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_pipeline_readme_see_also() -> None:
    text = (ROOT / "tests" / "evals" / "pipeline" / "README.md").read_text()
    assert "tests/evals/benchmark" in text


def test_observability_mentions_benchmark_spans() -> None:
    text = (ROOT / "shared" / "observability.md").read_text()
    assert "forge.benchmark.run" in text
    for attr in ("entry_id", "os", "model", "solved", "duration_s", "cost_usd"):
        assert f"forge.benchmark.{attr}" in text


def test_learnings_readme_lists_benchmark_regression() -> None:
    assert "benchmark.regression" in (ROOT / "shared" / "learnings" / "README.md").read_text()
