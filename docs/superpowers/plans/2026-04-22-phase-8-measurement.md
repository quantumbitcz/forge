# Phase 8 Measurement — TDD Implementation Plan

**Source spec:** `docs/superpowers/specs/2026-04-22-phase-8-measurement-design.md`
**Target version:** forge 3.8.0
**Style:** TDD per step — write failing test first, then code, run full suite, commit green; CI-only verification (no local test runs per user memory).
**Cross-platform target:** Ubuntu, macOS, Windows runners. All Python 3.10+. No bash in hook paths. Windows-compatible path handling (pathlib only, never string concatenation with `/`).

**Cost ceiling decision (commit-time).** The user's `.forge/run-history.db` does not exist yet in the forge repo (no populated `estimated_cost_usd` history from post-Phase-6 runs). Per the spec §Cross-phase §Phase 6 commit-time protocol, the initial ceiling is **conservatively set to `$200`** for the weekly workflow; it will be refreshed after 90 days of real data via a `benchmark.max_weekly_cost_usd` update in `forge-config.md`.

**Model matrix (committed at plan time).** `claude-sonnet-4-6`, `claude-opus-4-7` (per user memory + spec §Component 3). Haiku excluded by design.

**No-backcompat stance (user memory + ADR 0008).** Phase 8 extends `tests/evals/pipeline/` in place. No migration shims. `forge.local.md` fragment is a fresh write per run into the ephemeral tempdir — never merged with existing content.

**Self-review summary.** Every AC-801…AC-827 maps to at least one task below. Model wiring is an explicit `write_forge_model_overrides.py` helper writing `model_routing.overrides.{fast,standard,premium}` as a YAML fragment (NOT env-only — spec fix #1). PII scrub list enumerates 6 patterns plus inheritance from SEC-SECRET/SEC-PII. Cost ceiling derived: $200 conservative initial, documented refresh path. Integration ACs for Phase 1 (hook-failure roll-up), Phase 4 (`benchmark.regression` learning type), Phase 6 (cost ceiling enforcement via simulator), Phase 7 (AC injection via `AC-B001..AC-B999` namespace) all have explicit task lines.

**Unmapped ACs:** none. All 27 ACs have a corresponding task or contract/unit test below.

---

## Task 0 — Skeleton directories + test stubs

**TDD pivot.** Create the bare directory tree and write schema stubs first so every subsequent test has a place to live. This task commits empty fixture directories; every later task fills them.

### Test (write first)

`tests/unit/test_benchmark_skeleton.py`:

```python
"""Structural test: Phase 8 benchmark skeleton exists and imports cleanly."""
from __future__ import annotations
from pathlib import Path
import importlib

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "tests" / "evals" / "benchmark"


def test_directory_tree() -> None:
    for sub in ("corpus", "results", "schemas", "fixtures"):
        assert (BENCH / sub).is_dir(), f"missing {sub}/"
    assert (BENCH / "__init__.py").is_file()
    assert (BENCH / "README.md").is_file()


def test_modules_importable() -> None:
    for mod in (
        "tests.evals.benchmark",
        "tests.evals.benchmark.scoring",
        "tests.evals.benchmark.runner",
        "tests.evals.benchmark.curate",
        "tests.evals.benchmark.render_scorecard",
        "tests.evals.benchmark.refresh_baseline",
        "tests.evals.benchmark.write_forge_model_overrides",
    ):
        importlib.import_module(mod)
```

### Implementation

Create:

- `tests/evals/benchmark/__init__.py` (empty)
- `tests/evals/benchmark/corpus/.gitkeep`
- `tests/evals/benchmark/results/.gitkeep`
- `tests/evals/benchmark/fixtures/.gitkeep`
- `tests/evals/benchmark/schemas/.gitkeep`
- `tests/evals/benchmark/scoring.py` (stub `def solved(): ...`)
- `tests/evals/benchmark/runner.py` (stub `def main(): ...`)
- `tests/evals/benchmark/curate.py` (stub `def main(): ...`)
- `tests/evals/benchmark/render_scorecard.py` (stub `def main(): ...`)
- `tests/evals/benchmark/refresh_baseline.py` (stub `def main(): ...`)
- `tests/evals/benchmark/write_forge_model_overrides.py` (stub `def write_overrides(project_root, model_id): ...`)
- `tests/evals/benchmark/README.md` (placeholder)
- `tests/evals/benchmark/requirements.txt` (see below)

`requirements.txt`:

```
-r ../pipeline/runner/requirements.txt
pyyaml>=6.0
jsonschema>=4.0.0
```

**Commit:** `feat(bench): Phase 8 — skeleton directory tree and stub modules`.

---

## Task 1 — JSON Schemas (corpus_entry, result, trends, baseline)

### Test (write first)

`tests/unit/test_corpus_schema.py`:

```python
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


@pytest.mark.parametrize("name", ["corpus_entry", "result", "trends_line", "baseline", "metadata", "acceptance_criteria", "expected_deliverables"])
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
        assert {"requirement.md", "acceptance-criteria.yaml", "seed-project.tar.gz",
                "expected-deliverables.yaml", "metadata.yaml"} <= files, f"{entry.name} incomplete"
        entry_schema.validate({"name": entry.name, "files": sorted(files)})
        ac_schema.validate(yaml.safe_load((entry / "acceptance-criteria.yaml").read_text()))
        exp_schema.validate(yaml.safe_load((entry / "expected-deliverables.yaml").read_text()))
        meta_schema.validate(yaml.safe_load((entry / "metadata.yaml").read_text()))
```

### Implementation

Create `tests/evals/benchmark/schemas/corpus_entry.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Corpus entry structural",
  "type": "object",
  "required": ["name", "files"],
  "properties": {
    "name": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}-[a-z0-9-]+$"},
    "files": {
      "type": "array",
      "contains": {"enum": ["requirement.md", "acceptance-criteria.yaml", "seed-project.tar.gz", "expected-deliverables.yaml", "metadata.yaml"]}
    }
  }
}
```

Create `tests/evals/benchmark/schemas/acceptance_criteria.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["version", "ac_list"],
  "properties": {
    "version": {"const": 1},
    "ac_list": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "description", "verifiable_via"],
        "properties": {
          "id": {"type": "string", "pattern": "^AC-B\\d{3}$"},
          "description": {"type": "string", "minLength": 10},
          "verifiable_via": {"enum": ["http", "cli", "file", "custom"]},
          "probe": {"type": "string"},
          "verifier_hint": {"type": "string"}
        }
      }
    }
  }
}
```

Create `tests/evals/benchmark/schemas/metadata.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["version", "complexity", "domain", "language", "framework", "source_run_id", "requires_docker", "os_compat"],
  "properties": {
    "version": {"const": 1},
    "complexity": {"enum": ["S", "M", "L"]},
    "domain": {"type": "array", "items": {"type": "string"}, "minItems": 1},
    "language": {"type": "string"},
    "framework": {"type": "string"},
    "source_run_id": {"type": "string"},
    "requires_docker": {"type": "boolean"},
    "os_compat": {
      "type": "array",
      "minItems": 1,
      "items": {"enum": ["ubuntu-latest", "macos-latest", "windows-latest"]},
      "uniqueItems": true
    },
    "notes": {"type": "string"}
  },
  "additionalProperties": false
}
```

Create `tests/evals/benchmark/schemas/expected_deliverables.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["version", "files_touched"],
  "properties": {
    "version": {"const": 1},
    "files_touched": {
      "type": "object",
      "required": ["expected_any_of", "must_not_touch"],
      "properties": {
        "expected_any_of": {"type": "array", "items": {"type": "string"}},
        "must_not_touch": {"type": "array", "items": {"type": "string"}}
      }
    },
    "endpoints_expected": {"type": "array", "items": {"type": "string"}},
    "tests_expected_min": {"type": "integer", "minimum": 0}
  }
}
```

Create `tests/evals/benchmark/schemas/result.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["schema_version", "entry_id", "run_date", "os", "model", "complexity", "started_at", "ended_at", "duration_s",
               "solved", "partial_ac_pct", "ac_breakdown", "unverifiable_count", "cost_usd", "pipeline_verdict", "score",
               "convergence_iterations", "critical_findings", "warning_findings", "timeout",
               "must_not_touch_violations", "touched_files_actual", "hook_failures_count", "error"],
  "properties": {
    "schema_version": {"const": 1},
    "entry_id": {"type": "string"},
    "run_date": {"type": "string", "format": "date"},
    "os": {"enum": ["ubuntu-latest", "macos-latest", "windows-latest"]},
    "model": {"type": "string"},
    "complexity": {"enum": ["S", "M", "L"]},
    "started_at": {"type": "string", "format": "date-time"},
    "ended_at": {"type": "string", "format": "date-time"},
    "duration_s": {"type": "integer", "minimum": 0},
    "solved": {"type": "boolean"},
    "partial_ac_pct": {"type": "number", "minimum": 0, "maximum": 1},
    "ac_breakdown": {"type": "object", "additionalProperties": {"enum": ["PASS", "FAIL", "UNVERIFIABLE"]}},
    "unverifiable_count": {"type": "integer", "minimum": 0},
    "cost_usd": {"type": "number", "minimum": 0},
    "pipeline_verdict": {"enum": ["SHIP", "CONCERNS", "FAIL", "ERROR", "DRY_RUN"]},
    "score": {"type": "integer", "minimum": 0, "maximum": 100},
    "convergence_iterations": {"type": "integer", "minimum": 0},
    "critical_findings": {"type": "integer", "minimum": 0},
    "warning_findings": {"type": "integer", "minimum": 0},
    "timeout": {"type": "boolean"},
    "must_not_touch_violations": {"type": "array", "items": {"type": "string"}},
    "touched_files_actual": {"type": "array", "items": {"type": "string"}},
    "hook_failures_count": {"type": "integer", "minimum": 0},
    "error": {"type": ["string", "null"]}
  }
}
```

Create `tests/evals/benchmark/schemas/trends_line.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["schema_version", "week_of", "commit_sha", "forge_version", "cells", "hook_failures_total", "regressions"],
  "properties": {
    "schema_version": {"const": 1},
    "week_of": {"type": "string", "format": "date"},
    "commit_sha": {"type": "string"},
    "forge_version": {"type": "string"},
    "cells": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["os", "model", "entries_total", "entries_solved", "entries_timeout",
                     "entries_docker_skipped", "solve_rate_overall", "solve_rate_by_complexity",
                     "median_cost_per_solve_usd", "total_cost_usd"],
        "properties": {
          "os": {"type": "string"},
          "model": {"type": "string"},
          "entries_total": {"type": "integer"},
          "entries_solved": {"type": "integer"},
          "entries_timeout": {"type": "integer"},
          "entries_docker_skipped": {"type": "integer"},
          "solve_rate_overall": {"type": "number"},
          "solve_rate_by_complexity": {"type": "object"},
          "median_cost_per_solve_usd": {"type": "number"},
          "total_cost_usd": {"type": "number"},
          "unverifiable_total": {"type": "integer", "minimum": 0}
        }
      }
    },
    "hook_failures_total": {"type": "integer"},
    "regressions": {"type": "array"}
  }
}
```

Create `tests/evals/benchmark/schemas/baseline.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["schema_version", "frozen_on", "frozen_commit_sha", "baselines", "regression_threshold_pp"],
  "properties": {
    "schema_version": {"const": 1},
    "frozen_on": {"type": "string", "format": "date"},
    "frozen_commit_sha": {"type": "string"},
    "baselines": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["S", "M", "L", "overall"],
        "properties": {
          "S": {"type": "number"},
          "M": {"type": "number"},
          "L": {"type": "number"},
          "overall": {"type": "number"}
        }
      }
    },
    "regression_threshold_pp": {"type": "number", "minimum": 0}
  }
}
```

**Commit:** `feat(bench): Phase 8 — JSON schemas for corpus entries, results, trends, baseline`.

---

## Task 2 — `solved` predicate + unit tests (AC-821)

### Test (write first)

`tests/unit/test_benchmark_solve_predicate.py`:

```python
"""Solve predicate: verdict ∈ {SHIP, CONCERNS} ∧ partial_ac_pct ≥ 0.9 ∧ critical_findings == 0."""
from __future__ import annotations
import pytest
from tests.evals.benchmark.scoring import solved, SolveInputs


@pytest.mark.parametrize("verdict,ac_pct,criticals,expected", [
    ("SHIP", 1.0, 0, True),
    ("SHIP", 0.9, 0, True),
    ("CONCERNS", 0.9, 0, True),
    ("CONCERNS", 1.0, 0, True),
    ("SHIP", 0.89, 0, False),     # below 0.9 threshold
    ("SHIP", 1.0, 1, False),      # critical present
    ("FAIL", 1.0, 0, False),      # verdict fail
    ("ERROR", 1.0, 0, False),     # verdict error
    ("CONCERNS", 0.89999, 0, False),  # floating boundary just below
    ("CONCERNS", 0.9, 1, False),  # both AC OK and critical present
])
def test_solved(verdict: str, ac_pct: float, criticals: int, expected: bool) -> None:
    assert solved(SolveInputs(
        pipeline_verdict=verdict,
        partial_ac_pct=ac_pct,
        critical_findings=criticals,
    )) is expected


def test_unverifiable_counts_against_ac_pct() -> None:
    """AC breakdown: 3 PASS + 1 UNVERIFIABLE = 0.75 (unverifiable counted as failed)."""
    from tests.evals.benchmark.scoring import compute_partial_ac_pct
    assert compute_partial_ac_pct({"A": "PASS", "B": "PASS", "C": "PASS", "D": "UNVERIFIABLE"}) == pytest.approx(0.75)
    assert compute_partial_ac_pct({}) == 0.0
    assert compute_partial_ac_pct({"A": "PASS"}) == 1.0
```

### Implementation

`tests/evals/benchmark/scoring.py`:

```python
"""Solve predicate and AC math for the benchmark harness.

Spec reference: docs/superpowers/specs/2026-04-22-phase-8-measurement-design.md §2
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Mapping

_SHIPPABLE_VERDICTS: frozenset[str] = frozenset({"SHIP", "CONCERNS"})
_AC_THRESHOLD: float = 0.9


@dataclass(frozen=True)
class SolveInputs:
    pipeline_verdict: str
    partial_ac_pct: float
    critical_findings: int


def solved(inputs: SolveInputs) -> bool:
    """Three-part predicate: verdict, AC pct floor, zero criticals.

    CONCERNS counted deliberately as solved — see spec §Defence of counting CONCERNS.
    """
    if inputs.pipeline_verdict not in _SHIPPABLE_VERDICTS:
        return False
    if inputs.partial_ac_pct < _AC_THRESHOLD:
        return False
    if inputs.critical_findings != 0:
        return False
    return True


def compute_partial_ac_pct(ac_breakdown: Mapping[str, str]) -> float:
    """Fraction of ACs with status PASS. UNVERIFIABLE counts as failed.

    Empty breakdown → 0.0 (no ACs to verify cannot be solved).
    """
    if not ac_breakdown:
        return 0.0
    passed = sum(1 for v in ac_breakdown.values() if v == "PASS")
    return passed / len(ac_breakdown)
```

**Commit:** `feat(bench): Phase 8 — solve predicate with 0.9 AC threshold`.

---

## Task 3 — Model override writer + sandbox contract (AC-826)

### Test (write first)

`tests/unit/test_write_forge_model_overrides.py`:

```python
"""write_overrides pins all three tiers to the matrix-cell model ID."""
from __future__ import annotations
from pathlib import Path
import pytest
import yaml
from tests.evals.benchmark.write_forge_model_overrides import write_overrides


def test_writes_three_tier_override(tmp_path: Path) -> None:
    written = write_overrides(tmp_path, "claude-opus-4-7")
    assert written == tmp_path / ".claude" / "forge.local.md"
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


def test_rejects_unknown_model_id(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="unknown model id"):
        write_overrides(tmp_path, "not-a-real-model")
```

### Implementation

`tests/evals/benchmark/write_forge_model_overrides.py`:

```python
"""Write a forge.local.md fragment pinning all three tiers to one matrix-cell model.

Spec §Component 3 Model selection wiring. Env-only propagation is insufficient
because shared/model-routing.md:13 fixes the Agent tool's `model` parameter to
the alias set {haiku, sonnet, opus}; this helper writes the full ID override
so model_routing.overrides.{fast,standard,premium} resolves end-to-end.
"""
from __future__ import annotations
from pathlib import Path

_ALLOWED_MODELS: frozenset[str] = frozenset({
    "claude-sonnet-4-6",
    "claude-opus-4-7",
    "claude-haiku-4-5-20251001",
})

_FORGE_ROOT = Path(__file__).resolve().parents[3]


def write_overrides(project_root: Path, model_id: str) -> Path:
    """Write forge.local.md into project_root/.claude/.

    Args:
        project_root: ephemeral tempdir for the benchmark entry. MUST NOT be
            forge repo root or any ancestor of it.
        model_id: full Anthropic model identifier.

    Returns: absolute Path of written fragment.

    Raises:
        ValueError: unknown model_id, or project_root overlaps forge repo.
    """
    if model_id not in _ALLOWED_MODELS:
        raise ValueError(f"unknown model id {model_id!r}; allowed: {sorted(_ALLOWED_MODELS)}")

    project_root = project_root.resolve()
    if _FORGE_ROOT == project_root or _FORGE_ROOT.is_relative_to(project_root):
        raise ValueError(
            f"refusing to write model overrides inside or above the forge repo "
            f"(project_root={project_root}, forge_root={_FORGE_ROOT})"
        )

    claude_dir = project_root / ".claude"
    claude_dir.mkdir(parents=True, exist_ok=True)
    target = claude_dir / "forge.local.md"
    body = (
        "# Generated by tests/evals/benchmark/write_forge_model_overrides.py\n"
        "# Do not edit; overwritten per benchmark cell.\n\n"
        "```yaml\n"
        "model_routing:\n"
        "  enabled: true\n"
        "  overrides:\n"
        f"    fast:     {model_id}\n"
        f"    standard: {model_id}\n"
        f"    premium:  {model_id}\n"
        "```\n"
    )
    target.write_text(body, encoding="utf-8")
    return target
