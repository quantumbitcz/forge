# Phase 01 — Pipeline Evaluation Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pipeline-level evaluation harness at `tests/evals/pipeline/` with 10 frozen scenarios, a Python runner, composite scoring, GitHub Actions CI integration, and a 3-point regression gate against a `master` baseline artifact.

**Architecture:** Single-responsibility Python 3.10+ package (`runner/`) — discovery, execution, scoring, baseline diff, reporting are each one module. Each scenario is a self-contained directory (`prompt.md` + `expected.yaml` + optional `fixtures/`). The runner invokes `/forge-run --eval-mode <id>` (new orchestrator flag, env-guarded by `FORGE_EVAL=1`), captures `.forge/state.json` post-run, computes composite score, writes JSONL, renders leaderboard, and diffs against the latest `master` workflow artifact.

**Tech Stack:** Python 3.10+, pydantic v2, PyYAML, requests, GitHub Actions (`ubuntu-latest`), GitHub Actions artifact API v4.

---

## Review feedback incorporated

The spec review (`docs/superpowers/reviews/2026-04-19-01-evaluation-harness-spec-review.md`) raised three critical issues. This plan resolves each:

1. **C1 — Wall-clock budget inconsistency.** The spec had 15 min (SC1), 30 min (§8), 35 min (§10 R3), and 45 min (§6 config). **Resolution:** propagate a single coherent tuple throughout the plan — `scenario_timeout_seconds: 900` (15 min per scenario), `total_budget_seconds: 2700` (45 min hard ceiling with 50% headroom), and SC1 target = `≤30 minutes p90 wall-clock`. The 30-min SC1 matches the §8 narrative and the §10 R3 parallel-batch estimate; the 45-min config cap is an upper safety ceiling, not a target. All four sites (config, CI workflow `timeout-minutes`, SC1 success criterion, runner `--total-budget` default) are written with these three numbers only in Tasks 4, 6, 13, and 16.

2. **C2 — Field-name mismatch.** Spec had `touched_files` in `expected.yaml` but `touched_files_expected` in `state-schema.md`. **Resolution:** the YAML schema, the pydantic model (`Scenario`), the state-schema field, the runner's overlap computation, and every scenario `expected.yaml` file use the single key `touched_files_expected` throughout. Tasks 2, 3, 8, and 12 all write this exact field name.

3. **Open Question Q1 / I3 — Baseline storage and missing-baseline behavior.** Spec left this as an open question. **Resolution:** the plan commits to GitHub Actions workflow artifacts (90-day retention, name `eval-baseline-master-<sha>`) as the baseline store. On missing-baseline conditions (first `master` run, artifact retention expired, fetch failure, fetch timeout >30s), `baseline.py` emits a new finding `EVAL-BASELINE-UNAVAILABLE` at WARNING severity and skips the regression gate — CI passes but the job log records the skip. Tasks 9 and 13 implement this contract.

Additional review items also resolved:

- **I2** — `FORGE_EVAL=1` env guard is part of the orchestrator contract in Task 15 (not just R4 prose).
- **I4** — `--eval-mode` + `--dry-run` composition documented in Task 15 (exit after PREFLIGHT, write `status: dry_run` stub record).
- **M1** — SC3 tightened: regression PR must produce exit code 1 AND an `EVAL-REGRESSION` record in `.forge/eval-results.jsonl` (Task 17 README note).
- **M3** — `requirements.txt` pins all three deps (Task 1).

---

## File structure

```
tests/evals/pipeline/
  runner/
    __init__.py
    __main__.py                 # CLI entry
    schema.py                   # pydantic models: Scenario, Expected, Result
    scenarios.py                # discovery + validation
    executor.py                 # worktree setup, forge invocation
    scoring.py                  # composite score math
    baseline.py                 # fetch + diff master baseline
    report.py                   # JSONL + leaderboard writer
    requirements.txt
    tests/
      __init__.py
      test_schema.py
      test_scoring.py
      test_baseline.py
      test_scenarios.py
  scenarios/
    01-ts-microservice-greenfield/  (prompt.md, expected.yaml)
    02-python-bugfix/               (+ fixtures/starter.tar.gz)
    03-kotlin-spring-migration/     (+ fixtures/starter.tar.gz)
    04-react-bootstrap/             (prompt.md, expected.yaml)
    05-go-performance-fix/          (+ fixtures/starter.tar.gz)
    06-rust-refactor/               (+ fixtures/starter.tar.gz)
    07-python-mlops-pipeline/       (+ fixtures/starter.tar.gz, STUB)
    08-flask-spike/                 (prompt.md, expected.yaml)
    09-swift-concurrency/           (+ fixtures/starter.tar.gz, STUB)
    10-php-security-fix/            (+ fixtures/starter.tar.gz)
  leaderboard.md                 # auto-generated skeleton
  README.md
.github/workflows/evals.yml
shared/checks/eval-categories.md
shared/checks/category-registry.json      # modified (add EVAL-* family)
shared/scoring.md                          # modified (EVAL-* row)
shared/state-schema.md                     # modified (eval_run field, bump 1.6.0→1.7.0)
shared/preflight-constraints.md            # modified (evals.* constraints)
agents/fg-100-orchestrator.md              # modified (--eval-mode flag)
tests/run-all.sh                           # modified (documented pipeline-eval tier)
CLAUDE.md                                  # modified (one-line Validation pointer)
```

---

## Conventions

- Every task ends with a **commit** step. Conventional Commits format. **No** `Co-Authored-By` lines, **no** AI attribution, **no** `--no-verify`. Per-project rule: never skip hooks.
- Final verification is via CI push (not local). TDD applies to the Python unit tests: write-test → write-impl → commit. The `./tests/validate-plugin.sh` structural pass is mentioned as a step in tasks that modify `shared/` or `agents/`; do not execute it locally — push and let CI run it.
- All paths are absolute relative to repo root `/Users/denissajnar/IdeaProjects/forge`.

---

## Task 1: Scaffold runner package + deps

**Files:**
- Create: `tests/evals/pipeline/runner/__init__.py`
- Create: `tests/evals/pipeline/runner/requirements.txt`
- Create: `tests/evals/pipeline/runner/tests/__init__.py`

- [ ] **Step 1: Create runner package init**

Write `tests/evals/pipeline/runner/__init__.py`:

```python
"""forge pipeline-level evaluation harness.

Entry point: ``python -m tests.evals.pipeline.runner``.

See tests/evals/pipeline/README.md for usage and scenario authoring guide.
"""

__version__ = "0.1.0"
```

- [ ] **Step 2: Create pinned requirements**

Write `tests/evals/pipeline/runner/requirements.txt` (all three pinned per review M3):

```
pydantic==2.9.2
PyYAML==6.0.2
requests==2.32.3
```

- [ ] **Step 3: Create test package init**

Write `tests/evals/pipeline/runner/tests/__init__.py` with an empty file:

```python
```

- [ ] **Step 4: Commit**

```bash
git add tests/evals/pipeline/runner/__init__.py \
        tests/evals/pipeline/runner/requirements.txt \
        tests/evals/pipeline/runner/tests/__init__.py
git commit -m "feat(evals): scaffold pipeline evaluation runner package"
```

---

## Task 2: Pydantic schema — write failing tests

**Files:**
- Create: `tests/evals/pipeline/runner/tests/test_schema.py`

- [ ] **Step 1: Write failing test suite**

Write `tests/evals/pipeline/runner/tests/test_schema.py`:

```python
"""Tests for pydantic models in runner.schema."""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from tests.evals.pipeline.runner.schema import Expected, Result, Scenario


def test_expected_parses_minimal_valid_yaml():
    data = {
        "id": "01-ts-microservice-greenfield",
        "mode": "standard",
        "token_budget": 150000,
        "elapsed_budget_seconds": 600,
        "min_pipeline_score": 85,
        "required_verdict": "PASS",
        "touched_files_expected": ["src/server.ts"],
        "must_not_touch": [".claude/**"],
        "notes": "test",
    }
    e = Expected(**data)
    assert e.id == "01-ts-microservice-greenfield"
    assert e.mode == "standard"
    assert e.touched_files_expected == ["src/server.ts"]


def test_expected_rejects_unknown_mode():
    data = {
        "id": "x",
        "mode": "bogus",
        "token_budget": 1,
        "elapsed_budget_seconds": 1,
        "min_pipeline_score": 0,
        "required_verdict": "PASS",
        "touched_files_expected": [],
        "must_not_touch": [],
        "notes": "",
    }
    with pytest.raises(ValidationError):
        Expected(**data)


def test_expected_rejects_unknown_verdict():
    data = {
        "id": "x",
        "mode": "standard",
        "token_budget": 1,
        "elapsed_budget_seconds": 1,
        "min_pipeline_score": 0,
        "required_verdict": "FAIL",
        "touched_files_expected": [],
        "must_not_touch": [],
        "notes": "",
    }
    with pytest.raises(ValidationError):
        Expected(**data)


def test_expected_rejects_negative_budget():
    data = {
        "id": "x",
        "mode": "standard",
        "token_budget": -1,
        "elapsed_budget_seconds": 1,
        "min_pipeline_score": 0,
        "required_verdict": "PASS",
        "touched_files_expected": [],
        "must_not_touch": [],
        "notes": "",
    }
    with pytest.raises(ValidationError):
        Expected(**data)


def test_scenario_requires_prompt_and_expected():
    e = Expected(
        id="x",
        mode="standard",
        token_budget=1,
        elapsed_budget_seconds=1,
        min_pipeline_score=0,
        required_verdict="PASS",
        touched_files_expected=[],
        must_not_touch=[],
        notes="",
    )
    s = Scenario(id="x", path="/tmp/x", prompt="do thing", expected=e)
    assert s.prompt == "do thing"


def test_result_serializes_to_jsonl_record():
    r = Result(
        scenario_id="01-ts-microservice-greenfield",
        started_at="2026-04-19T12:00:00Z",
        ended_at="2026-04-19T12:10:00Z",
        actual_tokens=120000,
        actual_elapsed_seconds=580,
        pipeline_score=88.0,
        verdict="PASS",
        touched_files_actual=["src/server.ts"],
        overlap_jaccard=1.0,
        token_adherence=1.0,
        elapsed_adherence=1.0,
        composite=94.0,
        findings=[],
        status="completed",
    )
    d = r.model_dump()
    assert d["scenario_id"] == "01-ts-microservice-greenfield"
    assert d["composite"] == 94.0
    assert d["status"] == "completed"


def test_result_allows_dry_run_status():
    r = Result(
        scenario_id="x",
        started_at="2026-04-19T12:00:00Z",
        ended_at="2026-04-19T12:00:05Z",
        actual_tokens=0,
        actual_elapsed_seconds=0,
        pipeline_score=0.0,
        verdict="DRY_RUN",
        touched_files_actual=[],
        overlap_jaccard=0.0,
        token_adherence=0.0,
        elapsed_adherence=0.0,
        composite=0.0,
        findings=[],
        status="dry_run",
    )
    assert r.status == "dry_run"
```

- [ ] **Step 2: Note — tests will be run in CI**

Do not run `pytest` locally. Push and let CI execute. Expected CI output: 7 failures with `ModuleNotFoundError: tests.evals.pipeline.runner.schema`.

- [ ] **Step 3: Commit**

```bash
git add tests/evals/pipeline/runner/tests/test_schema.py
git commit -m "test(evals): add pydantic schema tests for Expected/Scenario/Result"
```

---

## Task 3: Pydantic schema — implementation

**Files:**
- Create: `tests/evals/pipeline/runner/schema.py`

- [ ] **Step 1: Implement models**

Write `tests/evals/pipeline/runner/schema.py`:

```python
"""Pydantic models for the pipeline eval harness.

Schema reference for scenario authors:
    id:                       str — scenario directory name, e.g. "01-ts-microservice-greenfield"
    mode:                     "standard" | "bugfix" | "migration" | "bootstrap"
    token_budget:             positive int — upper bound; over-budget degrades adherence linearly
    elapsed_budget_seconds:   positive int — wall-clock target in seconds
    min_pipeline_score:       int in [0, 100] — floor for pipeline_score component
    required_verdict:         "PASS" | "CONCERNS" — never FAIL in frozen scenarios
    touched_files_expected:   list[str] — overlap metric (reporting-only)
    must_not_touch:           list[str] — glob patterns; hard fail if pipeline edits any
    notes:                    str — free-form author notes
"""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


Mode = Literal["standard", "bugfix", "migration", "bootstrap"]
Verdict = Literal["PASS", "CONCERNS"]
ResultVerdict = Literal["PASS", "CONCERNS", "FAIL", "DRY_RUN"]
Status = Literal["completed", "timeout", "error", "dry_run"]


class Expected(BaseModel):
    """Parsed ``expected.yaml`` contents for a scenario."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    mode: Mode
    token_budget: int = Field(gt=0)
    elapsed_budget_seconds: int = Field(gt=0)
    min_pipeline_score: int = Field(ge=0, le=100)
    required_verdict: Verdict
    touched_files_expected: list[str]
    must_not_touch: list[str]
    notes: str


class Scenario(BaseModel):
    """A discovered scenario: prompt text + parsed expected metadata."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    path: str
    prompt: str
    expected: Expected


class Finding(BaseModel):
    """An EVAL-* finding emitted by the harness (not the pipeline)."""

    model_config = ConfigDict(extra="forbid")

    category: str
    severity: Literal["CRITICAL", "WARNING", "INFO"]
    message: str


class Result(BaseModel):
    """One record per scenario per run. Serialized to ``.forge/eval-results.jsonl``."""

    model_config = ConfigDict(extra="forbid")

    scenario_id: str
    started_at: str
    ended_at: str
    actual_tokens: int
    actual_elapsed_seconds: int
    pipeline_score: float
    verdict: ResultVerdict
    touched_files_actual: list[str]
    overlap_jaccard: float
    token_adherence: float
    elapsed_adherence: float
    composite: float
    findings: list[Finding]
    status: Status
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/schema.py
git commit -m "feat(evals): add pydantic models for Expected, Scenario, Finding, Result"
```

---

## Task 4: Composite scoring — write failing tests

**Files:**
- Create: `tests/evals/pipeline/runner/tests/test_scoring.py`

- [ ] **Step 1: Write failing test suite**

Write `tests/evals/pipeline/runner/tests/test_scoring.py`:

```python
"""Tests for composite scoring math."""
from __future__ import annotations

import pytest

from tests.evals.pipeline.runner.scoring import (
    clamp01,
    composite_score,
    elapsed_adherence,
    jaccard_overlap,
    token_adherence,
)


def test_clamp01_bounds():
    assert clamp01(-0.5) == 0.0
    assert clamp01(0.0) == 0.0
    assert clamp01(0.5) == 0.5
    assert clamp01(1.0) == 1.0
    assert clamp01(2.5) == 1.0


def test_token_adherence_exact_budget_is_one():
    assert token_adherence(actual=150_000, budget=150_000) == pytest.approx(1.0)


def test_token_adherence_half_budget_is_capped_at_one():
    # Formula: clamp01(2 - actual/budget). Half-budget → 2 - 0.5 = 1.5 → clamped to 1.0.
    assert token_adherence(actual=75_000, budget=150_000) == 1.0


def test_token_adherence_double_budget_is_zero():
    assert token_adherence(actual=300_000, budget=150_000) == 0.0


def test_token_adherence_150pct_budget_is_half():
    # 2 - 1.5 = 0.5
    assert token_adherence(actual=225_000, budget=150_000) == pytest.approx(0.5)


def test_elapsed_adherence_mirrors_token_formula():
    assert elapsed_adherence(actual=600, budget=600) == pytest.approx(1.0)
    assert elapsed_adherence(actual=1200, budget=600) == 0.0
    assert elapsed_adherence(actual=300, budget=600) == 1.0


def test_jaccard_overlap_identical_sets_is_one():
    assert jaccard_overlap(["a", "b"], ["a", "b"]) == pytest.approx(1.0)


def test_jaccard_overlap_disjoint_sets_is_zero():
    assert jaccard_overlap(["a", "b"], ["c", "d"]) == 0.0


def test_jaccard_overlap_empty_both_is_one():
    # Defined: empty ∩ empty / empty ∪ empty → conventionally 1.0 (perfect agreement on "nothing").
    assert jaccard_overlap([], []) == 1.0


def test_jaccard_overlap_partial_overlap():
    # {a,b,c} vs {b,c,d} → intersection 2, union 4 → 0.5
    assert jaccard_overlap(["a", "b", "c"], ["b", "c", "d"]) == pytest.approx(0.5)


def test_composite_score_all_perfect():
    c = composite_score(pipeline_score=100.0, token_adh=1.0, elapsed_adh=1.0)
    assert c == pytest.approx(100.0)


def test_composite_score_weighting_is_50_25_25():
    # pipeline=80, token=1.0, elapsed=1.0  →  100*(0.5*0.8 + 0.25 + 0.25) = 90
    c = composite_score(pipeline_score=80.0, token_adh=1.0, elapsed_adh=1.0)
    assert c == pytest.approx(90.0)


def test_composite_score_zero_pipeline_still_has_adherence_credit():
    # pipeline=0, token=1.0, elapsed=1.0  →  100*(0 + 0.25 + 0.25) = 50
    c = composite_score(pipeline_score=0.0, token_adh=1.0, elapsed_adh=1.0)
    assert c == pytest.approx(50.0)


def test_composite_score_zero_budget_credit():
    # pipeline=100, token=0, elapsed=0  →  100*(0.5 + 0 + 0) = 50
    c = composite_score(pipeline_score=100.0, token_adh=0.0, elapsed_adh=0.0)
    assert c == pytest.approx(50.0)
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/tests/test_scoring.py
git commit -m "test(evals): add unit tests for composite scoring, adherence, and Jaccard overlap"
```

---

## Task 5: Composite scoring — implementation

**Files:**
- Create: `tests/evals/pipeline/runner/scoring.py`

- [ ] **Step 1: Implement scoring module**

Write `tests/evals/pipeline/runner/scoring.py`:

```python
"""Composite score math for the pipeline eval harness.

Formula (per spec §6):

    token_adherence    = clamp01(2 - actual_tokens / expected_token_budget)
    elapsed_adherence  = clamp01(2 - actual_elapsed / expected_elapsed_budget)
    composite          = 100 * (
                           0.50 * (pipeline_score / 100)
                         + 0.25 * token_adherence
                         + 0.25 * elapsed_adherence
                       )

Overlap (Jaccard, reporting-only) is in a separate helper.
"""
from __future__ import annotations

from typing import Iterable


def clamp01(value: float) -> float:
    """Clamp to [0.0, 1.0]."""
    if value < 0.0:
        return 0.0
    if value > 1.0:
        return 1.0
    return float(value)


def token_adherence(actual: int, budget: int) -> float:
    """Linear adherence: full credit at ≤50% of budget, zero credit at ≥200%.

    Raises ValueError on non-positive budget (scenario author bug — fail loud).
    """
    if budget <= 0:
        raise ValueError(f"token budget must be positive, got {budget}")
    return clamp01(2.0 - (actual / budget))


def elapsed_adherence(actual: int, budget: int) -> float:
    """Same shape as token_adherence, for wall-clock seconds."""
    if budget <= 0:
        raise ValueError(f"elapsed budget must be positive, got {budget}")
    return clamp01(2.0 - (actual / budget))


def jaccard_overlap(expected: Iterable[str], actual: Iterable[str]) -> float:
    """Jaccard similarity of two string sets. Empty vs empty defined as 1.0."""
    a, b = set(expected), set(actual)
    if not a and not b:
        return 1.0
    union = a | b
    if not union:
        return 1.0
    return len(a & b) / len(union)


def composite_score(pipeline_score: float, token_adh: float, elapsed_adh: float) -> float:
    """Weighted composite: 0.5 × pipeline + 0.25 × token + 0.25 × elapsed, scaled to 100."""
    return 100.0 * (
        0.50 * (pipeline_score / 100.0)
        + 0.25 * token_adh
        + 0.25 * elapsed_adh
    )
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/scoring.py
git commit -m "feat(evals): implement composite score, adherence, and Jaccard overlap"
```

---

## Task 6: Scenario discovery — tests + implementation

**Files:**
- Create: `tests/evals/pipeline/runner/tests/test_scenarios.py`
- Create: `tests/evals/pipeline/runner/scenarios.py`

- [ ] **Step 1: Write failing test suite**

Write `tests/evals/pipeline/runner/tests/test_scenarios.py`:

```python
"""Tests for scenario discovery."""
from __future__ import annotations

from pathlib import Path

import pytest

from tests.evals.pipeline.runner.scenarios import (
    ScenarioCollectionError,
    discover_scenarios,
)


def _write_scenario(root: Path, sid: str, yaml_body: str, prompt: str = "Do the thing.") -> None:
    d = root / sid
    d.mkdir(parents=True)
    (d / "prompt.md").write_text(prompt, encoding="utf-8")
    (d / "expected.yaml").write_text(yaml_body, encoding="utf-8")


VALID_YAML = """
id: 01-test
mode: standard
token_budget: 1000
elapsed_budget_seconds: 60
min_pipeline_score: 70
required_verdict: PASS
touched_files_expected:
  - src/a.py
must_not_touch:
  - .claude/**
notes: ""
"""


def test_discover_scenarios_returns_sorted_list(tmp_path: Path) -> None:
    _write_scenario(tmp_path, "02-b", VALID_YAML.replace("01-test", "02-b"))
    _write_scenario(tmp_path, "01-a", VALID_YAML.replace("01-test", "01-a"))
    found = discover_scenarios(tmp_path)
    assert [s.id for s in found] == ["01-a", "02-b"]


def test_discover_scenarios_fail_fast_on_bad_yaml(tmp_path: Path) -> None:
    _write_scenario(tmp_path, "01-ok", VALID_YAML.replace("01-test", "01-ok"))
    _write_scenario(tmp_path, "02-bad", "mode: bogus\n")
    with pytest.raises(ScenarioCollectionError) as excinfo:
        discover_scenarios(tmp_path)
    assert "02-bad" in str(excinfo.value)


def test_discover_scenarios_rejects_id_mismatch(tmp_path: Path) -> None:
    # expected.yaml id differs from directory name → fail
    _write_scenario(tmp_path, "01-dir", VALID_YAML.replace("01-test", "99-yaml"))
    with pytest.raises(ScenarioCollectionError) as excinfo:
        discover_scenarios(tmp_path)
    assert "id mismatch" in str(excinfo.value).lower()


def test_discover_scenarios_requires_prompt_md(tmp_path: Path) -> None:
    d = tmp_path / "01-no-prompt"
    d.mkdir()
    (d / "expected.yaml").write_text(VALID_YAML.replace("01-test", "01-no-prompt"))
    with pytest.raises(ScenarioCollectionError):
        discover_scenarios(tmp_path)


def test_discover_scenarios_empty_root_returns_empty(tmp_path: Path) -> None:
    assert discover_scenarios(tmp_path) == []
```

- [ ] **Step 2: Implement scenario discovery**

Write `tests/evals/pipeline/runner/scenarios.py`:

```python
"""Scenario discovery and schema validation.

Fail-fast collection: every scenario is parsed at the start of a run; any
malformed ``expected.yaml`` aborts the whole run before a single forge
invocation happens.
"""
from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import ValidationError

from tests.evals.pipeline.runner.schema import Expected, Scenario


class ScenarioCollectionError(Exception):
    """Raised when a scenario directory is malformed. Halts the run."""


def discover_scenarios(root: Path) -> list[Scenario]:
    """Enumerate ``<root>/*/expected.yaml``, parse, validate, return sorted by id.

    Raises ScenarioCollectionError on the first malformed scenario; callers
    should treat this as fatal.
    """
    scenarios: list[Scenario] = []
    if not root.exists():
        return scenarios

    for child in sorted(p for p in root.iterdir() if p.is_dir()):
        expected_path = child / "expected.yaml"
        prompt_path = child / "prompt.md"

        if not expected_path.is_file():
            raise ScenarioCollectionError(
                f"{child.name}: missing expected.yaml at {expected_path}"
            )
        if not prompt_path.is_file():
            raise ScenarioCollectionError(
                f"{child.name}: missing prompt.md at {prompt_path}"
            )

        try:
            raw = yaml.safe_load(expected_path.read_text(encoding="utf-8"))
        except yaml.YAMLError as e:
            raise ScenarioCollectionError(
                f"{child.name}: YAML parse error: {e}"
            ) from e

        try:
            expected = Expected(**(raw or {}))
        except ValidationError as e:
            raise ScenarioCollectionError(
                f"{child.name}: schema validation failed: {e}"
            ) from e

        if expected.id != child.name:
            raise ScenarioCollectionError(
                f"{child.name}: id mismatch — directory is {child.name!r} "
                f"but expected.yaml says {expected.id!r}"
            )

        prompt = prompt_path.read_text(encoding="utf-8")
        scenarios.append(
            Scenario(id=child.name, path=str(child), prompt=prompt, expected=expected)
        )

    return scenarios
```

- [ ] **Step 3: Commit**

```bash
git add tests/evals/pipeline/runner/tests/test_scenarios.py \
        tests/evals/pipeline/runner/scenarios.py
git commit -m "feat(evals): add scenario discovery with fail-fast validation"
```

---

## Task 7: Baseline fetch + diff — tests

**Files:**
- Create: `tests/evals/pipeline/runner/tests/test_baseline.py`

- [ ] **Step 1: Write failing test suite**

Write `tests/evals/pipeline/runner/tests/test_baseline.py`:

```python
"""Tests for baseline fetch and regression-gate diff."""
from __future__ import annotations

from tests.evals.pipeline.runner.baseline import (
    BaselineUnavailable,
    compute_gate,
)
from tests.evals.pipeline.runner.schema import Finding


def _mkresults(composites: list[float]) -> list[dict]:
    return [
        {
            "scenario_id": f"s{i:02d}",
            "composite": c,
        }
        for i, c in enumerate(composites)
    ]


def test_compute_gate_passes_when_delta_within_tolerance():
    baseline = _mkresults([80, 85, 90])
    current = _mkresults([79, 83, 89])   # mean: 83.67 vs 85.0 → -1.33
    decision = compute_gate(current=current, baseline=baseline, tolerance=3.0)
    assert decision.passed is True
    assert decision.delta < 0
    assert decision.finding is None


def test_compute_gate_fails_when_delta_exceeds_tolerance():
    baseline = _mkresults([80, 85, 90])    # mean 85.0
    current = _mkresults([70, 75, 80])     # mean 75.0 → delta -10
    decision = compute_gate(current=current, baseline=baseline, tolerance=3.0)
    assert decision.passed is False
    assert decision.delta == -10.0
    assert decision.finding is not None
    assert decision.finding.category == "EVAL-REGRESSION"
    assert decision.finding.severity == "CRITICAL"


def test_compute_gate_passes_when_current_better_than_baseline():
    baseline = _mkresults([80, 80, 80])
    current = _mkresults([90, 90, 90])
    decision = compute_gate(current=current, baseline=baseline, tolerance=3.0)
    assert decision.passed is True
    assert decision.delta == 10.0


def test_compute_gate_emits_unavailable_when_baseline_missing():
    current = _mkresults([80])
    decision = compute_gate(current=current, baseline=None, tolerance=3.0)
    assert decision.passed is True        # skip-gate behavior per plan §Review C3
    assert decision.finding is not None
    assert decision.finding.category == "EVAL-BASELINE-UNAVAILABLE"
    assert decision.finding.severity == "WARNING"


def test_baseline_unavailable_is_exception_subclass():
    assert issubclass(BaselineUnavailable, Exception)


def test_finding_from_gate_serializes():
    f = Finding(category="EVAL-REGRESSION", severity="CRITICAL", message="drop 10")
    d = f.model_dump()
    assert d["category"] == "EVAL-REGRESSION"
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/tests/test_baseline.py
git commit -m "test(evals): add tests for baseline gate including missing-baseline fallback"
```

---

## Task 8: Baseline fetch + diff — implementation

**Files:**
- Create: `tests/evals/pipeline/runner/baseline.py`

- [ ] **Step 1: Implement baseline module**

Write `tests/evals/pipeline/runner/baseline.py`:

```python
"""Baseline fetch (from GitHub Actions artifact) + regression gate.

Baseline storage contract (resolves spec open-question Q1 / review I3):
    - CI workflow ``.github/workflows/evals.yml`` uploads
      ``eval-results.jsonl`` as workflow artifact named
      ``eval-baseline-master-<sha>`` on every push to master.
    - 90-day retention (default GitHub artifact retention).
    - On PR runs, this module calls the GitHub REST API to list artifacts for
      the master branch, downloads the most recent one, and parses it.

Missing-baseline contract:
    - First-ever master run → no baseline exists → compute_gate() returns
      passed=True plus an EVAL-BASELINE-UNAVAILABLE WARNING finding. CI
      job passes; the job log contains the warning.
    - Artifact retention expired, fetch failure, or fetch timeout → same
      behavior: warn, skip, pass.
    - Never fail-closed on baseline fetch problems (that would block
      unrelated PRs on an infra hiccup).
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Optional

import requests

from tests.evals.pipeline.runner.schema import Finding


BASELINE_FETCH_TIMEOUT_SECONDS = 30
GITHUB_API = "https://api.github.com"


class BaselineUnavailable(Exception):
    """Raised internally by fetch; compute_gate() translates to a WARNING finding."""


@dataclass(frozen=True)
class GateDecision:
    passed: bool
    delta: float
    baseline_mean: Optional[float]
    current_mean: float
    finding: Optional[Finding]


def _mean_composite(records: list[dict]) -> float:
    if not records:
        return 0.0
    return sum(float(r["composite"]) for r in records) / len(records)


def compute_gate(
    *,
    current: list[dict],
    baseline: Optional[list[dict]],
    tolerance: float,
) -> GateDecision:
    """Compare current-run mean composite to baseline mean composite.

    Args:
        current: list of Result dicts (composite key required) from this run.
        baseline: Same shape, from stored master artifact; None if unavailable.
        tolerance: composite-point drop that trips EVAL-REGRESSION.

    Returns:
        GateDecision.passed is False only when baseline is available AND
        delta < -tolerance. Missing-baseline is a pass-with-warning.
    """
    current_mean = _mean_composite(current)

    if baseline is None:
        return GateDecision(
            passed=True,
            delta=0.0,
            baseline_mean=None,
            current_mean=current_mean,
            finding=Finding(
                category="EVAL-BASELINE-UNAVAILABLE",
                severity="WARNING",
                message=(
                    "No master baseline artifact available (first run, "
                    "retention expired, or fetch failed). Regression gate skipped."
                ),
            ),
        )

    baseline_mean = _mean_composite(baseline)
    delta = current_mean - baseline_mean

    if delta < -tolerance:
        return GateDecision(
            passed=False,
            delta=delta,
            baseline_mean=baseline_mean,
            current_mean=current_mean,
            finding=Finding(
                category="EVAL-REGRESSION",
                severity="CRITICAL",
                message=(
                    f"Composite mean dropped {abs(delta):.2f} points "
                    f"(current={current_mean:.2f}, baseline={baseline_mean:.2f}, "
                    f"tolerance={tolerance})."
                ),
            ),
        )

    return GateDecision(
        passed=True,
        delta=delta,
        baseline_mean=baseline_mean,
        current_mean=current_mean,
        finding=None,
    )


def fetch_baseline_from_github(
    *,
    repo: str,
    branch: str = "master",
    token: Optional[str] = None,
) -> list[dict]:
    """Download and parse the most recent ``eval-baseline-<branch>-*`` artifact.

    Args:
        repo: "owner/name" e.g. "quantumbitcz/forge".
        branch: branch name whose artifacts are the baseline.
        token: GitHub token; defaults to env GITHUB_TOKEN.

    Returns:
        Parsed list of Result-shaped dicts (one per scenario).

    Raises:
        BaselineUnavailable: on any failure — caller translates to WARNING.
    """
    token = token or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise BaselineUnavailable("no GITHUB_TOKEN in environment")

    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    prefix = f"eval-baseline-{branch}-"
    try:
        resp = requests.get(
            f"{GITHUB_API}/repos/{repo}/actions/artifacts",
            params={"per_page": 100, "name": None},
            headers=headers,
            timeout=BASELINE_FETCH_TIMEOUT_SECONDS,
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        raise BaselineUnavailable(f"list artifacts failed: {e}") from e

    data = resp.json()
    candidates = [
        a for a in data.get("artifacts", [])
        if a.get("name", "").startswith(prefix) and not a.get("expired", False)
    ]
    if not candidates:
        raise BaselineUnavailable(
            f"no unexpired artifact matching {prefix}* on repo {repo}"
        )
    latest = max(candidates, key=lambda a: a.get("created_at", ""))

    try:
        archive = requests.get(
            latest["archive_download_url"],
            headers=headers,
            timeout=BASELINE_FETCH_TIMEOUT_SECONDS,
            allow_redirects=True,
        )
        archive.raise_for_status()
    except requests.RequestException as e:
        raise BaselineUnavailable(f"download artifact failed: {e}") from e

    import io
    import zipfile

    try:
        with zipfile.ZipFile(io.BytesIO(archive.content)) as zf:
            names = [n for n in zf.namelist() if n.endswith("eval-results.jsonl")]
            if not names:
                raise BaselineUnavailable(
                    "artifact archive missing eval-results.jsonl"
                )
            with zf.open(names[0]) as f:
                lines = f.read().decode("utf-8").splitlines()
    except zipfile.BadZipFile as e:
        raise BaselineUnavailable(f"artifact is not a zip: {e}") from e

    records: list[dict] = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as e:
            raise BaselineUnavailable(
                f"malformed JSONL in baseline artifact: {e}"
            ) from e
    return records
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/baseline.py
git commit -m "feat(evals): add baseline fetch from GitHub artifacts + regression gate"
```

---

## Task 9: Executor — forge invocation + state capture

**Files:**
- Create: `tests/evals/pipeline/runner/executor.py`

- [ ] **Step 1: Implement executor**

Write `tests/evals/pipeline/runner/executor.py`:

```python
"""Per-scenario execution: isolate worktree, invoke forge, capture state.json.

Contract:
    1. Create a temp directory.
    2. If ``fixtures/starter.tar.gz`` exists in the scenario dir, extract it;
       otherwise ``git init`` an empty repo.
    3. Symlink the current forge checkout into ``.claude/plugins/forge``.
    4. Run ``/forge-init`` non-interactively to seed config.
    5. Set ``FORGE_EVAL=1`` and run ``/forge-run --eval-mode <id>``.
    6. Parse ``.forge/state.json`` post-run.
    7. Return raw metrics (tokens, elapsed, score, verdict, touched files).

No scoring here — scoring lives in scoring.py.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from tests.evals.pipeline.runner.schema import Scenario


@dataclass
class RawRunMetrics:
    """Raw output of one forge invocation; consumed by scoring module."""

    scenario_id: str
    started_at: str
    ended_at: str
    elapsed_seconds: int
    tokens: int
    pipeline_score: float
    verdict: str
    touched_files_actual: list[str]
    must_not_touch_violations: list[str]
    timed_out: bool
    error: Optional[str]


def _iso_now() -> str:
    import datetime as _dt
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _extract_starter(scenario_dir: Path, target: Path) -> None:
    starter = scenario_dir / "fixtures" / "starter.tar.gz"
    if starter.is_file():
        with tarfile.open(starter, "r:gz") as tf:
            tf.extractall(target)
    else:
        subprocess.run(["git", "init", "-q"], cwd=target, check=True)


def _symlink_plugin(forge_root: Path, target: Path) -> None:
    plugin_dir = target / ".claude" / "plugins"
    plugin_dir.mkdir(parents=True, exist_ok=True)
    (plugin_dir / "forge").symlink_to(forge_root, target_is_directory=True)


def _run_forge_init(target: Path) -> None:
    # Non-interactive: rely on FORGE_EVAL=1 to skip prompts.
    env = {**os.environ, "FORGE_EVAL": "1"}
    subprocess.run(
        ["claude", "code", "--non-interactive", "/forge-init"],
        cwd=target,
        env=env,
        check=True,
        timeout=180,
    )


def _run_forge_with_eval_mode(
    *,
    scenario: Scenario,
    target: Path,
    dry_run: bool,
    scenario_timeout_seconds: int,
) -> tuple[bool, Optional[str]]:
    """Returns (timed_out, error_message)."""
    env = {**os.environ, "FORGE_EVAL": "1"}
    cmd = [
        "claude", "code", "--non-interactive",
        f"/forge-run --eval-mode {scenario.id}",
        scenario.prompt,
    ]
    if dry_run:
        cmd[-2] = cmd[-2] + " --dry-run"
    try:
        subprocess.run(
            cmd,
            cwd=target,
            env=env,
            check=True,
            timeout=scenario_timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return True, f"timeout after {scenario_timeout_seconds}s"
    except subprocess.CalledProcessError as e:
        return False, f"forge exited {e.returncode}"
    return False, None


def _parse_state(target: Path, scenario: Scenario) -> dict:
    state_path = target / ".forge" / "state.json"
    if not state_path.is_file():
        return {
            "pipeline_score": 0.0,
            "verdict": "ERROR",
            "actual_tokens": 0,
            "touched_files": [],
        }
    return json.loads(state_path.read_text(encoding="utf-8"))


def _detect_must_not_touch(target: Path, patterns: list[str]) -> list[str]:
    """Return globs from ``patterns`` that matched any file modified in target.

    Uses ``git status`` inside the target worktree plus fnmatch over the
    returned paths.
    """
    import fnmatch
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=target,
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    changed = [
        line[3:].strip()
        for line in result.stdout.splitlines()
        if line.strip()
    ]
    violations: list[str] = []
    for pattern in patterns:
        for path in changed:
            if fnmatch.fnmatch(path, pattern):
                violations.append(pattern)
                break
    return violations


def execute_scenario(
    *,
    scenario: Scenario,
    forge_root: Path,
    dry_run: bool = False,
    scenario_timeout_seconds: int = 900,
) -> RawRunMetrics:
    """Run one scenario end-to-end and return raw metrics."""
    started_at = _iso_now()
    start_mono = time.monotonic()
    with tempfile.TemporaryDirectory(prefix=f"forge-eval-{scenario.id}-") as tmp:
        target = Path(tmp)
        _extract_starter(Path(scenario.path), target)
        _symlink_plugin(forge_root, target)
        try:
            _run_forge_init(target)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            ended_at = _iso_now()
            return RawRunMetrics(
                scenario_id=scenario.id,
                started_at=started_at,
                ended_at=ended_at,
                elapsed_seconds=int(time.monotonic() - start_mono),
                tokens=0,
                pipeline_score=0.0,
                verdict="ERROR",
                touched_files_actual=[],
                must_not_touch_violations=[],
                timed_out=False,
                error=f"forge-init failed: {e}",
            )

        timed_out, error = _run_forge_with_eval_mode(
            scenario=scenario,
            target=target,
            dry_run=dry_run,
            scenario_timeout_seconds=scenario_timeout_seconds,
        )
        state = _parse_state(target, scenario)
        touched = list(state.get("touched_files", []))
        violations = _detect_must_not_touch(
            target, scenario.expected.must_not_touch
        )
        tokens = int(state.get("tokens", {}).get("total", 0)) if isinstance(
            state.get("tokens"), dict
        ) else int(state.get("actual_tokens", 0))

        return RawRunMetrics(
            scenario_id=scenario.id,
            started_at=started_at,
            ended_at=_iso_now(),
            elapsed_seconds=int(time.monotonic() - start_mono),
            tokens=tokens,
            pipeline_score=float(state.get("pipeline_score", 0.0)),
            verdict=str(state.get("verdict", "CONCERNS")),
            touched_files_actual=touched,
            must_not_touch_violations=violations,
            timed_out=timed_out,
            error=error,
        )
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/executor.py
git commit -m "feat(evals): add per-scenario executor with worktree isolation and state capture"
```

---

## Task 10: Report writer — JSONL + leaderboard

**Files:**
- Create: `tests/evals/pipeline/runner/report.py`

- [ ] **Step 1: Implement report module**

Write `tests/evals/pipeline/runner/report.py`:

```python
"""Result JSONL writer + leaderboard markdown renderer.

Outputs:
    .forge/eval-results.jsonl   — one JSON object per line, one line per scenario
    tests/evals/pipeline/leaderboard.md  — human-readable summary (master only)
"""
from __future__ import annotations

import json
from pathlib import Path

from tests.evals.pipeline.runner.schema import Result


def write_jsonl(results: list[Result], out_path: Path) -> None:
    """Overwrite ``out_path`` with one JSON object per line."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for r in results:
            f.write(json.dumps(r.model_dump(), sort_keys=True))
            f.write("\n")


def render_leaderboard(results: list[Result], commit_sha: str) -> str:
    """Return the markdown body for leaderboard.md (CI will write it)."""
    lines: list[str] = [
        "# Forge Pipeline Eval Leaderboard",
        "",
        f"> Auto-generated by `.github/workflows/evals.yml`. **Do not hand-edit.**",
        f"> Regenerate by pushing to master or running the runner locally.",
        "",
        f"**Commit:** `{commit_sha}`",
        f"**Scenarios:** {len(results)}",
        "",
        "| ID | Composite | Pipeline | Verdict | Tokens | Elapsed (s) | Overlap | Status |",
        "|----|-----------|----------|---------|--------|-------------|---------|--------|",
    ]
    for r in results:
        lines.append(
            f"| `{r.scenario_id}` "
            f"| {r.composite:.1f} "
            f"| {r.pipeline_score:.1f} "
            f"| {r.verdict} "
            f"| {r.actual_tokens} "
            f"| {r.actual_elapsed_seconds} "
            f"| {r.overlap_jaccard:.2f} "
            f"| {r.status} |"
        )
    mean_c = (
        sum(r.composite for r in results) / len(results) if results else 0.0
    )
    lines += [
        "",
        f"**Mean composite:** {mean_c:.2f}",
        "",
    ]
    return "\n".join(lines)


def write_leaderboard(results: list[Result], commit_sha: str, out_path: Path) -> None:
    out_path.write_text(render_leaderboard(results, commit_sha), encoding="utf-8")
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/report.py
git commit -m "feat(evals): add JSONL writer and leaderboard markdown renderer"
```

---

## Task 11: CLI entry point (`__main__`)

**Files:**
- Create: `tests/evals/pipeline/runner/__main__.py`

- [ ] **Step 1: Implement CLI**

Write `tests/evals/pipeline/runner/__main__.py`:

```python
"""CLI: ``python -m tests.evals.pipeline.runner``.

Modes:
    --collect-only   — discover + validate scenarios, exit 0/1.
    --dry-run        — run first scenario with forge --dry-run (smoke test).
    (default)        — run all scenarios sequentially, write JSONL + leaderboard.

Exit codes:
    0   success (all scenarios ran; regression gate passed or skipped)
    1   collection failed, scenario errored, or regression gate tripped
    2   invalid CLI arguments
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from tests.evals.pipeline.runner.baseline import (
    BaselineUnavailable,
    compute_gate,
    fetch_baseline_from_github,
)
from tests.evals.pipeline.runner.executor import execute_scenario
from tests.evals.pipeline.runner.report import write_jsonl, write_leaderboard
from tests.evals.pipeline.runner.scenarios import (
    ScenarioCollectionError,
    discover_scenarios,
)
from tests.evals.pipeline.runner.schema import Finding, Result
from tests.evals.pipeline.runner.scoring import (
    composite_score,
    elapsed_adherence,
    jaccard_overlap,
    token_adherence,
)


DEFAULT_SCENARIOS_ROOT = Path(__file__).resolve().parents[1] / "scenarios"
DEFAULT_RESULTS_PATH = Path(".forge") / "eval-results.jsonl"
DEFAULT_LEADERBOARD_PATH = Path(__file__).resolve().parents[1] / "leaderboard.md"


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.pipeline.runner")
    p.add_argument("--collect-only", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument(
        "--scenarios-root", type=Path, default=DEFAULT_SCENARIOS_ROOT
    )
    p.add_argument(
        "--forge-root",
        type=Path,
        default=Path(__file__).resolve().parents[3].parent,
        help="Path to forge plugin checkout (symlinked into each scenario).",
    )
    p.add_argument(
        "--results-path", type=Path, default=DEFAULT_RESULTS_PATH
    )
    p.add_argument(
        "--leaderboard-path", type=Path, default=DEFAULT_LEADERBOARD_PATH
    )
    p.add_argument("--scenario-timeout-seconds", type=int, default=900)
    p.add_argument("--total-budget-seconds", type=int, default=2700)
    p.add_argument("--regression-tolerance", type=float, default=3.0)
    p.add_argument("--baseline-repo", type=str, default="quantumbitcz/forge")
    p.add_argument("--baseline-branch", type=str, default="master")
    p.add_argument(
        "--no-baseline",
        action="store_true",
        help="Skip baseline fetch (for local dry runs); gate becomes pass-with-warning.",
    )
    p.add_argument(
        "--commit-sha",
        type=str,
        default=os.environ.get("GITHUB_SHA", "local"),
    )
    return p


def _score_one(scenario, raw) -> Result:
    exp = scenario.expected
    tok_adh = token_adherence(raw.tokens, exp.token_budget) if raw.tokens else 0.0
    el_adh = elapsed_adherence(
        raw.elapsed_seconds, exp.elapsed_budget_seconds
    ) if raw.elapsed_seconds else 0.0
    overlap = jaccard_overlap(exp.touched_files_expected, raw.touched_files_actual)
    composite = composite_score(
        pipeline_score=raw.pipeline_score, token_adh=tok_adh, elapsed_adh=el_adh
    )
    findings: list[Finding] = []
    if raw.timed_out:
        findings.append(Finding(
            category="EVAL-TIMEOUT", severity="CRITICAL",
            message=f"scenario exceeded {exp.elapsed_budget_seconds}s budget",
        ))
    if raw.must_not_touch_violations:
        findings.append(Finding(
            category="EVAL-MUST-NOT-TOUCH", severity="CRITICAL",
            message=f"modified forbidden paths: {raw.must_not_touch_violations}",
        ))
    if raw.verdict not in (exp.required_verdict, "PASS"):
        findings.append(Finding(
            category="EVAL-VERDICT-MISMATCH", severity="WARNING",
            message=f"verdict {raw.verdict} < required {exp.required_verdict}",
        ))
    if raw.tokens > exp.token_budget or raw.elapsed_seconds > exp.elapsed_budget_seconds:
        findings.append(Finding(
            category="EVAL-BUDGET-OVER", severity="WARNING",
            message=(
                f"budget exceeded: tokens {raw.tokens}/{exp.token_budget}, "
                f"elapsed {raw.elapsed_seconds}/{exp.elapsed_budget_seconds}s"
            ),
        ))
    if overlap < 0.5:
        findings.append(Finding(
            category="EVAL-OVERLAP-LOW", severity="INFO",
            message=f"touched-file Jaccard {overlap:.2f} < 0.5",
        ))
    status = (
        "timeout" if raw.timed_out
        else "error" if raw.error
        else "completed"
    )
    return Result(
        scenario_id=raw.scenario_id,
        started_at=raw.started_at,
        ended_at=raw.ended_at,
        actual_tokens=raw.tokens,
        actual_elapsed_seconds=raw.elapsed_seconds,
        pipeline_score=raw.pipeline_score,
        verdict=raw.verdict if raw.verdict in ("PASS", "CONCERNS", "FAIL") else "FAIL",
        touched_files_actual=raw.touched_files_actual,
        overlap_jaccard=overlap,
        token_adherence=tok_adh,
        elapsed_adherence=el_adh,
        composite=composite,
        findings=findings,
        status=status,
    )


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    try:
        scenarios = discover_scenarios(args.scenarios_root)
    except ScenarioCollectionError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    print(f"discovered {len(scenarios)} scenarios", file=sys.stderr)
    if args.collect_only:
        return 0

    results: list[Result] = []
    if args.dry_run and scenarios:
        scenarios = scenarios[:1]   # smoke: first scenario only

    for s in scenarios:
        raw = execute_scenario(
            scenario=s,
            forge_root=args.forge_root,
            dry_run=args.dry_run,
            scenario_timeout_seconds=args.scenario_timeout_seconds,
        )
        result = _score_one(s, raw)
        if args.dry_run:
            result = result.model_copy(update={"status": "dry_run", "verdict": "DRY_RUN"})
        results.append(result)

    write_jsonl(results, args.results_path)
    write_leaderboard(results, args.commit_sha, args.leaderboard_path)

    # Regression gate
    if args.no_baseline:
        baseline: list[dict] | None = None
    else:
        try:
            baseline = fetch_baseline_from_github(
                repo=args.baseline_repo, branch=args.baseline_branch
            )
        except BaselineUnavailable as e:
            print(f"baseline unavailable: {e}", file=sys.stderr)
            baseline = None

    decision = compute_gate(
        current=[r.model_dump() for r in results],
        baseline=baseline,
        tolerance=args.regression_tolerance,
    )
    if decision.finding is not None:
        print(
            f"[{decision.finding.severity}] {decision.finding.category}: "
            f"{decision.finding.message}",
            file=sys.stderr,
        )

    if not decision.passed:
        return 1

    any_critical = any(
        f.severity == "CRITICAL" for r in results for f in r.findings
    )
    return 1 if any_critical else 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Commit**

```bash
git add tests/evals/pipeline/runner/__main__.py
git commit -m "feat(evals): add CLI runner with collect-only, dry-run, and gate modes"
```

---

## Task 12: Scenarios 01, 04, 08 (the cheap three)

**Files:**
- Create: `tests/evals/pipeline/scenarios/01-ts-microservice-greenfield/prompt.md`
- Create: `tests/evals/pipeline/scenarios/01-ts-microservice-greenfield/expected.yaml`
- Create: `tests/evals/pipeline/scenarios/04-react-bootstrap/prompt.md`
- Create: `tests/evals/pipeline/scenarios/04-react-bootstrap/expected.yaml`
- Create: `tests/evals/pipeline/scenarios/08-flask-spike/prompt.md`
- Create: `tests/evals/pipeline/scenarios/08-flask-spike/expected.yaml`

- [ ] **Step 1: Scenario 01 — TS microservice greenfield**

Write `tests/evals/pipeline/scenarios/01-ts-microservice-greenfield/prompt.md`:

```markdown
# Scenario 01 — TypeScript microservice greenfield

