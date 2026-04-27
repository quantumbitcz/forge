# Forge Mega-Consolidation — Phase A: Helpers + Schema Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land 6 atomic helper additions and the state-schema bump that all subsequent phases depend on.

**Architecture:** Pure-addition phase — every commit is a new file or a stdlib-only module. No existing agents are modified. State schema gains four new objects (brainstorm, bug, feedback_decisions, platform) but no existing fields change.

**Tech Stack:** Python 3.10+, urllib.request (stdlib), regex (stdlib), pathlib, JSON. No new external dependencies.

**Spec reference:** `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` commit 660dbef7. Read §2, §3, §6.1, §11, §11.1 before starting.

---

## Phase scope and ordering

| # | Commit | Spec section | Owns ACs |
|---|---|---|---|
| A1 | `feat(helpers): add ac-extractor` | §3 | AC-S022 (extractor side) |
| A2 | `feat(helpers): add bootstrap-detect with atomic-write contract` | §2 | AC-S015, AC-S017, AC-S018, AC-S027 (helper side) |
| A3 | `feat(helpers): add platform-detect + 4 adapters` | §6.1 | AC-FEEDBACK-006 (helper side), AC-FEEDBACK-007 |
| A4 | `docs(preflight-constraints): validate new config keys` | §11.1 | AC-S028, AC-FEEDBACK-007 (validation slot) |
| A5 | `docs(intent-classification): add 11 verbs + vague outcome` | §1, AC-S007 | AC-S007 (classifier side), AC-S008, AC-S009 (matrix) |
| A6 | `feat(state-schema): bump for BRAINSTORMING + brainstorm/bug/feedback_decisions/platform` | §11 | AC-S024, AC-S025 (event-name slots), AC-S026 |

All six commits are **pure additions** — nothing in Phase A modifies an existing agent or skill body. Phases B–E consume from A.

---

## Cross-phase consumption map

| Producer (Phase A) | Consumer (other phase) | What is consumed |
|---|---|---|
| A1 `shared/ac-extractor.py` | C1 `agents/fg-010-shaper.md` | Imported in autonomous degradation path |
| A2 `shared/bootstrap-detect.py` | B1 `skills/forge/SKILL.md`, B2 `skills/forge-admin/SKILL.md` | Called when `forge.local.md` is absent |
| A3 `shared/platform-detect.py` | C2 `agents/fg-100-orchestrator.md` (PREFLIGHT) | Invoked at PREFLIGHT, result written to `state.platform` |
| A3 `shared/platform_adapters/*.py` | D5 `agents/fg-710-post-run.md` | Defense-comment posting |
| A4 `shared/preflight-constraints.md` | A6, all of D | Validation contract for new config keys |
| A5 `shared/intent-classification.md` | B1 `skills/forge/SKILL.md`, B7 reconciliation | Verb → mode dispatch + `vague` outcome |
| A6 `shared/state-schema.md` | C1, C2, all of D | Persists brainstorm/bug/feedback_decisions/platform |

---

## Task A1: Add `shared/ac-extractor.py` (autonomous AC extractor)

**Risk:** medium

**Risk justification:** Heuristic regex extractors can produce silent low-quality output that the BRAINSTORMING autonomous-mode path then promotes to a real spec. The risk is high-output low-confidence specs slipping past the `fg-210-validator` confidence gate. Mitigation: confidence enum is mandatory, three-tier confidence is the only output (no continuous score), and the integration in C1 emits `[AUTO] brainstorm skipped — extractor confidence: <level>` so downstream review sees it. Tests cover all five regex paths plus low-confidence fallback. Spec §3 `Autonomous-mode degradation` is the binding contract.

**Files:**
- Create: `shared/ac-extractor.py`
- Test: `tests/unit/ac_extractor_test.py`

**Implementer prompt (inline for this task):** Write a Python 3.10+ stdlib-only module exposing `extract_acs(raw_text: str) -> dict`. Output schema is exactly `{objective: str, acceptance_criteria: list[str], confidence: "high" | "medium" | "low"}`. Match (a) `Given/When/Then` lines, (b) numbered list items `^\s*\d+[.)]\s+`, (c) imperative-verb bullets prefixed by one of `must, should, will, ensure, validate, return, expose, accept, reject` (case-insensitive). Confidence is `low` when the deduplicated AC count is `<2`, `medium` for 2–4, `high` for 5+. Objective is the first non-empty line of `raw_text`, capped at 200 chars. The dedup must be order-preserving exact-string-match. Do NOT use any third-party library; pure stdlib only.

