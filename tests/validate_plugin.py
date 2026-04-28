#!/usr/bin/env python3
"""Structural validation for the forge plugin (Python entry point).

Python alternative to ``tests/validate-plugin.sh``. The shell
version remains the canonical implementation since it ships with deeper
legacy-specific checks; this Python port covers the core structural
invariants (~40 of the most important checks) and is intended for use in
environments where bash + jq aren't installed (and to give us a single Python
process that can run the gating checks during Python-only test passes).

Both entry points exit 0 on success, 1 on any failure.

Usage:
  python3 tests/validate_plugin.py            # all checks
  python3 tests/validate_plugin.py --help     # show help
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections.abc import Callable, Iterable
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

# ───────────────────────────── Discovery ───────────────────────────────────


def _list_dirs(parent: Path) -> list[str]:
    return sorted(p.name for p in parent.iterdir() if p.is_dir()) if parent.is_dir() else []


def _list_md_stems(parent: Path) -> list[str]:
    return sorted(p.stem for p in parent.glob("*.md") if p.is_file()) if parent.is_dir() else []


FRAMEWORKS = _list_dirs(REPO / "modules" / "frameworks")
LANGUAGES = _list_md_stems(REPO / "modules" / "languages")
TESTING_FILES = sorted(
    p.name for p in (REPO / "modules" / "testing").glob("*.md") if p.is_file()
) if (REPO / "modules" / "testing").is_dir() else []

BUILD_SYSTEMS = sorted({
    *(p.stem for p in (REPO / "modules" / "build-systems").glob("*.md")),
    *(p.name for p in (REPO / "modules" / "build-systems").iterdir()
      if p.is_dir() and (p / "conventions.md").is_file()),
}) if (REPO / "modules" / "build-systems").is_dir() else []

CI_PLATFORMS = _list_md_stems(REPO / "modules" / "ci-cd")
CONTAINER_ORCH = _list_md_stems(REPO / "modules" / "container-orchestration")

NON_LAYER_DIRS = {"frameworks", "languages", "testing", "build-systems",
                  "ci-cd", "container-orchestration"}
LAYERS = [d for d in _list_dirs(REPO / "modules") if d not in NON_LAYER_DIRS]

REQUIRED_FRAMEWORK_FILES = (
    "conventions.md", "local-template.md", "forge-config-template.md",
    "rules-override.json", "known-deprecations.json",
)
REQUIRED_DEPRECATION_FIELDS = (
    "pattern", "replacement", "package", "since", "applies_from", "applies_to",
)

MIN_FRAMEWORKS = 21
MIN_LANGUAGES = 15
MIN_TESTING_FILES = 19
MIN_BUILD_SYSTEMS = 9
MIN_CI_PLATFORMS = 7
MIN_CONTAINER_ORCH = 11
MIN_LAYERS = 12

# ───────────────────────────── Helpers ─────────────────────────────────────


def _frontmatter(path: Path) -> dict[str, str]:
    """Return YAML frontmatter as flat str→str dict (subset)."""
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    if not text.startswith("---"):
        return {}
    body = text.split("---", 2)
    if len(body) < 3:
        return {}
    fm: dict[str, str] = {}
    for line in body[1].splitlines():
        m = re.match(r"^([a-zA-Z_][a-zA-Z0-9_-]*)\s*:\s*(.+?)\s*$", line)
        if m:
            value = m.group(2)
            if (value.startswith('"') and value.endswith('"')) or (
                value.startswith("'") and value.endswith("'")
            ):
                value = value[1:-1]
            fm[m.group(1)] = value
    return fm


def _frontmatter_block_contains(path: Path, key: str) -> bool:
    """True if the frontmatter block contains a top-level key (e.g., 'tools:')."""
    if not path.is_file():
        return False
    text = path.read_text(encoding="utf-8", errors="replace")
    if not text.startswith("---"):
        return False
    body = text.split("---", 2)
    if len(body) < 3:
        return False
    return any(line.startswith(f"{key}:") for line in body[1].splitlines())


def _load_json(path: Path) -> tuple[bool, object]:
    try:
        return True, json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False, None


# ───────────────────────────── Check primitives ────────────────────────────


CheckFn = Callable[[], list[str]]
"""A check returns a list of failure detail strings; empty list = pass."""


def _check_for_each(
    items: Iterable[str],
    predicate: Callable[[str], str | None],
) -> list[str]:
    """Run predicate on every item; collect non-None failure messages."""
    return [msg for msg in (predicate(it) for it in items) if msg]


# ───────────────────────────── Check definitions ───────────────────────────


def check_agents_have_frontmatter() -> list[str]:
    failures: list[str] = []
    for f in (REPO / "agents").glob("*.md"):
        fm = _frontmatter(f)
        if "name" not in fm or "description" not in fm:
            failures.append(f"{f.name}: missing name or description in frontmatter")
    return failures


def check_agent_name_matches_filename() -> list[str]:
    failures: list[str] = []
    for f in (REPO / "agents").glob("*.md"):
        fm = _frontmatter(f)
        if fm.get("name") != f.stem:
            failures.append(f"{f.name}: name field {fm.get('name')!r} != filename {f.stem!r}")
    return failures


def check_pipeline_agents_naming() -> list[str]:
    pat = re.compile(r"^fg-[0-9]{3}-.+$")
    return [
        f"{f.name}: doesn't match fg-{{NNN}}-{{role}} pattern"
        for f in (REPO / "agents").glob("fg-*.md")
        if not pat.match(f.stem)
    ]


def check_agents_have_forbidden_actions() -> list[str]:
    return [
        f"{f.name}: missing 'Forbidden Actions' section"
        for f in (REPO / "agents").glob("*.md")
        if "Forbidden Actions" not in f.read_text(encoding="utf-8", errors="replace")
    ]


def check_framework_files_present() -> list[str]:
    failures: list[str] = []
    for fw in FRAMEWORKS:
        for req in REQUIRED_FRAMEWORK_FILES:
            if not (REPO / "modules" / "frameworks" / fw / req).is_file():
                failures.append(f"frameworks/{fw}/{req} missing")
    return failures


def check_conventions_have_donts() -> list[str]:
    pat = re.compile(r"don'?ts?", re.IGNORECASE)
    failures: list[str] = []
    for fw in FRAMEWORKS:
        path = REPO / "modules" / "frameworks" / fw / "conventions.md"
        if not path.is_file():
            failures.append(f"{fw}/conventions.md missing")
            continue
        if not pat.search(path.read_text(encoding="utf-8", errors="replace")):
            failures.append(f"{fw}/conventions.md missing Dos/Don'ts section")
    return failures


def check_config_template_has_total_retries() -> list[str]:
    return _check_for_each(FRAMEWORKS, lambda fw: (
        None if "total_retries_max" in (
            (REPO / "modules" / "frameworks" / fw / "forge-config-template.md")
            .read_text(encoding="utf-8", errors="replace")
        ) else f"{fw}/forge-config-template.md missing total_retries_max"
    ))


def check_config_template_has_oscillation_tolerance() -> list[str]:
    return _check_for_each(FRAMEWORKS, lambda fw: (
        None if "oscillation_tolerance" in (
            (REPO / "modules" / "frameworks" / fw / "forge-config-template.md")
            .read_text(encoding="utf-8", errors="replace")
        ) else f"{fw}/forge-config-template.md missing oscillation_tolerance"
    ))


def check_local_template_has_linear() -> list[str]:
    return _check_for_each(FRAMEWORKS, lambda fw: (
        None if "linear:" in (
            (REPO / "modules" / "frameworks" / fw / "local-template.md")
            .read_text(encoding="utf-8", errors="replace")
        ) else f"{fw}/local-template.md missing linear: section"
    ))


def check_rules_override_valid_json() -> list[str]:
    failures: list[str] = []
    for fw in FRAMEWORKS:
        ok, _ = _load_json(REPO / "modules" / "frameworks" / fw / "rules-override.json")
        if not ok:
            failures.append(f"{fw}/rules-override.json invalid JSON")
    return failures


def check_known_deprecations_valid_json() -> list[str]:
    failures: list[str] = []
    for fw in FRAMEWORKS:
        ok, _ = _load_json(REPO / "modules" / "frameworks" / fw / "known-deprecations.json")
        if not ok:
            failures.append(f"{fw}/known-deprecations.json invalid JSON")
    return failures


def check_deprecations_v2() -> list[str]:
    failures: list[str] = []
    for fw in FRAMEWORKS:
        ok, data = _load_json(REPO / "modules" / "frameworks" / fw / "known-deprecations.json")
        if not ok or not isinstance(data, dict):
            continue
        if str(data.get("version")) != "2":
            failures.append(f"{fw}/known-deprecations.json missing 'version': 2")
    return failures


def check_deprecation_required_fields() -> list[str]:
    failures: list[str] = []
    for fw in FRAMEWORKS:
        ok, data = _load_json(REPO / "modules" / "frameworks" / fw / "known-deprecations.json")
        if not ok or not isinstance(data, dict):
            continue
        for entry in data.get("deprecations", []):
            if not isinstance(entry, dict):
                failures.append(f"{fw}: non-object deprecation entry")
                continue
            for field in REQUIRED_DEPRECATION_FIELDS:
                if field not in entry:
                    failures.append(f"{fw}: deprecation entry missing field {field!r}")
                    break
    return failures


def _all_sh_files() -> list[Path]:
    sh_files: list[Path] = []
    for sub in ("shared", "hooks", "modules"):
        sh_files.extend((REPO / sub).rglob("*.sh"))
    return sh_files


def check_sh_have_shebang() -> list[str]:
    failures: list[str] = []
    for f in _all_sh_files():
        try:
            first = f.open(encoding="utf-8", errors="replace").readline()
        except OSError:
            failures.append(f"{f.relative_to(REPO)}: unreadable")
            continue
        if not first.startswith("#!"):
            failures.append(f"{f.relative_to(REPO)}: missing shebang")
    return failures


def check_sh_executable() -> list[str]:
    # Skip on Windows — POSIX exec bit isn't meaningful there.
    if sys.platform.startswith("win"):
        return []
    return [
        f"{f.relative_to(REPO)}: not executable"
        for f in _all_sh_files()
        if not f.stat().st_mode & 0o111
    ]


def check_hooks_json_valid() -> list[str]:
    ok, _ = _load_json(REPO / "hooks" / "hooks.json")
    return [] if ok else ["hooks/hooks.json invalid JSON"]


def check_hooks_json_has_events() -> list[str]:
    ok, data = _load_json(REPO / "hooks" / "hooks.json")
    if not ok or not isinstance(data, dict):
        return ["hooks/hooks.json: cannot inspect events"]
    nested = data.get("hooks", data)
    failures: list[str] = []
    if "PostToolUse" not in nested:
        failures.append("hooks/hooks.json missing PostToolUse")
    if "Stop" not in nested:
        failures.append("hooks/hooks.json missing Stop")
    return failures


def check_skills_have_frontmatter() -> list[str]:
    failures: list[str] = []
    for skill_dir in (REPO / "skills").iterdir() if (REPO / "skills").is_dir() else []:
        if not skill_dir.is_dir():
            continue
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            failures.append(f"{skill_dir.name}/SKILL.md missing")
            continue
        fm = _frontmatter(skill_md)
        if "name" not in fm or "description" not in fm:
            failures.append(f"{skill_dir.name}/SKILL.md missing name or description")
    return failures


def check_skill_descriptions_have_badge() -> list[str]:
    failures: list[str] = []
    for skill_md in (REPO / "skills").glob("*/SKILL.md"):
        fm = _frontmatter(skill_md)
        desc = fm.get("description", "")
        if not (desc.startswith("[read-only]") or desc.startswith("[writes]")):
            failures.append(f"{skill_md.parent.name}: description missing [read-only]/[writes] badge")
    return failures


def check_layer1_patterns_valid_json() -> list[str]:
    patterns_dir = REPO / "shared" / "checks" / "layer-1-fast" / "patterns"
    if not patterns_dir.is_dir():
        return []
    failures: list[str] = []
    for f in patterns_dir.glob("*.json"):
        ok, _ = _load_json(f)
        if not ok:
            failures.append(f"{f.relative_to(REPO)}: invalid JSON")
    return failures


def check_pattern_rules_have_required_fields() -> list[str]:
    patterns_dir = REPO / "shared" / "checks" / "layer-1-fast" / "patterns"
    if not patterns_dir.is_dir():
        return []
    required = ("id", "pattern", "severity", "category", "message")
    failures: list[str] = []
    for f in patterns_dir.glob("*.json"):
        ok, data = _load_json(f)
        if not ok or not isinstance(data, dict):
            continue
        for rule in data.get("rules", []):
            if not isinstance(rule, dict):
                continue
            missing = [k for k in required if k not in rule]
            if missing:
                failures.append(f"{f.relative_to(REPO)}: rule missing {missing}")
                break
    return failures


def check_pattern_rule_ids_unique() -> list[str]:
    patterns_dir = REPO / "shared" / "checks" / "layer-1-fast" / "patterns"
    if not patterns_dir.is_dir():
        return []
    failures: list[str] = []
    for f in patterns_dir.glob("*.json"):
        ok, data = _load_json(f)
        if not ok or not isinstance(data, dict):
            continue
        ids = [r.get("id") for r in data.get("rules", []) if isinstance(r, dict)]
        if len(ids) != len(set(ids)):
            failures.append(f"{f.relative_to(REPO)}: duplicate rule ids")
    return failures


def check_severity_map_valid_json() -> list[str]:
    sev = REPO / "shared" / "checks" / "layer-2-linter" / "config" / "severity-map.json"
    if not sev.is_file():
        return ["severity-map.json missing"]
    ok, _ = _load_json(sev)
    return [] if ok else ["severity-map.json invalid JSON"]


def check_framework_learnings_exist() -> list[str]:
    return [
        f"shared/learnings/{fw}.md missing"
        for fw in FRAMEWORKS
        if not (REPO / "shared" / "learnings" / f"{fw}.md").is_file()
    ]


def check_version_consistency() -> list[str]:
    plugin_json = REPO / ".claude-plugin" / "plugin.json"
    claude_md = REPO / "CLAUDE.md"
    ok, data = _load_json(plugin_json)
    if not ok or not isinstance(data, dict):
        return ["plugin.json: cannot read version"]
    plugin_ver = str(data.get("version", "")).strip()
    if not plugin_ver:
        return ["plugin.json: empty version"]

    text = claude_md.read_text(encoding="utf-8", errors="replace") if claude_md.is_file() else ""
    m = re.search(r"v(\d+\.\d+\.\d+)", text)
    if not m:
        return ["CLAUDE.md: no v{maj.min.patch} version found"]
    if m.group(1) != plugin_ver:
        return [f"version mismatch: plugin.json={plugin_ver} CLAUDE.md=v{m.group(1)}"]
    return []


def check_min_module_counts() -> list[str]:
    failures: list[str] = []
    for label, found, minimum in (
        ("frameworks", len(FRAMEWORKS), MIN_FRAMEWORKS),
        ("languages", len(LANGUAGES), MIN_LANGUAGES),
        ("testing files", len(TESTING_FILES), MIN_TESTING_FILES),
        ("build systems", len(BUILD_SYSTEMS), MIN_BUILD_SYSTEMS),
        ("ci/cd platforms", len(CI_PLATFORMS), MIN_CI_PLATFORMS),
        ("container orchestrators", len(CONTAINER_ORCH), MIN_CONTAINER_ORCH),
        ("crosscutting layers", len(LAYERS), MIN_LAYERS),
    ):
        if found < minimum:
            failures.append(f"{label}: {found} < min {minimum}")
    return failures


def check_build_system_modules_exist() -> list[str]:
    bs_dir = REPO / "modules" / "build-systems"
    failures: list[str] = []
    for bs in BUILD_SYSTEMS:
        if not (bs_dir / f"{bs}.md").is_file() and not (bs_dir / bs / "conventions.md").is_file():
            failures.append(f"build-systems/{bs} missing")
    return failures


def check_ci_modules_exist() -> list[str]:
    return [
        f"ci-cd/{ci}.md missing"
        for ci in CI_PLATFORMS
        if not (REPO / "modules" / "ci-cd" / f"{ci}.md").is_file()
    ]


def check_container_orch_modules_exist() -> list[str]:
    return [
        f"container-orchestration/{co}.md missing"
        for co in CONTAINER_ORCH
        if not (REPO / "modules" / "container-orchestration" / f"{co}.md").is_file()
    ]


def check_layer_dirs_exist() -> list[str]:
    return [
        f"modules/{layer} missing"
        for layer in LAYERS
        if not (REPO / "modules" / layer).is_dir()
    ]


def check_recovery_engine_doc() -> list[str]:
    re_md = REPO / "shared" / "recovery" / "recovery-engine.md"
    if not re_md.is_file():
        return ["shared/recovery/recovery-engine.md missing"]
    text = re_md.read_text(encoding="utf-8", errors="replace")
    # Match what the bash version actually checks.
    return [
        f"recovery-engine.md missing section: {section}"
        for section in ("Boundary", "Failure Classification",
                        "Recovery Execution", "Recovery Budget")
        if section not in text
    ]


def check_python_modules_exist() -> list[str]:
    """Invariant: ported scripts have a .py module."""
    expected = [
        "shared/check_prerequisites.py",
        "shared/config_validator.py",
        "shared/context_guard.py",
        "shared/cost_alerting.py",
        "shared/validate_finding.py",
        "shared/generate_conventions_index.py",
        "shared/convergence_engine_sim.py",
        "tests/validate_plugin.py",
    ]
    return [
        f"{p} missing (Python port required)"
        for p in expected
        if not (REPO / p).is_file()
    ]


def check_no_orphan_python_imports() -> list[str]:
    """The new shared/*.py modules must not import from third-party packages."""
    forbidden = {"yaml", "requests", "click", "tomli"}
    failures: list[str] = []
    for py in (REPO / "shared").glob("*.py"):
        text = py.read_text(encoding="utf-8", errors="replace")
        for line in text.splitlines():
            m = re.match(r"^(?:from|import)\s+([a-zA-Z_][a-zA-Z0-9_]*)", line)
            if m and m.group(1) in forbidden:
                failures.append(f"{py.relative_to(REPO)}: forbidden import {m.group(1)}")
    return failures


# ───────────────────────────── Check registry ──────────────────────────────


CHECKS: list[tuple[str, str, CheckFn]] = [
    ("AGENTS", "All agents have valid YAML frontmatter (name, description)",
     check_agents_have_frontmatter),
    ("AGENTS", "Agent name matches filename without .md",
     check_agent_name_matches_filename),
    ("AGENTS", "Pipeline agents follow fg-{NNN}-{role} naming",
     check_pipeline_agents_naming),
    ("AGENTS", "All agents have Forbidden Actions section",
     check_agents_have_forbidden_actions),
    ("MODULES", "All framework directories have required 5 files",
     check_framework_files_present),
    ("MODULES", "All conventions.md have Dos/Don'ts section",
     check_conventions_have_donts),
    ("MODULES", "All forge-config-template.md have total_retries_max",
     check_config_template_has_total_retries),
    ("MODULES", "All forge-config-template.md have oscillation_tolerance",
     check_config_template_has_oscillation_tolerance),
    ("MODULES", "All local-template.md have linear: section",
     check_local_template_has_linear),
    ("MODULES", "Min module counts satisfied",
     check_min_module_counts),
    ("JSON", "All rules-override.json are valid JSON",
     check_rules_override_valid_json),
    ("JSON", "All known-deprecations.json are valid JSON",
     check_known_deprecations_valid_json),
    ("JSON", 'All known-deprecations.json have "version": 2',
     check_deprecations_v2),
    ("JSON", "All deprecation entries have required v2 fields",
     check_deprecation_required_fields),
    ("SCRIPTS", "All .sh files in shared/, hooks/, and modules/ have shebang",
     check_sh_have_shebang),
    ("SCRIPTS", "All .sh files in shared/, hooks/, and modules/ are executable (POSIX only)",
     check_sh_executable),
    ("HOOKS", "hooks/hooks.json is valid JSON",
     check_hooks_json_valid),
    ("HOOKS", "hooks/hooks.json has PostToolUse and Stop event types",
     check_hooks_json_has_events),
    ("SKILLS", "All skills/*/SKILL.md have name: and description: frontmatter",
     check_skills_have_frontmatter),
    ("SKILLS", "All SKILL.md descriptions have [read-only] or [writes] badge prefix",
     check_skill_descriptions_have_badge),
    ("PATTERNS", "layer-2-linter/config/severity-map.json is valid JSON",
     check_severity_map_valid_json),
    ("PATTERNS", "All layer-1 pattern files are valid JSON",
     check_layer1_patterns_valid_json),
    ("PATTERNS", "All pattern rules have required fields (id, pattern, severity, category, message)",
     check_pattern_rules_have_required_fields),
    ("PATTERNS", "Pattern rule IDs are unique within each language file",
     check_pattern_rule_ids_unique),
    ("LEARNINGS", "shared/learnings/{framework}.md exists for each framework",
     check_framework_learnings_exist),
    ("VERSION", "plugin.json version matches CLAUDE.md version",
     check_version_consistency),
    ("CROSSCUTTING LAYERS", "All crosscutting layer directories exist",
     check_layer_dirs_exist),
    ("BUILD SYSTEMS", "All build system generic modules exist",
     check_build_system_modules_exist),
    ("CI/CD PLATFORMS", "All CI/CD platform generic modules exist",
     check_ci_modules_exist),
    ("CONTAINER ORCHESTRATION", "All container orchestration generic modules exist",
     check_container_orch_modules_exist),
    ("RECOVERY ENGINE", "Recovery engine doc has required sections",
     check_recovery_engine_doc),
    ("PHASE 02.1", "All ported Python modules exist",
     check_python_modules_exist),
    ("PHASE 02.1", "shared/*.py have no third-party imports",
     check_no_orphan_python_imports),
]