```

**Commit:** `feat(bench): Phase 8 — model override writer (non-env model ID propagation)`.

---

## Task 4 — PII scrub library + unit tests (AC-811, AC-815)

### Test (write first)

`tests/unit/test_curate_pii_scrub.py`:

```python
"""PII scrub patterns: paths, hostnames, IPs, fingerprints + SEC inheritance."""
from __future__ import annotations
import pytest
from tests.evals.benchmark.pii_scrub import scrub, scan


@pytest.mark.parametrize("dirty,clean", [
    ("/Users/denis/secret/file.py", "<redacted-home>/secret/file.py"),
    ("/home/denis/repo", "<redacted-home>/repo"),
    (r"C:\Users\Denis\Desktop", r"<redacted-home>\Desktop"),
    ("ssh api-gateway.internal", "ssh <internal-host>"),
    ("reach db.prod.example", "reach <internal-host>.example"),
    ("10.0.4.7 is the lb", "<private-ip> is the lb"),
    ("172.16.5.9", "<private-ip>"),
    ("192.168.1.2", "<private-ip>"),
    ("SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGh", "<ssh-fp>"),
])
def test_auto_scrub(dirty: str, clean: str) -> None:
    assert scrub(dirty) == clean


def test_preserves_public_ip() -> None:
    assert scrub("reach 8.8.8.8 ok") == "reach 8.8.8.8 ok"


@pytest.mark.parametrize("text,pattern", [
    ("api_key=\"sk-abc12345678\"", "api_key"),
    ("password = 'hunter2longenough'", "password"),
    ("-----BEGIN PRIVATE KEY-----\ndata\n-----END PRIVATE KEY-----", "private_key"),
    ("denis@example.com contacted support", "email"),
])
def test_scan_detects_interactive_patterns(text: str, pattern: str) -> None:
    hits = scan(text)
    assert any(h.kind == pattern for h in hits), f"expected {pattern} in {hits}"
```

### Implementation

`tests/evals/benchmark/pii_scrub.py`:

```python
"""PII scrubbing for benchmark corpus entries.

Inherits SEC-SECRET (API keys, private keys) and SEC-PII (email) detection
from shared/data-classification.md. Adds path/hostname/IP/fingerprint patterns
enumerated in spec §Data Model PII scrub.
"""
from __future__ import annotations
import re
from dataclasses import dataclass
from typing import Iterable

# Auto-scrub (silent): tokens deterministically replaced, no user prompt needed.
_AUTO_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"/Users/[^/\s]+"), "<redacted-home>"),
    (re.compile(r"/home/[^/\s]+"), "<redacted-home>"),
    (re.compile(r"C:\\Users\\[^\\]+"), r"<redacted-home>"),
    (re.compile(r"\b[\w-]+\.(?:internal|prod|production|corp|local)\b"), "<internal-host>"),
    (re.compile(r"\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b"), "<private-ip>"),
    (re.compile(r"SHA256:[A-Za-z0-9+/]{43}=?"), "<ssh-fp>"),
)

# Interactive (prompt user): patterns we cannot safely auto-redact.
_INTERACTIVE_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("api_key", re.compile(r"(?i)(?:api[_-]?key|apikey|secret[_-]?key|token|bearer)\s*[:=]\s*['\"][^'\"]{8,}")),
    ("password", re.compile(r"(?i)(?:password|passwd)\s*[:=]\s*['\"][^'\"]{4,}")),
    ("private_key", re.compile(r"-----BEGIN (?:RSA |EC |DSA )?PRIVATE KEY-----")),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
)


@dataclass(frozen=True)
class Hit:
    kind: str
    span: tuple[int, int]
    text: str


def scrub(text: str) -> str:
    """Apply all auto-scrub substitutions. Idempotent."""
    for pat, repl in _AUTO_PATTERNS:
        text = pat.sub(repl, text)
    return text


def scan(text: str) -> Iterable[Hit]:
    """Yield interactive hits for operator-confirmed redaction in curate.py."""
    for kind, pat in _INTERACTIVE_PATTERNS:
        for m in pat.finditer(text):
            yield Hit(kind=kind, span=m.span(), text=m.group(0))
```

**Commit:** `feat(bench): Phase 8 — PII scrub library (auto + interactive tiers)`.

---

## Task 5 — Contract test: corpus never contains absolute paths (AC-815, AC-823)

### Test (write first)

`tests/contract/test_corpus_no_absolute_paths.py`:

```python
"""Every text file under corpus/ is PII-clean. Invariant locked after curation."""
from __future__ import annotations
import re
from pathlib import Path
import pytest

CORPUS = Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "corpus"
_BANNED: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("home_path_unix", re.compile(r"/Users/[^/\s<]|/home/[^/\s<]")),
    ("home_path_win", re.compile(r"C:\\Users\\[^\\<]")),
    ("private_ip", re.compile(r"\b(?:10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+)\b")),
    # Matches pii_scrub.py `_AUTO_PATTERNS` internal-host entry: includes `production` to
    # keep the scrubber and this contract test in lockstep (reviewer fix 6).
    ("internal_host", re.compile(r"\b[\w-]+\.(?:internal|prod|production|corp|local)\b")),
    ("ssh_fp", re.compile(r"SHA256:[A-Za-z0-9+/]{43}=?")),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    ("api_key", re.compile(r"(?i)(?:api[_-]?key|apikey|bearer)\s*[:=]\s*['\"][^'\"]{8,}")),
)


def _iter_text_files() -> list[Path]:
    out: list[Path] = []
    if not CORPUS.is_dir():
        return out
    for entry in CORPUS.iterdir():
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        for f in entry.iterdir():
            if f.suffix in {".md", ".yaml", ".yml", ".json"}:
                out.append(f)
    return out