**Spec-reviewer prompt (inline for this task):** Verify the regex set matches §3 of the spec verbatim — three patterns: numbered list, given/when/then, imperative verbs (10-verb whitelist). Confirm `confidence: "low" | "medium" | "high"` enum is preserved (no `unknown`, no scoring float). Confirm the module is importable as `shared.ac_extractor` (file name `shared/ac-extractor.py` — Python's import system will not import a hyphenated filename as a normal module, so the test must use `importlib.util.spec_from_file_location`; flag this in review if missing). Read the test file and check it covers all five cases listed in commit A1's test enumeration: numbered list, given/when/then, imperative bullets, low-confidence (<2 ACs), high-confidence (≥5 ACs).

> **Module-import note:** Because the spec dictates the file name `shared/ac-extractor.py` (with a hyphen), the test imports the module via `importlib.util` rather than `from shared.ac_extractor import extract_acs`. The hyphen is non-negotiable — it matches the rest of `shared/` (e.g., `shared/check-environment.sh`) and is what §12 of the spec lists as the artefact path.

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/ac_extractor_test.py
"""Tests for shared/ac-extractor.py — autonomous AC extractor.

The module file uses a hyphen (`shared/ac-extractor.py`) per the spec.
Python's normal import system rejects hyphenated module names, so this
test loads it via importlib.util.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "ac-extractor.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("ac_extractor", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["ac_extractor"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def ac_extractor():
    return _load_module()


def test_extracts_numbered_list_acs(ac_extractor):
    text = """
1. The system MUST authenticate users.
2. Sessions expire after 30 minutes.
3. Users can reset password via email.
""".strip()
    result = ac_extractor.extract_acs(text)
    assert isinstance(result, dict)
    assert set(result.keys()) == {"objective", "acceptance_criteria", "confidence"}
    assert len(result["acceptance_criteria"]) == 3
    assert result["confidence"] == "medium"


def test_low_confidence_when_under_2_acs(ac_extractor):
    result = ac_extractor.extract_acs("Just one bullet point: do something.")
    assert len(result["acceptance_criteria"]) <= 1
    assert result["confidence"] == "low"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/ac_extractor_test.py -v`

Expected: FAIL with `FileNotFoundError` or `AssertionError` because `shared/ac-extractor.py` does not yet exist (the `spec_from_file_location` call returns `None` when the path doesn't resolve, so the assertion `assert spec is not None` fires).

- [ ] **Step 3: Write minimal implementation**

```python
# shared/ac-extractor.py
"""Autonomous acceptance-criteria extractor used by fg-010-shaper in --autonomous mode.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §3 (commit 660dbef7).
Pure stdlib. No third-party dependencies. Cross-platform (Windows/macOS/Linux).
"""
from __future__ import annotations

import re
from typing import Literal, TypedDict

Confidence = Literal["high", "medium", "low"]


class ACResult(TypedDict):
    objective: str
    acceptance_criteria: list[str]
    confidence: Confidence


# Pattern (a): numbered list — "1." or "1)" at start of line, optional leading whitespace.
_NUMBERED = re.compile(r"^\s*\d+[.)]\s+(.+?)\s*$", re.MULTILINE)

# Pattern (b): Given/When/Then BDD lines.
_GIVEN_WHEN_THEN = re.compile(
    r"^\s*(?:Given|When|Then)\s+(.+?)\s*$",
    re.MULTILINE | re.IGNORECASE,
)

# Pattern (c): bullet (- or *) prefixed by an imperative verb from the whitelist.
_IMPERATIVE_VERBS = (
    "must",
    "should",
    "will",
    "ensure",
    "validate",
    "return",
    "expose",
    "accept",
    "reject",
)
_IMPERATIVE = re.compile(
    r"^\s*[-*]\s+(?:" + "|".join(_IMPERATIVE_VERBS) + r")\b(.+?)\s*$",
    re.MULTILINE | re.IGNORECASE,
)

_OBJECTIVE_MAX_CHARS = 200


def _classify_confidence(ac_count: int) -> Confidence:
    if ac_count < 2:
        return "low"
    if ac_count <= 4:
        return "medium"
    return "high"


def extract_acs(raw_text: str) -> ACResult:
    """Extract acceptance criteria from free-text input.

    Returns a dict with keys (objective, acceptance_criteria, confidence).
    Order-preserving deduplication via exact string match.
    """
    if not isinstance(raw_text, str):
        raise TypeError(f"raw_text must be str, got {type(raw_text).__name__}")

    matches: list[str] = []
    for pattern in (_NUMBERED, _GIVEN_WHEN_THEN, _IMPERATIVE):
        for hit in pattern.findall(raw_text):
            matches.append(hit.strip())

    seen: set[str] = set()
    deduped: list[str] = []
    for ac in matches:
        if ac and ac not in seen:
            seen.add(ac)
            deduped.append(ac)

    confidence = _classify_confidence(len(deduped))

    objective = ""
    for line in raw_text.splitlines():
        stripped = line.strip()
        if stripped:
            objective = stripped[:_OBJECTIVE_MAX_CHARS]
            break

    return {
        "objective": objective,
        "acceptance_criteria": deduped,
        "confidence": confidence,
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/ac_extractor_test.py -v`

Expected: PASS (2/2 tests).

- [ ] **Step 5: Add the remaining test cases**

Replace the test file with the full set of five required cases plus three edge cases:

```python
# tests/unit/ac_extractor_test.py
"""Tests for shared/ac-extractor.py — autonomous AC extractor.

The module file uses a hyphen (`shared/ac-extractor.py`) per the spec.
Python's normal import system rejects hyphenated module names, so this
test loads it via importlib.util.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "ac-extractor.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("ac_extractor", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["ac_extractor"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def ac_extractor():
    return _load_module()


def test_extracts_numbered_list_acs(ac_extractor):
    text = """
1. The system MUST authenticate users.
2. Sessions expire after 30 minutes.
3. Users can reset password via email.
""".strip()
    result = ac_extractor.extract_acs(text)
    assert set(result.keys()) == {"objective", "acceptance_criteria", "confidence"}
    assert len(result["acceptance_criteria"]) == 3
    assert result["confidence"] == "medium"


def test_extracts_given_when_then_acs(ac_extractor):
    text = """
Add OAuth login.

Given a user with valid credentials
When they hit /login
Then a session token is returned
""".strip()
    result = ac_extractor.extract_acs(text)
    assert len(result["acceptance_criteria"]) == 3
    assert any("valid credentials" in ac for ac in result["acceptance_criteria"])
    assert result["confidence"] == "medium"


def test_extracts_imperative_bullets(ac_extractor):
    text = """
- must reject empty passwords
- should expose a /health endpoint
- will accept JSON over POST
""".strip()
    result = ac_extractor.extract_acs(text)
    assert len(result["acceptance_criteria"]) == 3
    assert result["confidence"] == "medium"


def test_low_confidence_when_under_2_acs(ac_extractor):
    result = ac_extractor.extract_acs("Just one bullet point: do something.")
    assert len(result["acceptance_criteria"]) <= 1
    assert result["confidence"] == "low"


def test_high_confidence_with_five_or_more_acs(ac_extractor):
    text = """
1. The API MUST authenticate every request.
2. Sessions expire after 30 minutes of idle.
3. Password reset goes via email.
4. Failed login attempts trigger rate limiting after 5 tries.
5. All endpoints return JSON, never HTML.
6. Errors include a stable error code.
""".strip()
    result = ac_extractor.extract_acs(text)
    assert len(result["acceptance_criteria"]) >= 5
    assert result["confidence"] == "high"


def test_dedup_preserves_first_occurrence_order(ac_extractor):
    text = """
1. A
2. B
- must A
""".strip()
    result = ac_extractor.extract_acs(text)
    # Numbered "A" and "B" are extracted; "must A" picks up " A" (with leading space) which
    # after strip becomes "A" — duplicate suppressed. Order: A first, B second.
    assert result["acceptance_criteria"][0] == "A"
    assert result["acceptance_criteria"][1] == "B"


def test_empty_input_returns_low_confidence(ac_extractor):
    result = ac_extractor.extract_acs("")
    assert result["objective"] == ""
    assert result["acceptance_criteria"] == []
    assert result["confidence"] == "low"


def test_objective_truncated_to_200_chars(ac_extractor):
    long_first_line = "x" * 500
    result = ac_extractor.extract_acs(long_first_line + "\n1. foo\n2. bar")
    assert len(result["objective"]) == 200
    assert result["objective"] == "x" * 200


def test_non_string_input_raises_typeerror(ac_extractor):
    with pytest.raises(TypeError):
        ac_extractor.extract_acs(None)  # type: ignore[arg-type]
```

- [ ] **Step 6: Run full test suite for this module**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/ac_extractor_test.py -v`

Expected: PASS (9/9 tests). If any fail, fix the regex or dedup logic in `shared/ac-extractor.py` and re-run.

- [ ] **Step 7: Commit**

```bash
git add shared/ac-extractor.py tests/unit/ac_extractor_test.py
git commit -m "$(cat <<'EOF'
feat(helpers): add ac-extractor for autonomous BRAINSTORMING

Module: shared/ac-extractor.py (Python 3.10+ stdlib only)
Tests:  tests/unit/ac_extractor_test.py (9 cases)
Spec:   docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §3
Owns:   AC-S022 (extractor side; agent integration in C1)
EOF
)"
```

> **Consumed by:** C1 imports this module from `agents/fg-010-shaper.md` autonomous degradation path. The integration test for AC-S022 lives in Phase B (`tests/scenarios/autonomous-cold-start.bats`).

---

## Task A2: Extract `shared/bootstrap-detect.py` (atomic-write contract)

**Risk:** medium

**Risk justification:** Bootstrap writes a config file that downstream pipeline runs treat as the single source of truth. A partial write (interrupted by signal, disk full, or filesystem flush bug) leaves the project in a `forge.local.md exists but is malformed` state — and per spec §2, that state must NOT auto-bootstrap, it must abort with an explicit error. The atomic-write contract (`tmp + rename`) is the only thing preventing a half-written config from poisoning every subsequent `/forge` invocation. Tests must simulate mid-write interrupt to prove atomicity. Mitigation: Path.rename is atomic on POSIX and Windows ≥ 10; the simulated-interrupt test proves we never leave a half-written target.

**Files:**
- Create: `shared/bootstrap-detect.py`
- Test: `tests/unit/bootstrap_detect_test.py`

**Implementer prompt (inline for this task):** Write a Python 3.10+ stdlib-only module exposing two functions: `detect_stack(repo_root: Path) -> dict` and `write_forge_local_md(stack: dict, target_path: Path) -> None`. `detect_stack` returns `{language, framework, testing, build, ambiguous: bool, reason: str}` based on file probes (`pom.xml` → java/maven, `build.gradle.kts` → kotlin/gradle, `package.json` + `next.config.js` → typescript/next, `pyproject.toml` + `fastapi` dependency → python/fastapi, etc.). When detection is `ambiguous: true`, callers must abort and point the user to `/forge-admin config wizard`. `write_forge_local_md` MUST use atomic-write semantics: write to `<target>.tmp` (same directory) then call `Path.rename(target)`. The temp file gets the same parent directory so `rename` is atomic on the same filesystem. On error, the temp file is deleted and an exception propagates.

**Spec-reviewer prompt (inline for this task):** Verify the atomic-write contract — there must be a `.tmp` intermediate file in the same parent directory as the target, and the final step is `Path.rename` (not `shutil.copy`, not `open(target, 'w')` direct). Confirm detection covers the three reference stacks listed in the spec (Kotlin/Spring, TypeScript/Next, Python/FastAPI) plus an ambiguous-stack rejection path. Confirm there is a test that simulates mid-write interrupt (e.g., monkeypatches `Path.rename` to raise) and asserts the target file is absent afterward (not partial). Read AC-S027 — write contract is REQUIRED.

- [ ] **Step 1: Write the failing test scaffold**

```python
# tests/unit/bootstrap_detect_test.py
"""Tests for shared/bootstrap-detect.py — stack detection + atomic-write contract.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §2
ACs:  AC-S015, AC-S017, AC-S018, AC-S027 (atomic-write).
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "bootstrap-detect.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("bootstrap_detect", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["bootstrap_detect"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def bootstrap_detect():
    return _load_module()


def test_detects_kotlin_spring(bootstrap_detect, tmp_path):
    (tmp_path / "build.gradle.kts").write_text(
        'plugins { id("org.springframework.boot") version "3.4.0" }\n'
    )
    (tmp_path / "settings.gradle.kts").write_text("")
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "kotlin"
    assert result["framework"] == "spring"
    assert result["build"] == "gradle"
    assert result["ambiguous"] is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/bootstrap_detect_test.py -v`

Expected: FAIL with `assert spec is not None` because `shared/bootstrap-detect.py` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```python
# shared/bootstrap-detect.py
"""Project stack detection + atomic forge.local.md writer.

Used by:
  - skills/forge/SKILL.md (auto-bootstrap branch when forge.local.md is absent)
  - skills/forge-admin/SKILL.md (config wizard)
  - agents/fg-050-project-bootstrapper.md (greenfield bootstrap)

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §2 (commit 660dbef7).
Atomic-write contract: AC-S027 — target file is either absent or fully written.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import TypedDict


class StackResult(TypedDict):
    language: str | None
    framework: str | None
    testing: str | None
    build: str | None
    ambiguous: bool
    reason: str


_TEMP_SUFFIX = ".tmp"


def _file_contains(path: Path, needle: str) -> bool:
    try:
        return needle in path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False


def _detect_kotlin(root: Path) -> StackResult | None:
    gradle_kts = root / "build.gradle.kts"
    if not gradle_kts.exists():
        return None
    is_spring = _file_contains(gradle_kts, "org.springframework.boot")
    return {
        "language": "kotlin",
        "framework": "spring" if is_spring else None,
        "testing": "junit5" if is_spring else "kotest",
        "build": "gradle",
        "ambiguous": False,
        "reason": "build.gradle.kts present" + (" (Spring Boot detected)" if is_spring else ""),
    }


def _detect_typescript(root: Path) -> StackResult | None:
    pkg = root / "package.json"
    if not pkg.exists():
        return None
    try:
        data = json.loads(pkg.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
    is_next = "next" in deps or (root / "next.config.js").exists() or (root / "next.config.mjs").exists()
    has_ts = "typescript" in deps or (root / "tsconfig.json").exists()
    if not has_ts and not is_next:
        return None
    return {
        "language": "typescript",
        "framework": "nextjs" if is_next else None,
        "testing": "vitest" if "vitest" in deps else ("jest" if "jest" in deps else None),
        "build": "npm",
        "ambiguous": False,
        "reason": "package.json + " + ("next.config detected" if is_next else "tsconfig.json"),
    }


def _detect_python(root: Path) -> StackResult | None:
    pyproject = root / "pyproject.toml"
    if not pyproject.exists():
        return None
    body = pyproject.read_text(encoding="utf-8", errors="ignore")
    is_fastapi = "fastapi" in body.lower()
    is_django = "django" in body.lower()
    framework: str | None = None
    if is_fastapi and not is_django:
        framework = "fastapi"
    elif is_django and not is_fastapi:
        framework = "django"
    return {
        "language": "python",
        "framework": framework,
        "testing": "pytest" if "pytest" in body else None,
        "build": "uv" if (root / "uv.lock").exists() else "pip",
        "ambiguous": is_fastapi and is_django,
        "reason": "pyproject.toml present"
        + (" (ambiguous: both fastapi and django referenced)" if is_fastapi and is_django else ""),
    }


def detect_stack(repo_root: Path) -> StackResult:
    """Detect language/framework/testing/build for the project at repo_root.

    Probes are deterministic and ordered. The first non-None probe wins.
    Returns ambiguous: True when no single stack can be picked confidently.
    """
    if not isinstance(repo_root, Path):
        repo_root = Path(repo_root)

    probes = (_detect_kotlin, _detect_typescript, _detect_python)
    hits = [r for r in (p(repo_root) for p in probes) if r is not None]

    if not hits:
        return {
            "language": None,
            "framework": None,
            "testing": None,
            "build": None,
            "ambiguous": True,
            "reason": "no recognized build manifest at repo root",
        }
    if len(hits) > 1:
        return {
            "language": None,
            "framework": None,
            "testing": None,
            "build": None,
            "ambiguous": True,
            "reason": f"multiple stacks detected: {[h['language'] for h in hits]}",
        }
    return hits[0]


def write_forge_local_md(stack: StackResult, target_path: Path) -> None:
    """Atomically write forge.local.md.

    Contract (AC-S027):
      - Target is either absent or fully written; never partial.
      - Implementation: write to <target>.tmp in the same parent dir, then Path.rename.
      - On any error during write, the temp file is removed and the exception propagates.
    """
    if not isinstance(target_path, Path):
        target_path = Path(target_path)
    if stack["ambiguous"]:
        raise ValueError(
            f"refusing to write forge.local.md: stack detection ambiguous ({stack['reason']})"
        )

    target_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = target_path.with_suffix(target_path.suffix + _TEMP_SUFFIX)

    body = _render_forge_local_md(stack)
    try:
        temp_path.write_text(body, encoding="utf-8")
        temp_path.rename(target_path)
    except Exception:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass
        raise


def _render_forge_local_md(stack: StackResult) -> str:
    lines = [
        "---",
        "# Auto-generated by shared/bootstrap-detect.py.",
        "# Edit freely — `/forge-admin config` re-reads this file.",
        f"language: {stack['language'] or 'null'}",
        f"framework: {stack['framework'] or 'null'}",
        f"testing: {stack['testing'] or 'null'}",
        f"build: {stack['build'] or 'null'}",
        "autonomous: false",
        "---",
        "",
        "# Project configuration (forge)",
        "",
        f"Detected stack: **{stack['language']}** / **{stack['framework']}**.",
        f"Reason: {stack['reason']}.",
        "",
    ]
    return "\n".join(lines)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/bootstrap_detect_test.py -v`

Expected: PASS (1/1 — the Kotlin/Spring detection case).

- [ ] **Step 5: Add the remaining test cases including atomic-write under simulated interrupt**

Replace the test file with the full set:

```python
# tests/unit/bootstrap_detect_test.py
"""Tests for shared/bootstrap-detect.py — stack detection + atomic-write contract.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §2
ACs:  AC-S015, AC-S017, AC-S018, AC-S027 (atomic-write).
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "bootstrap-detect.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("bootstrap_detect", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["bootstrap_detect"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def bootstrap_detect():
    return _load_module()


def test_detects_kotlin_spring(bootstrap_detect, tmp_path):
    (tmp_path / "build.gradle.kts").write_text(
        'plugins { id("org.springframework.boot") version "3.4.0" }\n'
    )
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "kotlin"
    assert result["framework"] == "spring"
    assert result["build"] == "gradle"
    assert result["ambiguous"] is False


def test_detects_typescript_next(bootstrap_detect, tmp_path):
    (tmp_path / "package.json").write_text(
        json.dumps(
            {
                "name": "demo",
                "dependencies": {"next": "14.0.0", "react": "18.0.0"},
                "devDependencies": {"typescript": "5.0.0", "vitest": "1.0.0"},
            }
        )
    )
    (tmp_path / "tsconfig.json").write_text("{}")
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "typescript"
    assert result["framework"] == "nextjs"
    assert result["testing"] == "vitest"
    assert result["ambiguous"] is False


def test_detects_python_fastapi(bootstrap_detect, tmp_path):
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "demo"\ndependencies = ["fastapi", "uvicorn", "pytest"]\n'
    )
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "python"
    assert result["framework"] == "fastapi"
    assert result["testing"] == "pytest"
    assert result["ambiguous"] is False


def test_ambiguous_stack_rejected(bootstrap_detect, tmp_path):
    # Both Kotlin and TypeScript hits — mixed monorepo without a clear primary.
    (tmp_path / "build.gradle.kts").write_text("plugins { kotlin(\"jvm\") }")
    (tmp_path / "package.json").write_text(json.dumps({"dependencies": {"next": "14"}}))
    (tmp_path / "tsconfig.json").write_text("{}")
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["ambiguous"] is True
    assert "multiple" in result["reason"]


def test_no_recognized_stack_is_ambiguous(bootstrap_detect, tmp_path):
    # Empty directory — no manifest at all.
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["ambiguous"] is True
    assert result["language"] is None


def test_write_forge_local_md_creates_target(bootstrap_detect, tmp_path):
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": "kotlin",
        "framework": "spring",
        "testing": "junit5",
        "build": "gradle",
        "ambiguous": False,
        "reason": "build.gradle.kts present (Spring Boot detected)",
    }
    bootstrap_detect.write_forge_local_md(stack, target)
    assert target.exists()
    body = target.read_text(encoding="utf-8")
    assert "language: kotlin" in body
    assert "framework: spring" in body


def test_write_refuses_ambiguous_stack(bootstrap_detect, tmp_path):
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": None,
        "framework": None,
        "testing": None,
        "build": None,
        "ambiguous": True,
        "reason": "no recognized build manifest at repo root",
    }
    with pytest.raises(ValueError, match="ambiguous"):
        bootstrap_detect.write_forge_local_md(stack, target)
    assert not target.exists()


def test_write_is_atomic_under_simulated_interrupt(bootstrap_detect, tmp_path, monkeypatch):
    """AC-S027: target is either absent or fully written, never partial.

    We simulate a mid-write interrupt by monkeypatching Path.rename to raise.
    After the failure, the target must NOT exist — only the .tmp file may
    have been written, and our cleanup deletes it.
    """
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": "kotlin",
        "framework": "spring",
        "testing": "junit5",
        "build": "gradle",
        "ambiguous": False,
        "reason": "ok",
    }

    original_rename = Path.rename

    def boom(self: Path, *args, **kwargs):  # type: ignore[no-untyped-def]
        raise RuntimeError("simulated interrupt during rename")

    monkeypatch.setattr(Path, "rename", boom)
    with pytest.raises(RuntimeError, match="simulated interrupt"):
        bootstrap_detect.write_forge_local_md(stack, target)

    # Target file must NOT exist after failure (atomic-write contract).
    assert not target.exists(), "target file leaked after simulated rename failure"
    # Temp file must also be cleaned up.
    monkeypatch.setattr(Path, "rename", original_rename)
    temp = target.with_suffix(target.suffix + ".tmp")
    assert not temp.exists(), "temp file leaked after simulated rename failure"


def test_write_handles_disk_full_simulation(bootstrap_detect, tmp_path, monkeypatch):
    """AC-S018: a write failure aborts cleanly; target stays absent."""
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": "python",
        "framework": "fastapi",
        "testing": "pytest",
        "build": "uv",
        "ambiguous": False,
        "reason": "ok",
    }
    original_write = Path.write_text

    def fail(self: Path, *args, **kwargs):  # type: ignore[no-untyped-def]
        raise OSError(28, "No space left on device")

    monkeypatch.setattr(Path, "write_text", fail)
    with pytest.raises(OSError):
        bootstrap_detect.write_forge_local_md(stack, target)
    monkeypatch.setattr(Path, "write_text", original_write)
    assert not target.exists()
```

- [ ] **Step 6: Run full test suite for this module**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/bootstrap_detect_test.py -v`

Expected: PASS (9/9 tests).

- [ ] **Step 7: Commit**

```bash
git add shared/bootstrap-detect.py tests/unit/bootstrap_detect_test.py
git commit -m "$(cat <<'EOF'
feat(helpers): add bootstrap-detect with atomic-write contract

Module: shared/bootstrap-detect.py (Python 3.10+ stdlib only)
Tests:  tests/unit/bootstrap_detect_test.py (9 cases incl. simulated-interrupt)
Spec:   docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §2
Owns:   AC-S015, AC-S017, AC-S018, AC-S027 (helper side; B1/B2 wire to skills)

Atomic-write: write_forge_local_md uses tmp + Path.rename so the target
is never partial. Tested by monkeypatching rename to raise mid-flight
and asserting the target file is absent after the failure.
EOF
)"
```

> **Consumed by:** B1 calls `shared/bootstrap-detect.py` from `skills/forge/SKILL.md` when `.claude/forge.local.md` is absent. B2 calls it from `skills/forge-admin/SKILL.md`'s `config wizard` subcommand.

---

## Task A3: Add `shared/platform-detect.py` + 4 adapters under `shared/platform_adapters/`

**Risk:** medium

**Risk justification:** This module touches network I/O (Gitea API probe) and credential discovery (env vars). A mis-detection silently selects the wrong adapter and the post-run agent posts defenses to the wrong host, or worse, leaks credentials by reading the wrong env var. Mitigation: detection algorithm is purely local-first (git remote URL match), API probe is only the last resort with a hard 3-second timeout, and adapters are constructed with no auth at detect time — auth is loaded lazily by `fg-710-post-run` from env when posting. Tests cover all four happy paths plus unknown remote and missing-auth warning. The file/dir layout follows §6.1 verbatim.

**Files:**
- Create: `shared/platform-detect.py`
- Create: `shared/platform_adapters/__init__.py`
- Create: `shared/platform_adapters/github.py`
- Create: `shared/platform_adapters/gitlab.py`
- Create: `shared/platform_adapters/bitbucket.py`
- Create: `shared/platform_adapters/gitea.py`
- Test: `tests/unit/platform_detect_test.py`

**Implementer prompt (inline for this task):** Write a Python 3.10+ stdlib-only module at `shared/platform-detect.py` exposing `detect_platform(repo_root: Path, config: dict | None = None) -> dict` returning `{platform: str, remote_url: str, api_base: str, auth_method: str, detected_at: str}`. Detection rules per spec §6.1: (1) explicit `config['platform']['detection']` overrides everything except `auto`; (2) `auto` shells `git remote get-url <remote_name>` (default `origin`) and matches against host patterns; (3) self-hosted Gitea/Forgejo via API probe at `<host>/api/v1/version` with 3-second timeout; (4) unknown returns `platform: "unknown"`. Adapters in `shared/platform_adapters/` each expose a single `post_comment(pr_url, body, auth) -> dict` function — implementations are stubs in this task (raise `NotImplementedError("D5 wires this up")`); the contract and module surface ship now so D5 can fill bodies later.

**Spec-reviewer prompt (inline for this task):** Verify §6.1 detection rules — explicit override path, then auto path with remote URL inspection, then Gitea API probe as last resort. Confirm GitHub uses `api.github.com`; GitLab uses host-based `https://gitlab.com/api/v4` or self-hosted equivalent; Bitbucket Cloud uses `https://api.bitbucket.org/2.0`; Gitea uses `<host>/api/v1`. Confirm adapter modules exist as plug-in files (one per platform) with the spec'd `post_comment` signature; their bodies may be `NotImplementedError` stubs in this commit (D5 fills them). Verify the missing-auth path emits a warning string but does not raise.

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/platform_detect_test.py
"""Tests for shared/platform-detect.py — VCS platform detection.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §6.1
ACs:  AC-FEEDBACK-006 (helper side), AC-FEEDBACK-007 (explicit override).
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "platform-detect.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("platform_detect", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["platform_detect"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def platform_detect():
    return _load_module()


def test_detects_github(platform_detect, tmp_path):
    with patch("subprocess.run") as run:
        run.return_value = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout="https://github.com/quantumbitcz/forge.git\n",
        )
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "github"
    assert result["api_base"] == "https://api.github.com"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/platform_detect_test.py -v`

Expected: FAIL with `assert spec is not None` because `shared/platform-detect.py` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create the adapter package first:

```python
# shared/platform_adapters/__init__.py
"""Per-VCS adapters for posting comments. D5 fills in the bodies.