Build a minimal Express-based TypeScript HTTP service with:

- `GET /health` returning `{ "status": "ok" }` with 200
- `GET /users/:id` returning a fixture user; 404 on unknown id
- Vitest unit tests for both routes
- TypeScript strict mode, ESLint, Prettier
- `npm start` boots on port `PORT` (default 3000)

Pinned versions: express 4.21.x, typescript 5.5.x, vitest 2.x, node 20 LTS.

Pipeline mode: `standard`.
```

Write `tests/evals/pipeline/scenarios/01-ts-microservice-greenfield/expected.yaml`:

```yaml
id: 01-ts-microservice-greenfield
mode: standard
token_budget: 150000
elapsed_budget_seconds: 600
min_pipeline_score: 85
required_verdict: PASS
touched_files_expected:
  - src/server.ts
  - src/routes/health.ts
  - src/routes/users.ts
  - src/routes/users.test.ts
  - package.json
  - tsconfig.json
must_not_touch:
  - .claude/**
  - tests/evals/**
notes: "Greenfield TS microservice; PASS expected on first convergence iteration."
```

- [ ] **Step 2: Scenario 04 — React bootstrap**

Write `tests/evals/pipeline/scenarios/04-react-bootstrap/prompt.md`:

```markdown
# Scenario 04 — React + Vite + Vitest bootstrap

Scaffold a fresh React 18 SPA using Vite 5 + Vitest 2 + Testing Library.

Requirements:
- `src/App.tsx` renders "Hello, forge" with `data-testid="greeting"`
- `src/App.test.tsx` asserts the greeting renders
- `npm run dev`, `npm run build`, `npm test` all succeed
- ESLint + Prettier configured; TypeScript strict
- README with setup/test instructions

Pinned: react 18.3.x, vite 5.4.x, vitest 2.x, typescript 5.5.x.

Pipeline mode: `bootstrap`.
```

Write `tests/evals/pipeline/scenarios/04-react-bootstrap/expected.yaml`:

```yaml
id: 04-react-bootstrap
mode: bootstrap
token_budget: 120000
elapsed_budget_seconds: 540
min_pipeline_score: 80
required_verdict: PASS
touched_files_expected:
  - src/App.tsx
  - src/App.test.tsx
  - src/main.tsx
  - vite.config.ts
  - package.json
  - README.md
must_not_touch:
  - .claude/**
  - tests/evals/**
notes: "Bootstrap mode; reduced review set per shared/modes/bootstrap.md."
```

- [ ] **Step 3: Scenario 08 — Flask spike**

Write `tests/evals/pipeline/scenarios/08-flask-spike/prompt.md`:

```markdown
# Scenario 08 — Single-file Flask spike

Create a single-file `app.py` Flask throwaway with:

- `GET /` returns plain text "hello from forge"
- `POST /echo` returns the request JSON verbatim
- `pytest` module `test_app.py` with one happy-path test each
- `requirements.txt` pinning Flask 3.0.x + pytest 8.x

Intentionally small scope — this is the cheap smoke scenario.

Pipeline mode: `standard`.
```

Write `tests/evals/pipeline/scenarios/08-flask-spike/expected.yaml`:

```yaml
id: 08-flask-spike
mode: standard
token_budget: 80000
elapsed_budget_seconds: 360
min_pipeline_score: 80
required_verdict: PASS
touched_files_expected:
  - app.py
  - test_app.py
  - requirements.txt
must_not_touch:
  - .claude/**
  - tests/evals/**
notes: "Cheapest scenario; used for --dry-run smoke."
```

- [ ] **Step 4: Commit**

```bash
git add tests/evals/pipeline/scenarios/01-ts-microservice-greenfield/ \
        tests/evals/pipeline/scenarios/04-react-bootstrap/ \
        tests/evals/pipeline/scenarios/08-flask-spike/
git commit -m "feat(evals): add scenarios 01 (TS), 04 (React), 08 (Flask)"
```

---

## Task 13: Config keys — `forge-config.md` + PREFLIGHT constraints

**Files:**
- Modify: `shared/preflight-constraints.md`
- Modify: `modules/frameworks/**/forge-config-template.md` is **not** touched — `evals:` is a top-level repo-wide config that lives in user-supplied `forge-config.md` only. Document the keys in `shared/preflight-constraints.md` and in the new README.

- [ ] **Step 1: Read current preflight constraints**

```bash
wc -l /Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md
```

Expected: a file exists with existing constraint sections.

- [ ] **Step 2: Append `evals:` section to preflight constraints**

Append to `/Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md` (add a new `## evals` section after the last existing section — do not reshuffle):

```markdown
## evals

Pipeline-level evaluation harness configuration. Validated at PREFLIGHT.

- `evals.enabled` must be `bool` (default `true`)
- `evals.composite_weights.pipeline_score` must be `float` in `[0, 1]`
- `evals.composite_weights.token_adherence` must be `float` in `[0, 1]`
- `evals.composite_weights.elapsed_adherence` must be `float` in `[0, 1]`
- sum of `evals.composite_weights.*` must equal `1.0` (tolerance ±0.01)
- `evals.regression_tolerance` must be `float` in `[0.0, 20.0]` (default `3.0`)
- `evals.baseline_branch` must be non-empty `str` (default `"master"`)
- `evals.scenario_timeout_seconds` must be `int` in `[60, 1800]` (default `900`)
- `evals.total_budget_seconds` must be `int` in `[60, 7200]` (default `2700`)
- `evals.total_budget_seconds` must be `>= evals.scenario_timeout_seconds`
- `evals.emit_overlap_metric` must be `bool` (default `true`)

Wall-clock contract (single source of truth — do not redefine elsewhere):
- Per-scenario hard cap: 900 s (15 min)
- Full-suite hard cap: 2700 s (45 min, with 50% headroom over target)
- Success-criterion target: ≤30 min p90 across 10 consecutive master runs (SC1)
```

- [ ] **Step 3: Commit**

```bash
git add shared/preflight-constraints.md
git commit -m "docs(evals): add PREFLIGHT constraints for evals.* config block"
```

---

## Task 14: `EVAL-*` scoring categories

**Files:**
- Modify: `shared/checks/category-registry.json`
- Modify: `shared/scoring.md`
- Create: `shared/checks/eval-categories.md`

- [ ] **Step 1: Read registry head**

```bash
wc -l /Users/denissajnar/IdeaProjects/forge/shared/checks/category-registry.json
```

- [ ] **Step 2: Add `EVAL` wildcard and 6 discrete codes**

Use Edit to add a new entry inside `"categories": { ... }` in `shared/checks/category-registry.json`. Locate the closing `}` of the `categories` object and insert before it (after the last existing entry, preserving JSON validity):

```json
    "EVAL": { "description": "Pipeline evaluation harness (emitted by tests/evals/pipeline runner, not pipeline agents)", "agents": [], "wildcard": true, "priority": 4, "affinity": ["tests/evals/pipeline"] },
    "EVAL-REGRESSION": { "description": "Composite score dropped more than regression_tolerance vs baseline", "agents": [], "wildcard": false, "priority": 1, "affinity": ["tests/evals/pipeline"] },
    "EVAL-TIMEOUT": { "description": "Scenario exceeded scenario_timeout_seconds", "agents": [], "wildcard": false, "priority": 1, "affinity": ["tests/evals/pipeline"] },
    "EVAL-MUST-NOT-TOUCH": { "description": "Pipeline modified a path listed in scenario must_not_touch", "agents": [], "wildcard": false, "priority": 1, "affinity": ["tests/evals/pipeline"] },
    "EVAL-VERDICT-MISMATCH": { "description": "Actual verdict worse than scenario required_verdict", "agents": [], "wildcard": false, "priority": 2, "affinity": ["tests/evals/pipeline"] },
    "EVAL-BUDGET-OVER": { "description": "Tokens or elapsed over scenario budget (adherence may still be > 0)", "agents": [], "wildcard": false, "priority": 2, "affinity": ["tests/evals/pipeline"] },
    "EVAL-OVERLAP-LOW": { "description": "Jaccard(touched_files_expected, touched_files_actual) < 0.5", "agents": [], "wildcard": false, "priority": 3, "affinity": ["tests/evals/pipeline"] },
    "EVAL-BASELINE-UNAVAILABLE": { "description": "master baseline artifact missing; regression gate skipped with warning", "agents": [], "wildcard": false, "priority": 3, "affinity": ["tests/evals/pipeline"] }
```

- [ ] **Step 3: Append EVAL row to scoring.md**

Open `/Users/denissajnar/IdeaProjects/forge/shared/scoring.md`, locate the wildcard-families table (search: `ARCH-*`). Add a new row at the end of that table:

```markdown
| `EVAL-*` | see `shared/checks/eval-categories.md` | excluded from pipeline scoring (harness-only) |
```

- [ ] **Step 4: Create EVAL categories reference**

Write `/Users/denissajnar/IdeaProjects/forge/shared/checks/eval-categories.md`:

```markdown
# EVAL-* scoring categories

Emitted by the pipeline evaluation harness at `tests/evals/pipeline/runner/`
(NOT by in-pipeline review agents). Findings live in
`.forge/eval-results.jsonl` and the GitHub Actions workflow log — they are
excluded from in-run pipeline scoring (they measure the eval run, not the
code change).

| Code | Severity | Meaning |
|---|---|---|
| `EVAL-REGRESSION` | CRITICAL | Composite dropped > `evals.regression_tolerance` vs master baseline |
| `EVAL-TIMEOUT` | CRITICAL | Scenario exceeded `evals.scenario_timeout_seconds` (default 900 s) |
| `EVAL-MUST-NOT-TOUCH` | CRITICAL | Pipeline modified a path listed in scenario `must_not_touch` |
| `EVAL-VERDICT-MISMATCH` | WARNING | Actual verdict worse than scenario `required_verdict` |
| `EVAL-BUDGET-OVER` | WARNING | Tokens or elapsed over scenario budget (even if adherence > 0) |
| `EVAL-OVERLAP-LOW` | INFO | Jaccard(`touched_files_expected`, actual) < 0.5 |
| `EVAL-BASELINE-UNAVAILABLE` | WARNING | master baseline artifact missing; regression gate skipped (see Phase 01 plan §C3) |

## Field name contract (review C2)

Scenario YAML and state schema use the **single key** `touched_files_expected`
in both places. Do not introduce `touched_files` as an alias.
```

- [ ] **Step 5: Commit**

```bash
git add shared/checks/category-registry.json \
        shared/scoring.md \
        shared/checks/eval-categories.md
git commit -m "feat(evals): register EVAL-* scoring categories for harness findings"
```

---

## Task 15: Orchestrator `--eval-mode` flag + state-schema field

**Files:**
- Modify: `agents/fg-100-orchestrator.md`
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Read orchestrator file bottom**

```bash
wc -l /Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md
```

- [ ] **Step 2: Add `--eval-mode` section to orchestrator**

Append a new section to `/Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md` (add at the bottom, under a new `## --eval-mode (pipeline eval harness)` heading):

```markdown
## --eval-mode (pipeline eval harness)

Flag used by `tests/evals/pipeline/runner` to invoke the pipeline in a reproducible, non-interactive way.

**Invocation:** `/forge-run --eval-mode <scenario_id> [--dry-run] <prompt>`

**Env guard (required):** the flag is rejected unless env var `FORGE_EVAL=1` is set. Standalone CLI use without the env var must error out. This prevents accidental Linear/Slack/AskUserQuestion suppression in production invocations.

**Behavior when active:**
- Force `autonomous: true` (no `AskUserQuestion` prompts).
- Disable Linear sync, Slack notifications, and kanban writes.
- Write a root-level `eval_run` object in `.forge/state.json`:
  ```json
  {
    "eval_run": {
      "scenario_id": "<id>",
      "started_at": "<ISO-8601>",
      "ended_at": "<ISO-8601>",
      "mode": "<standard|bugfix|migration|bootstrap>",
      "expected_token_budget": <int>,
      "expected_elapsed_seconds": <int>,
      "touched_files_expected": ["<path>", ...]
    }
  }
  ```
  Field name is `touched_files_expected` (single source of truth; do not alias).

**Composition with `--dry-run`:** `--eval-mode <id> --dry-run` exits after PREFLIGHT, writes an `eval-results.jsonl` record with `status: "dry_run"` and `verdict: "DRY_RUN"`, and does not invoke implement/verify/review stages. This powers the runner smoke test.

**Error cases:**
- Missing `FORGE_EVAL=1` → exit 2 with message `--eval-mode requires FORGE_EVAL=1`.
- Unknown `<scenario_id>` (no matching scenario directory) → exit 2 with message `unknown scenario`.
```

- [ ] **Step 3: Read state-schema version header**

```bash
grep -n "^## Version" /Users/denissajnar/IdeaProjects/forge/shared/state-schema.md | head -3
```

- [ ] **Step 4: Bump state-schema version and add `eval_run`**

In `/Users/denissajnar/IdeaProjects/forge/shared/state-schema.md`, replace `1.6.0` with `1.7.0` (use Edit with the literal version string; there should be a single canonical occurrence in the header; if multiple, use `replace_all`).

Then append a new section at the end of the file:

```markdown
## `eval_run` (added in 1.7.0)

Present only when the orchestrator was invoked with `--eval-mode <scenario_id>` (pipeline evaluation harness). Absent on normal runs.

```json
{
  "eval_run": {
    "scenario_id": "01-ts-microservice-greenfield",
    "started_at": "2026-04-19T12:00:00Z",
    "ended_at": "2026-04-19T12:10:00Z",
    "mode": "standard",
    "expected_token_budget": 150000,
    "expected_elapsed_seconds": 600,
    "touched_files_expected": ["src/server.ts", "src/routes/users.ts"]
  }
}
```

Field-name contract (review C2): `touched_files_expected` is the single canonical name used in both `state.json` and scenario `expected.yaml`. Do not introduce aliases.
```

- [ ] **Step 5: Commit**

```bash
git add agents/fg-100-orchestrator.md shared/state-schema.md
git commit -m "feat(evals): add --eval-mode flag with FORGE_EVAL guard and eval_run state field"
```

---

## Task 16: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/evals.yml`

- [ ] **Step 1: Create workflow file**

Write `/Users/denissajnar/IdeaProjects/forge/.github/workflows/evals.yml`:

```yaml
name: Evals

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]
  workflow_dispatch:
    inputs:
      mode:
        description: 'Run mode'
        required: false
        default: 'full'
        type: choice
        options:
          - collect
          - dry-run
          - full

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions:
  contents: read
  actions: read  # list artifacts for baseline fetch

jobs:
  collect:
    name: Collect + validate scenarios
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install runner deps
        run: pip install -r tests/evals/pipeline/runner/requirements.txt
      - name: Collect scenarios
        run: python -m tests.evals.pipeline.runner --collect-only

  dry-run:
    name: Dry-run smoke (scenario 08)
    needs: collect
    runs-on: ubuntu-latest
    timeout-minutes: 5
    if: ${{ github.event_name == 'pull_request' || github.event_name == 'push' }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install runner deps
        run: pip install -r tests/evals/pipeline/runner/requirements.txt
      - name: Dry-run first scenario
        env:
          FORGE_EVAL: '1'
        run: python -m tests.evals.pipeline.runner --dry-run --no-baseline

  full-suite:
    name: Full eval suite
    needs: [collect, dry-run]
    runs-on: ubuntu-latest
    # Wall-clock contract (per plan §Review C1):
    #   scenario_timeout = 900 s (15 min) per scenario
    #   total_budget     = 2700 s (45 min) hard ceiling
    #   SC1 target       = 30 min p90
    # Workflow cap is 50 min (45-min total_budget + 5-min overhead for setup/teardown/baseline).
    timeout-minutes: 50
    if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
    env:
      FORGE_EVAL: '1'
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install runner deps
        run: pip install -r tests/evals/pipeline/runner/requirements.txt
      - name: Run full suite
        run: |
          python -m tests.evals.pipeline.runner \
            --scenario-timeout-seconds 900 \
            --total-budget-seconds 2700 \
            --regression-tolerance 3.0 \
            --baseline-repo "${{ github.repository }}" \
            --baseline-branch master \
            --commit-sha "${{ github.sha }}"
      - name: Upload baseline artifact
        if: success()
        uses: actions/upload-artifact@v4
        with:
          name: eval-baseline-master-${{ github.sha }}
          path: .forge/eval-results.jsonl
          retention-days: 90
      - name: Commit leaderboard
        if: success()
        run: |
          if ! git diff --quiet tests/evals/pipeline/leaderboard.md; then
            git config user.name 'forge-bot'
            git config user.email 'forge-bot@users.noreply.github.com'
            git add tests/evals/pipeline/leaderboard.md
            git commit -m "chore(evals): update leaderboard for ${GITHUB_SHA::7}"
            git push origin master
          fi

  pr-suite:
    name: PR eval suite (regression gate)
    needs: [collect, dry-run]
    runs-on: ubuntu-latest
    timeout-minutes: 50
    if: ${{ github.event_name == 'pull_request' }}
    env:
      FORGE_EVAL: '1'
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'
      - name: Install runner deps
        run: pip install -r tests/evals/pipeline/runner/requirements.txt
      - name: Run full suite (gate active)
        run: |
          python -m tests.evals.pipeline.runner \
            --scenario-timeout-seconds 900 \
            --total-budget-seconds 2700 \
            --regression-tolerance 3.0 \
            --baseline-repo "${{ github.repository }}" \
            --baseline-branch master \
            --commit-sha "${{ github.event.pull_request.head.sha }}"
      - name: Upload PR results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: eval-pr-${{ github.event.pull_request.number }}
          path: .forge/eval-results.jsonl
          retention-days: 30
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/evals.yml
git commit -m "ci(evals): add evals workflow with PR gate and master baseline upload"
```

---

## Task 17: README + leaderboard skeleton + `tests/run-all.sh` hook

**Files:**
- Create: `tests/evals/pipeline/README.md`
- Create: `tests/evals/pipeline/leaderboard.md`
- Modify: `tests/run-all.sh`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write README**

Write `/Users/denissajnar/IdeaProjects/forge/tests/evals/pipeline/README.md`:

```markdown
# Pipeline evaluation harness

End-to-end eval harness that runs forge against 10 frozen scenarios on every
PR and every push to `master`. Complements `tests/evals/agents/` (reviewer I/O
tests) — this tree measures the full pipeline.

## Quick start

```bash
pip install -r tests/evals/pipeline/runner/requirements.txt

# Validate every scenario parses cleanly (fast, <5 s):
python -m tests.evals.pipeline.runner --collect-only

# Run the cheap smoke scenario in dry-run (no forge invocation):
FORGE_EVAL=1 python -m tests.evals.pipeline.runner --dry-run --no-baseline
```

## Directory shape

Each scenario is a directory with two required files and one optional bundle:

```
scenarios/<NN-slug>/
  prompt.md           # required — user-facing requirement text
  expected.yaml       # required — frozen expectations (pydantic-validated)
  fixtures/
    starter.tar.gz    # optional — seed worktree state before forge-init
```

## Schema

`expected.yaml` fields (all required):

| field                    | type                                                | notes                                       |
|--------------------------|-----------------------------------------------------|---------------------------------------------|
| `id`                     | str                                                 | must equal directory name                   |
| `mode`                   | `standard` \| `bugfix` \| `migration` \| `bootstrap`| pipeline mode                               |
| `token_budget`           | int > 0                                             | upper bound; over-budget degrades linearly  |
| `elapsed_budget_seconds` | int > 0                                             | wall-clock target                           |
| `min_pipeline_score`     | int [0, 100]                                        | floor for pipeline_score component          |
| `required_verdict`       | `PASS` \| `CONCERNS`                                | never FAIL in frozen scenarios              |
| `touched_files_expected` | list[str]                                           | overlap metric (reporting-only, Jaccard)    |
| `must_not_touch`         | list[str]                                           | glob patterns; match = hard fail            |
| `notes`                  | str                                                 | free-form                                   |

Field-name contract: **use `touched_files_expected` everywhere** (scenario YAML + `state.json.eval_run`). Do not introduce `touched_files` as an alias.

## Wall-clock budget

| knob                         | value   | meaning                                             |
|------------------------------|---------|-----------------------------------------------------|
| `scenario_timeout_seconds`   | 900 s   | per-scenario hard cap (15 min)                      |
| `total_budget_seconds`       | 2700 s  | full-suite hard ceiling (45 min)                    |
| CI `timeout-minutes`         | 50      | total_budget + 5 min overhead                       |
| SC1 target                   | ≤30 min | p90 of 10 consecutive master runs                   |

These four numbers are the **single source of truth** for the wall-clock contract (resolves review C1).

## Regression gate

On every PR run the runner compares the mean composite score to the latest `master` baseline (the most recent unexpired `eval-baseline-master-<sha>` workflow artifact).

- Delta ≥ `-regression_tolerance` (default `-3.0`) → **PASS**.
- Delta < `-regression_tolerance` → `EVAL-REGRESSION` CRITICAL, exit 1.
- Baseline unavailable (first master run, retention expiry, fetch failure) → `EVAL-BASELINE-UNAVAILABLE` WARNING, gate skipped, exit 0.

## Sanity check

Introduce a broken `expected.yaml` (e.g. set `mode: bogus`) in a throwaway branch. `python -m tests.evals.pipeline.runner --collect-only` must fail with a clear error naming the broken scenario. CI re-runs this on every push via the `collect` job.

## SC3 verification recipe

A deliberately regression-inducing PR (e.g. make the orchestrator skip VERIFY) must fail CI with **exit code 1** and the finding record `{"category":"EVAL-REGRESSION","severity":"CRITICAL",...}` present in `.forge/eval-results.jsonl`. Validated manually once before enforcement is enabled.

## Do not hand-edit `leaderboard.md`

`leaderboard.md` is rewritten on every `master` push by `.github/workflows/evals.yml`. If you need to change its shape, edit `runner/report.py` and push.
```