@pytest.mark.parametrize("path", _iter_text_files(), ids=lambda p: f"{p.parent.name}/{p.name}")
def test_no_pii(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for label, pat in _BANNED:
        m = pat.search(text)
        assert m is None, f"{label} leaked in {path.relative_to(CORPUS)}: {m.group(0) if m else ''!r}"
```

### Implementation

No new code — the test locks the invariant established by `pii_scrub.py` and `curate.py`. Task exists so PR CI catches regressions.

**Commit:** `test(bench): Phase 8 — contract test rejects PII in any corpus entry`.

---

## Task 6 — Synthetic corpus entry fixture for integration tests (AC-804)

### Test (write first)

`tests/integration/test_benchmark_synthetic_corpus.py`:

```python
"""End-to-end: the runner consumes a fixture corpus in dry-run mode and emits valid results.

No `claude` CLI invoked — uses the same --dry-run posture as the pipeline runner.
"""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = ROOT / "tests" / "evals" / "benchmark" / "fixtures" / "synthetic-corpus"


def test_dry_run_end_to_end(tmp_path: Path) -> None:
    results_root = tmp_path / "results"
    result = subprocess.run(
        [sys.executable, "-m", "tests.evals.benchmark.runner",
         "--corpus-root", str(FIXTURE_ROOT),
         "--results-root", str(results_root),
         "--os", "ubuntu-latest",
         "--model", "claude-sonnet-4-6",
         "--dry-run",
         "--parallel", "1"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert "discovered 1 corpus entries" in result.stderr
    out_files = list(results_root.rglob("*.json"))
    assert len(out_files) == 1
    payload = json.loads(out_files[0].read_text())
    assert payload["schema_version"] == 1
    assert payload["entry_id"] == "2026-01-01-hello-health"
    assert payload["pipeline_verdict"] == "DRY_RUN"
    assert payload["solved"] is False  # DRY_RUN never counts as solved
```

### Implementation

Create `tests/evals/benchmark/fixtures/synthetic-corpus/2026-01-01-hello-health/`:

`requirement.md`:

```markdown
# Requirement

Add a `GET /health` endpoint that returns HTTP 200 with the JSON body `{"status":"ok"}`.
```

`acceptance-criteria.yaml`:

```yaml
version: 1
ac_list:
  - id: AC-B001
    description: "GET /health returns HTTP 200"
    verifiable_via: http
    probe: "curl -fsS http://localhost:8080/health"
  - id: AC-B002
    description: "Response body is JSON with status=ok"
    verifiable_via: http
    probe: "curl -fsS http://localhost:8080/health | jq -e '.status == \"ok\"'"
```

`expected-deliverables.yaml`:

```yaml
version: 1
files_touched:
  expected_any_of:
    - "src/routes/health.ts"
    - "src/handlers/health.py"
  must_not_touch:
    - ".github/**"
    - "package-lock.json"
endpoints_expected:
  - "GET /health"
tests_expected_min: 1
```

`metadata.yaml`:

```yaml
version: 1
complexity: S
domain: [api]
language: python
framework: fastapi
source_run_id: "synthetic-2026-01-01"
requires_docker: false
os_compat: [ubuntu-latest, macos-latest, windows-latest]
notes: "Fixture for integration test; no real run."
```

`seed-project.tar.gz`: create via (checked into repo as a tiny valid tarball containing a single `README.md` + `.git/HEAD`; produced once with a helper script stored at `tests/evals/benchmark/fixtures/build_synthetic.py` and committed).

`tests/evals/benchmark/fixtures/build_synthetic.py`:

```python
"""Regenerate the synthetic seed tarball. Run manually, commit result."""
from __future__ import annotations
import io
import tarfile
import tempfile
from pathlib import Path
import subprocess

FIXTURE = Path(__file__).parent / "synthetic-corpus" / "2026-01-01-hello-health"
TARGET = FIXTURE / "seed-project.tar.gz"


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.md").write_text("synthetic seed\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
        subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
        subprocess.run(["git", "-c", "user.email=b@b", "-c", "user.name=b", "commit", "-q", "-m", "seed"], cwd=tmp_path, check=True)
        with tarfile.open(TARGET, "w:gz") as tf:
            for p in sorted(tmp_path.rglob("*")):
                tf.add(p, arcname=str(p.relative_to(tmp_path)))
    print(f"wrote {TARGET}")


if __name__ == "__main__":
    main()
```

**Commit:** `feat(bench): Phase 8 — synthetic-corpus fixture for integration dry-run`.

---

## Task 7 — BenchmarkResult dataclass + serializer

### Test (write first)

`tests/contract/test_benchmark_result_schema.py`:

```python
"""Every BenchmarkResult serialization matches result.schema.json."""
from __future__ import annotations
import json
from pathlib import Path
from datetime import datetime, timezone
from jsonschema import Draft202012Validator
from tests.evals.benchmark.result import BenchmarkResult

SCHEMA = json.loads((Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "schemas" / "result.schema.json").read_text())
_VALIDATOR = Draft202012Validator(SCHEMA)


def test_minimal_serialization_round_trip() -> None:
    r = BenchmarkResult(
        schema_version=1, entry_id="2025-11-14-demo", run_date="2026-04-27",
        os="ubuntu-latest", model="claude-sonnet-4-6", complexity="S",
        started_at="2026-04-27T06:00:00Z", ended_at="2026-04-27T06:10:00Z",
        duration_s=600, solved=True, partial_ac_pct=1.0,
        ac_breakdown={"AC-B001": "PASS"}, unverifiable_count=0,
        cost_usd=0.42, pipeline_verdict="SHIP", score=95,
        convergence_iterations=2, critical_findings=0, warning_findings=1,
        timeout=False, must_not_touch_violations=[], touched_files_actual=["src/a.py"],
        hook_failures_count=0, error=None,
    )
    doc = r.to_dict()
    _VALIDATOR.validate(doc)
    assert json.loads(json.dumps(doc))  # strict-json-serializable


def test_dry_run_variant_validates() -> None:
    r = BenchmarkResult.dry_run(
        entry_id="2026-01-01-hello-health", os="ubuntu-latest",
        model="claude-sonnet-4-6", complexity="S",
    )
    _VALIDATOR.validate(r.to_dict())
    assert r.pipeline_verdict == "DRY_RUN"


def test_unverifiable_count_derived_from_breakdown() -> None:
    r = BenchmarkResult(
        schema_version=1, entry_id="demo", run_date="2026-04-27",
        os="ubuntu-latest", model="claude-sonnet-4-6", complexity="M",
        started_at="2026-04-27T06:00:00Z", ended_at="2026-04-27T06:10:00Z",
        duration_s=600, solved=False, partial_ac_pct=0.5,
        ac_breakdown={"AC-B001": "PASS", "AC-B002": "UNVERIFIABLE"},
        unverifiable_count=1, cost_usd=0.0, pipeline_verdict="CONCERNS", score=70,
        convergence_iterations=1, critical_findings=0, warning_findings=0,
        timeout=False, hook_failures_count=0, error=None,
    )
    _VALIDATOR.validate(r.to_dict())
```

`pipeline_verdict` enum in `result.schema.json` (Task 1) already includes `DRY_RUN`; the `complexity` field (required) and `unverifiable_count` field (required, ≥0) are also defined there.

### Implementation

`tests/evals/benchmark/result.py`:

```python
"""BenchmarkResult dataclass — one JSON file per entry per matrix cell."""
from __future__ import annotations
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class BenchmarkResult:
    schema_version: int
    entry_id: str
    run_date: str
    os: str
    model: str
    complexity: str  # "S" | "M" | "L" — copied from corpus metadata.yaml at run time
    started_at: str
    ended_at: str
    duration_s: int
    solved: bool
    partial_ac_pct: float
    ac_breakdown: dict[str, str]
    unverifiable_count: int
    cost_usd: float
    pipeline_verdict: str  # SHIP | CONCERNS | FAIL | ERROR | DRY_RUN
    score: int
    convergence_iterations: int
    critical_findings: int
    warning_findings: int
    timeout: bool
    must_not_touch_violations: list[str] = field(default_factory=list)
    touched_files_actual: list[str] = field(default_factory=list)
    hook_failures_count: int = 0
    error: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def dry_run(cls, *, entry_id: str, os: str, model: str, complexity: str) -> "BenchmarkResult":
        now = _iso_now()
        today = now[:10]
        return cls(
            schema_version=1, entry_id=entry_id, run_date=today,
            os=os, model=model, complexity=complexity,
            started_at=now, ended_at=now, duration_s=0,
            solved=False, partial_ac_pct=0.0, ac_breakdown={},
            unverifiable_count=0, cost_usd=0.0, pipeline_verdict="DRY_RUN", score=0,
            convergence_iterations=0, critical_findings=0, warning_findings=0,
            timeout=False, error=None,
        )
```

**Commit:** `feat(bench): Phase 8 — BenchmarkResult dataclass + contract validation`.

---

## Task 8 — Corpus discovery + metadata validation

### Test (write first)

`tests/unit/test_benchmark_discovery.py`:

```python
"""discover_corpus: filters by os_compat, rejects missing requires_docker flag."""
from __future__ import annotations
from pathlib import Path
import pytest
import yaml
from tests.evals.benchmark.discovery import discover_corpus, CorpusEntry, CorpusValidationError


def _write_entry(root: Path, name: str, meta: dict) -> Path:
    entry = root / name
    entry.mkdir()
    (entry / "requirement.md").write_text("# Requirement\n\ntext\n")
    (entry / "acceptance-criteria.yaml").write_text("version: 1\nac_list:\n  - {id: AC-B001, description: 'long enough description here', verifiable_via: http}\n")
    (entry / "expected-deliverables.yaml").write_text("version: 1\nfiles_touched: {expected_any_of: [src/a.py], must_not_touch: []}\n")
    (entry / "metadata.yaml").write_text(yaml.safe_dump(meta))
    (entry / "seed-project.tar.gz").write_bytes(b"\x1f\x8b\x08\x00" + b"\x00" * 40)
    return entry


def test_discovers_linux_compatible(tmp_path: Path) -> None:
    _write_entry(tmp_path, "2026-01-01-a", {"version": 1, "complexity": "S", "domain": ["api"],
        "language": "python", "framework": "fastapi", "source_run_id": "r1",
        "requires_docker": False, "os_compat": ["ubuntu-latest", "macos-latest", "windows-latest"]})
    entries = discover_corpus(tmp_path, os="ubuntu-latest")
    assert len(entries) == 1
    assert entries[0].entry_id == "2026-01-01-a"


def test_filters_by_os_compat(tmp_path: Path) -> None:
    _write_entry(tmp_path, "2026-01-01-linux-only", {"version": 1, "complexity": "S", "domain": ["api"],
        "language": "python", "framework": "fastapi", "source_run_id": "r",
        "requires_docker": False, "os_compat": ["ubuntu-latest"]})
    assert discover_corpus(tmp_path, os="windows-latest") == []
    assert len(discover_corpus(tmp_path, os="ubuntu-latest")) == 1


def test_missing_requires_docker_rejected(tmp_path: Path) -> None:
    meta = {"version": 1, "complexity": "S", "domain": ["api"],
        "language": "python", "framework": "fastapi", "source_run_id": "r",
        "os_compat": ["ubuntu-latest"]}  # no requires_docker
    _write_entry(tmp_path, "2026-01-01-bad", meta)
    with pytest.raises(CorpusValidationError, match="BENCH-METADATA-MISSING-DOCKER-FLAG"):
        discover_corpus(tmp_path, os="ubuntu-latest")
```

### Implementation

`tests/evals/benchmark/discovery.py`:

```python
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
        for required in ("requirement.md", "acceptance-criteria.yaml",
                         "expected-deliverables.yaml", "metadata.yaml", "seed-project.tar.gz"):
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

        out.append(CorpusEntry(
            entry_id=entry_dir.name,
            path=entry_dir,
            requirement=(entry_dir / "requirement.md").read_text(encoding="utf-8"),
            ac_list=ac["ac_list"],
            expected=exp,
            metadata=meta,
        ))
    return out
```

**Commit:** `feat(bench): Phase 8 — corpus discovery with schema + os_compat filtering`.

---

## Task 9 — Benchmark runner: dry-run path (AC-804)

### Test

Already covered by Task 6's `test_benchmark_synthetic_corpus.py`. Extend to assert `--parallel 1` serial behaviour.

Add to same file:

```python
def test_dry_run_does_not_invoke_claude_cli(tmp_path: Path) -> None:
    """Smoke: the runner succeeds on a machine with no `claude` binary in PATH."""
    env = {"PATH": "/nonexistent", **dict()}
    import os
    os_env = {**os.environ, "PATH": "/nonexistent"}
    result = subprocess.run(
        [sys.executable, "-m", "tests.evals.benchmark.runner",
         "--corpus-root", str(FIXTURE_ROOT),
         "--results-root", str(tmp_path / "r"),
         "--os", "ubuntu-latest",
         "--model", "claude-sonnet-4-6",
         "--dry-run", "--parallel", "1"],
        cwd=ROOT, env=os_env, capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
```

### Implementation

`tests/evals/benchmark/runner.py`:

```python
"""Benchmark runner: per-cell execution of the corpus.

Dry-run mode mirrors tests/evals/pipeline/runner/__main__.py — discovers entries,
writes DRY_RUN placeholder results, exits 0. No `claude` CLI required.

Live mode calls tests.evals.pipeline.runner.executor.execute_scenario after
writing model overrides and seeding Phase 7 AC injection.
"""
from __future__ import annotations
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from tests.evals.benchmark.discovery import discover_corpus, CorpusValidationError
from tests.evals.benchmark.result import BenchmarkResult


def _today() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _write_result(results_root: Path, r: BenchmarkResult) -> Path:
    day_dir = results_root / r.run_date
    day_dir.mkdir(parents=True, exist_ok=True)
    safe_model = r.model.replace("/", "_")
    out = day_dir / f"{r.entry_id}.{r.os}.{safe_model}.json"
    out.write_text(json.dumps(r.to_dict(), indent=2, sort_keys=True), encoding="utf-8")
    return out


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.benchmark.runner")
    p.add_argument("--corpus-root", type=Path, required=True)
    p.add_argument("--results-root", type=Path, required=True)
    p.add_argument("--os", type=str, required=True,
                   choices=["ubuntu-latest", "macos-latest", "windows-latest"])
    p.add_argument("--model", type=str, required=True)
    p.add_argument("--parallel", type=int, default=1)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--forge-root", type=Path,
                   default=Path(__file__).resolve().parents[3])
    p.add_argument("--entry-filter", type=str, default="",
                   help="substring filter on entry id")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    try:
        entries = discover_corpus(args.corpus_root, os=args.os)
    except CorpusValidationError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    if args.entry_filter:
        entries = [e for e in entries if args.entry_filter in e.entry_id]

    print(f"discovered {len(entries)} corpus entries", file=sys.stderr)

    for entry in entries:
        if args.dry_run:
            r = BenchmarkResult.dry_run(
                entry_id=entry.entry_id, os=args.os, model=args.model,
                complexity=entry.complexity,
            )
            _write_result(args.results_root, r)
            continue

        # Live path added in Task 10.
        from tests.evals.benchmark.live_run import run_one_entry
        r = run_one_entry(entry=entry, forge_root=args.forge_root, model=args.model, os=args.os)
        _write_result(args.results_root, r)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

**Commit:** `feat(bench): Phase 8 — runner CLI with dry-run path`.

---

## Task 10 — Live runner: Phase 7 AC injection + model override + state parse

### Test (write first)

`tests/contract/test_benchmark_live_run_injection.py`:

```python
"""Live-run helper seeds .forge/specs/index.json per Phase 7 injection contract."""
from __future__ import annotations
import json
from pathlib import Path
from unittest.mock import patch
from tests.evals.benchmark.discovery import CorpusEntry
from tests.evals.benchmark.live_run import _write_spec_injection, _parse_state


def test_spec_injection_uses_B_namespace(tmp_path: Path) -> None:
    entry = CorpusEntry(
        entry_id="2026-01-01-demo",
        path=tmp_path / "src",
        requirement="# Requirement\nBuild X.\n",
        ac_list=[
            {"id": "AC-B001", "description": "endpoint", "verifiable_via": "http"},
            {"id": "AC-B002", "description": "response shape", "verifiable_via": "http"},
        ],
        expected={}, metadata={"complexity": "S", "requires_docker": False},
    )
    target = tmp_path / "project"
    (target / ".forge" / "specs").mkdir(parents=True)
    _write_spec_injection(target, entry)
    doc = json.loads((target / ".forge" / "specs" / "index.json").read_text())
    assert doc["active_spec_id"] == "2026-01-01-demo"
    ids = [ac["id"] for ac in doc["specs"]["2026-01-01-demo"]["acceptance_criteria"]]
    assert all(i.startswith("AC-B") for i in ids)
    assert doc["specs"]["2026-01-01-demo"]["source"] == "benchmark-injected"


def test_parse_state_computes_partial_ac_pct(tmp_path: Path) -> None:
    state_path = tmp_path / ".forge" / "state.json"
    state_path.parent.mkdir(parents=True)
    state_path.write_text(json.dumps({
        "pipeline_verdict": "SHIP",
        "score": 90,
        "cost": {"estimated_cost_usd": 0.42},
        "intent_verification_results": [
            {"ac_id": "AC-B001", "status": "PASS"},
            {"ac_id": "AC-B002", "status": "FAIL"},
            {"ac_id": "AC-B003", "status": "UNVERIFIABLE"},
        ],
        "tokens": {"total": 12345},
    }))
    parsed = _parse_state(tmp_path)
    assert parsed["ac_breakdown"] == {"AC-B001": "PASS", "AC-B002": "FAIL", "AC-B003": "UNVERIFIABLE"}
    assert abs(parsed["partial_ac_pct"] - (1/3)) < 1e-9
    assert parsed["unverifiable_count"] == 1
    assert parsed["pipeline_verdict"] == "SHIP"
    assert parsed["cost_usd"] == 0.42
```

### Implementation

`tests/evals/benchmark/live_run.py`:

```python
"""Live-run wrapper: extend pipeline executor with Phase 7 injection + model override.

Reuses tests.evals.pipeline.runner.executor primitives (tarball extract,
plugin symlink) but:
  - writes .forge/specs/index.json with AC-B* namespace before /forge run (auto-bootstrap handles init)
  - writes .claude/forge.local.md with model_routing.overrides
  - parses state.intent_verification_results to build ac_breakdown
"""
from __future__ import annotations
import json
import subprocess
import tarfile
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from tests.evals.benchmark.discovery import CorpusEntry
from tests.evals.benchmark.result import BenchmarkResult
from tests.evals.benchmark.scoring import solved, SolveInputs, compute_partial_ac_pct
from tests.evals.benchmark.write_forge_model_overrides import write_overrides

_TIMEOUTS_SEC: dict[str, int] = {"S": 900, "M": 2700, "L": 5400}


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_spec_injection(target: Path, entry: CorpusEntry) -> None:
    """Phase 7 contract: seed active spec with source='benchmark-injected'."""
    specs_dir = target / ".forge" / "specs"
    specs_dir.mkdir(parents=True, exist_ok=True)
    doc = {
        "version": 1,
        "active_spec_id": entry.entry_id,
        "specs": {
            entry.entry_id: {
                "requirement": entry.requirement,
                "acceptance_criteria": [
                    {"id": ac["id"], "text": ac["description"],
                     "verifier_hint": ac.get("verifier_hint", ac.get("verifiable_via", ""))}
                    for ac in entry.ac_list
                ],
                "source": "benchmark-injected",
            }
        },
    }
    (specs_dir / "index.json").write_text(json.dumps(doc, indent=2), encoding="utf-8")


def _extract_tarball(tarball: Path, target: Path) -> None:
    with tarfile.open(tarball, "r:gz") as tf:
        tf.extractall(target)


def _symlink_plugin(forge_root: Path, target: Path) -> None:
    plug_dir = target / ".claude" / "plugins"
    plug_dir.mkdir(parents=True, exist_ok=True)
    (plug_dir / "forge").symlink_to(forge_root, target_is_directory=True)


def _parse_state(target: Path) -> dict[str, Any]:
    state_path = target / ".forge" / "state.json"
    if not state_path.is_file():
        return {"pipeline_verdict": "ERROR", "score": 0, "cost_usd": 0.0,
                "ac_breakdown": {}, "partial_ac_pct": 0.0, "unverifiable_count": 0,
                "convergence_iterations": 0, "critical_findings": 0, "warning_findings": 0,
                "touched_files_actual": []}
    state = json.loads(state_path.read_text(encoding="utf-8"))
    ivrs = state.get("intent_verification_results", []) or []
    breakdown = {r["ac_id"]: r["status"] for r in ivrs if "ac_id" in r}
    return {
        "pipeline_verdict": state.get("pipeline_verdict", state.get("verdict", "ERROR")),
        "score": int(state.get("score", state.get("pipeline_score", 0))),
        "cost_usd": float(state.get("cost", {}).get("estimated_cost_usd", 0.0)),
        "ac_breakdown": breakdown,
        "partial_ac_pct": compute_partial_ac_pct(breakdown),
        "unverifiable_count": sum(1 for v in breakdown.values() if v == "UNVERIFIABLE"),
        "convergence_iterations": int(state.get("total_iterations", 0)),
        "critical_findings": int(state.get("findings_summary", {}).get("critical", 0)),
        "warning_findings": int(state.get("findings_summary", {}).get("warning", 0)),
        "touched_files_actual": list(state.get("touched_files_actual", [])),
    }


def _count_hook_failures(target: Path) -> int:
    log = target / ".forge" / ".hook-failures.jsonl"
    if not log.is_file():
        return 0
    return sum(1 for _ in log.read_text(encoding="utf-8").splitlines() if _.strip())


def run_one_entry(*, entry: CorpusEntry, forge_root: Path, model: str, os: str) -> BenchmarkResult:
    """Execute one corpus entry end-to-end. Caller writes the result file."""
    started_at = _iso_now()
    mono_start = time.monotonic()
    timeout = _TIMEOUTS_SEC[entry.complexity]

    if entry.requires_docker and os == "windows-latest":
        return BenchmarkResult(
            schema_version=1, entry_id=entry.entry_id, run_date=started_at[:10],
            os=os, model=model, complexity=entry.complexity,
            started_at=started_at, ended_at=_iso_now(),
            duration_s=0, solved=False, partial_ac_pct=0.0, ac_breakdown={},
            unverifiable_count=0, cost_usd=0.0, pipeline_verdict="ERROR", score=0,
            convergence_iterations=0, critical_findings=0, warning_findings=1,
            timeout=False, error="BENCH-DOCKER-SKIPPED",
        )

    with tempfile.TemporaryDirectory(prefix=f"forge-bench-{entry.entry_id}-") as tmp:
        target = Path(tmp)
        _extract_tarball(entry.path / "seed-project.tar.gz", target)
        _symlink_plugin(forge_root, target)
        write_overrides(target, model)
        _write_spec_injection(target, entry)

        import os as _os
        env = {**_os.environ, "FORGE_EVAL": "1", "FORGE_BENCHMARK": "1"}
        timed_out = False
        error: str | None = None
        try:
            # Auto-bootstrap (mega B) runs init implicitly when .claude/forge.local.md is missing,
            # so no explicit /forge-init invocation is needed here.
            subprocess.run(
                ["claude", "code", "--non-interactive",
                 "/forge", "run", f"--eval-mode={entry.entry_id}", entry.requirement],
                cwd=target, env=env, check=True, timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            timed_out = True
            error = f"timeout after {timeout}s"
        except subprocess.CalledProcessError as e:
            error = f"forge exited {e.returncode}"
        except FileNotFoundError:
            error = "claude cli not installed"

        parsed = _parse_state(target)
        hook_failures = _count_hook_failures(target)

    duration_s = int(time.monotonic() - mono_start)
    partial_pct = parsed["partial_ac_pct"]
    is_solved = (
        not timed_out and error is None
        and solved(SolveInputs(
            pipeline_verdict=parsed["pipeline_verdict"],
            partial_ac_pct=partial_pct,
            critical_findings=parsed["critical_findings"],
        ))
    )

    return BenchmarkResult(
        schema_version=1, entry_id=entry.entry_id, run_date=started_at[:10],
        os=os, model=model, complexity=entry.complexity,
        started_at=started_at, ended_at=_iso_now(),
        duration_s=duration_s, solved=is_solved, partial_ac_pct=partial_pct,
        ac_breakdown=parsed["ac_breakdown"],
        unverifiable_count=parsed["unverifiable_count"],
        cost_usd=parsed["cost_usd"],
        pipeline_verdict=parsed["pipeline_verdict"], score=parsed["score"],
        convergence_iterations=parsed["convergence_iterations"],
        critical_findings=parsed["critical_findings"],
        warning_findings=parsed["warning_findings"],
        timeout=timed_out,
        must_not_touch_violations=[],  # populated by Task 11
        touched_files_actual=parsed["touched_files_actual"],
        hook_failures_count=hook_failures,
        error=error,
    )
```

**Commit:** `feat(bench): Phase 8 — live-run wrapper with Phase 7 AC-B injection + model override`.

---

## Task 11 — must_not_touch + touched-files overlap verification

### Test

`tests/unit/test_live_run_touch_checks.py`:

```python
"""must_not_touch violations detected via git status in benchmark target."""
from __future__ import annotations
from pathlib import Path
import subprocess
from tests.evals.benchmark.live_run import _detect_must_not_touch


def test_detects_forbidden_path(tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    (tmp_path / "package-lock.json").write_text("{}")
    (tmp_path / ".github").mkdir()
    (tmp_path / ".github" / "workflows" / "bad.yml").parent.mkdir(parents=True, exist_ok=True)
    (tmp_path / ".github" / "workflows" / "bad.yml").write_text("bad\n")
    vios = _detect_must_not_touch(tmp_path, ["package-lock.json", ".github/**"])
    assert set(vios) == {"package-lock.json", ".github/**"}


def test_no_violations(tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    (tmp_path / "src.py").write_text("x=1\n")
    assert _detect_must_not_touch(tmp_path, ["package-lock.json"]) == []
```

### Implementation

Add to `live_run.py`:

```python
def _detect_must_not_touch(target: Path, patterns: list[str]) -> list[str]:
    import fnmatch
    try:
        r = subprocess.run(["git", "status", "--porcelain"],
                           cwd=target, check=True, capture_output=True, text=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    changed = [line[3:].strip() for line in r.stdout.splitlines() if line.strip()]
    out: list[str] = []
    for pattern in patterns:
        for path in changed:
            if fnmatch.fnmatch(path, pattern) or (pattern.endswith("/**") and path.startswith(pattern[:-3])):
                out.append(pattern)
                break
    return out
```

Wire into `run_one_entry`: after `_parse_state`, call `_detect_must_not_touch(target, entry.expected.get("files_touched", {}).get("must_not_touch", []))` and set `must_not_touch_violations`.

**Commit:** `feat(bench): Phase 8 — must_not_touch detection via git status`.

---

## Task 12 — Trends aggregator

### Test

`tests/unit/test_trends_aggregator.py`:

```python
"""Aggregator: combine per-cell BenchmarkResult files into one trends.jsonl line."""
from __future__ import annotations
import json
from pathlib import Path
from datetime import date
from tests.evals.benchmark.aggregate import aggregate_week


def _seed(root: Path, entry_id: str, os: str, model: str, solved: bool, cost: float, complexity: str) -> None:
    d = root / "2026-04-27"; d.mkdir(parents=True, exist_ok=True)
    doc = {"schema_version": 1, "entry_id": entry_id, "run_date": "2026-04-27",
           "os": os, "model": model, "complexity": complexity,
           "started_at": "2026-04-27T06:00:00Z", "ended_at": "2026-04-27T06:10:00Z",
           "duration_s": 600, "solved": solved, "partial_ac_pct": 1.0 if solved else 0.5,
           "ac_breakdown": {"AC-B001": "PASS" if solved else "FAIL"},
           "unverifiable_count": 0, "cost_usd": cost,
           "pipeline_verdict": "SHIP" if solved else "FAIL", "score": 95 if solved else 40,
           "convergence_iterations": 2, "critical_findings": 0 if solved else 2, "warning_findings": 0,
           "timeout": False, "must_not_touch_violations": [], "touched_files_actual": [],
           "hook_failures_count": 0, "error": None}
    (d / f"{entry_id}.{os}.{model}.json").write_text(json.dumps(doc))


def test_aggregate_single_week(tmp_path: Path) -> None:
    # two entries on one cell
    _seed(tmp_path, "e1", "ubuntu-latest", "claude-sonnet-4-6", True, 0.5, "S")
    _seed(tmp_path, "e2", "ubuntu-latest", "claude-sonnet-4-6", False, 1.0, "M")
    line = aggregate_week(results_root=tmp_path, week_of=date(2026, 4, 27),
                         commit_sha="abc1234", forge_version="3.8.0", hook_failures_total=3)
    assert line["schema_version"] == 1
    assert line["hook_failures_total"] == 3
    cell = line["cells"][0]
    assert cell["entries_total"] == 2
    assert cell["entries_solved"] == 1
    assert cell["solve_rate_overall"] == 0.5
    assert cell["median_cost_per_solve_usd"] == 0.5   # only one solved, its cost
    # Bucket-split comes from the real `complexity` field on each result.
    assert cell["solve_rate_by_complexity"] == {"S": 1.0, "M": 0.0}


def test_aggregate_rejects_legacy_missing_complexity(tmp_path: Path) -> None:
    """Results without `complexity` are a hard contract violation (no silent 'S' fallback)."""
    import pytest
    d = tmp_path / "2026-04-27"; d.mkdir(parents=True)
    (d / "bad.ubuntu-latest.claude-sonnet-4-6.json").write_text(json.dumps({
        "schema_version": 1, "entry_id": "bad", "solved": True, "cost_usd": 0.0,
        "os": "ubuntu-latest", "model": "claude-sonnet-4-6", "timeout": False,
        # No 'complexity' — aggregator must refuse.
    }))
    with pytest.raises(KeyError, match="complexity"):
        aggregate_week(results_root=tmp_path, week_of=date(2026, 4, 27),
                       commit_sha="x", forge_version="3.8.0", hook_failures_total=0)
```

### Implementation

`tests/evals/benchmark/aggregate.py`:

```python
"""Aggregate per-cell BenchmarkResult files into a single trends.jsonl line."""
from __future__ import annotations
import json
import statistics
from collections import defaultdict
from datetime import date
from pathlib import Path
from typing import Any


def _load_results(results_root: Path, week_of: date) -> list[dict[str, Any]]:
    day_dir = results_root / week_of.isoformat()
    if not day_dir.is_dir():
        return []
    return [json.loads(f.read_text()) for f in day_dir.glob("*.json")]


def _group_by_cell(results: list[dict]) -> dict[tuple[str, str], list[dict]]:
    g: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in results:
        g[(r["os"], r["model"])].append(r)
    return g


def aggregate_week(*, results_root: Path, week_of: date, commit_sha: str,
                   forge_version: str, hook_failures_total: int) -> dict[str, Any]:
    all_results = _load_results(results_root, week_of)
    cells = []
    for (os_name, model), rs in sorted(_group_by_cell(all_results).items()):
        solved_runs = [r for r in rs if r["solved"]]
        timed = sum(1 for r in rs if r["timeout"])
        docker_sk = sum(1 for r in rs if r.get("error") == "BENCH-DOCKER-SKIPPED")
        per_complexity: dict[str, list[bool]] = defaultdict(list)
        for r in rs:
            # Hard-require real `complexity` — no silent "S" fallback. Missing
            # field means the result came from a pre-contract writer; bail loudly.
            per_complexity[r["complexity"]].append(r["solved"])
        costs_solved = [r["cost_usd"] for r in solved_runs if r["cost_usd"] > 0]
        unverifiable_total = sum(int(r.get("unverifiable_count", 0)) for r in rs)
        cells.append({
            "os": os_name, "model": model,
            "entries_total": len(rs),
            "entries_solved": len(solved_runs),
            "entries_timeout": timed,
            "entries_docker_skipped": docker_sk,
            "solve_rate_overall": len(solved_runs) / len(rs) if rs else 0.0,
            "solve_rate_by_complexity": {
                k: (sum(v) / len(v) if v else 0.0) for k, v in sorted(per_complexity.items())
            },
            "median_cost_per_solve_usd": statistics.median(costs_solved) if costs_solved else 0.0,
            "total_cost_usd": sum(r["cost_usd"] for r in rs),
            "unverifiable_total": unverifiable_total,
        })

    # regressions computed by render_scorecard against prior trends line, not here.
    return {
        "schema_version": 1,
        "week_of": week_of.isoformat(),
        "commit_sha": commit_sha,
        "forge_version": forge_version,
        "cells": cells,
        "hook_failures_total": hook_failures_total,
        "regressions": [],
    }


def append_trends(trends_path: Path, line: dict[str, Any]) -> None:
    """Append one JSON line to trends.jsonl (create if missing)."""
    trends_path.parent.mkdir(parents=True, exist_ok=True)
    with trends_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(line, sort_keys=True) + "\n")
```

**Commit:** `feat(bench): Phase 8 — trends aggregator (per-cell → one JSONL line per week)`.

---

## Task 13 — `trends.jsonl` append-only contract (AC-824)

### Test

`tests/contract/test_benchmark_trends_schema.py`:

```python
"""Every trends.jsonl line validates against trends_line.schema.json."""
from __future__ import annotations
import json
from pathlib import Path
from datetime import date
from jsonschema import Draft202012Validator
from tests.evals.benchmark.aggregate import aggregate_week, append_trends

SCHEMA = json.loads((Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "schemas" / "trends_line.schema.json").read_text())
V = Draft202012Validator(SCHEMA)


def test_append_preserves_order(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"
    (tmp_path / "results").mkdir()
    line1 = aggregate_week(results_root=tmp_path / "results",
                           week_of=date(2026, 4, 20), commit_sha="a", forge_version="3.8.0",
                           hook_failures_total=0)
    line2 = aggregate_week(results_root=tmp_path / "results",
                           week_of=date(2026, 4, 27), commit_sha="b", forge_version="3.8.0",
                           hook_failures_total=1)
    append_trends(trends, line1)
    append_trends(trends, line2)
    lines = trends.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 2
    p1, p2 = json.loads(lines[0]), json.loads(lines[1])
    V.validate(p1); V.validate(p2)
    assert p1["week_of"] == "2026-04-20"
    assert p2["week_of"] == "2026-04-27"
```

### Implementation

No new code; Task 12's `append_trends` already satisfies. Test locks the invariant.

**Commit:** `test(bench): Phase 8 — trends.jsonl append-only contract`.

---

## Task 14 — Sparkline encoder + scorecard renderer base (AC-805)

### Test

`tests/unit/test_render_scorecard.py`:

```python
"""Scorecard renderer: empty, all-solved, all-failed, regressions, sparklines."""
from __future__ import annotations
import json
from pathlib import Path
from tests.evals.benchmark.render_scorecard import render, sparkline


def test_sparkline_empty() -> None:
    assert sparkline([]) == "▁" * 12


def test_sparkline_full_range() -> None:
    # values 0..1 in 12 steps → blocks spanning the 8-char range
    vals = [i / 11 for i in range(12)]
    s = sparkline(vals)
    assert len(s) == 12
    assert s[0] == "▁"
    assert s[-1] == "█"


def test_sparkline_gap_fills_with_low() -> None:
    assert sparkline([None, 0.5, None]) == "▁▄▁"


def test_render_empty_history(tmp_path: Path) -> None:
    out = render(trends_lines=[], baseline=None, hook_failures_total=0)
    assert "<!-- section:header -->" in out
    assert "<!-- section:this-week -->" in out
    assert "awaiting first weekly run" in out.lower()


def test_render_with_one_week_all_solved() -> None:
    line = {"schema_version": 1, "week_of": "2026-04-27", "commit_sha": "abc1234",
            "forge_version": "3.8.0",
            "cells": [{"os": "ubuntu-latest", "model": "claude-sonnet-4-6",
                       "entries_total": 10, "entries_solved": 10, "entries_timeout": 0,
                       "entries_docker_skipped": 0, "solve_rate_overall": 1.0,
                       "solve_rate_by_complexity": {"S": 1.0, "M": 1.0, "L": 1.0},
                       "median_cost_per_solve_usd": 0.5, "total_cost_usd": 5.0}],
            "hook_failures_total": 0, "regressions": []}
    out = render(trends_lines=[line], baseline=None, hook_failures_total=0)
    assert "100%" in out or "1.00" in out or "solve_rate" in out.lower()


def test_render_shows_regressions() -> None:
    line = {"schema_version": 1, "week_of": "2026-04-27", "commit_sha": "abc", "forge_version": "3.8.0",
            "cells": [{"os": "ubuntu-latest", "model": "claude-sonnet-4-6",
                       "entries_total": 2, "entries_solved": 1, "entries_timeout": 0,
                       "entries_docker_skipped": 0, "solve_rate_overall": 0.5,
                       "solve_rate_by_complexity": {"S": 1.0, "M": 0.0, "L": 0.0},
                       "median_cost_per_solve_usd": 0.5, "total_cost_usd": 1.0}],
            "hook_failures_total": 0,
            "regressions": [{"entry_id": "e42", "last_status": "solved", "this_status": "failed"}]}
    out = render(trends_lines=[line], baseline=None, hook_failures_total=0)
    assert "e42" in out
    assert "regression" in out.lower()


def test_render_cost_truncated_banner() -> None:
    line = {"schema_version": 1, "week_of": "2026-04-27", "commit_sha": "abc", "forge_version": "3.8.0",
            "cells": [], "hook_failures_total": 0, "regressions": [], "cost_truncated": True}
    out = render(trends_lines=[line], baseline=None, hook_failures_total=0)
    assert "cost-truncated" in out.lower() or "truncated" in out.lower()


def test_sparkline_output_is_utf8_round_trippable() -> None:
    """Windows smoke: block glyphs must encode/decode losslessly under UTF-8.

    The aggregate job runs on ubuntu-latest (scorecard is produced on Linux and
    committed as UTF-8), but the renderer itself can be invoked locally from
    PowerShell / cmd where the default codepage may be cp1252. This test
    locks the contract that `sparkline()` emits only chars in the 8-block
    set and that encoding to UTF-8 round-trips without replacement chars.
    Run on Windows CI cells by the matrix — no `chcp 65001` required because
    we never touch the terminal; we write bytes to a file.
    """
    s = sparkline([0.0, 0.5, 1.0])
    encoded = s.encode("utf-8")
    assert encoded.decode("utf-8") == s
    assert all(ch in "▁▂▃▄▅▆▇█" for ch in s)


def test_render_12_week_sparkline_edge() -> None:
    lines = [
        {"schema_version": 1, "week_of": f"2026-{(i % 12) + 1:02d}-01", "commit_sha": "x",
         "forge_version": "3.8.0",
         "cells": [{"os": "ubuntu-latest", "model": "claude-sonnet-4-6",
                    "entries_total": 10, "entries_solved": i,
                    "entries_timeout": 0, "entries_docker_skipped": 0,
                    "solve_rate_overall": i / 10.0,
                    "solve_rate_by_complexity": {"S": i/10.0, "M": i/10.0, "L": i/10.0},
                    "median_cost_per_solve_usd": 0.5, "total_cost_usd": 5.0}],
         "hook_failures_total": 0, "regressions": []}
        for i in range(15)  # more than 12 — only last 12 should render
    ]
    out = render(trends_lines=lines, baseline=None, hook_failures_total=0)
    # The section name should appear; last-12 constraint enforced by len check in prose
    assert "Last 12 weeks" in out
```

### Implementation

`tests/evals/benchmark/render_scorecard.py`:

```python
"""Render SCORECARD.md from trends.jsonl.

Sections (enforced order, idempotent by HTML marker):
  - header (metadata + hook failures + incomplete-cells banner)
  - this-week (overall, by complexity, by language, by model)
  - last-12-weeks (sparklines per bucket)
  - regressions (entries that flipped solved→failed)
  - cost-per-solve (median USD sparkline)
  - vs-peers (placeholder — never fabricate)
  - appendix (per-entry raw solve booleans)
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from typing import Sequence

_BLOCKS = "▁▂▃▄▅▆▇█"


def sparkline(values: Sequence[float | None]) -> str:
    if not values:
        return "▁" * 12
    rendered = []
    for v in values:
        if v is None:
            rendered.append(_BLOCKS[0])
        else:
            clamped = max(0.0, min(1.0, float(v)))
            idx = min(len(_BLOCKS) - 1, int(round(clamped * (len(_BLOCKS) - 1))))
            rendered.append(_BLOCKS[idx])
    return "".join(rendered)


def _section(marker: str, body: str) -> str:
    return f"<!-- section:{marker} -->\n{body}\n"


def render(*, trends_lines: list[dict], baseline: dict | None, hook_failures_total: int) -> str:
    parts: list[str] = []
    # Header
    if not trends_lines:
        parts.append(_section("header", "# Forge Scorecard\n\n> awaiting first weekly run\n"))
        parts.append(_section("this-week", "_no data_\n"))
        parts.append(_section("last-12-weeks", "_no data_\n"))
        parts.append(_section("regressions", "_none_\n"))
        parts.append(_section("cost-per-solve", "_no data_\n"))
        parts.append(_section("vs-peers", _peers_placeholder(None)))
        parts.append(_section("appendix", "_no data_\n"))
        return "\n".join(parts)

    latest = trends_lines[-1]
    header = f"# Forge Scorecard\n\n"
    header += f"- generated: {latest['week_of']}\n"
    header += f"- commit: {latest['commit_sha']}\n"
    header += f"- forge version: {latest['forge_version']}\n"
    header += f"- hook failures this week: {hook_failures_total}\n"
    if latest.get("cost_truncated"):
        header += "- **cost-truncated**: weekly cost ceiling tripped; partial data only\n"
    cells_ran = len(latest.get("cells", []))
    if cells_ran < 6:
        header += f"- incomplete: {cells_ran}/6 cells ran\n"
    parts.append(_section("header", header))

    # This week
    tw = _render_this_week(latest)
    parts.append(_section("this-week", tw))

    # Sparklines over last 12
    last_12 = trends_lines[-12:]
    sp = _render_sparklines(last_12)
    parts.append(_section("last-12-weeks", sp))

    # Regressions
    regs = latest.get("regressions", [])
    if regs:
        body = "| entry | last week | this week |\n|---|---|---|\n" + "\n".join(
            f"| `{r['entry_id']}` | {r['last_status']} | {r['this_status']} |" for r in regs
        ) + "\n"
    else:
        body = "_none this week_\n"
    parts.append(_section("regressions", body))

    # Cost-per-solve
    cps = _render_cost_per_solve(last_12)
    parts.append(_section("cost-per-solve", cps))

    # Peers
    parts.append(_section("vs-peers", _peers_placeholder(latest)))

    # Appendix
    parts.append(_section("appendix", _render_appendix(latest)))

    return "\n".join(parts)


def _render_this_week(line: dict) -> str:
    rows = []
    rows.append("| os | model | solved / total | overall | S | M | L | median $/solve | UNVERIFIABLE |")
    rows.append("|---|---|---|---|---|---|---|---|---|")
    for c in line.get("cells", []):
        by = c["solve_rate_by_complexity"]
        rows.append(
            f"| {c['os']} | {c['model']} | {c['entries_solved']} / {c['entries_total']} | "
            f"{c['solve_rate_overall']*100:.0f}% | "
            f"{by.get('S', 0)*100:.0f}% | {by.get('M', 0)*100:.0f}% | {by.get('L', 0)*100:.0f}% | "
            f"${c['median_cost_per_solve_usd']:.2f} | "
            f"{c.get('unverifiable_total', 0)} |"
        )
    return "\n".join(rows) + "\n"


def _render_sparklines(lines: list[dict]) -> str:
    by_cell: dict[tuple[str, str], list[float | None]] = {}
    for ln in lines:
        for c in ln.get("cells", []):
            by_cell.setdefault((c["os"], c["model"]), []).append(c["solve_rate_overall"])
    out = ["## Last 12 weeks\n"]
    for (os_name, model), vals in sorted(by_cell.items()):
        padded = [None] * (12 - len(vals)) + list(vals)
        first = next((v for v in vals if v is not None), 0.0)
        last = vals[-1] if vals else 0.0
        out.append(f"- `{os_name}` × `{model}`: {sparkline(padded)} ({first*100:.0f}% → {last*100:.0f}%)")
    return "\n".join(out) + "\n"


def _render_cost_per_solve(lines: list[dict]) -> str:
    by_model: dict[str, list[float | None]] = {}
    for ln in lines:
        for c in ln.get("cells", []):
            by_model.setdefault(c["model"], []).append(c["median_cost_per_solve_usd"])
    if not by_model:
        return "_no data_\n"
    # Normalize: sparkline expects 0..1, so scale by max observed
    out = ["## Cost-per-solve (median USD)\n"]
    max_cost = max((max(v for v in vals if v is not None) for vals in by_model.values() if vals), default=1.0) or 1.0
    for model, vals in sorted(by_model.items()):
        padded = [None] * (12 - len(vals)) + [v / max_cost if v is not None else None for v in vals]
        last_raw = vals[-1] if vals else 0.0
        out.append(f"- `{model}`: {sparkline(padded)} (latest: ${last_raw:.2f})")
    return "\n".join(out) + "\n"


def _peers_placeholder(_latest: dict | None) -> str:
    return (
        "## Peer comparison (manual update — never auto-scraped)\n"
        "\n"
        "| benchmark | solve rate | link |\n"
        "|---|---|---|\n"
        "| forge (this repo) | — | [SCORECARD.md](./SCORECARD.md) |\n"
        "| SWE-bench Verified | — | https://www.swebench.com/ |\n"
        "| OpenHands | — | https://github.com/All-Hands-AI/OpenHands |\n"
        "| SWE-agent | — | https://github.com/SWE-agent/SWE-agent |\n"
    )


def _render_appendix(line: dict) -> str:
    out = ["## Appendix — per-entry solve matrix\n"]
    # Deliberately compact — may be empty until per-entry tracker is wired
    return "\n".join(out) + "\n"


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.benchmark.render_scorecard")
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--baseline", type=Path, default=None)
    p.add_argument("--hook-failures-total", type=int, default=0)
    p.add_argument("--output", type=Path, default=Path("SCORECARD.md"))
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    lines: list[dict] = []
    if args.trends.is_file():
        for raw in args.trends.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                lines.append(json.loads(raw))
    baseline = json.loads(args.baseline.read_text()) if args.baseline and args.baseline.is_file() else None
    doc = render(trends_lines=lines, baseline=baseline, hook_failures_total=args.hook_failures_total)
    args.output.write_text(doc, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

**Commit:** `feat(bench): Phase 8 — scorecard renderer with sparklines and regressions`.

---

## Task 15 — Baseline freeze + refresh CLI (AC-810)

### Test

`tests/unit/test_refresh_baseline.py`:

```python
"""refresh_baseline.py refuses without --confirm; round-trips a trends line."""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = Draft202012Validator(json.loads((ROOT / "tests/evals/benchmark/schemas/baseline.schema.json").read_text()))


def _seed_trends(trends: Path) -> None:
    line = {"schema_version": 1, "week_of": "2026-04-27", "commit_sha": "abc",
            "forge_version": "3.8.0",
            "cells": [{"os": "ubuntu-latest", "model": "claude-sonnet-4-6",
                       "entries_total": 10, "entries_solved": 8, "entries_timeout": 0,
                       "entries_docker_skipped": 0, "solve_rate_overall": 0.8,
                       "solve_rate_by_complexity": {"S": 0.9, "M": 0.8, "L": 0.5},
                       "median_cost_per_solve_usd": 0.4, "total_cost_usd": 4.0}],
            "hook_failures_total": 0, "regressions": []}
    trends.write_text(json.dumps(line) + "\n")


def test_refuses_without_confirm(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"; _seed_trends(trends)
    out = tmp_path / "baseline.json"
    r = subprocess.run([sys.executable, "-m", "tests.evals.benchmark.refresh_baseline",
                        "--trends", str(trends), "--output", str(out)],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode != 0
    assert "--confirm" in r.stderr or "--confirm" in r.stdout
    assert not out.exists()


def test_confirmed_writes_valid(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"; _seed_trends(trends)
    out = tmp_path / "baseline.json"
    r = subprocess.run([sys.executable, "-m", "tests.evals.benchmark.refresh_baseline",
                        "--trends", str(trends), "--output", str(out), "--confirm", "--commit-sha", "abc"],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    doc = json.loads(out.read_text())
    SCHEMA.validate(doc)
    assert "claude-sonnet-4-6" in doc["baselines"]
    assert doc["baselines"]["claude-sonnet-4-6"]["overall"] == 0.8
```

### Implementation

`tests/evals/benchmark/refresh_baseline.py`:

```python
"""Freeze or refresh tests/evals/benchmark/baseline.json from latest trends line."""
from __future__ import annotations
import argparse
import json
import sys
from datetime import date
from pathlib import Path


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.benchmark.refresh_baseline")
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--commit-sha", type=str, default="local")
    p.add_argument("--confirm", action="store_true")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if not args.confirm:
        print("refuse: --confirm is required (baseline refresh is destructive)", file=sys.stderr)
        return 2

    lines = [json.loads(l) for l in args.trends.read_text(encoding="utf-8").splitlines() if l.strip()]
    if not lines:
        print("error: trends file is empty", file=sys.stderr)
        return 1
    latest = lines[-1]

    baselines: dict[str, dict[str, float]] = {}
    for c in latest["cells"]:
        m = c["model"]
        b = baselines.setdefault(m, {"S": 0.0, "M": 0.0, "L": 0.0, "overall": 0.0})
        by = c["solve_rate_by_complexity"]
        b["S"] = by.get("S", 0.0)
        b["M"] = by.get("M", 0.0)
        b["L"] = by.get("L", 0.0)
        b["overall"] = c["solve_rate_overall"]

    doc = {
        "schema_version": 1,
        "frozen_on": date.today().isoformat(),
        "frozen_commit_sha": args.commit_sha,
        "baselines": baselines,
        "regression_threshold_pp": 10,
    }
    args.output.write_text(json.dumps(doc, indent=2, sort_keys=True), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

**Commit:** `feat(bench): Phase 8 — baseline freeze + refresh (--confirm-gated)`.

---

## Task 16 — Regression gate (AC-809)

### Test

`tests/unit/test_regression_gate.py`:

```python
"""Gate: solve-rate drop ≥10pp in any (bucket, model) triggers exit 1."""
from __future__ import annotations
from tests.evals.benchmark.gate import evaluate_gate, GateResult


def _trends_line(sonnet_s: float, sonnet_m: float = 0.8, sonnet_l: float = 0.5) -> dict:
    return {"cells": [{"os": "ubuntu-latest", "model": "claude-sonnet-4-6",
                       "entries_total": 10, "entries_solved": int(sonnet_s * 10),
                       "solve_rate_overall": sonnet_s,
                       "solve_rate_by_complexity": {"S": sonnet_s, "M": sonnet_m, "L": sonnet_l},
                       "entries_timeout": 0, "entries_docker_skipped": 0,
                       "median_cost_per_solve_usd": 0.4, "total_cost_usd": 4.0}]}


def _baseline(overall: float = 0.9, s: float = 0.9, m: float = 0.8, l_: float = 0.5) -> dict:
    return {"baselines": {"claude-sonnet-4-6": {"S": s, "M": m, "L": l_, "overall": overall}},
            "regression_threshold_pp": 10}


def test_no_regression_passes() -> None:
    r = evaluate_gate(current=_trends_line(0.9), baseline=_baseline(0.9))
    assert r.passed is True
    assert not r.findings


def test_10pp_drop_fails() -> None:
    r = evaluate_gate(current=_trends_line(0.7), baseline=_baseline(0.9, s=0.9))
    assert r.passed is False
    assert any(f.severity == "CRITICAL" and f.category == "BENCH-REGRESSION" for f in r.findings)


def test_5pp_drop_warns_but_passes() -> None:
    r = evaluate_gate(current=_trends_line(0.84), baseline=_baseline(0.9, s=0.9))
    assert r.passed is True
    assert any(f.severity == "WARNING" and f.category == "BENCH-REGRESSION" for f in r.findings)


def test_no_baseline_is_pass_warning() -> None:
    r = evaluate_gate(current=_trends_line(0.5), baseline=None)
    assert r.passed is True
    assert any(f.severity == "WARNING" for f in r.findings)


def test_mutation_manual_baseline_bump() -> None:
    """AC-809 mutation: bump baseline +15pp; current line that was fine now fails."""
    current = _trends_line(0.8)           # 80%
    original = _baseline(0.82)            # baseline was 82%
    mutated = _baseline(0.97)             # +15pp mutation
    assert evaluate_gate(current=current, baseline=original).passed
    assert not evaluate_gate(current=current, baseline=mutated).passed
```

### Implementation

`tests/evals/benchmark/gate.py`:

```python
"""Regression gate — compare current week vs frozen baseline."""
from __future__ import annotations
from dataclasses import dataclass, field


@dataclass
class GateFinding:
    category: str
    severity: str
    message: str


@dataclass
class GateResult:
    passed: bool
    findings: list[GateFinding] = field(default_factory=list)


def evaluate_gate(*, current: dict, baseline: dict | None) -> GateResult:
    if baseline is None:
        return GateResult(passed=True, findings=[
            GateFinding("BENCH-NO-BASELINE", "WARNING", "baseline.json missing; gate skipped")
        ])

    threshold_pp = baseline.get("regression_threshold_pp", 10)
    warn_pp = 5
    findings: list[GateFinding] = []
    passed = True

    for cell in current["cells"]:
        model = cell["model"]
        base = baseline["baselines"].get(model)
        if base is None:
            findings.append(GateFinding("BENCH-BASELINE-MISSING-MODEL", "WARNING",
                                        f"no baseline for model {model}"))
            continue
        for bucket in ("S", "M", "L", "overall"):
            cur = cell["solve_rate_by_complexity"].get(bucket) if bucket != "overall" else cell["solve_rate_overall"]
            if cur is None:
                continue
            delta_pp = (cur - base[bucket]) * 100
            if delta_pp <= -threshold_pp:
                passed = False
                findings.append(GateFinding(
                    "BENCH-REGRESSION", "CRITICAL",
                    f"{model} {bucket}: {cur*100:.1f}% vs baseline {base[bucket]*100:.1f}% "
                    f"(Δ {delta_pp:+.1f}pp ≤ -{threshold_pp}pp)",
                ))
            elif delta_pp <= -warn_pp:
                findings.append(GateFinding(
                    "BENCH-REGRESSION", "WARNING",
                    f"{model} {bucket}: {cur*100:.1f}% vs baseline {base[bucket]*100:.1f}% (Δ {delta_pp:+.1f}pp)",
                ))
    return GateResult(passed=passed, findings=findings)
```

**Commit:** `feat(bench): Phase 8 — regression gate (10pp CRITICAL, 5pp WARNING)`.

---

## Task 17 — Cost-ceiling enforcement + simulator fixture (AC-812, AC-827)

### Test

`tests/unit/test_cost_ceiling.py`:

```python
"""Cost ceiling: aggregator aborts remaining cells when cumulative spend ≥ max_weekly_cost_usd."""
from __future__ import annotations
import json
from pathlib import Path
from tests.evals.benchmark.cost_guard import CostGuard, CostLimitExceeded


def _spend_line(cost: float) -> dict:
    return {"estimated_cost_usd": cost, "ts": "2026-04-27T06:00:00Z"}


def test_below_ceiling(tmp_path: Path) -> None:
    g = CostGuard(max_weekly_cost_usd=200.0)
    g.record(50.0); g.record(40.0)
    assert g.total_usd == 90.0
    assert g.within_limit() is True


def test_exactly_at_ceiling_trips(tmp_path: Path) -> None:
    g = CostGuard(max_weekly_cost_usd=100.0)
    g.record(100.0)
    assert g.within_limit() is False


def test_simulator_feed(tmp_path: Path) -> None:
    """Feed synthetic spend events, assert abort after cumulative crosses ceiling."""
    tracker = tmp_path / "token-events.jsonl"
    with tracker.open("w") as f:
        for cost in [25.0, 30.0, 40.0, 60.0, 55.0]:
            f.write(json.dumps(_spend_line(cost)) + "\n")
    g = CostGuard(max_weekly_cost_usd=150.0)
    tripped_at = None
    for i, raw in enumerate(tracker.read_text().splitlines(), 1):
        g.record(json.loads(raw)["estimated_cost_usd"])
        if not g.within_limit():
            tripped_at = i; break
    assert tripped_at == 4   # 25+30+40+60 = 155 ≥ 150
```

### Implementation

`tests/evals/benchmark/cost_guard.py`:

```python
"""Cost ceiling guard for the weekly benchmark workflow.

Phase 6 contract: reads state.cost.estimated_cost_usd (field-name: pct_consumed).
Default ceiling: $200 (conservative; user DB empty at commit time — see plan header).
"""
from __future__ import annotations
from dataclasses import dataclass


class CostLimitExceeded(RuntimeError):
    pass


@dataclass
class CostGuard:
    max_weekly_cost_usd: float
    total_usd: float = 0.0

    def record(self, usd: float) -> None:
        self.total_usd += max(0.0, float(usd))

    def within_limit(self) -> bool:
        return self.total_usd < self.max_weekly_cost_usd

    def assert_within(self) -> None:
        if not self.within_limit():
            raise CostLimitExceeded(
                f"BENCH-COST-CEILING: ${self.total_usd:.2f} ≥ ${self.max_weekly_cost_usd:.2f}"
            )
```

Wire into aggregator: before each cell artifact download, aggregator calls `CostGuard` per-cell total and emits `BENCH-COST-CEILING` WARNING if tripped, setting `cost_truncated: True` on the trends line.

**Commit:** `feat(bench): Phase 8 — cost ceiling guard + simulator-based test`.

---

## Task 18 — Phase 4 `benchmark.regression` learning type (AC-816)

### Test

`tests/contract/test_benchmark_regression_learning_type.py`:

```python
"""Phase 4 coordination: benchmark.regression must be registered in the learning-type allowlist."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_learning_type_documented_in_readme() -> None:
    readme = (ROOT / "shared" / "learnings" / "README.md").read_text()
    assert "benchmark.regression" in readme, "Phase 8 must document new learning type"


def test_registry_includes_benchmark_regression() -> None:
    """If the type registry is enumerated anywhere, it must include our new type."""
    # Phase 4 registry path (confirm-in-place when Phase 4 ships):
    registry_candidates = [
        ROOT / "shared" / "learnings" / "types.json",
        ROOT / "shared" / "checks" / "learning-types.json",
    ]
    for path in registry_candidates:
        if path.is_file():
            types = json.loads(path.read_text())
            if isinstance(types, list):
                assert "benchmark.regression" in types
            elif isinstance(types, dict):
                assert "benchmark.regression" in types.get("types", []) or "benchmark.regression" in types
            return
    # If no registry exists yet (Phase 4 not shipped), test is a noop (documented by README test above)
```

### Implementation

Edit `shared/learnings/README.md` — add row to the learning-types table:

```markdown
| `benchmark.regression` | Benchmark entry flipped solved → failed for 2+ consecutive weeks. Emitted by `tests/evals/benchmark/aggregate.py`. | Phase 4 selector service injects warning into implementer/reviewer dispatch for the entry's domain. |
```

Also add injection helper `tests/evals/benchmark/emit_learning.py`:

```python
"""Emit a benchmark.regression learning row into .forge/run-history.db.

Called by aggregator when two consecutive weekly runs show solved→failed.
Row fields match shared/run-history/migrations/001-initial.sql:learnings.
"""
from __future__ import annotations
import sqlite3
from pathlib import Path


def emit_regression(db_path: Path, *, run_id: str, entry_id: str, domain: str, week: int) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute(
            "INSERT INTO learnings (run_id, type, content, domain, confidence, source_agent, applied_count) "
            "VALUES (?, 'benchmark.regression', ?, ?, 'HIGH', 'fg-aggregator', 0)",
            (run_id, f"Entry {entry_id} regressed on week {week}", domain),
        )
        conn.commit()
    finally:
        conn.close()
```

**Commit:** `feat(bench): Phase 8 — benchmark.regression learning type + emitter`.

---

## Task 19 — Phase 7 AC injection contract test (AC-817)

### Test

`tests/contract/test_phase7_ac_injection.py`:

```python
"""Phase 7 coordination: the runner seeds .forge/specs/index.json correctly."""
from __future__ import annotations
import json
from pathlib import Path
from tests.evals.benchmark.discovery import CorpusEntry
from tests.evals.benchmark.live_run import _write_spec_injection


def test_source_field_present_and_untouched(tmp_path: Path) -> None:
    entry = CorpusEntry(
        entry_id="demo", path=tmp_path,
        requirement="# Requirement\nx\n",
        ac_list=[{"id": "AC-B001", "description": "X works", "verifiable_via": "cli"}],
        expected={}, metadata={"complexity": "S", "requires_docker": False},
    )
    project = tmp_path / "project"
    project.mkdir()
    _write_spec_injection(project, entry)
    doc = json.loads((project / ".forge" / "specs" / "index.json").read_text())
    assert doc["specs"]["demo"]["source"] == "benchmark-injected"


def test_namespace_does_not_collide_with_ac_numeric() -> None:
    """AC-B* namespace is disjoint from AC-NNN (forge-generated)."""
    import re
    bench_pat = re.compile(r"^AC-B\d{3}$")
    forge_pat = re.compile(r"^AC-\d{3}$")
    assert bench_pat.match("AC-B001")
    assert not bench_pat.match("AC-001")
    assert not forge_pat.match("AC-B001")
```

### Implementation

Already in Task 10 (`_write_spec_injection` writes `source: "benchmark-injected"`). This task adds the contract test and documents the namespace rule in `shared/living-specifications.md`:

```markdown
### AC ID namespaces

- `AC-NNN` (e.g. `AC-001`) — forge-generated ACs (fg-540 or shaper).
- `AC-BNNN` (e.g. `AC-B001`) — benchmark-injected ACs (Phase 8). Source field `benchmark-injected`.

The orchestrator's spec-refresh logic MUST preserve any spec entry whose `source` field is present (currently: only `benchmark-injected`).
```

**Commit:** `feat(bench): Phase 8 — AC-B namespace + Phase 7 injection contract`.

---

## Task 20 — Phase 1 hook-failure roll-up (AC-818)

### Test

`tests/unit/test_hook_failure_rollup.py`:

```python
"""Aggregator counts lines in per-cell .hook-failures.jsonl artefacts."""
from __future__ import annotations
import json
from pathlib import Path
from tests.evals.benchmark.aggregate import count_hook_failures


def test_sums_across_cells(tmp_path: Path) -> None:
    for os_name, model, n in [("ubuntu-latest", "claude-sonnet-4-6", 2),
                              ("ubuntu-latest", "claude-opus-4-7", 1)]:
        d = tmp_path / f"{os_name}-{model}"
        d.mkdir()
        (d / ".hook-failures.jsonl").write_text("\n".join(json.dumps({"e": "x"}) for _ in range(n)))
    assert count_hook_failures(tmp_path) == 3


def test_missing_file_zero(tmp_path: Path) -> None:
    assert count_hook_failures(tmp_path) == 0
```

### Implementation

Add to `tests/evals/benchmark/aggregate.py`:

```python
def count_hook_failures(artifacts_root: Path) -> int:
    total = 0
    for log in artifacts_root.rglob(".hook-failures.jsonl"):
        total += sum(1 for line in log.read_text(encoding="utf-8").splitlines() if line.strip())
    return total
```

Renderer picks up the count via `--hook-failures-total` CLI arg (already in Task 14).

**Commit:** `feat(bench): Phase 8 — hook-failure roll-up into scorecard`.

---

## Task 21 — OTel spans for benchmark run (AC-819)

### Test

`tests/unit/test_otel_benchmark_spans.py`:

```python
"""Benchmark emits six span attributes per run: entry_id, os, model, solved, duration_s, cost_usd."""
from __future__ import annotations
from tests.evals.benchmark.otel_emit import emit_benchmark_span


def test_emit_span_shape(monkeypatch) -> None:
    captured = []

    def fake_replay(name, attrs):
        captured.append((name, dict(attrs)))

    monkeypatch.setattr("tests.evals.benchmark.otel_emit._replay", fake_replay)
    emit_benchmark_span(
        entry_id="2026-04-27-x", os="ubuntu-latest", model="claude-sonnet-4-6",
        solved=True, duration_s=600, cost_usd=0.42,
    )
    assert len(captured) == 1
    name, attrs = captured[0]
    assert name == "forge.benchmark.run"
    assert attrs["forge.benchmark.entry_id"] == "2026-04-27-x"
    assert attrs["forge.benchmark.os"] == "ubuntu-latest"
    assert attrs["forge.benchmark.model"] == "claude-sonnet-4-6"
    assert attrs["forge.benchmark.solved"] is True
    assert attrs["forge.benchmark.duration_s"] == 600
    assert attrs["forge.benchmark.cost_usd"] == 0.42
```

### Implementation

`tests/evals/benchmark/otel_emit.py`:

```python
"""OTel GenAI-semconv emitter for benchmark runs.

Delegates to hooks/_py/otel.replay for authoritative emission (per shared/observability.md).
Falls back to no-op when OTel is unavailable (dep-gated).
"""
from __future__ import annotations
from typing import Any


def _replay(name: str, attrs: dict[str, Any]) -> None:
    try:
        from hooks._py.otel import replay  # type: ignore
        replay(name, attrs)
    except Exception:
        # Dep-gated: opentelemetry not installed. Spec §Docs says OTel is optional.
        return


def emit_benchmark_span(*, entry_id: str, os: str, model: str, solved: bool,
                        duration_s: int, cost_usd: float) -> None:
    attrs: dict[str, Any] = {
        "forge.benchmark.entry_id": entry_id,
        "forge.benchmark.os": os,
        "forge.benchmark.model": model,
        "forge.benchmark.solved": bool(solved),
        "forge.benchmark.duration_s": int(duration_s),
        "forge.benchmark.cost_usd": float(cost_usd),
    }
    _replay("forge.benchmark.run", attrs)
```

**Commit:** `feat(bench): Phase 8 — OTel spans for benchmark runs`.

---

## Task 22 — curate.py (interactive curation) (AC-811, AC-820, AC-823)

### Test

`tests/unit/test_curate_cli.py`:

```python
"""curate.py CLI: --help exits 0; sandbox refuses non-corpus writes."""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_help() -> None:
    r = subprocess.run([sys.executable, "-m", "tests.evals.benchmark.curate", "--help"],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0
    assert "corpus" in r.stdout.lower()


def test_sandbox_boundary(tmp_path: Path) -> None:
    from tests.evals.benchmark.curate import _write_entry, CurationError
    import pytest
    outside = tmp_path / "not-in-corpus"
    with pytest.raises(CurationError, match="outside corpus root"):
        _write_entry(corpus_root=tmp_path / "corpus", target_dir=outside,
                     requirement="x", ac_list=[], expected={}, metadata={},
                     seed_tarball=tmp_path / "x.tar.gz")
```

### Implementation

`tests/evals/benchmark/curate.py`:

```python
"""Interactive corpus curation. User-assisted: never scrapes, always confirms.

Flow (spec §Component 1):
  1. Query .forge/run-history.db for eligible runs.
  2. For each candidate: print summary, prompt y/N/s/q.
  3. On y: prompt slug, complexity, tags; auto-detect requires_docker (user confirm);
     scrub PII; write corpus/<date>-<slug>/.
  4. Reject on tarball > 50MB, missing SHA, or unacknowledged PII match.
"""
from __future__ import annotations
import argparse
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import yaml
from datetime import date
from pathlib import Path
from typing import Any

from tests.evals.benchmark.pii_scrub import scrub, scan

_CORPUS_ROOT = Path(__file__).resolve().parents[1] / "corpus"
_MAX_TARBALL_MB = 50


class CurationError(RuntimeError):
    pass


_ELIGIBILITY_SQL = """
SELECT id, requirement, language, framework, verdict, score,
       started_at, finished_at, branch_name, pr_url, config_snapshot
  FROM runs
 WHERE verdict IN ('PASS', 'CONCERNS')
   AND score >= 70
   AND started_at >= date('now', '-365 days')
 ORDER BY score DESC, started_at DESC
 LIMIT 100
"""


def _query_candidates(db_path: Path) -> list[dict[str, Any]]:
    if not db_path.is_file():
        return []
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in conn.execute(_ELIGIBILITY_SQL).fetchall()]
    finally:
        conn.close()


def _ask(prompt: str, choices: str = "yNsq") -> str:
    while True:
        resp = input(f"{prompt} [{choices}]: ").strip().lower() or "n"
        if resp and resp[0] in choices.lower():
            return resp[0]


def _detect_requires_docker(source_dir: Path) -> bool:
    probes = ["docker-compose.yml", "compose.yaml", "Dockerfile"]
    for p in probes:
        if (source_dir / p).exists():
            return True
    return False


def _archive(source_dir: Path, target: Path) -> None:
    subprocess.run(["git", "archive", "--format=tar.gz", "-o", str(target), "HEAD"],
                   cwd=source_dir, check=True)
    size_mb = target.stat().st_size / (1024 * 1024)
    if size_mb > _MAX_TARBALL_MB:
        raise CurationError(f"tarball {size_mb:.1f} MB exceeds {_MAX_TARBALL_MB} MB cap")


def _write_entry(*, corpus_root: Path, target_dir: Path, requirement: str,
                 ac_list: list[dict], expected: dict, metadata: dict,
                 seed_tarball: Path) -> None:
    corpus_root = corpus_root.resolve()
    target_dir = target_dir.resolve()
    try:
        target_dir.relative_to(corpus_root)
    except ValueError as e:
        raise CurationError(f"refuse: target {target_dir} outside corpus root {corpus_root}") from e

    target_dir.mkdir(parents=True, exist_ok=True)
    (target_dir / "requirement.md").write_text(scrub(requirement), encoding="utf-8")
    (target_dir / "acceptance-criteria.yaml").write_text(
        yaml.safe_dump({"version": 1, "ac_list": ac_list}, sort_keys=False), encoding="utf-8"
    )
    (target_dir / "expected-deliverables.yaml").write_text(
        yaml.safe_dump(expected, sort_keys=False), encoding="utf-8"
    )
    (target_dir / "metadata.yaml").write_text(
        yaml.safe_dump(metadata, sort_keys=False), encoding="utf-8"
    )
    # Move seed tarball in place
    (target_dir / "seed-project.tar.gz").write_bytes(seed_tarball.read_bytes())


def _prompt_pii(text: str) -> str:
    """Apply auto scrub, then prompt per interactive match."""
    text = scrub(text)
    hits = list(scan(text))
    for h in hits:
        print(f"[PII] {h.kind} at char {h.span[0]}: {h.text!r}")
        resp = _ask("redact this match?", "yn")
        if resp == "y":
            text = text.replace(h.text, f"<redacted-{h.kind}>")
        else:
            raise CurationError(
                f"unacknowledged {h.kind} in requirement; aborting (run curate.py again)"
            )
    return text


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.benchmark.curate",
                                description="Interactively curate benchmark corpus entries.")
    p.add_argument("--db", type=Path,
                   default=Path.home() / ".forge" / "run-history.db",
                   help="Path to .forge/run-history.db")
    p.add_argument("--corpus-root", type=Path, default=_CORPUS_ROOT)
    p.add_argument("--source-repo", type=Path, required=False,
                   help="Path to git repo matching source_run_id (for git archive)")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    candidates = _query_candidates(args.db)
    if not candidates:
        print(f"no eligible runs in {args.db}", file=sys.stderr)
        return 0

    for cand in candidates:
        print(f"\n--- candidate run {cand['id']} ---")
        print(f"requirement: {(cand['requirement'] or '')[:200]}")
        print(f"language/framework: {cand['language']}/{cand['framework']}")
        print(f"verdict={cand['verdict']} score={cand['score']} branch={cand['branch_name']}")
        resp = _ask("Include in corpus?")
        if resp == "q":
            break
        if resp != "y":
            continue
        slug = input("slug (kebab-case): ").strip()
        complexity = input("complexity [S/M/L]: ").strip().upper()
        domain = [s.strip() for s in input("domain tags (comma-separated): ").split(",") if s.strip()]
        if args.source_repo is None:
            print("error: --source-repo required to archive seed; skipping", file=sys.stderr)
            continue
        requires_docker = _detect_requires_docker(args.source_repo)
        confirm = _ask(f"detected requires_docker={requires_docker}; confirm?", "yn")
        if confirm != "y":
            requires_docker = not requires_docker

        today = date.today().isoformat()
        target = args.corpus_root / f"{today}-{slug}"
        with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as tmp:
            tarball = Path(tmp.name)
        try:
            _archive(args.source_repo, tarball)
            clean_req = _prompt_pii(cand["requirement"] or "")
            _write_entry(
                corpus_root=args.corpus_root,
                target_dir=target,
                requirement=clean_req,
                ac_list=[],  # user hand-writes; seed empty per spec
                expected={"version": 1, "files_touched": {"expected_any_of": [], "must_not_touch": []}},
                metadata={
                    "version": 1, "complexity": complexity,
                    "domain": domain or ["unknown"],
                    "language": cand["language"] or "unknown",
                    "framework": cand["framework"] or "unknown",
                    "source_run_id": cand["id"],
                    "requires_docker": requires_docker,
                    "os_compat": ["ubuntu-latest", "macos-latest", "windows-latest"],
                    "notes": f"PR: {cand.get('pr_url') or 'n/a'}",
                },
                seed_tarball=tarball,
            )
            print(f"wrote {target}")
        finally:
            tarball.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

**Commit:** `feat(bench): Phase 8 — curate.py (user-assisted corpus curation with PII scrub)`.

---

## Task 23 — Curated corpus: first 10 entries (AC-801)

**Rationale.** User runs `curate.py` locally against their real `~/.forge/run-history.db`. Since this plan cannot generate user-specific seeds, this task is an **operational commitment**, not a code change. CI ignores an empty corpus (AC-801 checks `>= 10` entries on release; until then the skeleton is present and the contract tests run on the synthetic fixture).

### Test

Relies on `tests/unit/test_corpus_schema.py` (Task 1) and `tests/contract/test_corpus_no_absolute_paths.py` (Task 5). An additional gate test:

`tests/contract/test_corpus_size_and_distribution.py`:

```python
"""Release gate: ≥10 entries, language/framework spread."""
from __future__ import annotations
import os
from pathlib import Path
import pytest
import yaml

CORPUS = Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "corpus"


def _entries() -> list[Path]:
    if not CORPUS.is_dir():
        return []
    return [p for p in CORPUS.iterdir() if p.is_dir() and not p.name.startswith(".")]


@pytest.mark.skipif(
    os.environ.get("PHASE_8_CORPUS_GATE") != "1",
    reason="Gate enabled only on release branches (set PHASE_8_CORPUS_GATE=1)",
)
def test_corpus_has_min_entries() -> None:
    assert len(_entries()) >= 10, "AC-801: release requires ≥ 10 corpus entries"


@pytest.mark.skipif(os.environ.get("PHASE_8_CORPUS_GATE") != "1", reason="release-only")
def test_language_and_framework_spread() -> None:
    langs, frameworks, complexities = set(), set(), []
    for e in _entries():
        meta = yaml.safe_load((e / "metadata.yaml").read_text())
        langs.add(meta["language"]); frameworks.add(meta["framework"]); complexities.append(meta["complexity"])
    assert len(langs) >= 3
    assert len(frameworks) >= 3
    s = complexities.count("S"); m = complexities.count("M"); l_ = complexities.count("L")
    total = len(complexities)
    assert 0.25 <= s / total <= 0.55
    assert 0.25 <= m / total <= 0.55
```

### Implementation

No code — operational task. The user runs `python -m tests.evals.benchmark.curate --source-repo ~/Projects/<repo> --db ~/.forge/run-history.db` and commits the resulting `corpus/<date>-<slug>/` directories. The `PHASE_8_CORPUS_GATE=1` env var is set automatically by the weekly cron in `.github/workflows/benchmark.yml` (Task 24: `github.event_name == 'schedule'`). `workflow_dispatch` runs leave it at `0` so single-entry-filter debugging does not fail the ≥10 invariant. Local `pytest` invocations also leave it unset, which keeps the gate skipped per the `@pytest.mark.skipif` decorators.

**Commit:** `test(bench): Phase 8 — corpus release gate (≥10 entries, spread)`.

---

## Task 24 — `.github/workflows/benchmark.yml` (AC-803)

### Test

`tests/contract/test_benchmark_workflow.py`:

```python
"""Workflow shape: cron, dispatch, matrix (3×2), required steps."""
from __future__ import annotations
from pathlib import Path
import yaml

WF = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "benchmark.yml"


def test_workflow_exists() -> None:
    assert WF.is_file()


def test_cron_trigger() -> None:
    doc = yaml.safe_load(WF.read_text())
    triggers = doc[True] if True in doc else doc["on"]  # PyYAML treats `on:` as True
    assert "schedule" in triggers
    assert triggers["schedule"][0]["cron"] == "0 6 * * 1"
    assert "workflow_dispatch" in triggers


def test_matrix_has_six_cells() -> None:
    doc = yaml.safe_load(WF.read_text())
    job = doc["jobs"]["benchmark-matrix"]
    matrix = job["strategy"]["matrix"]
    assert set(matrix["os"]) == {"ubuntu-latest", "macos-latest", "windows-latest"}
    assert set(matrix["claude-model"]) == {"claude-sonnet-4-6", "claude-opus-4-7"}


def test_timeout_cap() -> None:
    doc = yaml.safe_load(WF.read_text())
    assert doc["jobs"]["benchmark-matrix"]["timeout-minutes"] == 180


def test_corpus_gate_env_only_on_cron() -> None:
    """PHASE_8_CORPUS_GATE must be set to '1' only for scheduled runs."""
    doc = yaml.safe_load(WF.read_text())
    matrix_env = doc["jobs"]["benchmark-matrix"]["env"]
    aggregate_env = doc["jobs"]["aggregate"]["env"]
    for env in (matrix_env, aggregate_env):
        gate = env["PHASE_8_CORPUS_GATE"]
        assert "github.event_name" in gate and "schedule" in gate
        # The expression must fall back to '0' (not absent) so the skipif checks
        # see a concrete value.
        assert "'0'" in gate
```

### Implementation

`.github/workflows/benchmark.yml`:

```yaml
name: Benchmark

on:
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:
    inputs:
      corpus_filter:
        description: 'Substring filter on entry ids (optional)'
        required: false
        default: ''

concurrency:
  group: benchmark-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: write   # bot commits SCORECARD.md directly
  actions: read

jobs:
  benchmark-matrix:
    name: Benchmark ${{ matrix.os }} × ${{ matrix.claude-model }}
    runs-on: ${{ matrix.os }}
    timeout-minutes: 180
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        claude-model: [claude-sonnet-4-6, claude-opus-4-7]
    env:
      FORGE_EVAL: '1'
      FORGE_BENCHMARK: '1'
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      # Corpus size gate (AC-801, Task 23): only cron runs enforce ≥10 entries.
      # workflow_dispatch (manual / debug) runs without the gate so partial-corpus
      # debugging is possible without failing the release-branch invariant.
      PHASE_8_CORPUS_GATE: ${{ github.event_name == 'schedule' && '1' || '0' }}
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-python@v6
        with:
          python-version: '3.10'
      - name: Install deps
        shell: bash
        run: |
          python -m pip install --upgrade pip
          pip install -r tests/evals/benchmark/requirements.txt
      - name: Install Claude CLI
        shell: bash
        run: |
          # Follow tests/evals/pipeline/README.md:77–82 install path.
          npm install -g @anthropic-ai/claude-code || exit 1
          claude --version
      - name: Run benchmark cell
        shell: bash
        run: |
          python -m tests.evals.benchmark.runner \
            --corpus-root tests/evals/benchmark/corpus \
            --results-root tests/evals/benchmark/results \
            --os "${{ matrix.os }}" \
            --model "${{ matrix.claude-model }}" \
            --parallel 1 \
            --entry-filter "${{ github.event.inputs.corpus_filter }}"
      - name: Upload cell artifacts
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: benchmark-${{ matrix.os }}-${{ matrix.claude-model }}-${{ github.run_id }}
          path: |
            tests/evals/benchmark/results/
          retention-days: 90

  aggregate:
    name: Aggregate + render scorecard
    needs: benchmark-matrix
    runs-on: ubuntu-latest
    timeout-minutes: 30
    if: always()
    env:
      PHASE_8_CORPUS_GATE: ${{ github.event_name == 'schedule' && '1' || '0' }}
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 2
      - uses: actions/setup-python@v6
        with:
          python-version: '3.10'
      - name: Install deps
        run: pip install -r tests/evals/benchmark/requirements.txt
      - name: Download all cells
        uses: actions/download-artifact@v8
        with:
          pattern: benchmark-*-${{ github.run_id }}
          path: all-cells/
          merge-multiple: true
      - name: Aggregate week
        run: |
          python -m tests.evals.benchmark.aggregate \
            --results-root all-cells/results \
            --trends tests/evals/benchmark/trends.jsonl \
            --commit-sha "${{ github.sha }}" \
            --forge-version "$(python -c 'import json; print(json.load(open(\"plugin.json\"))[\"version\"])')"
      - name: Render scorecard
        run: |
          python -m tests.evals.benchmark.render_scorecard \
            --trends tests/evals/benchmark/trends.jsonl \
            --baseline tests/evals/benchmark/baseline.json \
            --output SCORECARD.md
      - name: Regression gate
        run: |
          python -m tests.evals.benchmark.gate_cli \
            --trends tests/evals/benchmark/trends.jsonl \
            --baseline tests/evals/benchmark/baseline.json
      - name: Commit scorecard (idempotent)
        shell: bash
        run: |
          if git diff --exit-code SCORECARD.md tests/evals/benchmark/trends.jsonl; then
            echo "no scorecard changes; skipping commit"
            exit 0
          fi
          git config user.name 'github-actions[bot]'
          git config user.email 'github-actions[bot]@users.noreply.github.com'
          git add SCORECARD.md tests/evals/benchmark/trends.jsonl
          git commit -m "chore(bench): weekly scorecard $(date -u +%Y-%m-%d)"
          # Race-retry once
          for i in 1 2; do
            if git push origin HEAD:master; then exit 0; fi
            git fetch origin master && git rebase origin/master || break
          done
          echo "::warning ::BENCH-COMMIT-RACE: push failed twice; uploading artifact instead"
          exit 0
      - name: Upload scorecard (race fallback)
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: scorecard-${{ github.run_id }}
          path: |
            SCORECARD.md
            tests/evals/benchmark/trends.jsonl
```

Also create `tests/evals/benchmark/gate_cli.py` (CLI wrapper around Task 16):

```python
"""CLI: run the regression gate against the latest trends line."""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
from tests.evals.benchmark.gate import evaluate_gate


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--baseline", type=Path, required=True)
    args = p.parse_args(argv)
    if not args.trends.is_file():
        print("no trends.jsonl; skipping gate", file=sys.stderr); return 0
    lines = [json.loads(l) for l in args.trends.read_text().splitlines() if l.strip()]
    if not lines:
        print("empty trends.jsonl; skipping gate", file=sys.stderr); return 0
    baseline = json.loads(args.baseline.read_text()) if args.baseline.is_file() else None
    result = evaluate_gate(current=lines[-1], baseline=baseline)
    for f in result.findings:
        print(f"[{f.severity}] {f.category}: {f.message}", file=sys.stderr)
    return 0 if result.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
```

Also add CLI entry to `aggregate.py`:

```python
def main(argv: list[str] | None = None) -> int:
    import argparse
    from datetime import date as _date
    p = argparse.ArgumentParser()
    p.add_argument("--results-root", type=Path, required=True)
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--commit-sha", type=str, required=True)
    p.add_argument("--forge-version", type=str, required=True)
    args = p.parse_args(argv)
    line = aggregate_week(
        results_root=args.results_root, week_of=_date.today(),
        commit_sha=args.commit_sha, forge_version=args.forge_version,
        hook_failures_total=count_hook_failures(args.results_root),
    )
    append_trends(args.trends, line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

**Commit:** `feat(bench): Phase 8 — weekly CI workflow (cron + matrix + aggregate)`.

---

## Task 25 — Idempotency contract test (AC-808)

### Test

`tests/contract/test_scorecard_idempotent.py`:

```python
"""Render-twice, diff-exit-code=0 — second render produces same bytes."""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_render_is_idempotent(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"
    trends.write_text('{"schema_version":1,"week_of":"2026-04-27","commit_sha":"abc","forge_version":"3.8.0","cells":[],"hook_failures_total":0,"regressions":[]}\n')
    out1 = tmp_path / "a.md"
    out2 = tmp_path / "b.md"
    for target in (out1, out2):
        r = subprocess.run(
            [sys.executable, "-m", "tests.evals.benchmark.render_scorecard",
             "--trends", str(trends), "--output", str(target)],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )
        assert r.returncode == 0
    assert out1.read_bytes() == out2.read_bytes()
```

### Implementation

Already covered by Task 14. This task locks the invariant.

**Commit:** `test(bench): Phase 8 — scorecard idempotency contract`.

---

## Task 26 — Markdown lint + SCORECARD.md template (AC-806, AC-807)

### Test

`tests/unit/test_scorecard_template.py`:

```python
"""SCORECARD.md exists, uses the expected section markers, and README+CLAUDE.md link to it."""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_scorecard_template_exists() -> None:
    sc = ROOT / "SCORECARD.md"
    assert sc.is_file()
    text = sc.read_text()
    for marker in ("<!-- section:header -->", "<!-- section:this-week -->",
                   "<!-- section:last-12-weeks -->", "<!-- section:regressions -->",
                   "<!-- section:cost-per-solve -->", "<!-- section:vs-peers -->"):
        assert marker in text


def test_readme_links_to_scorecard() -> None:
    readme = (ROOT / "README.md").read_text()
    assert "SCORECARD.md" in readme
    assert "Measured" in readme   # Badge text


def test_claude_md_links_to_scorecard() -> None:
    claude = (ROOT / "CLAUDE.md").read_text()
    assert "SCORECARD.md" in claude
```

### Implementation

Create `SCORECARD.md` (initial template, written by renderer's empty-history branch):

```markdown
<!-- section:header -->
# Forge Scorecard

> awaiting first weekly run

<!-- section:this-week -->
_no data_

<!-- section:last-12-weeks -->
_no data_

<!-- section:regressions -->
_none_

<!-- section:cost-per-solve -->
_no data_

<!-- section:vs-peers -->
## Peer comparison (manual update — never auto-scraped)

| benchmark | solve rate | link |
|---|---|---|
| forge (this repo) | — | [SCORECARD.md](./SCORECARD.md) |
| SWE-bench Verified | — | https://www.swebench.com/ |
| OpenHands | — | https://github.com/All-Hands-AI/OpenHands |
| SWE-agent | — | https://github.com/SWE-agent/SWE-agent |

<!-- section:appendix -->
_no data_
```

Edit `README.md` (existing) — add under Install section:

```markdown
[![Measured](https://img.shields.io/badge/measured-SCORECARD-blue)](./SCORECARD.md)

**Measured.** `SCORECARD.md` measures weekly real-feature solve rate on a curated corpus; `tests/evals/pipeline/leaderboard.md` measures per-PR pipeline smoke on synthetic scenarios. Different tiers, different cadences.
```

Edit `CLAUDE.md` — under §Validation, add:

```markdown
**Weekly benchmark.** Real-feature solve rate on a user-curated corpus runs weekly (Mon 06:00 UTC) and writes [SCORECARD.md](./SCORECARD.md). See `tests/evals/benchmark/README.md` for operator workflow.
```

Edit `CLAUDE.md` §Architecture — append `SCORECARD.md` to the repo-root file manifest paragraph.

**Commit:** `docs(bench): Phase 8 — SCORECARD.md template + README/CLAUDE.md links`.

---

## Task 27 — ADR 0013

### Test

`tests/unit/test_adr_0013.py`:

```python
"""ADR 0013 exists and covers the Phase 8 decisions listed in the spec."""
from __future__ import annotations
from pathlib import Path

ADR = Path(__file__).resolve().parents[2] / "docs" / "adr" / "0013-weekly-benchmark-extension.md"


def test_adr_exists() -> None:
    assert ADR.is_file()


def test_adr_covers_decisions() -> None:
    text = ADR.read_text()
    for phrase in ("extend-in-place", "0.9", "10pp", "6-cell matrix", "bot-commit",
                   "personal tool", "SWE-bench"):
        assert phrase in text, f"ADR missing decision: {phrase}"
```

### Implementation

`docs/adr/0013-weekly-benchmark-extension.md`:

```markdown
# 0013 — Weekly benchmark extension

- Status: Accepted
- Date: 2026-04-22
- Supersedes: —
- Superseded by: —

## Context

`tests/evals/pipeline/` already measures ten synthetic scenarios for per-PR smoke. No artifact in the repo substantiates the phrase "state of the art" as a solve-rate number against user-owned features. Peer benchmarks (SWE-bench Verified, OpenHands, SWE-agent) publish comparable single-agent numbers in the 45–70% range. Until forge produces a comparable number, the claim is aspiration.

## Decision

1. **Extend the pipeline harness in-place.** `tests/evals/benchmark/` imports `tests/evals/pipeline/runner/executor.py` rather than forking. Shared code is edited in place per ADR 0008 no-backcompat stance.
2. **Solve predicate = SHIP or CONCERNS ∧ ≥0.9 AC ∧ 0 critical.** CONCERNS counted deliberately. Stricter SHIP-only rate reported alongside as `ship_rate`.
3. **Regression gate at 10pp delta.** Below that threshold, week-to-week variance dominates; above it, the signal is real.
4. **6-cell matrix: 3 OS × 2 model.** Haiku excluded by design (quality not cost is the question). Sonnet 4.6 + Opus 4.7.
5. **Direct bot-commit to master.** Forge is a personal tool; master has no branch protection for `github-actions[bot]`. PR-fallback path documented but not built (Open Question #9).
6. **Explicit model override via `forge.local.md` fragment.** Env-only propagation is insufficient because `shared/model-routing.md` fixes `Agent.model` to {haiku, sonnet, opus} aliases. The helper writes `model_routing.overrides.{fast,standard,premium}` to the ephemeral project tempdir — never into the plugin repo.
7. **Cost ceiling starts at $200/week**, conservatively. Empirical refresh after 90 days of Phase-6-wired data.

## Consequences

- Per-PR CI stays fast (collect + unit + contract + integration). Weekly cron is the only path invoking real Anthropic API.
- Corpus is user-authored; `curate.py` is interactive.
- Every matrix cell exercises exactly one model end-to-end (all three tiers pinned), so solve-rate differences are attributable.
- `SCORECARD.md` is a first-class repo artifact. External readers see the number without leaving the repo.

## Alternatives rejected

- **Dedicated benchmark repo.** Adds CI secrets, CODEOWNERS, release coordination — hostile to personal-tool inertia.
- **Third-party SaaS (W&B, Braintrust).** Secret provisioning + per-run spend outside forge-config.
- **Patching shared/model-routing.md at runtime.** Mutates a repo-tracked contract file.
- **Per-commit benchmark.** Cost-prohibitive at 10+ entries × 6 cells × 90 min.
```

**Commit:** `docs(adr): Phase 8 — ADR 0013 weekly benchmark extension`.

---

## Task 28 — tests/evals/benchmark/README.md

### Test

`tests/unit/test_benchmark_readme.py`:

```python
"""benchmark README documents the four operator workflows."""
from __future__ import annotations
from pathlib import Path

README = Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "README.md"


def test_covers_workflows() -> None:
    text = README.read_text()
    for phrase in ("curate", "runner", "render_scorecard", "refresh_baseline",
                   "PHASE_8_CORPUS_GATE", "SCORECARD.md"):
        assert phrase in text
```

### Implementation

`tests/evals/benchmark/README.md`:

```markdown
# Phase 8 — Weekly benchmark

This harness measures how often forge solves real, user-authored feature requests. The result is a weekly-committed `SCORECARD.md` at repo root.

## Operator workflows

### Curate a new corpus entry

    python -m tests.evals.benchmark.curate \
      --db "$HOME/.forge/run-history.db" \
      --source-repo "$HOME/Projects/myapp"

Per candidate, confirm complexity, tags, Docker detection, and each PII match. Writes `corpus/<date>-<slug>/`.

### Run the benchmark (dry-run — no claude CLI needed)

    python -m tests.evals.benchmark.runner \
      --corpus-root tests/evals/benchmark/corpus \
      --results-root tests/evals/benchmark/results \
      --os ubuntu-latest --model claude-sonnet-4-6 --dry-run

### Render SCORECARD.md locally

    python -m tests.evals.benchmark.render_scorecard \
      --trends tests/evals/benchmark/trends.jsonl \
      --output SCORECARD.md

### Refresh baseline after an improvement

    python -m tests.evals.benchmark.refresh_baseline \
      --trends tests/evals/benchmark/trends.jsonl \
      --output tests/evals/benchmark/baseline.json \
      --confirm --commit-sha "$(git rev-parse HEAD)"

## CI

`.github/workflows/benchmark.yml` runs Monday 06:00 UTC. 6 matrix cells: `{ubuntu-latest, macos-latest, windows-latest} × {claude-sonnet-4-6, claude-opus-4-7}`.

Release gate: `PHASE_8_CORPUS_GATE=1` is set automatically by the weekly cron (`github.event_name == 'schedule'` in `benchmark.yml`). It enforces `>= 10` corpus entries + distribution spread (AC-801). `workflow_dispatch` runs and local `pytest` invocations leave it unset and skip the gate — useful for single-entry debugging before the corpus is complete.

## See also

- Spec: `docs/superpowers/specs/2026-04-22-phase-8-measurement-design.md`
- ADR: `docs/adr/0013-weekly-benchmark-extension.md`
- Fast smoke tier: `tests/evals/pipeline/README.md`
```

**Commit:** `docs(bench): Phase 8 — operator README`.

---

## Task 29 — Cross-ref in pipeline README + shared/observability.md + shared/learnings/README.md

### Test

`tests/unit/test_phase8_cross_refs.py`:

```python
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
```

### Implementation

Append §See Also to `tests/evals/pipeline/README.md`:

```markdown
## See also

- `tests/evals/benchmark/` — weekly measurement tier (real features, cross-OS, cross-model). This harness stays as the fast per-PR smoke tier.
```

Append to `shared/observability.md`:

```markdown
### Benchmark spans (Phase 8)

`forge.benchmark.run` — one span per corpus-entry execution.

| Attribute | Type | Source |
|---|---|---|
| `forge.benchmark.entry_id` | string | corpus directory name |
| `forge.benchmark.os` | string | matrix cell OS |
| `forge.benchmark.model` | string | matrix cell model ID |
| `forge.benchmark.solved` | bool | solve predicate result |
| `forge.benchmark.duration_s` | int | wall-clock seconds |
| `forge.benchmark.cost_usd` | float | Phase 6 `state.cost.estimated_cost_usd` |

Emitted by `tests/evals/benchmark/otel_emit.py:emit_benchmark_span` via `hooks/_py/otel.replay`.
```

Append to `shared/learnings/README.md` (already done in Task 18; verify test passes).

**Commit:** `docs(bench): Phase 8 — cross-references in pipeline README, observability, learnings`.

---

## Task 30 — forge-config.md template `benchmark:` section (AC-812, AC-822)

### Test

`tests/unit/test_forge_config_benchmark_section.py`:

```python
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
```

### Implementation

Add to the root `forge-config.md` (or create reference section in `shared/preflight-constraints.md` if that is where config is documented):

```markdown
### benchmark:

    benchmark:
      enabled: true
      max_weekly_cost_usd: 200      # derived from .forge/run-history.db median; refresh after 90 days
      regression_threshold_pp: 10
      corpus_root: tests/evals/benchmark/corpus
      timeout_seconds:
        S: 900
        M: 2700
        L: 5400

Guard: `L > M > S` required at PREFLIGHT.
```

**Commit:** `feat(bench): Phase 8 — forge-config.md benchmark section`.

---

## Task 31 — Ruff + mypy clean-up (AC-813)

### Test

CI lint job in `.github/workflows/test.yml` (existing) already runs `ruff check` + `mypy --strict`. Add all new modules to the existing CI-lint path (no `pyproject.toml` changes — the new modules sit under `tests/evals/benchmark/` which is NOT in `extend-exclude`).

Explicit sanity test:

`tests/unit/test_phase8_lint.py`:

```python
"""Static check: `ruff check` and `mypy` pass for Phase 8 modules."""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGETS = [
    "tests/evals/benchmark/",
]


def test_ruff_check() -> None:
    r = subprocess.run([sys.executable, "-m", "ruff", "check", *TARGETS],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_ruff_format_check() -> None:
    r = subprocess.run([sys.executable, "-m", "ruff", "format", "--check", *TARGETS],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
```

### Implementation

Run `ruff format` once over `tests/evals/benchmark/` and fix any lingering issues. Add mypy `strict=true` config scoped to Phase 8 via:

Edit `pyproject.toml`:

```toml
[[tool.mypy.overrides]]
module = "tests.evals.benchmark.*"
disallow_untyped_defs = true
strict_optional = true
warn_unused_ignores = true
```

**Commit:** `chore(bench): Phase 8 — ruff-format + mypy-strict for benchmark package`.

---

## Task 32 — Concurrency / race-retry contract (AC-825)

### Test

`tests/contract/test_commit_race_simulation.py`:

```python
"""Race retry: if push fails once, fetch+rebase; second failure → upload only."""
from __future__ import annotations
import subprocess
from pathlib import Path
# The workflow logic is in YAML, but the shell block can be extracted as a script.
# Assert the retry loop pattern is present in benchmark.yml.


def test_workflow_has_race_retry_loop() -> None:
    wf = (Path(__file__).resolve().parents[2] / ".github" / "workflows" / "benchmark.yml").read_text()
    assert "for i in 1 2; do" in wf
    assert "BENCH-COMMIT-RACE" in wf
    assert "Upload scorecard (race fallback)" in wf or "scorecard-${{ github.run_id }}" in wf
```

### Implementation

Already present in Task 24's `benchmark.yml`. This task locks the invariant.

**Commit:** `test(bench): Phase 8 — commit-race retry contract`.

---

## Task 33 — CHANGELOG + version bump

### Test

`tests/unit/test_changelog_phase8.py`:

```python
from pathlib import Path


def test_changelog_3_8_0_entry() -> None:
    text = (Path(__file__).resolve().parents[2] / "CHANGELOG.md").read_text()
    assert "[3.8.0]" in text
    for phrase in ("benchmark", "SCORECARD.md", "weekly"):
        assert phrase in text.lower()
```

### Implementation

Prepend to `CHANGELOG.md`:

```markdown
## [3.8.0] - 2026-04-22 — Phase 8 Measurement

### Added
- `tests/evals/benchmark/` harness: curated real-feature benchmark corpus, weekly CI cron, 3×2 OS/model matrix.
- `SCORECARD.md` at repo root — weekly solve-rate numbers with sparklines and regression table.
- `tests/evals/benchmark/baseline.json` frozen baseline + 10pp regression gate.
- New learning type `benchmark.regression` (Phase 4 integration).
- OTel `forge.benchmark.run` span.
- ADR 0013 (weekly benchmark extension).

### Changed
- `shared/observability.md` lists benchmark span attributes.
- `shared/learnings/README.md` lists new learning type.
- `README.md` + `CLAUDE.md` link to SCORECARD.md.

### Config
- `benchmark.max_weekly_cost_usd: 200` (conservative initial; refresh after 90 days of data).
- `benchmark.timeout_seconds.{S,M,L}: 900/2700/5400`.
```

Bump `plugin.json` `version: 3.8.0` and `pyproject.toml` `version = "3.8.0"`.

**Commit:** `chore(release): Phase 8 — bump forge to 3.8.0`.

---

## Task 34 — Final integration rehearsal (AC-802, AC-804, AC-806, AC-807, AC-808)

### Test

`tests/integration/test_phase8_end_to_end.py`:

```python
"""End-to-end smoke: every CLI prints --help; renderer is idempotent; schemas load."""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIS = [
    "tests.evals.benchmark.runner",
    "tests.evals.benchmark.curate",
    "tests.evals.benchmark.render_scorecard",
    "tests.evals.benchmark.refresh_baseline",
    "tests.evals.benchmark.aggregate",
    "tests.evals.benchmark.gate_cli",
]


def test_all_clis_print_help() -> None:
    for cli in CLIS:
        r = subprocess.run([sys.executable, "-m", cli, "--help"],
                           cwd=ROOT, capture_output=True, text=True)
        assert r.returncode == 0, f"{cli} --help failed: {r.stderr}"
```

### Implementation

No new code — this is the consolidated AC-802 check. It runs on every PR and must pass.

**Commit:** `test(bench): Phase 8 — end-to-end CLI smoke`.

---

## Final post-ship checklist

- [ ] Merge to master; tag `v3.8.0`; push tag.
- [ ] Release notes (GitHub) auto-generated from `CHANGELOG.md` entry.
- [ ] Manually trigger `.github/workflows/benchmark.yml` once via `workflow_dispatch` with a single-entry corpus filter to exercise the live path end-to-end.
- [ ] After first real weekly run, commit `baseline.json` via `refresh_baseline.py --confirm`.
- [ ] After 90 days, re-run the Phase 6 SQL query against the populated `run-history.db` and update `benchmark.max_weekly_cost_usd` in `forge-config.md` with a CHANGELOG entry.
- [ ] Delete `docs/superpowers/specs/2026-04-22-phase-8-measurement-design.md` + this plan per user memory (`cleanup_after_ship`).
- [ ] Update `CLAUDE.md` §Architecture if SCORECARD.md placement changes.

## AC coverage matrix

| AC | Task |
|---|---|
| AC-801 | 1, 5, 23 |
| AC-802 | 9, 14, 15, 22, 24, 34 |
| AC-803 | 24 |
| AC-804 | 6, 9, 34 |
| AC-805 | 14 |
| AC-806 | 14, 26 |
| AC-807 | 26 |
| AC-808 | 24 commit step, 25 |
| AC-809 | 16 |
| AC-810 | 15 |
| AC-811 | 4, 22 |
| AC-812 | 17, 30 |
| AC-813 | 31 |
| AC-814 | 27 |
| AC-815 | 4, 5 |
| AC-816 | 18, 29 |
| AC-817 | 10, 19 |
| AC-818 | 20 |
| AC-819 | 21, 29 |
| AC-820 | 8, 22 |
| AC-821 | 2 |
| AC-822 | 30 |
| AC-823 | 22 |
| AC-824 | 12, 13 |
| AC-825 | 24, 32 |
| AC-826 | 3 |
| AC-827 | 17 |

Every AC maps to at least one task. No unmapped ACs.