Each adapter exposes:
    post_comment(pr_url: str, body: str, auth: dict) -> dict

Returning {posted: bool, response: dict | str, error: str | None}.
"""

__all__ = ["github", "gitlab", "bitbucket", "gitea"]
```

```python
# shared/platform_adapters/github.py
"""GitHub adapter — uses the GitHub MCP or `gh api` fallback.

D5 fills this in. The detect path constructs the adapter info; runtime
posting lives in fg-710-post-run.
"""
from __future__ import annotations


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    raise NotImplementedError("D5 wires this up — see fg-710-post-run rewrite")
```

```python
# shared/platform_adapters/gitlab.py
"""GitLab adapter — `glab api` CLI when present, else stdlib urllib REST."""
from __future__ import annotations


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    raise NotImplementedError("D5 wires this up — see fg-710-post-run rewrite")
```

```python
# shared/platform_adapters/bitbucket.py
"""Bitbucket Cloud adapter — pure stdlib urllib.request against REST v2.0."""
from __future__ import annotations


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    raise NotImplementedError("D5 wires this up — see fg-710-post-run rewrite")
```

```python
# shared/platform_adapters/gitea.py
"""Gitea/Forgejo adapter — pure stdlib urllib.request against REST v1."""
from __future__ import annotations


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    raise NotImplementedError("D5 wires this up — see fg-710-post-run rewrite")
```

Now the detect module:

```python
# shared/platform-detect.py
"""VCS platform detection.