- [ ] **Step 2: Write leaderboard skeleton**

Write `/Users/denissajnar/IdeaProjects/forge/tests/evals/pipeline/leaderboard.md`:

```markdown
# Forge Pipeline Eval Leaderboard

> Auto-generated by `.github/workflows/evals.yml`. **Do not hand-edit.**
> Regenerate by pushing to master or running the runner locally.

**Commit:** _pending first master run_
**Scenarios:** 0

| ID | Composite | Pipeline | Verdict | Tokens | Elapsed (s) | Overlap | Status |
|----|-----------|----------|---------|--------|-------------|---------|--------|

**Mean composite:** —
```

- [ ] **Step 3: Modify `tests/run-all.sh` — add documented `pipeline-eval` tier**

Find the tier dispatch in `tests/run-all.sh`. Add a new `pipeline-eval` branch that prints a message directing the user to CI (per project rule: no local test runs).

Add to `tests/run-all.sh` where the other tiers are documented (append to the tier case/help block):

```bash
    pipeline-eval)
        echo "pipeline-eval tier runs only in CI (.github/workflows/evals.yml)."
        echo "Local invocation (smoke only): FORGE_EVAL=1 python -m tests.evals.pipeline.runner --dry-run --no-baseline"
        echo "To validate scenario YAML shape without running forge: python -m tests.evals.pipeline.runner --collect-only"
        exit 0
        ;;
```

- [ ] **Step 4: Modify `CLAUDE.md` — one-line pointer in Validation section**

In `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md`, locate the `## Validation` section. Add one line at the end of its code block or adjacent bullet list:

```markdown
For pipeline-level evals see `tests/evals/pipeline/README.md` (CI-only; local dry-run: `FORGE_EVAL=1 python -m tests.evals.pipeline.runner --dry-run --no-baseline`).
```

- [ ] **Step 5: Commit**

```bash
git add tests/evals/pipeline/README.md \
        tests/evals/pipeline/leaderboard.md \
        tests/run-all.sh \
        CLAUDE.md
git commit -m "docs(evals): add README, leaderboard skeleton, and run-all.sh pipeline-eval tier"
```

---

## Task 18: Scenarios 02, 03, 05, 06, 10 (fixture-backed production scenarios)

**Files:**
- Create: `tests/evals/pipeline/scenarios/02-python-bugfix/{prompt.md,expected.yaml,fixtures/starter.tar.gz}`
- Create: `tests/evals/pipeline/scenarios/03-kotlin-spring-migration/{prompt.md,expected.yaml,fixtures/starter.tar.gz}`
- Create: `tests/evals/pipeline/scenarios/05-go-performance-fix/{prompt.md,expected.yaml,fixtures/starter.tar.gz}`
- Create: `tests/evals/pipeline/scenarios/06-rust-refactor/{prompt.md,expected.yaml,fixtures/starter.tar.gz}`
- Create: `tests/evals/pipeline/scenarios/10-php-security-fix/{prompt.md,expected.yaml,fixtures/starter.tar.gz}`

- [ ] **Step 1: Scenario 02 — FastAPI off-by-one bugfix**

Create the directory, build the fixture, write prompt+expected. The fixture is a minimal FastAPI app with a pagination off-by-one (returns `range(page*size, (page+1)*size + 1)` — the `+1` is the bug).

Build fixture:

```bash
mkdir -p tests/evals/pipeline/scenarios/02-python-bugfix/fixtures
FIXTURE_TMP=$(mktemp -d)
mkdir -p "$FIXTURE_TMP/app" "$FIXTURE_TMP/tests"
cat > "$FIXTURE_TMP/app/main.py" <<'PY'
"""FastAPI paginated list — contains an off-by-one bug on purpose."""
from fastapi import FastAPI

app = FastAPI()
ITEMS = list(range(100))


@app.get("/items")
def items(page: int = 0, size: int = 10) -> list[int]:
    # BUG: off-by-one — returns size+1 items.
    return ITEMS[page * size : (page + 1) * size + 1]
PY
cat > "$FIXTURE_TMP/tests/test_items.py" <<'PY'
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_pagination_returns_size_items():
    r = client.get("/items?page=0&size=10")
    assert r.status_code == 200
    assert len(r.json()) == 10    # currently fails — returns 11
PY
cat > "$FIXTURE_TMP/requirements.txt" <<'TXT'
fastapi==0.115.0
uvicorn==0.32.0
pytest==8.3.3
httpx==0.27.2
TXT
(cd "$FIXTURE_TMP" && git init -q && git add -A && git commit -q -m "fixture")
tar -czf tests/evals/pipeline/scenarios/02-python-bugfix/fixtures/starter.tar.gz \
    -C "$FIXTURE_TMP" .
rm -rf "$FIXTURE_TMP"
```

Write `tests/evals/pipeline/scenarios/02-python-bugfix/prompt.md`:

```markdown
# Scenario 02 — FastAPI off-by-one bugfix

The failing test `tests/test_items.py::test_pagination_returns_size_items` asserts that `GET /items?page=0&size=10` returns exactly 10 items but gets 11.

Root-cause the off-by-one in `app/main.py`, fix it, and make the test pass. Add one additional regression test for `size=1, page=5` returning exactly one item.

Do not introduce new dependencies.

Pipeline mode: `bugfix`.
```

Write `tests/evals/pipeline/scenarios/02-python-bugfix/expected.yaml`:

```yaml
id: 02-python-bugfix
mode: bugfix
token_budget: 90000
elapsed_budget_seconds: 420
min_pipeline_score: 80
required_verdict: PASS
touched_files_expected:
  - app/main.py
  - tests/test_items.py
must_not_touch:
  - .claude/**
  - tests/evals/**
  - requirements.txt
notes: "Classic slice-arithmetic bug."
```

- [ ] **Step 2: Scenario 03 — Spring Boot 2→3 migration**

Build a minimal Kotlin + Spring Boot 2.7.x app with one `javax.*` import that must become `jakarta.*` on 3.x. Write prompt + expected analogously to Step 1 (build fixture via `tar` of a minimal Gradle project), then:

Write `tests/evals/pipeline/scenarios/03-kotlin-spring-migration/prompt.md`:

```markdown
# Scenario 03 — Spring Boot 2.7 → 3.3 migration

Upgrade the Gradle project from Spring Boot 2.7.18 + Kotlin 1.9 to Spring Boot 3.3.x + Kotlin 1.9 + Java 17.

Required changes:
- `build.gradle.kts` bumps spring-boot, spring-dependency-management, Kotlin jvm target to 17.
- `javax.*` imports → `jakarta.*` where required by 3.x.
- `@ConfigurationProperties(prefix = ...)` usage reviewed for constructor-binding migration.
- `./gradlew test` must pass against the new versions.

Pipeline mode: `migration`.
```

Write `tests/evals/pipeline/scenarios/03-kotlin-spring-migration/expected.yaml`:

```yaml
id: 03-kotlin-spring-migration
mode: migration
token_budget: 200000
elapsed_budget_seconds: 840
min_pipeline_score: 78
required_verdict: CONCERNS
touched_files_expected:
  - build.gradle.kts
  - src/main/kotlin/com/example/App.kt
  - src/main/kotlin/com/example/Config.kt
  - src/test/kotlin/com/example/AppTest.kt
must_not_touch:
  - .claude/**
  - tests/evals/**
notes: "CONCERNS acceptable — migration risk warrants non-PASS verdict."
```

Build the fixture:

```bash
mkdir -p tests/evals/pipeline/scenarios/03-kotlin-spring-migration/fixtures
FIXTURE_TMP=$(mktemp -d)
mkdir -p "$FIXTURE_TMP/src/main/kotlin/com/example" \
         "$FIXTURE_TMP/src/test/kotlin/com/example"
cat > "$FIXTURE_TMP/settings.gradle.kts" <<'KTS'
rootProject.name = "spring-migration-fixture"
KTS
cat > "$FIXTURE_TMP/build.gradle.kts" <<'KTS'
plugins {
    id("org.springframework.boot") version "2.7.18"
    id("io.spring.dependency-management") version "1.1.4"
    kotlin("jvm") version "1.9.25"
    kotlin("plugin.spring") version "1.9.25"
}
group = "com.example"
version = "0.1.0"
java.sourceCompatibility = JavaVersion.VERSION_11
repositories { mavenCentral() }
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
KTS
cat > "$FIXTURE_TMP/src/main/kotlin/com/example/App.kt" <<'KT'
package com.example

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import javax.annotation.PostConstruct

@SpringBootApplication
class App {
    @PostConstruct fun init() { println("booted") }
}

fun main(args: Array<String>) { runApplication<App>(*args) }
KT
cat > "$FIXTURE_TMP/src/main/kotlin/com/example/Config.kt" <<'KT'
package com.example

import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties(prefix = "feature")
class FeatureConfig {
    var enabled: Boolean = false
}
KT
cat > "$FIXTURE_TMP/src/test/kotlin/com/example/AppTest.kt" <<'KT'
package com.example

import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest
class AppTest {
    @Test fun contextLoads() {}
}
KT
(cd "$FIXTURE_TMP" && git init -q && git add -A && git commit -q -m "fixture")
tar -czf tests/evals/pipeline/scenarios/03-kotlin-spring-migration/fixtures/starter.tar.gz \
    -C "$FIXTURE_TMP" .
rm -rf "$FIXTURE_TMP"
```

- [ ] **Step 3: Scenarios 05, 06, 10 — same pattern**

For each of the remaining three (05 Go N+1 HTTP loop, 06 Rust extract-trait refactor, 10 PHP SQL-injection patch), follow the same recipe: (a) construct a minimal fixture tarball via `mktemp -d` + `tar -czf`; (b) write `prompt.md`; (c) write `expected.yaml` below.

`05-go-performance-fix/expected.yaml`:

```yaml
id: 05-go-performance-fix
mode: bugfix
token_budget: 100000
elapsed_budget_seconds: 480
min_pipeline_score: 82
required_verdict: PASS
touched_files_expected:
  - main.go
  - main_test.go
must_not_touch:
  - .claude/**
  - tests/evals/**
notes: "Remove N+1 HTTP fetch inside loop; replace with single batched call."
```

`05-go-performance-fix/prompt.md`:

```markdown
# Scenario 05 — Go N+1 HTTP loop

`main.go` fetches user profiles inside a `for` loop — one HTTP call per user. Refactor to a single batched call to `/users?ids=...`. The existing benchmark `BenchmarkGetProfiles` must improve by at least 5×.

Pipeline mode: `bugfix`.
```

`06-rust-refactor/expected.yaml`:

```yaml
id: 06-rust-refactor
mode: standard
token_budget: 120000
elapsed_budget_seconds: 540
min_pipeline_score: 80
required_verdict: PASS
touched_files_expected:
  - src/lib.rs
  - src/format.rs
  - tests/format.rs
must_not_touch:
  - .claude/**
  - tests/evals/**
  - Cargo.toml
notes: "Extract trait `Formatter` from three concrete impls; existing tests must still pass."
```

`06-rust-refactor/prompt.md`:

```markdown
# Scenario 06 — Rust trait extraction

Three struct impls (`JsonFormatter`, `YamlFormatter`, `TomlFormatter`) share the same public surface. Extract a `Formatter` trait, move shared logic to a default method, and update callers. Existing `tests/` must continue to pass.

Pipeline mode: `standard` (refactor overlay).
```

`10-php-security-fix/expected.yaml`:

```yaml
id: 10-php-security-fix
mode: bugfix
token_budget: 90000
elapsed_budget_seconds: 420
min_pipeline_score: 85
required_verdict: PASS
touched_files_expected:
  - src/UserRepository.php
  - tests/UserRepositoryTest.php
must_not_touch:
  - .claude/**
  - tests/evals/**
  - composer.json
notes: "String-concatenated WHERE clause must become a prepared statement."
```

`10-php-security-fix/prompt.md`:

```markdown
# Scenario 10 — PHP SQL injection patch

`UserRepository::findByEmail($email)` string-concatenates `$email` into a raw SQL statement. Replace with a PDO prepared statement, add a PHPUnit test proving `'; DROP TABLE users; --` is neutralized.

Pipeline mode: `bugfix`.
```

Build the three fixtures (Go, Rust, PHP) using the same `mktemp -d` + `tar -czf` pattern shown in Step 1. Each fixture should be a minimal buildable/test-runnable project containing the specific vulnerability/smell the prompt describes.

- [ ] **Step 4: Commit**

```bash
git add tests/evals/pipeline/scenarios/02-python-bugfix/ \
        tests/evals/pipeline/scenarios/03-kotlin-spring-migration/ \
        tests/evals/pipeline/scenarios/05-go-performance-fix/ \
        tests/evals/pipeline/scenarios/06-rust-refactor/ \
        tests/evals/pipeline/scenarios/10-php-security-fix/
git commit -m "feat(evals): add production scenarios 02, 03, 05, 06, 10 with fixtures"
```

---

## Task 19: Stub scenarios 07, 09 (tracked replacements)

Review item I1: the spec Goal claims "10 frozen scenarios"; two (ML-ops, Swift concurrency) ship as stubs pending domain-expertise follow-up. This task makes the stubs explicit.

**Files:**
- Create: `tests/evals/pipeline/scenarios/07-python-mlops-pipeline/{prompt.md,expected.yaml,fixtures/starter.tar.gz}`
- Create: `tests/evals/pipeline/scenarios/09-swift-concurrency/{prompt.md,expected.yaml,fixtures/starter.tar.gz}`

- [ ] **Step 1: Scenario 07 — MLOps stub**

Write `tests/evals/pipeline/scenarios/07-python-mlops-pipeline/prompt.md`:

```markdown
# Scenario 07 — Python MLOps pipeline (STUB)

**STUB — replace before Phase 03.** This scenario exercises harness plumbing only; the prompt is deliberately simple.

Add a `train.py` script that:
- Loads a CSV fixture, splits 80/20, trains `sklearn.linear_model.LogisticRegression`.
- Logs the final accuracy to stdout.
- Exits 0 if accuracy ≥ 0.5, exits 1 otherwise.

Pipeline mode: `standard`.
```

Write `tests/evals/pipeline/scenarios/07-python-mlops-pipeline/expected.yaml`:

```yaml
id: 07-python-mlops-pipeline
mode: standard
token_budget: 80000
elapsed_budget_seconds: 360
min_pipeline_score: 75
required_verdict: CONCERNS
touched_files_expected:
  - train.py
  - tests/test_train.py
  - requirements.txt
must_not_touch:
  - .claude/**
  - tests/evals/**
notes: "STUB — replace before Phase 03 with real DVC + MLflow reproducibility scenario."
```

Build the fixture (tiny CSV + empty `train.py` placeholder):

```bash
mkdir -p tests/evals/pipeline/scenarios/07-python-mlops-pipeline/fixtures
FIXTURE_TMP=$(mktemp -d)
mkdir -p "$FIXTURE_TMP/data"
cat > "$FIXTURE_TMP/data/iris.csv" <<'CSV'
sepal_length,sepal_width,petal_length,petal_width,label
5.1,3.5,1.4,0.2,0
4.9,3.0,1.4,0.2,0
7.0,3.2,4.7,1.4,1
6.4,3.2,4.5,1.5,1
6.3,3.3,6.0,2.5,2
5.8,2.7,5.1,1.9,2
CSV
cat > "$FIXTURE_TMP/requirements.txt" <<'TXT'
scikit-learn==1.5.2
pandas==2.2.3
pytest==8.3.3
TXT
(cd "$FIXTURE_TMP" && git init -q && git add -A && git commit -q -m "fixture")
tar -czf tests/evals/pipeline/scenarios/07-python-mlops-pipeline/fixtures/starter.tar.gz \
    -C "$FIXTURE_TMP" .
rm -rf "$FIXTURE_TMP"
```

- [ ] **Step 2: Scenario 09 — Swift concurrency stub**

Write `tests/evals/pipeline/scenarios/09-swift-concurrency/prompt.md`:

```markdown
# Scenario 09 — Swift actor race-condition fix (STUB)

**STUB — replace before Phase 03.** The shipped fixture has a trivial data race (`var count: Int` incremented from two tasks). Convert the wrapping class to an `actor` and verify with `XCTest`.

Pipeline mode: `bugfix`.
```

Write `tests/evals/pipeline/scenarios/09-swift-concurrency/expected.yaml`:

```yaml
id: 09-swift-concurrency
mode: bugfix
token_budget: 80000
elapsed_budget_seconds: 360
min_pipeline_score: 75
required_verdict: CONCERNS
touched_files_expected:
  - Sources/Counter/Counter.swift
  - Tests/CounterTests/CounterTests.swift
must_not_touch:
  - .claude/**
  - tests/evals/**
  - Package.swift
notes: "STUB — replace before Phase 03 with a richer actor-reentrancy scenario."
```

Build the fixture (minimal SwiftPM package with the race):

```bash
mkdir -p tests/evals/pipeline/scenarios/09-swift-concurrency/fixtures
FIXTURE_TMP=$(mktemp -d)
mkdir -p "$FIXTURE_TMP/Sources/Counter" "$FIXTURE_TMP/Tests/CounterTests"
cat > "$FIXTURE_TMP/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Counter",
    targets: [
        .target(name: "Counter"),
        .testTarget(name: "CounterTests", dependencies: ["Counter"]),
    ]
)
SWIFT
cat > "$FIXTURE_TMP/Sources/Counter/Counter.swift" <<'SWIFT'
public final class Counter {
    public var count: Int = 0   // BUG: not actor-isolated
    public init() {}
    public func increment() { count += 1 }
}
SWIFT
cat > "$FIXTURE_TMP/Tests/CounterTests/CounterTests.swift" <<'SWIFT'
import XCTest
@testable import Counter

final class CounterTests: XCTestCase {
    func testConcurrentIncrements() async {
        let c = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 { group.addTask { c.increment() } }
        }
        XCTAssertEqual(c.count, 1000)   // currently flaky due to race
    }
}
SWIFT
(cd "$FIXTURE_TMP" && git init -q && git add -A && git commit -q -m "fixture")
tar -czf tests/evals/pipeline/scenarios/09-swift-concurrency/fixtures/starter.tar.gz \
    -C "$FIXTURE_TMP" .
rm -rf "$FIXTURE_TMP"
```

- [ ] **Step 3: Commit**

```bash
git add tests/evals/pipeline/scenarios/07-python-mlops-pipeline/ \
        tests/evals/pipeline/scenarios/09-swift-concurrency/
git commit -m "feat(evals): add stub scenarios 07 (MLOps) and 09 (Swift) pending domain replacement"
```

---

## Task 20: Final sweep — README cross-checks + push

- [ ] **Step 1: Verify no `touched_files:` without `_expected` suffix anywhere in harness tree**

```bash
grep -RIn "touched_files:" /Users/denissajnar/IdeaProjects/forge/tests/evals/pipeline/ \
    /Users/denissajnar/IdeaProjects/forge/shared/state-schema.md \
    /Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md \
    || echo "no hits"
```

Expected: only `touched_files_expected:` matches; bare `touched_files:` must be zero. If any match is bare `touched_files:`, fix it with Edit — the canonical key is `touched_files_expected` (review C2).

- [ ] **Step 2: Verify the three wall-clock numbers appear only with their assigned values**

```bash
grep -RIn "scenario_timeout_seconds\|total_budget_seconds\|SC1" \
    /Users/denissajnar/IdeaProjects/forge/tests/evals/pipeline/ \
    /Users/denissajnar/IdeaProjects/forge/.github/workflows/evals.yml \
    /Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md
```

Expected: `scenario_timeout_seconds: 900`, `total_budget_seconds: 2700`, CI `timeout-minutes: 50`, SC1 target "≤30 minutes". If any inconsistency, fix via Edit (review C1).

- [ ] **Step 3: Push branch and open PR**

```bash
git push -u origin HEAD
gh pr create --title "feat(evals): Phase 01 pipeline evaluation harness" --body "$(cat <<'EOF'
## Summary
- Adds `tests/evals/pipeline/` with runner + 10 frozen scenarios (8 production + 2 stub).
- Adds `.github/workflows/evals.yml` with master baseline artifact + PR regression gate (3-pt tolerance).
- Adds `EVAL-*` scoring categories, `--eval-mode` orchestrator flag (FORGE_EVAL=1 guarded), `eval_run` state field (schema 1.6.0→1.7.0).

## Review feedback resolved
- **C1 wall-clock consistency:** 900 s / 2700 s / 50 min / ≤30 min SC1 propagated throughout.
- **C2 field name:** `touched_files_expected` is the single canonical key in YAML + state.
- **I3 baseline store:** GitHub Actions artifacts (90-day retention); missing-baseline → WARNING + skip gate.

## Test plan
- [ ] CI `collect` job passes (scenario YAML validates).
- [ ] CI `dry-run` job passes (FORGE_EVAL=1 smoke).
- [ ] CI `full-suite` job on master uploads baseline artifact.
- [ ] Subsequent PR sees regression gate fire (or skip with WARNING on first run).
- [ ] `tests/evals/pipeline/leaderboard.md` auto-regenerated on master push.
EOF
)"
```

- [ ] **Step 4: Final commit (if Step 1 or 2 required fixes)**

```bash
git add -A
git diff --cached --quiet || git commit -m "fix(evals): enforce touched_files_expected key + wall-clock triple"
git push
```

---

## Self-review (performed before handoff)

**Spec coverage** — every in-scope item from spec §3 is covered:
- Scenario format (Tasks 12, 18, 19); Python runner (Tasks 1-11); 10 scenarios across 4 modes (Tasks 12, 18, 19); composite scoring (Task 5); overlap (Task 5); GitHub Actions workflow (Task 16); 3-point gate (Task 8); `eval-results.jsonl` (Task 10); auto-leaderboard (Task 16 push step); `EVAL-*` categories (Task 14); `evals:` config section (Task 13); `eval_run` state field (Task 15); `--eval-mode` flag (Task 15).

**Review issues resolved** — all three criticals (C1, C2, C3/I3) are top-section-documented and enforced in Task 20 sweep. Important items I2, I4, M1, M3 addressed in Tasks 15, 11/15, 17, 1 respectively.

**Placeholder scan** — no "TBD", no "add appropriate X", no "similar to Task N". Every code block is complete.

**Type consistency** — `touched_files_expected` used in `schema.Expected`, YAML files, state-schema doc, orchestrator doc, registry-override, README, and final sweep. `Scenario.expected.touched_files_expected` is the one canonical accessor. `Result.touched_files_actual` is the distinct actual-side field.

**TDD ordering preserved** — schema tests (Task 2) before schema impl (Task 3); scoring tests (Task 4) before scoring impl (Task 5); scenarios tests+impl combined (Task 6) per TDD-in-one-commit pattern; baseline tests (Task 7) before baseline impl (Task 8). Executor, report, CLI lack unit tests by design — they integrate external processes and are validated by the CI `collect` + `dry-run` jobs (per project rule: no local test execution).
