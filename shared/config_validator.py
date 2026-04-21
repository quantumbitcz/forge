#!/usr/bin/env python3
"""Validate forge-config.md and forge.local.md against schema constraints.

Replaces the legacy ``shared/config-validator.sh``. Pure stdlib —
no PyYAML, no third-party deps.

Exit codes:
  0 — all validations passed
  1 — one or more errors (CRITICAL or ERROR severity)
  2 — warnings only (no errors)
  3 — input error (files not found, invalid args)

Usage:
  python3 -m shared.config_validator [--verbose] [--json] [--check-commands] PROJECT_ROOT
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from typing import Any

VALIDATOR_VERSION = "2.0.0"

VALID_LANGUAGES = {
    "kotlin", "java", "typescript", "python", "go", "rust", "swift",
    "c", "csharp", "ruby", "php", "dart", "elixir", "scala", "cpp",
}

VALID_FRAMEWORKS = {
    "spring", "react", "fastapi", "axum", "swiftui", "vapor", "express",
    "sveltekit", "k8s", "embedded", "go-stdlib", "aspnet", "django",
    "nextjs", "gin", "jetpack-compose", "kotlin-multiplatform", "angular",
    "nestjs", "vue", "svelte",
}

VALID_TESTING = {
    "kotest", "junit5", "vitest", "jest", "pytest", "go-testing", "xctest",
    "rust-test", "xunit-nunit", "testcontainers", "playwright", "cypress",
    "cucumber", "k6", "detox", "rspec", "phpunit", "exunit", "scalatest",
}

KNOWN_CONFIG_FIELDS = {
    "scoring", "convergence", "total_retries_max", "shipping", "sprint",
    "tracking", "scope", "routing", "model_routing", "quality_gate",
    "mutation_testing", "visual_verification", "lsp", "observability",
    "data_classification", "automations", "wiki", "memory_discovery",
    "forge_ask", "graph", "linear", "frontend_polish", "preview", "infra",
    "autonomous", "documentation", "explore", "plan_cache", "confidence",
    "test_history", "condensation", "check_engine", "code_graph",
    "living_specs", "events", "playbooks", "mode_config",
}


# ───────────────────────────── YAML / JSON helpers ─────────────────────────


def extract_yaml(path: Path) -> str:
    """Pull YAML out of a markdown file (frontmatter first, then ```yaml fences)."""
    if not path.is_file():
        return ""
    content = path.read_text(encoding="utf-8")

    fm = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if fm:
        return fm.group(1)

    fences = re.findall(r"```ya?ml\s*\n(.*?)\n```", content, re.DOTALL)
    if fences:
        return "\n".join(fences)
    return ""


def _parse_scalar(s: str) -> Any:
    s = s.strip()
    if not s:
        return None
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        return s[1:-1]
    low = s.lower()
    if low in {"true", "yes", "on"}:
        return True
    if low in {"false", "no", "off"}:
        return False
    if low in {"null", "~"}:
        return None
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        pass
    if s.startswith("[") and s.endswith("]"):
        items = s[1:-1].split(",")
        return [_parse_scalar(i) for i in items if i.strip()]
    return s


def parse_yaml_subset(text: str) -> dict[str, Any]:
    """Minimal YAML parser supporting the forge config subset.

    Handles: key: value pairs, nested objects (2-space indent), inline lists
    [...], block lists with `-`, comments, scalars (int/float/bool/null/str).
    """
    result: dict[str, Any] = {}
    stack: list[tuple[dict[str, Any], int]] = [(result, -1)]
    current_list: list[Any] | None = None
    current_list_indent = -1

    for raw_line in text.split("\n"):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indent = len(raw_line) - len(raw_line.lstrip())

        list_match = re.match(r"^(\s*)- (.+)$", raw_line)
        if list_match:
            item_indent = len(list_match.group(1))
            if current_list is not None and item_indent >= current_list_indent:
                current_list.append(_parse_scalar(list_match.group(2)))
                continue

        kv_match = re.match(r"^(\s*)([a-zA-Z_][a-zA-Z0-9_.-]*)\s*:\s*(.*?)$", raw_line)
        if not kv_match:
            continue

        key = kv_match.group(2)
        raw_val = kv_match.group(3).strip()

        while len(stack) > 1 and stack[-1][1] >= indent:
            stack.pop()
        parent = stack[-1][0]

        # Strip inline `# comment` from non-quoted scalars.
        if raw_val and not raw_val.startswith(('"', "'", "[")):
            comment_pos = raw_val.find(" #")
            if comment_pos > 0:
                raw_val = raw_val[:comment_pos].strip()

        if raw_val == "":
            new_dict: dict[str, Any] = {}
            parent[key] = new_dict
            stack.append((new_dict, indent))
            current_list = None
        elif raw_val == "[]":
            parent[key] = []
            current_list = parent[key]
            current_list_indent = indent + 2
        else:
            val = _parse_scalar(raw_val)
            parent[key] = val
            current_list = val if isinstance(val, list) else None
            if isinstance(val, list):
                current_list_indent = indent + 2

    return result


def get_path(data: dict[str, Any], dotted: str) -> Any:
    cur: Any = data
    for k in dotted.split("."):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return None
    return cur


# ───────────────────────────── Validation engine ──────────────────────────


class Validator:
    def __init__(self) -> None:
        self.results: list[dict[str, str]] = []

    def add(self, severity: str, file: str, field: str, message: str) -> None:
        self.results.append(
            {"severity": severity, "file": file, "field": field, "message": message}
        )

    def counts(self) -> dict[str, int]:
        c = {"CRITICAL": 0, "ERROR": 0, "WARNING": 0, "OK": 0}
        for r in self.results:
            c[r["severity"]] = c.get(r["severity"], 0) + 1
        return c

    # ---- Range / enum primitives ---------------------------------------------

    def validate_range(
        self,
        file: str,
        data: dict[str, Any],
        field: str,
        minimum: int | None,
        maximum: int | None,
        default: int,
    ) -> None:
        val = get_path(data, field)
        if val is None:
            self.add("OK", file, field, f"Not set (default: {default})")
            return
        if not isinstance(val, int):
            self.add("ERROR", file, field, f'Value "{val}" is not an integer')
            return
        if minimum is not None and val < minimum:
            self.add("ERROR", file, field, f"Value {val} is below minimum {minimum}")
            return
        if maximum is not None and val > maximum:
            self.add("ERROR", file, field, f"Value {val} exceeds maximum {maximum}")
            return
        self.add("OK", file, field, f"Value {val} is within range [{minimum}, {maximum}]")

    def validate_enum(
        self,
        file: str,
        data: dict[str, Any],
        field: str,
        allowed: set[str] | list[str],
        default: str,
    ) -> None:
        val = get_path(data, field)
        if val is None:
            self.add("OK", file, field, f"Not set (default: {default})")
            return
        if val in allowed:
            self.add("OK", file, field, f'Value "{val}" is valid')
        else:
            self.add(
                "ERROR",
                file,
                field,
                f'Value "{val}" is not one of: {" ".join(sorted(allowed))}',
            )

    # ---- High-level checks ---------------------------------------------------

    def check_required_fields(self, local: dict[str, Any]) -> tuple[str | None, str | None, str | None]:
        framework = get_path(local, "components.framework")
        language = get_path(local, "components.language")
        testing = get_path(local, "components.testing")

        if not language:
            if framework != "k8s":
                self.add("ERROR", "forge.local.md", "components.language",
                         "Required (unless framework is k8s). Value: empty")
            else:
                self.add("OK", "forge.local.md", "components.language",
                         "null (valid for k8s)")
        elif language in VALID_LANGUAGES:
            self.add("OK", "forge.local.md", "components.language",
                     f'Value "{language}" is valid')
        else:
            self.add("ERROR", "forge.local.md", "components.language",
                     f'Unknown language "{language}". Must be one of: '
                     f'{" ".join(sorted(VALID_LANGUAGES))}')

        if not framework:
            self.add("WARNING", "forge.local.md", "components.framework",
                     "No framework specified")
        elif framework in VALID_FRAMEWORKS:
            self.add("OK", "forge.local.md", "components.framework",
                     f'Value "{framework}" is valid')
        else:
            self.add("ERROR", "forge.local.md", "components.framework",
                     f'Unknown framework "{framework}". Must be one of: '
                     f'{" ".join(sorted(VALID_FRAMEWORKS))}')

        if not testing:
            sev = "OK" if framework == "k8s" else "WARNING"
            msg = "null (valid for k8s)" if framework == "k8s" else "No testing framework specified"
            self.add(sev, "forge.local.md", "components.testing", msg)
        elif testing in VALID_TESTING:
            self.add("OK", "forge.local.md", "components.testing",
                     f'Value "{testing}" is valid')
        else:
            self.add("ERROR", "forge.local.md", "components.testing",
                     f'Unknown testing framework "{testing}". Must be one of: '
                     f'{" ".join(sorted(VALID_TESTING))}')

        return language, framework, testing

    def check_commands_present(self, local: dict[str, Any]) -> dict[str, str]:
        cmds: dict[str, str] = {}
        for name, severity in (("build", "ERROR"), ("test", "ERROR"), ("lint", "WARNING")):
            val = get_path(local, f"commands.{name}")
            if not val or val == {} or val == "{}":
                self.add(severity, "forge.local.md", f"commands.{name}",
                         f"Empty value — {name} command is required" if severity == "ERROR"
                         else f"No {name} command specified")
                cmds[name] = ""
            else:
                self.add("OK", "forge.local.md", f"commands.{name}",
                         f'Value "{val}" is set')
                cmds[name] = str(val)

        fmt = get_path(local, "commands.format")
        if fmt and fmt != {}:
            cmds["format"] = str(fmt)
        return cmds

    def check_ranges(self, config: dict[str, Any]) -> None:
        for field, lo, hi, default in (
            ("scoring.critical_weight", 10, None, 20),
            ("scoring.warning_weight", 1, None, 5),
            ("scoring.info_weight", 0, None, 2),
            ("scoring.pass_threshold", 60, 100, 80),
            ("scoring.concerns_threshold", 40, None, 60),
            ("scoring.oscillation_tolerance", 0, 20, 5),
            ("convergence.max_iterations", 3, 20, 15),
            ("convergence.plateau_threshold", 0, 10, 3),
            ("convergence.plateau_patience", 1, 5, 3),
            ("convergence.target_score", 60, 100, 90),
            ("total_retries_max", 5, 30, 10),
            ("shipping.min_score", 60, 100, 90),
            ("shipping.evidence_max_age_minutes", 5, 60, 30),
            ("sprint.poll_interval_seconds", 10, 120, 30),
            ("sprint.dependency_timeout_minutes", 5, 180, 60),
            ("scope.decomposition_threshold", 2, 10, 3),
            ("infra.max_verification_tier", 1, 5, 3),
            ("preview.max_fix_loops", 1, 10, 3),
        ):
            self.validate_range("forge-config.md", config, field, lo, hi, default)

        # archive_after_days: 0 (disabled) or 30-365
        archive = get_path(config, "tracking.archive_after_days")
        if archive is None:
            self.add("OK", "forge-config.md", "tracking.archive_after_days",
                     "Not set (default: 90)")
        elif not isinstance(archive, int):
            self.add("ERROR", "forge-config.md", "tracking.archive_after_days",
                     f'Value "{archive}" is not an integer')
        elif archive == 0 or 30 <= archive <= 365:
            self.add("OK", "forge-config.md", "tracking.archive_after_days",
                     f"Value {archive} is valid (0 or 30-365)")
        else:
            self.add("ERROR", "forge-config.md", "tracking.archive_after_days",
                     f"Value {archive} must be 0 (disabled) or 30-365")

        self.validate_enum("forge-config.md", config, "routing.vague_threshold",
                           {"low", "medium", "high"}, "medium")
        if "model_routing" in config:
            self.validate_enum("forge-config.md", config, "model_routing.default_tier",
                               {"fast", "standard", "premium"}, "standard")

    def check_cross_field(self, config: dict[str, Any]) -> None:
        pass_t = get_path(config, "scoring.pass_threshold") or 80
        concerns_t = get_path(config, "scoring.concerns_threshold") or 60
        if isinstance(pass_t, int) and isinstance(concerns_t, int):
            gap = pass_t - concerns_t
            if gap < 10:
                self.add("ERROR", "forge-config.md",
                         "scoring.pass_threshold - concerns_threshold",
                         f"Gap is {gap} (must be >= 10)")
            else:
                self.add("OK", "forge-config.md",
                         "scoring.pass_threshold - concerns_threshold",
                         f"Gap is {gap} (>= 10)")

        warn_w = get_path(config, "scoring.warning_weight") or 5
        info_w = get_path(config, "scoring.info_weight") or 2
        if isinstance(warn_w, int) and isinstance(info_w, int):
            if warn_w <= info_w:
                self.add("ERROR", "forge-config.md",
                         "scoring.warning_weight > info_weight",
                         f"warning_weight ({warn_w}) must be greater than info_weight ({info_w})")
            else:
                self.add("OK", "forge-config.md",
                         "scoring.warning_weight > info_weight",
                         f"warning_weight ({warn_w}) > info_weight ({info_w})")

        target = get_path(config, "convergence.target_score") or 90
        if isinstance(target, int) and isinstance(pass_t, int):
            if target < pass_t:
                self.add("ERROR", "forge-config.md",
                         "convergence.target_score >= pass_threshold",
                         f"target_score ({target}) must be >= pass_threshold ({pass_t})")
            else:
                self.add("OK", "forge-config.md",
                         "convergence.target_score >= pass_threshold",
                         f"target_score ({target}) >= pass_threshold ({pass_t})")

        min_score = get_path(config, "shipping.min_score") or 90
        if isinstance(min_score, int) and isinstance(pass_t, int):
            if min_score < pass_t:
                self.add("ERROR", "forge-config.md",
                         "shipping.min_score >= pass_threshold",
                         f"min_score ({min_score}) must be >= pass_threshold ({pass_t})")
            else:
                self.add("OK", "forge-config.md",
                         "shipping.min_score >= pass_threshold",
                         f"min_score ({min_score}) >= pass_threshold ({pass_t})")

    def check_command_executability(
        self, project_root: Path, commands: dict[str, str]
    ) -> None:
        for name, cmd in commands.items():
            if not cmd:
                continue
            binary = cmd.split()[0]
            if binary.startswith("./"):
                full = project_root / binary
                if full.exists() and full.stat().st_mode & 0o111:
                    self.add("OK", "forge.local.md", f"commands.{name}",
                             f'Executable "{binary}" found at {full}')
                else:
                    self.add("WARNING", "forge.local.md", f"commands.{name}",
                             f'Executable "{binary}" not found or not executable at {full}')
            else:
                if shutil.which(binary):
                    self.add("OK", "forge.local.md", f"commands.{name}",
                             f'Executable "{binary}" found on PATH')
                else:
                    self.add("CRITICAL", "forge.local.md", f"commands.{name}",
                             f'Executable "{binary}" not found on PATH')

    def check_unknown_fields(self, config: dict[str, Any]) -> None:
        for key in config:
            if key in KNOWN_CONFIG_FIELDS:
                continue
            suggestion = ""
            for known in KNOWN_CONFIG_FIELDS:
                if key[:3] == known[:3] and key != known:
                    suggestion = f" (did you mean {known}?)"
                    break
            self.add("WARNING", "forge-config.md", key,
                     f"Unknown top-level field{suggestion}")

    def check_framework_compat(self, language: str | None, framework: str | None) -> None:
        if not framework:
            return
        if framework == "k8s" and language:
            self.add("WARNING", "forge.local.md", "components (k8s+language)",
                     f'k8s framework typically has language: null, got "{language}"')
        if framework == "go-stdlib" and language != "go":
            self.add("WARNING", "forge.local.md", "components (go-stdlib+language)",
                     f'go-stdlib framework should have language: go, got "{language}"')
        if framework == "embedded" and language not in {"c", "cpp"}:
            self.add("WARNING", "forge.local.md", "components (embedded+language)",
                     f'embedded framework should have language: c or cpp, got "{language}"')


# ───────────────────────────── Output ──────────────────────────────────────


def render_human(
    v: Validator,
    project_root: Path,
    local_file: Path,
    config_file: Path | None,
    verbose: bool,
) -> str:
    lines: list[str] = [
        "Config Validation Report",
        "========================",
        "",
        f"Project:         {project_root}",
        f"forge.local.md:  {local_file}",
        f"forge-config.md: {config_file or '(not found — using defaults)'}",
        "",
    ]
    for r in v.results:
        if r["severity"] == "OK" and not verbose:
            continue
        lines.append(f"{r['severity']:<9} {r['file']:<17} {r['field']:<40} {r['message']}")

    counts = v.counts()
    lines.append("")
    lines.append(
        f"Summary: {counts['CRITICAL']} critical, {counts['ERROR']} errors, "
        f"{counts['WARNING']} warnings, {counts['OK']} ok"
    )
    if counts["CRITICAL"] or counts["ERROR"]:
        lines.append("Fix errors before running the pipeline.")
    elif counts["WARNING"]:
        lines.append("Warnings found. Pipeline will use defaults for unset values.")
    else:
        lines.append("Configuration is valid. Ready for /forge-run.")
    return "\n".join(lines) + "\n"


def render_json(
    v: Validator,
    files_checked: list[str],
    verbose: bool,
) -> str:
    visible = v.results if verbose else [r for r in v.results if r["severity"] != "OK"]
    counts = v.counts()
    report = {
        "validator_version": VALIDATOR_VERSION,
        "files_checked": files_checked,
        "results": visible,
        "summary": {
            "critical": counts["CRITICAL"],
            "error": counts["ERROR"],
            "warning": counts["WARNING"],
            "ok": counts["OK"],
        },
    }
    return json.dumps(report, indent=2) + "\n"


# ───────────────────────────── Entry point ─────────────────────────────────


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="config-validator", description=__doc__)
    ap.add_argument("--verbose", action="store_true", help="Show OK results too")
    ap.add_argument("--json", dest="as_json", action="store_true", help="JSON output")
    ap.add_argument("--check-commands", action="store_true",
                    help="Verify configured commands are executable")
    ap.add_argument("project_root", help="Path to project root containing .claude/")
    args = ap.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    claude_dir = project_root / ".claude"
    local_file = claude_dir / "forge.local.md"
    config_file = claude_dir / "forge-config.md"

    if not claude_dir.is_dir():
        print(f"ERROR: .claude/ directory not found in {project_root}", file=sys.stderr)
        return 3
    if not local_file.is_file():
        print(f"ERROR: forge.local.md not found at {local_file}", file=sys.stderr)
        print("Run /forge-init to generate configuration.", file=sys.stderr)
        return 3

    v = Validator()

    # Parse local config (required)
    local_yaml = extract_yaml(local_file)
    local_data: dict[str, Any] = {}
    if not local_yaml:
        v.add("CRITICAL", "forge.local.md", "_parse",
              "Could not extract YAML from forge.local.md")
    else:
        try:
            local_data = parse_yaml_subset(local_yaml)
        except Exception as exc:
            v.add("CRITICAL", "forge.local.md", "_parse", f"YAML parse error: {exc}")

    # Parse config (optional)
    has_config = config_file.is_file()
    config_data: dict[str, Any] = {}
    files_checked = ["forge.local.md"]
    if has_config:
        files_checked.append("forge-config.md")
        config_yaml = extract_yaml(config_file)
        if config_yaml:
            try:
                config_data = parse_yaml_subset(config_yaml)
            except Exception as exc:
                v.add("WARNING", "forge-config.md", "_parse", f"YAML parse error: {exc}")
        else:
            v.add("WARNING", "forge-config.md", "_parse",
                  "Could not extract YAML from forge-config.md")

    # Validate
    language, framework, _ = v.check_required_fields(local_data)
    commands = v.check_commands_present(local_data)
    if has_config:
        v.check_ranges(config_data)
        v.check_cross_field(config_data)
        v.check_unknown_fields(config_data)
    if args.check_commands:
        v.check_command_executability(project_root, commands)
    v.check_framework_compat(language, framework)

    # Render
    if args.as_json:
        sys.stdout.write(render_json(v, files_checked, args.verbose))
    else:
        sys.stdout.write(render_human(
            v, project_root, local_file,
            config_file if has_config else None, args.verbose,
        ))

    counts = v.counts()
    if counts["CRITICAL"] or counts["ERROR"]:
        return 1
    if counts["WARNING"]:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