Reads `git remote get-url <remote_name>` and matches against known host
patterns. Falls back to a Gitea API probe with 3-second timeout. Honors
explicit override via config['platform']['detection'].

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §6.1
ACs:  AC-FEEDBACK-006, AC-FEEDBACK-007.
"""
from __future__ import annotations

import datetime as _dt
import os
import re
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import TypedDict
from urllib.parse import urlparse


class PlatformInfo(TypedDict):
    platform: str  # github | gitlab | bitbucket | gitea | unknown
    remote_url: str
    api_base: str
    auth_method: str
    detected_at: str
    warning: str | None


_KNOWN_HOSTS: tuple[tuple[re.Pattern[str], str, str, str], ...] = (
    (re.compile(r"(?:^|@|//)github\.com[:/]"), "github", "https://api.github.com", "gh-cli"),
    (re.compile(r"(?:^|@|//)gitlab\.com[:/]"), "gitlab", "https://gitlab.com/api/v4", "glab-cli"),
    (
        re.compile(r"(?:^|@|//)bitbucket\.org[:/]"),
        "bitbucket",
        "https://api.bitbucket.org/2.0",
        "app-password",
    ),
)

_GITEA_PROBE_TIMEOUT_SECONDS = 3
_VALID_DETECTION_VALUES = ("auto", "github", "gitlab", "bitbucket", "gitea")


def _now_iso() -> str:
    return _dt.datetime.now(tz=_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _read_remote_url(repo_root: Path, remote_name: str) -> str | None:
    try:
        proc = subprocess.run(
            ["git", "remote", "get-url", remote_name],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def _host_from_url(url: str) -> str | None:
    # Handle scp-style git@host:path/repo.git as well as URL form.
    if "://" in url:
        parsed = urlparse(url)
        return parsed.hostname
    if "@" in url and ":" in url:
        return url.split("@", 1)[1].split(":", 1)[0]
    return None


def _gitea_probe(host: str) -> bool:
    """Probe <host>/api/v1/version with a 3-second timeout. True iff Gitea/Forgejo."""
    if not host:
        return False
    url = f"https://{host}/api/v1/version"
    try:
        with urllib.request.urlopen(url, timeout=_GITEA_PROBE_TIMEOUT_SECONDS) as resp:
            body = resp.read(2048).decode("utf-8", errors="ignore").lower()
    except (urllib.error.URLError, TimeoutError, OSError):
        return False
    return "gitea" in body or "forgejo" in body


def _api_base_for(platform: str, remote_url: str) -> str:
    """Compute API base URL for a detected platform."""
    if platform == "github":
        return "https://api.github.com"
    if platform == "gitlab":
        host = _host_from_url(remote_url) or "gitlab.com"
        return f"https://{host}/api/v4"
    if platform == "bitbucket":
        return "https://api.bitbucket.org/2.0"
    if platform == "gitea":
        host = _host_from_url(remote_url)
        return f"https://{host}/api/v1" if host else ""
    return ""


def _auth_method_for(platform: str) -> str:
    return {
        "github": "gh-cli",
        "gitlab": "glab-cli",
        "bitbucket": "app-password",
        "gitea": "gitea-token",
        "unknown": "none",
    }.get(platform, "none")


def _auth_env_for(platform: str) -> str | None:
    return {
        "github": "GITHUB_TOKEN",
        "gitlab": "GITLAB_TOKEN",
        "bitbucket": "BITBUCKET_APP_PASSWORD",
        "gitea": "GITEA_TOKEN",
    }.get(platform)


def detect_platform(repo_root: Path, config: dict | None = None) -> PlatformInfo:
    """Detect the VCS platform for the repo at repo_root.

    Resolution:
      1. config['platform']['detection'] explicit override (skip auto path).
      2. git remote get-url <remote_name> match against known hosts.
      3. Gitea API probe as last resort.
      4. Fallback: platform = "unknown".
    """
    if config is None:
        config = {}
    platform_cfg = (config.get("platform") or {})
    detection = platform_cfg.get("detection", "auto")
    remote_name = platform_cfg.get("remote_name", "origin")

    if detection not in _VALID_DETECTION_VALUES:
        raise ValueError(
            f"platform.detection must be one of {_VALID_DETECTION_VALUES}; got {detection!r}"
        )

    remote_url = _read_remote_url(repo_root, remote_name) or ""

    if detection != "auto":
        platform = detection
    else:
        platform = "unknown"
        for pattern, name, _api_base, _auth in _KNOWN_HOSTS:
            if pattern.search(remote_url):
                platform = name
                break
        if platform == "unknown" and remote_url:
            host = _host_from_url(remote_url)
            if host and _gitea_probe(host):
                platform = "gitea"

    api_base = _api_base_for(platform, remote_url)
    auth_method = _auth_method_for(platform)

    warning: str | None = None
    env_var = _auth_env_for(platform)
    if env_var and not os.environ.get(env_var) and platform != "github":
        # GitHub uses gh CLI auth which is not env-var-bound; missing here is fine.
        # For others the env var is the canonical auth — warn (not abort) per §6.1.
        warning = (
            f"platform={platform} but {env_var} is not set; defenses will be logged "
            f"locally with addressed: defended_local_only"
        )

    return {
        "platform": platform,
        "remote_url": remote_url,
        "api_base": api_base,
        "auth_method": auth_method,
        "detected_at": _now_iso(),
        "warning": warning,
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/platform_detect_test.py -v`

Expected: PASS (1/1 — the GitHub detection case).

- [ ] **Step 5: Add the remaining test cases**

Replace the test file with the full set:

```python
# tests/unit/platform_detect_test.py
"""Tests for shared/platform-detect.py — VCS platform detection.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §6.1
ACs:  AC-FEEDBACK-006 (helper side), AC-FEEDBACK-007 (explicit override).
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "platform-detect.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("platform_detect", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["platform_detect"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def platform_detect():
    return _load_module()


def _git_remote(stdout: str) -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess(args=[], returncode=0, stdout=stdout)


def test_detects_github(platform_detect, tmp_path, monkeypatch):
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    with patch("subprocess.run", return_value=_git_remote("https://github.com/quantumbitcz/forge.git\n")):
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "github"
    assert result["api_base"] == "https://api.github.com"
    assert result["auth_method"] == "gh-cli"
    # GitHub does not need an env-var token (gh CLI handles auth) — no warning.
    assert result["warning"] is None


