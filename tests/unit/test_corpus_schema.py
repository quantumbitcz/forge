"""Every file in every corpus/<entry>/ validates against its schema."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "tests" / "evals" / "benchmark" / "schemas"
CORPUS = ROOT / "tests" / "evals" / "benchmark" / "corpus"


def _load(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "name",
    [
        "corpus_entry",
        "result",
        "trends_line",
        "baseline",
        "metadata",
        "acceptance_criteria",
        "expected_deliverables",
    ],
)
def test_schema_is_valid_json_schema(name: str) -> None:
    schema = _load(SCHEMAS / f"{name}.schema.json")
    Draft202012Validator.check_schema(schema)


def test_each_corpus_entry_validates() -> None:
    entry_schema = Draft202012Validator(_load(SCHEMAS / "corpus_entry.schema.json"))
    ac_schema = Draft202012Validator(_load(SCHEMAS / "acceptance_criteria.schema.json"))
    exp_schema = Draft202012Validator(_load(SCHEMAS / "expected_deliverables.schema.json"))
    meta_schema = Draft202012Validator(_load(SCHEMAS / "metadata.schema.json"))
    for entry in sorted(CORPUS.iterdir()):
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        files = {p.name for p in entry.iterdir()}
        assert {
            "requirement.md",
            "acceptance-criteria.yaml",
            "seed-project.tar.gz",
            "expected-deliverables.yaml",
            "metadata.yaml",
        } <= files, f"{entry.name} incomplete"
        entry_schema.validate({"name": entry.name, "files": sorted(files)})
        ac_schema.validate(yaml.safe_load((entry / "acceptance-criteria.yaml").read_text()))
        exp_schema.validate(yaml.safe_load((entry / "expected-deliverables.yaml").read_text()))
        meta_schema.validate(yaml.safe_load((entry / "metadata.yaml").read_text()))