# ───────────────────────────── Runner ──────────────────────────────────────


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="validate_plugin",
        description="Forge plugin structural validation (Python port).",
    )
    ap.add_argument("--quiet", action="store_true",
                    help="Only print failures and the summary line")
    ap.add_argument("--no-color", action="store_true", help="Disable ANSI color codes")
    args = ap.parse_args(argv)

    use_color = not args.no_color and sys.stdout.isatty()
    PASS = "\033[32mPASS\033[0m" if use_color else "PASS"
    FAIL_TAG = "\033[31mFAIL\033[0m" if use_color else "FAIL"

    pass_count = 0
    fail_count = 0
    current_section = ""

    print("\n=== forge structural validation (Python) ===\n")

    for section, name, fn in CHECKS:
        if section != current_section:
            print(f"\n--- {section} ---")
            current_section = section
        try:
            failures = fn()
        except Exception as exc:  # pragma: no cover — defensive
            print(f"  {FAIL_TAG}: {name}\n    EXCEPTION: {exc}")
            fail_count += 1
            continue
        if not failures:
            pass_count += 1
            if not args.quiet:
                print(f"  {PASS}: {name}")
        else:
            fail_count += 1
            print(f"  {FAIL_TAG}: {name}")
            for detail in failures[:5]:
                print(f"    DETAIL: {detail}")
            if len(failures) > 5:
                print(f"    ...and {len(failures) - 5} more")

    print(f"\n=== {pass_count} passed, {fail_count} failed ===")
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