def test_detects_gitlab_com(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("GITLAB_TOKEN", "glpat-fake")
    with patch("subprocess.run", return_value=_git_remote("git@gitlab.com:group/project.git\n")):
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "gitlab"
    assert result["api_base"] == "https://gitlab.com/api/v4"


def test_detects_self_hosted_gitlab_via_explicit_override(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("GITLAB_TOKEN", "glpat-fake")
    config = {"platform": {"detection": "gitlab", "remote_name": "origin"}}
    with patch("subprocess.run", return_value=_git_remote("https://gitlab.acme.io/team/repo.git\n")):
        result = platform_detect.detect_platform(tmp_path, config)
    assert result["platform"] == "gitlab"
    # api_base honors the host of the explicit remote URL.
    assert result["api_base"] == "https://gitlab.acme.io/api/v4"


def test_detects_bitbucket_org(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("BITBUCKET_APP_PASSWORD", "secret")
    with patch("subprocess.run", return_value=_git_remote("https://bitbucket.org/team/repo.git\n")):
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "bitbucket"
    assert result["api_base"] == "https://api.bitbucket.org/2.0"


def test_detects_gitea_via_api_probe(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("GITEA_TOKEN", "gitea-fake")

    # The remote URL is a self-hosted host with no `gitea` substring; the probe
    # is what tells us it's Gitea/Forgejo.
    def fake_urlopen(url, timeout=None):  # noqa: ANN001
        class _Resp:
            def read(self, _n):
                return b'{"version": "1.21.0", "server": "Gitea"}'

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        return _Resp()

    with patch("subprocess.run", return_value=_git_remote("git@code.acme.io:team/repo.git\n")), \
         patch("urllib.request.urlopen", side_effect=fake_urlopen):
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "gitea"
    assert result["api_base"] == "https://code.acme.io/api/v1"


def test_unknown_remote_returns_unknown(platform_detect, tmp_path, monkeypatch):
    # Probe fails (no Gitea signature in body).
    def fake_urlopen(url, timeout=None):  # noqa: ANN001
        class _Resp:
            def read(self, _n):
                return b"<html>nothing here</html>"

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        return _Resp()

    with patch("subprocess.run", return_value=_git_remote("https://my-vcs.example/team/repo.git\n")), \
         patch("urllib.request.urlopen", side_effect=fake_urlopen):
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "unknown"
    assert result["auth_method"] == "none"


def test_explicit_override_skips_auto_detect(platform_detect, tmp_path, monkeypatch):
    """AC-FEEDBACK-007: explicit platform.detection wins."""
    monkeypatch.setenv("GITLAB_TOKEN", "glpat-fake")
    config = {"platform": {"detection": "gitlab"}}
    # Even though remote URL says github.com, the explicit override wins.
    with patch("subprocess.run", return_value=_git_remote("https://github.com/x/y.git\n")):
        result = platform_detect.detect_platform(tmp_path, config)
    assert result["platform"] == "gitlab"


def test_missing_auth_emits_warning_not_error(platform_detect, tmp_path, monkeypatch):
    """AC-FEEDBACK-007 + §6.1: missing auth env warns, never aborts."""
    monkeypatch.delenv("GITLAB_TOKEN", raising=False)
    with patch("subprocess.run", return_value=_git_remote("https://gitlab.com/team/repo.git\n")):
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "gitlab"
    assert result["warning"] is not None
    assert "GITLAB_TOKEN" in result["warning"]


def test_invalid_explicit_detection_raises(platform_detect, tmp_path):
    """Detection enum is validated."""
    config = {"platform": {"detection": "perforce"}}
    with pytest.raises(ValueError, match="platform.detection"):
        platform_detect.detect_platform(tmp_path, config)


def test_adapter_modules_importable():
    """Each per-platform adapter module exists with a post_comment function."""
    import importlib

    for name in ("github", "gitlab", "bitbucket", "gitea"):
        mod = importlib.import_module(f"shared.platform_adapters.{name}")
        assert hasattr(mod, "post_comment"), f"{name} adapter missing post_comment"
```

> **Note for the implementer:** The `test_adapter_modules_importable` test imports `shared.platform_adapters.<name>` via the normal import system. For that to work, `shared/__init__.py` must exist; if it doesn't, create it as an empty file in this commit. The package layout `shared/platform_adapters/` requires its own `__init__.py` (already created above).

- [ ] **Step 6: Ensure `shared/__init__.py` exists**

Run: `cd /Users/denissajnar/IdeaProjects/forge && [ -f shared/__init__.py ] || touch shared/__init__.py`

Expected: `shared/__init__.py` exists (empty file is fine — it just makes `shared.platform_adapters` resolvable as a package).

- [ ] **Step 7: Run full test suite for this module**

Run: `cd /Users/denissajnar/IdeaProjects/forge && python -m pytest tests/unit/platform_detect_test.py -v`

Expected: PASS (10/10 tests).

- [ ] **Step 8: Commit**

```bash
git add shared/platform-detect.py shared/platform_adapters/ shared/__init__.py tests/unit/platform_detect_test.py
git commit -m "$(cat <<'EOF'
feat(helpers): add platform-detect + 4 adapter stubs

Module:   shared/platform-detect.py (Python 3.10+ stdlib only)
Adapters: shared/platform_adapters/{github,gitlab,bitbucket,gitea}.py (stubs)
Tests:    tests/unit/platform_detect_test.py (10 cases)
Spec:     docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §6.1
Owns:     AC-FEEDBACK-006 (helper side; PREFLIGHT wiring in C2),
          AC-FEEDBACK-007 (explicit override path).

Adapter post_comment() bodies are NotImplementedError stubs in this commit;
D5 (fg-710-post-run rewrite) wires them up.
EOF
)"
```

> **Consumed by:** C2 invokes `detect_platform` from `agents/fg-100-orchestrator.md` at PREFLIGHT and writes the result to `state.platform`. D5 imports the per-platform adapters from `agents/fg-710-post-run.md` for defense-comment posting.

---

## Task A4: Update `shared/preflight-constraints.md` for new config keys

**Risk:** low

**Files:**
- Modify: `shared/preflight-constraints.md`

**Implementer prompt (inline for this task):** Add a new validation block to `shared/preflight-constraints.md` covering the keys listed in spec §11.1: `brainstorm.{enabled,spec_dir,autonomous_extractor_min_confidence,transcript_mining.{enabled,top_k,max_chars}}`, `quality_gate.consistency_promotion.{enabled,threshold}`, `bug.{hypothesis_branching.enabled,fix_gate_threshold}`, `post_run.{defense_enabled,defense_min_evidence}`, `pr_builder.{default_strategy,cleanup_checklist_enabled}`, `worktree.stale_after_days`, `platform.{detection,remote_name}`. Use the same one-bullet-per-section style as existing constraints. Document each rule's range and default; cross-reference §11.1 for the full enum lists. Note that these keys are NOT subject to retrospective auto-tuning (they go in the `<!-- locked -->` block when generated).

**Spec-reviewer prompt (inline for this task):** Verify every key listed in spec §11.1 has a corresponding bullet (count: 16 keys). Verify enums match: `pr_builder.default_strategy` accepts only `open-pr | open-pr-draft | direct-push | stash` (NOT `abandon` — that's interactive-only); `platform.detection` accepts only `auto | github | gitlab | bitbucket | gitea`; `brainstorm.autonomous_extractor_min_confidence` accepts only `low | medium | high`. Confirm numeric ranges match: `consistency_promotion.threshold` is `[2, 9]`; `bug.fix_gate_threshold` is `[0.50, 0.95]` float; `worktree.stale_after_days` is `[1, 365]`; `transcript_mining.top_k` is `[1, 10]`; `transcript_mining.max_chars` is `[500, 32000]`. Confirm a note on the `<!-- locked -->` block is present.

- [ ] **Step 1: Read the current preflight-constraints.md**

Run: `cd /Users/denissajnar/IdeaProjects/forge && wc -l shared/preflight-constraints.md`

Expected: ~50 lines or so. Read the file to find the right insertion point — the bullet list ends before the per-section tables (e.g., `### Run History Store`).

- [ ] **Step 2: Insert the new validation rules**

Use Edit to append new bullets immediately before the first `###` table heading. The new bullets should match the existing one-bullet-per-rule style, e.g.:

```markdown
- BRAINSTORMING: `brainstorm.enabled` (boolean, default `true`); `brainstorm.spec_dir` (string, default `docs/superpowers/specs/`, parent directory must exist or be creatable — write probe at PREFLIGHT); `brainstorm.autonomous_extractor_min_confidence` must be one of `low | medium | high` (default `medium`); `brainstorm.transcript_mining.enabled` (boolean, default `true`); `brainstorm.transcript_mining.top_k` integer in [1, 10] (default 3); `brainstorm.transcript_mining.max_chars` integer in [500, 32000] (default 4000). All keys go in the `<!-- locked -->` block — not subject to retrospective auto-tuning.
- Cross-reviewer consistency: `quality_gate.consistency_promotion.enabled` (boolean, default `true`); `quality_gate.consistency_promotion.threshold` integer in [2, 9] (default 3).
- Bug investigator: `bug.hypothesis_branching.enabled` (boolean, default `true`); `bug.fix_gate_threshold` float in [0.50, 0.95] (default 0.75 — "almost perfect code" gate; only hypotheses above this posterior satisfy the fix gate).
- Post-run defense: `post_run.defense_enabled` (boolean, default `true`); `post_run.defense_min_evidence` (boolean, default `true` — defense responses must reference at least one file path or commit SHA when set).
- PR builder: `pr_builder.default_strategy` must be one of `open-pr | open-pr-draft | direct-push | stash` (default `open-pr-draft` — autonomous lands as draft for explicit human promotion; note: `abandon` is interactive-only, never an autonomous default); `pr_builder.cleanup_checklist_enabled` (boolean, default `true`).
- Worktree hygiene: `worktree.stale_after_days` integer in [1, 365] (default 30 — worktrees older than this are flagged `WORKTREE-STALE`).
- Platform detection: `platform.detection` must be one of `auto | github | gitlab | bitbucket | gitea` (default `auto` — detect via remote URL + repo files); `platform.remote_name` non-empty string matching `^[a-zA-Z0-9_./-]+$` (default `origin` — git remote to inspect when `platform.detection == auto`).
```

Run this Edit:

```
Edit shared/preflight-constraints.md
old_string:
- Compression eval: `compression_eval.enabled` (boolean, default `true`), `compression_eval.auto_run_after_compress` (boolean, default `false`), `compression_eval.drift_threshold_pct` 10-200 (default 50).

### Run History Store
new_string:
- Compression eval: `compression_eval.enabled` (boolean, default `true`), `compression_eval.auto_run_after_compress` (boolean, default `false`), `compression_eval.drift_threshold_pct` 10-200 (default 50).
- BRAINSTORMING: `brainstorm.enabled` (boolean, default `true`); `brainstorm.spec_dir` (string, default `docs/superpowers/specs/`, parent directory must exist or be creatable — write probe at PREFLIGHT); `brainstorm.autonomous_extractor_min_confidence` must be one of `low | medium | high` (default `medium`); `brainstorm.transcript_mining.enabled` (boolean, default `true`); `brainstorm.transcript_mining.top_k` integer in [1, 10] (default 3); `brainstorm.transcript_mining.max_chars` integer in [500, 32000] (default 4000). All keys go in the `<!-- locked -->` block — not subject to retrospective auto-tuning.
- Cross-reviewer consistency: `quality_gate.consistency_promotion.enabled` (boolean, default `true`); `quality_gate.consistency_promotion.threshold` integer in [2, 9] (default 3).
- Bug investigator: `bug.hypothesis_branching.enabled` (boolean, default `true`); `bug.fix_gate_threshold` float in [0.50, 0.95] (default 0.75 — "almost perfect code" gate; only hypotheses above this posterior satisfy the fix gate).
- Post-run defense: `post_run.defense_enabled` (boolean, default `true`); `post_run.defense_min_evidence` (boolean, default `true` — defense responses must reference at least one file path or commit SHA when set).
- PR builder: `pr_builder.default_strategy` must be one of `open-pr | open-pr-draft | direct-push | stash` (default `open-pr-draft` — autonomous lands as draft for explicit human promotion; `abandon` is interactive-only, never an autonomous default); `pr_builder.cleanup_checklist_enabled` (boolean, default `true`).
- Worktree hygiene: `worktree.stale_after_days` integer in [1, 365] (default 30 — worktrees older than this are flagged `WORKTREE-STALE`).
- Platform detection: `platform.detection` must be one of `auto | github | gitlab | bitbucket | gitea` (default `auto` — detect via remote URL + repo files); `platform.remote_name` non-empty string matching `^[a-zA-Z0-9_./-]+$` (default `origin` — git remote to inspect when `platform.detection == auto`).

### Run History Store
```

- [ ] **Step 3: Add a structural test for the rule additions**

Create `tests/structural/preflight-new-keys.bats`:

```bash
#!/usr/bin/env bats
# Asserts that shared/preflight-constraints.md documents all new config keys
# from the mega-consolidation spec §11.1.
#
# Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §11.1.
# AC:   AC-S028.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    CONSTRAINTS="$REPO_ROOT/shared/preflight-constraints.md"
}

@test "BRAINSTORMING keys are documented" {
    grep -F "brainstorm.enabled" "$CONSTRAINTS"
    grep -F "brainstorm.spec_dir" "$CONSTRAINTS"
    grep -F "brainstorm.autonomous_extractor_min_confidence" "$CONSTRAINTS"
    grep -F "brainstorm.transcript_mining.enabled" "$CONSTRAINTS"
    grep -F "brainstorm.transcript_mining.top_k" "$CONSTRAINTS"
    grep -F "brainstorm.transcript_mining.max_chars" "$CONSTRAINTS"
}

@test "consistency-promotion keys are documented" {
    grep -F "quality_gate.consistency_promotion.enabled" "$CONSTRAINTS"
    grep -F "quality_gate.consistency_promotion.threshold" "$CONSTRAINTS"
}

@test "bug investigator keys are documented" {
    grep -F "bug.hypothesis_branching.enabled" "$CONSTRAINTS"
    grep -F "bug.fix_gate_threshold" "$CONSTRAINTS"
}

@test "post_run defense keys are documented" {
    grep -F "post_run.defense_enabled" "$CONSTRAINTS"
    grep -F "post_run.defense_min_evidence" "$CONSTRAINTS"
}

@test "pr_builder keys are documented" {
    grep -F "pr_builder.default_strategy" "$CONSTRAINTS"
    grep -F "pr_builder.cleanup_checklist_enabled" "$CONSTRAINTS"
}

@test "worktree.stale_after_days is documented" {
    grep -F "worktree.stale_after_days" "$CONSTRAINTS"
}

@test "platform.detection and platform.remote_name are documented" {
    grep -F "platform.detection" "$CONSTRAINTS"
    grep -F "platform.remote_name" "$CONSTRAINTS"
}

@test "pr_builder.default_strategy enum lists open-pr-draft as default" {
    # Spec §11.1: default is open-pr-draft.
    grep -E "pr_builder.default_strategy.*open-pr-draft" "$CONSTRAINTS"
}

@test "platform.detection enum is exactly auto|github|gitlab|bitbucket|gitea" {
    grep -E "platform.detection.*auto.*github.*gitlab.*bitbucket.*gitea" "$CONSTRAINTS"
}
```

- [ ] **Step 4: Run the structural test**

Run: `cd /Users/denissajnar/IdeaProjects/forge && ./tests/lib/bats-core/bin/bats tests/structural/preflight-new-keys.bats`

Expected: PASS (9/9 tests).

- [ ] **Step 5: Commit**

```bash
git add shared/preflight-constraints.md tests/structural/preflight-new-keys.bats
git commit -m "$(cat <<'EOF'
docs(preflight-constraints): validate new mega-consolidation config keys

Adds:    brainstorm.*, quality_gate.consistency_promotion.*,
         bug.{hypothesis_branching,fix_gate_threshold},
         post_run.{defense_enabled,defense_min_evidence},
         pr_builder.{default_strategy,cleanup_checklist_enabled},
         worktree.stale_after_days, platform.{detection,remote_name}.
Tests:   tests/structural/preflight-new-keys.bats (9 cases)
Spec:    docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §11.1
Owns:    AC-S028 (validation slot — actual PREFLIGHT enforcement
         lives in B7/orchestrator update; this commit is the contract).
EOF
)"
```

> **Consumed by:** A6 (state-schema bump references these keys); B1/B2 skill bodies refer to these defaults; orchestrator (C2) reads them at PREFLIGHT.

---

## Task A5: Update `shared/intent-classification.md` (11 verbs + `vague` outcome)

**Risk:** low

**Files:**
- Modify: `shared/intent-classification.md`

**Implementer prompt (inline for this task):** Update `shared/intent-classification.md` to (a) add explicit signal-row entries for the 11 hybrid-grammar verbs from spec §1: `run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit`. Each verb is recognized when the input begins with the verb literal OR contains the verb in a clear command position. (b) Make the `vague` outcome explicit with a concrete signal-count threshold: `vague` fires when fewer than 2 of (actors, entities, surface, criteria) signals are present AND the input is also free of any explicit verb match. (c) Add a top-of-document note that the classifier is consumed by both the legacy `/forge-run` skill (during transition) and the new `/forge` skill body (post-Phase B). Default route on `vague` is `run` (which then triggers BRAINSTORMING per §3).

**Spec-reviewer prompt (inline for this task):** Verify all 11 verbs from spec §1 hybrid grammar table are present (`run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit`). Confirm `vague` is concretely defined with `signal-count < 2` (not qualitative). Confirm AC-S007 is satisfied: vague defaults to `run` mode, which triggers BRAINSTORMING. Confirm the priority table is updated to include the explicit-verb override at the top (highest priority). Confirm the document still validates against the structure used by `tests/unit/intent-classification/` if that suite exists; if not, add a structural bats test asserting the 11-verb section is present.

- [ ] **Step 1: Read the current intent-classification.md to find insertion points**

Run: `cd /Users/denissajnar/IdeaProjects/forge && wc -l shared/intent-classification.md`

Expected: ~113 lines. Read it to confirm the existing intents (bugfix, migration, bootstrap, multi-feature, vague, testing, documentation, refactor, performance, single-feature) and the priority table.

- [ ] **Step 2: Add the 11-verb explicit-grammar section after the classification table**

Edit `shared/intent-classification.md` to append a new section. Use this Edit:

```
Edit shared/intent-classification.md
old_string:
## Classification Priority

When multiple intents match, use this precedence (highest first):
1. Explicit prefix/flag override (always wins)
new_string:
## Hybrid-grammar verbs (added 2026-04-27)

The new `/forge` skill (per spec §1) recognizes 11 explicit verbs as the FIRST token of input. When present, the verb wins outright — no signal-counting, no NL classification. The classifier still runs to populate downstream telemetry but its outcome is overridden.

| Verb | Mode |
|---|---|
| `run` | `single-feature` (or downstream split via multi-feature detection) |
| `fix` | `bugfix` |
| `sprint` | `multi-feature` (sprint orchestration) |
| `review` | `review` (read or fix scope, per `--scope`/`--fix` flags) |
| `verify` | `verify` (build/lint/test or config) |
| `deploy` | `deploy` |
| `commit` | `commit` |
| `migrate` | `migration` |
| `bootstrap` | `bootstrap` (greenfield) |
| `docs` | `documentation` |
| `audit` | `security-audit` |

Detection rule: `^\s*(run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit)\b`. The match is case-sensitive and operates on the trimmed input. Anything matching falls into the verb's mode unconditionally.

When the input does NOT match the verb regex, the rest of this document's classifier runs as before — including the `vague` outcome below.

## Vague outcome (concrete threshold, added 2026-04-27)

The `vague` row in the table above is now defined concretely:

> **Vague triggers when:** the input contains fewer than 2 of the four completeness signals (actors, entities, surface, criteria) AND the input does not match any explicit verb regex AND no other intent reaches its confidence threshold.

When `vague` fires, the dispatcher routes to `run` mode (single-feature). The `run` pipeline immediately enters BRAINSTORMING (per spec §3), where `fg-010-shaper` resolves the ambiguity through clarifying questions.

This keeps the classifier deterministic — it never returns `vague` and walks away. It always returns a route; `vague` is just the route that says "go through BRAINSTORMING first."

## Classification Priority

When multiple intents match, use this precedence (highest first):
1. Explicit hybrid-grammar verb (always wins — see "Hybrid-grammar verbs" above)
2. Explicit prefix/flag override (always wins)
```

- [ ] **Step 3: Add a structural test for the new sections**

Create `tests/structural/intent-classification-verbs.bats`:

```bash
#!/usr/bin/env bats
# Asserts shared/intent-classification.md documents all 11 hybrid-grammar verbs
# and the concrete vague threshold. Spec §1, AC-S007.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    DOC="$REPO_ROOT/shared/intent-classification.md"
}

@test "Hybrid-grammar verbs section is present" {
    grep -F "## Hybrid-grammar verbs" "$DOC"
}

@test "All 11 verbs are listed" {
    for verb in run fix sprint review verify deploy commit migrate bootstrap docs audit; do
        grep -E "^\| \`$verb\` \|" "$DOC"
    done
}

@test "Detection regex is documented" {
    grep -F 'run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit' "$DOC"
}

@test "Vague threshold is concrete (signal-count < 2)" {
    grep -E "fewer than 2.*completeness signals|signal-count.*< 2|< 2.*signals" "$DOC"
}

@test "Vague routes to run mode" {
    # The vague outcome must explicitly route to run/BRAINSTORMING.
    grep -E "vague.*routes? to .*run|route.*run.*BRAINSTORMING" "$DOC"
}

@test "Priority table places explicit verb at the top" {
    # Look for the priority section and confirm the first item is the verb override.
    awk '/## Classification Priority/,/^##/{print}' "$DOC" | grep -E "1\. Explicit hybrid-grammar verb"
}
```

- [ ] **Step 4: Run the structural test**

Run: `cd /Users/denissajnar/IdeaProjects/forge && ./tests/lib/bats-core/bin/bats tests/structural/intent-classification-verbs.bats`

Expected: PASS (6/6 tests).

- [ ] **Step 5: Commit**

```bash
git add shared/intent-classification.md tests/structural/intent-classification-verbs.bats
git commit -m "$(cat <<'EOF'
docs(intent-classification): add 11 verbs + concrete vague threshold

Adds:    Hybrid-grammar verbs section (run, fix, sprint, review, verify,
         deploy, commit, migrate, bootstrap, docs, audit) — verb match
         always wins over signal-counting.
         Concrete vague threshold (signal-count < 2) routing to run+BRAINSTORMING.
Tests:   tests/structural/intent-classification-verbs.bats (6 cases)
Spec:    docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §1, AC-S007
Owns:    AC-S007 (classifier side; skill dispatch in B1).
         AC-S008/AC-S009 are help/usage exit ACs — those land in B1.
         This commit gives the matrix the verbs + vague resolution rule
         that the dispatch unit tests in B13 will exercise.
EOF
)"
```

> **Consumed by:** B1 `skills/forge/SKILL.md` reads this matrix when classifying a free-text invocation. B7 `agents/fg-100-orchestrator.md` reads it during PREFLIGHT routing. B13 `tests/unit/skill-execution/forge-dispatch.bats` references this document as the source of truth for the verb list.

---

## Task A6: State schema bump (BRAINSTORMING + brainstorm/bug/feedback_decisions/platform)

**Risk:** medium

**Risk justification:** Schema bumps are a project-wide contract — every agent that reads `state.json` must tolerate the new shape. The risk is twofold: (1) downstream agents written before the bump may bail when they see new top-level keys (mitigation: per CLAUDE.md memory `feedback_no_backcompat`, forge breaks freely; agents in Phase B/C/D explicitly load the new schema), and (2) versioning collision with Phase 5's coordinated v2.0.0 bump (mitigation: spec §11 says "v1.11.0 if Phase 5 hasn't landed, else v2.1.0" — this commit inspects the live schema version at execution time and picks the next minor). State recovery from old state files is NOT supported — per `feedback_no_backcompat`, old `.forge/state.json` is wiped on schema bump.

**Files:**
- Modify: `shared/state-schema.md` — bump version, document new fields.
- Modify: `shared/state-transitions.md` — add four BRAINSTORMING transitions per §11.
- Modify: `shared/stage-contract.md` — declare BRAINSTORMING stage.

**Implementer prompt (inline for this task):** Inspect the current `**Version:** N.N.N` line of `shared/state-schema.md`. If `N.N.N` is `2.0.0` or higher, the bump is `2.1.0`; otherwise `1.11.0`. Add a `## State Changes (mega-consolidation)` section documenting `state.stage = "BRAINSTORMING"` enum value, full `state.brainstorm` object (per §11), full `state.bug` object including `hypotheses[]` schema (per §7 + §11), `state.feedback_decisions[]` (per §6 + §11), `state.platform` (per §6.1 + §11). Update `shared/state-transitions.md` with four new transitions: PREFLIGHT → BRAINSTORMING (when `mode == feature` and `brainstorm.enabled == true`), BRAINSTORMING → EXPLORING (on completion), BRAINSTORMING → ABORTED (on user abort), BRAINSTORMING → BRAINSTORMING (self-loop on resume from cache). Update `shared/stage-contract.md` to insert BRAINSTORMING between PREFLIGHT and EXPLORING in the canonical state list. Register OTel event names: `forge.brainstorm.{started, question_asked, approaches_proposed, spec_written, completed, aborted}`.

**Spec-reviewer prompt (inline for this task):** Verify version bump correctness: re-read `shared/state-schema.md` at the time of review and confirm the chosen version is the next minor after the live one (1.11.0 from current 1.10.0, OR 2.1.0 if Phase 5 already shipped 2.0.0). Confirm full `state.bug.hypotheses[]` schema: id, statement, falsifiability_test, evidence_required, status (untested|testing|tested|dropped), passes_test, confidence (high|medium|low), posterior (float). Confirm `state.feedback_decisions[]` schema: comment_id, verdict (actionable|wrong|preference), reasoning, evidence, addressed (actionable_routed|defended|acknowledged), posted_at. Confirm `state.platform` schema: name, remote_url, api_base, auth_method, detected_at. Confirm the four BRAINSTORMING transitions are added to `shared/state-transitions.md` with `(current_state, event, guard, next_state, action)` rows. Confirm OTel event names are registered (AC-S025 schema slot — events fire from C1, but the names live in the schema doc). Confirm CLAUDE.md and README updates are NOT in this commit (those are E1).

- [ ] **Step 1: Inspect the current state schema version**

Run: `cd /Users/denissajnar/IdeaProjects/forge && grep -E '^\*\*Version:\*\*' shared/state-schema.md`

Expected output: a line like `**Version:** 1.10.0`. Record the version. Pick the bump:

- If current is `1.x.y` (Phase 5 not landed): bump to `1.11.0`.
- If current is `2.0.x` or `2.1.x` (Phase 5 already landed): bump to the next minor after the current — `2.1.0` if current is `2.0.x`, `2.2.0` if current is `2.1.x`.

For the rest of this task we assume `1.10.0 → 1.11.0`. If the inspection step yields a different baseline, substitute the correct next-minor in every Edit below.

- [ ] **Step 2: Bump the version line**

```
Edit shared/state-schema.md
old_string:
**Version:** 1.10.0
new_string:
**Version:** 1.11.0
```

- [ ] **Step 3: Append the new schema section to `shared/state-schema.md`**

Append the following block at the end of `shared/state-schema.md` (use Edit with the file's last unique line as the anchor; if the file ends with a known marker, anchor on that, otherwise append by reading the last 20 lines and inserting after the final paragraph):

```markdown
## State Changes — Mega-Consolidation v1.11.0 (2026-04-27)

Spec: `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` §11 (commit 660dbef7).

### New stage enum value

`state.story_state` (alias `state.stage` in some agents) gains the value `BRAINSTORMING`. It sits between `PREFLIGHT` and `EXPLORING` in the canonical pipeline ordering.

Transitions are documented in `shared/state-transitions.md`:

| current | event | guard | next |
|---|---|---|---|
| `PREFLIGHT` | `preflight_complete` | `mode == "feature"` AND `brainstorm.enabled == true` | `BRAINSTORMING` |
| `BRAINSTORMING` | `brainstorm_complete` | spec written and approved | `EXPLORING` |
| `BRAINSTORMING` | `user_abort` | — | `ABORTED` |
| `BRAINSTORMING` | `resume_with_cache` | `state.brainstorm.spec_path` exists | `BRAINSTORMING` (self-loop) |

### `state.brainstorm`

```jsonc
{
  "spec_path": "docs/superpowers/specs/2026-04-27-add-export-csv-design.md",
  "original_input": "add CSV export to the user list",
  "started_at": "2026-04-27T14:23:11Z",
  "completed_at": "2026-04-27T14:31:42Z",
  "autonomous": false,
  "questions_asked": 4,
  "approaches_proposed": 3,
  "section_approvals": ["architecture", "components", "data_flow", "error_handling", "testing"]
}
```

Per-field types:
- `spec_path` — string, repo-relative path to the written spec.
- `original_input` — string, the verbatim free-text input that triggered BRAINSTORMING. Required for autonomous-resume regeneration.
- `started_at`, `completed_at` — ISO-8601 timestamps.
- `autonomous` — boolean. True when `--autonomous` or `autonomous: true` config was active.
- `questions_asked` — int >= 0.
- `approaches_proposed` — int >= 0.
- `section_approvals` — list of strings; expected values: any of `architecture | components | data_flow | error_handling | testing`. Order reflects the order the user approved the sections.

### `state.bug`

```jsonc
{
  "ticket_id": "FG-742",
  "reproduction_attempts": 2,
  "reproduction_succeeded": true,
  "branching_used": true,
  "fix_gate_passed": true,
  "hypotheses": [
    {
      "id": "H1",
      "statement": "Concurrent writes to .forge/state.json cause race that loses the last write",
      "falsifiability_test": "Reproduce while holding the .forge/.lock file; expect bug to NOT occur",
      "evidence_required": "stack trace shows lock-skip OR successful concurrent reproduction without lock",
      "status": "tested",
      "passes_test": true,
      "confidence": "high",
      "posterior": 0.78
    }
  ]
}
```

Per-field types:
- `ticket_id` — string or null.
- `reproduction_attempts` — int in [0, 3].
- `reproduction_succeeded` — boolean.
- `branching_used` — boolean. True when `bug.hypothesis_branching.enabled` was true at investigation time.
- `fix_gate_passed` — boolean. True iff at least one hypothesis has `passes_test: true` AND `posterior >= bug.fix_gate_threshold` (default 0.75; configurable).
- `hypotheses[].id` — string, format `H<int>` (H1, H2, ...).
- `hypotheses[].statement` — string, the hypothesis itself.
- `hypotheses[].falsifiability_test` — string, an executable check that disproves the hypothesis if it fails.
- `hypotheses[].evidence_required` — string, what observation confirms or denies the hypothesis.
- `hypotheses[].status` — enum: `untested | testing | tested | dropped`.
- `hypotheses[].passes_test` — bool, set when status transitions to `tested`.
- `hypotheses[].confidence` — enum: `high | medium | low`.
- `hypotheses[].posterior` — float in [0.0, 1.0]; updated per the Bayes formula in spec §7.

### `state.feedback_decisions`

```jsonc
[
  {
    "comment_id": "github://pulls/123#issuecomment-9876",
    "verdict": "wrong",
    "reasoning": "Reviewer suggests we mock the database, but our memory says integration tests must hit a real DB.",
    "evidence": "agents/fg-300-implementer.md:45 enforces real-DB testing per project memory",
    "addressed": "defended",
    "posted_at": "2026-04-27T15:02:11Z"
  }
]
```

Per-field types:
- `comment_id` — string, opaque platform-scoped ID (e.g. `github://pulls/<n>#issuecomment-<id>`, `gitlab://merge_requests/<n>#note_<id>`).
- `verdict` — enum: `actionable | wrong | preference`.
- `reasoning` — string, defense or acknowledgment text. ≥1 character; required for `wrong` and `preference`; optional for `actionable`.
- `evidence` — string. For `wrong` verdict, must reference at least one file path or commit SHA. For other verdicts, optional.
- `addressed` — enum: `actionable_routed | defended | acknowledged | defended_local_only`. Set after the action completes.
- `posted_at` — ISO-8601 timestamp; set when defense or acknowledgment is posted to the PR thread.

The list is also mirrored to `.forge/runs/<run_id>/feedback-decisions.jsonl` (append-only). The state field is the in-memory canonical view; the JSONL is the durable record. Recovery rebuilds state from JSONL.

### `state.platform`

```jsonc
{
  "name": "github",
  "remote_url": "https://github.com/quantumbitcz/forge",
  "api_base": "https://api.github.com",
  "auth_method": "gh-cli",
  "detected_at": "2026-04-27T15:00:00Z"
}
```

Per-field types:
- `name` — enum: `github | gitlab | bitbucket | gitea | unknown`.
- `remote_url` — string. The git remote URL inspected during detection.
- `api_base` — string. Platform API base URL.
- `auth_method` — enum: `gh-cli | glab-cli | app-password | gitea-token | none`.
- `detected_at` — ISO-8601 timestamp. Set once at PREFLIGHT; not refreshed on subsequent stages within the run.

Detection logic and adapter wiring live in `shared/platform-detect.py` (added in commit A3 of the mega-consolidation plan).

### OTel events registered for BRAINSTORMING

The orchestrator (and `fg-010-shaper` once C1 lands) emits the following events under the `forge.brainstorm.*` namespace:

| Event name | When fired |
|---|---|
| `forge.brainstorm.started` | Stage entry. |
| `forge.brainstorm.question_asked` | Each `AskUserQuestion` invocation. |
| `forge.brainstorm.approaches_proposed` | When the agent presents its 2-3 approaches. |
| `forge.brainstorm.spec_written` | When the spec file is written (atomic write completes). |
| `forge.brainstorm.completed` | Stage exit on success. |
| `forge.brainstorm.aborted` | Stage exit on user abort or unrecoverable error. |

Names are registered here (AC-S025 slot); event-emission wiring lands in C1 and C2.
```

(Apply the section as an append at the end of the file.)

- [ ] **Step 4: Insert the four BRAINSTORMING transitions in `shared/state-transitions.md`**

Edit the transitions table to insert four new rows. Use:

```
Edit shared/state-transitions.md
old_string:
| 1 | `PREFLIGHT` | `preflight_complete` | `dry_run == false` | `EXPLORING` | Initialize state, create worktree, resolve convention stacks |
| 2 | `PREFLIGHT` | `preflight_complete` | `dry_run == true` | `EXPLORING` | Initialize state (no worktree, no lock, no checkpoints) |
new_string:
| 1 | `PREFLIGHT` | `preflight_complete` | `dry_run == false AND mode == "feature" AND brainstorm.enabled == true` | `BRAINSTORMING` | Initialize state, create worktree, resolve convention stacks; dispatch fg-010-shaper |
| 1a | `PREFLIGHT` | `preflight_complete` | `dry_run == false AND (mode != "feature" OR brainstorm.enabled == false)` | `EXPLORING` | Initialize state, create worktree, resolve convention stacks |
| 2 | `PREFLIGHT` | `preflight_complete` | `dry_run == true` | `EXPLORING` | Initialize state (no worktree, no lock, no checkpoints) — dry-run skips BRAINSTORMING |
| 2a | `BRAINSTORMING` | `brainstorm_complete` | spec written and approved | `EXPLORING` | Pass `state.brainstorm.spec_path` to planner |
| 2b | `BRAINSTORMING` | `user_abort` | — | `ABORTED` | Persist partial brainstorm cache; clean exit |
| 2c | `BRAINSTORMING` | `resume_with_cache` | `state.brainstorm.spec_path` exists AND file present | `BRAINSTORMING` | Self-loop — re-enter shaper with cache loaded |
```

Also update the line that lists pipeline states to include BRAINSTORMING:

```
Edit shared/state-transitions.md
old_string:
The canonical pipeline state values `story_state` can take are enumerated in `shared/state-schema.md`: `PREFLIGHT`, `EXPLORING`, `PLANNING`, `VALIDATING`, `IMPLEMENTING`, `VERIFYING`, `REVIEWING`, `DOCUMENTING`, `SHIPPING`, `LEARNING`, `COMPLETE`, `ABORTED`, plus the `ESCALATED` pseudo-state that resolves via user response.
new_string:
The canonical pipeline state values `story_state` can take are enumerated in `shared/state-schema.md`: `PREFLIGHT`, `BRAINSTORMING`, `EXPLORING`, `PLANNING`, `VALIDATING`, `IMPLEMENTING`, `VERIFYING`, `REVIEWING`, `DOCUMENTING`, `SHIPPING`, `LEARNING`, `COMPLETE`, `ABORTED`, plus the `ESCALATED` pseudo-state that resolves via user response. `BRAINSTORMING` was added in state-schema v1.11.0 (mega-consolidation, 2026-04-27); see `shared/state-schema.md` §"State Changes — Mega-Consolidation v1.11.0".
```

- [ ] **Step 5: Update `shared/stage-contract.md` to declare BRAINSTORMING**

Read `shared/stage-contract.md` to find the ordered stage list. Insert BRAINSTORMING between PREFLIGHT and EXPLORING. The exact Edit depends on the current shape of that file; use a small targeted Edit with sufficient context.

For example, if the doc lists stages as `1. PREFLIGHT ... 2. EXPLORING ...`, the Edit becomes:

```
Edit shared/stage-contract.md
old_string:
1. **PREFLIGHT**
new_string:
1. **PREFLIGHT**
2. **BRAINSTORMING** *(feature mode only; skipped for bugfix/migration/bootstrap and when `brainstorm.enabled: false`. Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §3.)*
```

…and a follow-up Edit to renumber subsequent stages. If `stage-contract.md` uses a table or different layout, adapt the Edits accordingly. Anchor on the smallest unique substring that places BRAINSTORMING between PREFLIGHT and EXPLORING in the canonical ordering. After the edit, the doc must list BRAINSTORMING as a known stage (a one-line declaration is enough for this commit; full per-stage detail can land in C2).

> **Note:** if `shared/stage-contract.md` doesn't exist or doesn't enumerate stages explicitly, this step is a no-op — the canonical ordering is already declared in `shared/state-schema.md` and `shared/state-transitions.md` after Steps 3–4. In that case, skip this step and document the omission in the commit message.

- [ ] **Step 6: Add a structural test for the schema bump**

Create `tests/structural/state-schema-mega.bats`:

```bash
#!/usr/bin/env bats
# Asserts shared/state-schema.md, shared/state-transitions.md, and
# shared/stage-contract.md document the mega-consolidation schema bump.
#
# Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §11.
# ACs:  AC-S024, AC-S025 (event-name slots), AC-S026.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCHEMA="$REPO_ROOT/shared/state-schema.md"
    TRANS="$REPO_ROOT/shared/state-transitions.md"
}

@test "state-schema.md version is at least 1.11.0" {
    # Accept 1.11.x, 2.x, or higher — anything greater than the pre-bump 1.10.x.
    grep -E '^\*\*Version:\*\* (1\.(1[1-9]|[2-9][0-9])|[2-9])\.' "$SCHEMA"
}

@test "state.brainstorm object is documented" {
    grep -F "state.brainstorm" "$SCHEMA"
    grep -F "spec_path" "$SCHEMA"
    grep -F "original_input" "$SCHEMA"
    grep -F "section_approvals" "$SCHEMA"
}

@test "state.bug.hypotheses schema is documented" {
    grep -F "state.bug" "$SCHEMA"
    grep -F "falsifiability_test" "$SCHEMA"
    grep -F "evidence_required" "$SCHEMA"
    grep -F "posterior" "$SCHEMA"
    grep -E "status.*untested.*testing.*tested.*dropped" "$SCHEMA"
}

@test "state.feedback_decisions schema is documented" {
    grep -F "state.feedback_decisions" "$SCHEMA"
    grep -E "verdict.*actionable.*wrong.*preference" "$SCHEMA"
    grep -E "addressed.*actionable_routed.*defended.*acknowledged" "$SCHEMA"
}

@test "state.platform schema is documented" {
    grep -F "state.platform" "$SCHEMA"
    grep -E "name.*github.*gitlab.*bitbucket.*gitea.*unknown" "$SCHEMA"
    grep -F "auth_method" "$SCHEMA"
}

@test "BRAINSTORMING enum value is documented" {
    grep -F "BRAINSTORMING" "$SCHEMA"
}

@test "OTel event names registered" {
    for ev in forge.brainstorm.started forge.brainstorm.question_asked \
              forge.brainstorm.approaches_proposed forge.brainstorm.spec_written \
              forge.brainstorm.completed forge.brainstorm.aborted; do
        grep -F "$ev" "$SCHEMA"
    done
}

@test "state-transitions.md lists BRAINSTORMING in the canonical state set" {
    grep -F "BRAINSTORMING" "$TRANS"
}

@test "PREFLIGHT -> BRAINSTORMING transition row exists" {
    grep -E '\| `PREFLIGHT` \|.*\| `BRAINSTORMING` \|' "$TRANS"
}

@test "BRAINSTORMING -> EXPLORING transition row exists" {
    grep -E '\| `BRAINSTORMING` \|.*\| `EXPLORING` \|' "$TRANS"
}

@test "BRAINSTORMING -> ABORTED transition row exists" {
    grep -E '\| `BRAINSTORMING` \|.*\| `ABORTED` \|' "$TRANS"
}

@test "BRAINSTORMING self-loop transition row exists" {
    # current=BRAINSTORMING and next also BRAINSTORMING — resume from cache.
    grep -E '\| `BRAINSTORMING` \|.*resume_with_cache.*\| `BRAINSTORMING` \|' "$TRANS"
}
```

- [ ] **Step 7: Run the structural test**

Run: `cd /Users/denissajnar/IdeaProjects/forge && ./tests/lib/bats-core/bin/bats tests/structural/state-schema-mega.bats`

Expected: PASS (12/12 tests). If `tests/structural/state-schema-mega.bats::stage-contract` doesn't exist (because step 5 was a no-op), the test for `stage-contract.md` is intentionally absent from the suite above.

- [ ] **Step 8: Commit**

```bash
git add shared/state-schema.md shared/state-transitions.md shared/stage-contract.md tests/structural/state-schema-mega.bats
git commit -m "$(cat <<'EOF'
feat(state-schema): bump for BRAINSTORMING + brainstorm/bug/feedback_decisions/platform

Schema:  shared/state-schema.md → v1.11.0 (or v2.1.0 if Phase 5 already shipped 2.0.0)
Adds:    state.stage="BRAINSTORMING" enum value
         state.brainstorm  (spec_path, original_input, started_at, completed_at,
                            autonomous, questions_asked, approaches_proposed,
                            section_approvals)
         state.bug         (ticket_id, reproduction_*, branching_used,
                            fix_gate_passed, hypotheses[] with full per-field schema)
         state.feedback_decisions[]  (comment_id, verdict, reasoning, evidence,
                                      addressed, posted_at)
         state.platform    (name, remote_url, api_base, auth_method, detected_at)
Transitions: PREFLIGHT->BRAINSTORMING, BRAINSTORMING->EXPLORING,
             BRAINSTORMING->ABORTED, BRAINSTORMING->BRAINSTORMING (resume cache)
OTel:    forge.brainstorm.{started,question_asked,approaches_proposed,
                           spec_written,completed,aborted} registered
Tests:   tests/structural/state-schema-mega.bats (12 cases)
Spec:    docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §11
Owns:    AC-S024, AC-S025 (event-name slots — emission lands in C1/C2),
         AC-S026 (4 BRAINSTORMING transitions documented).

No backwards compatibility — old .forge/state.json is wiped on schema bump
per CLAUDE.md feedback_no_backcompat.
EOF
)"
```

> **Consumed by:** C1 `agents/fg-010-shaper.md` writes `state.brainstorm`. C2 `agents/fg-100-orchestrator.md` writes `state.platform` at PREFLIGHT and reads `brainstorm.enabled` to decide PREFLIGHT→BRAINSTORMING. D1 `agents/fg-200-planner.md` reads `state.bug.fix_gate_passed`. D5 `agents/fg-710-post-run.md` writes `state.feedback_decisions[]`. D6 `agents/fg-020-bug-investigator.md` writes `state.bug.hypotheses[]`.

---

## Phase A self-review checklist

The plan author has scanned this document for the following:

- **Spec coverage** — every spec section listed in the Phase A scope is owned by exactly one task:
  - §2 (auto-bootstrap detection contract) → A2.
  - §3 (autonomous AC extractor) → A1.
  - §6.1 (platform detection) → A3.
  - §11 (state schema) → A6.
  - §11.1 (config validation rules) → A4.
  - §1 + AC-S007 (intent classifier verbs) → A5.
- **AC coverage** within Phase A scope: AC-S007, AC-S008/9 (matrix-side), AC-S017/18, AC-S022 (extractor side), AC-S024, AC-S025 (event names), AC-S026, AC-S027, AC-S028, AC-FEEDBACK-006 (helper side), AC-FEEDBACK-007 — all owned. Phases B–E own the runtime/agent-side ACs.
- **No placeholders** — every code block above is concrete; no `TODO`, no `# implement later`, no "similar to Task N." Adapter `post_comment` bodies are explicitly `NotImplementedError("D5 wires this up")` because the spec defers their implementation to D5; this is documented and intentional.
- **Type/signature consistency** — `extract_acs(raw_text: str) -> ACResult` signature is the same in test, implementation, and consumption note (C1). `detect_stack(repo_root: Path) -> StackResult` and `write_forge_local_md(stack, target_path)` signatures are consistent across A2 and the B1/B2 consumption note. `detect_platform(repo_root, config=None) -> PlatformInfo` matches A3 implementation and the C2 consumption note.
- **Risk justifications** — A1, A3, A6 are the medium-risk tasks and each carries a ≥30-word `Risk justification` block. A2 is medium-risk per AC-S027 (atomic write) — also has a ≥30-word justification. A4 and A5 are low-risk (pure documentation additions with structural tests) and explicitly marked low.
- **File paths** — every path is repo-rooted: `shared/ac-extractor.py`, `shared/bootstrap-detect.py`, `shared/platform-detect.py`, `shared/platform_adapters/{github,gitlab,bitbucket,gitea}.py`, `shared/preflight-constraints.md`, `shared/intent-classification.md`, `shared/state-schema.md`, `shared/state-transitions.md`, `shared/stage-contract.md`, `tests/unit/{ac_extractor,bootstrap_detect,platform_detect}_test.py`, `tests/structural/{preflight-new-keys,intent-classification-verbs,state-schema-mega}.bats`. No relative paths, no "the helper file."
- **Cross-phase consumption notes** — every task that produces something Phase B/C/D/E will consume has a `> Consumed by:` block (A1, A2, A3, A4, A5, A6).
- **Schema version inspection** — A6 Step 1 explicitly inspects the live schema version before deciding the bump, satisfying spec §14 open question 1 (decoupled from Phase 5).
