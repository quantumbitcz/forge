"""Corpus entry discovery and per-OS filtering.

Validates metadata.yaml against schema; emits CorpusValidationError on missing
requires_docker flag (AC-820), os_compat narrowing (AC-820), or structural drift.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, ValidationError

_SCHEMAS = Path(__file__).parent / "schemas"


class CorpusValidationError(RuntimeError):
    pass


@dataclass(frozen=True)
class CorpusEntry:
    entry_id: str
    path: Path
    requirement: str
    ac_list: list[dict[str, Any]]
    expected: dict[str, Any]
    metadata: dict[str, Any]

    @property
    def complexity(self) -> str:
        return str(self.metadata["complexity"])

    @property
    def requires_docker(self) -> bool:
        return bool(self.metadata["requires_docker"])


def _load_schema(name: str) -> Draft202012Validator:
    return Draft202012Validator(json.loads((_SCHEMAS / f"{name}.schema.json").read_text()))


def discover_corpus(corpus_root: Path, *, os: str) -> list[CorpusEntry]:
    """Discover + validate every entry, filter by os_compat."""
    meta_v = _load_schema("metadata")
    ac_v = _load_schema("acceptance_criteria")
    exp_v = _load_schema("expected_deliverables")

    out: list[CorpusEntry] = []
    if not corpus_root.is_dir():
        return out

    for entry_dir in sorted(corpus_root.iterdir()):
        if not entry_dir.is_dir() or entry_dir.name.startswith("."):
            continue
        for required in (
            "requirement.md",
            "acceptance-criteria.yaml",
            "expected-deliverables.yaml",
            "metadata.yaml",
            "seed-project.tar.gz",
        ):
            if not (entry_dir / required).exists():
                raise CorpusValidationError(f"{entry_dir.name}: missing {required}")

        try:
            meta = yaml.safe_load((entry_dir / "metadata.yaml").read_text())
            ac = yaml.safe_load((entry_dir / "acceptance-criteria.yaml").read_text())
            exp = yaml.safe_load((entry_dir / "expected-deliverables.yaml").read_text())
        except yaml.YAMLError as e:
            raise CorpusValidationError(f"{entry_dir.name}: yaml parse error: {e}") from e

        if "requires_docker" not in (meta or {}):
            raise CorpusValidationError(
                f"{entry_dir.name}: BENCH-METADATA-MISSING-DOCKER-FLAG — "
                f"metadata.yaml must declare requires_docker: true|false"
            )

        try:
            meta_v.validate(meta)
            ac_v.validate(ac)
            exp_v.validate(exp)
        except ValidationError as e:
            raise CorpusValidationError(f"{entry_dir.name}: schema violation: {e.message}") from e

        if os not in meta["os_compat"]:
            continue

        out.append(
            CorpusEntry(
                entry_id=entry_dir.name,
                path=entry_dir,
                requirement=(entry_dir / "requirement.md").read_text(encoding="utf-8"),
                ac_list=ac["ac_list"],
                expected=exp,
                metadata=meta,
            )
        )
    return out
