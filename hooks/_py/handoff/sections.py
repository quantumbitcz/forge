"""Pure body section renderers. Each function takes SectionInputs + variant and returns markdown."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

Variant = Literal["light", "full"]

SEVERITY_ORDER = {"CRITICAL": 0, "WARNING": 1, "INFO": 2}


@dataclass
class SectionInputs:
    requirement: str = ""
    completed_acs: list[dict[str, Any]] = field(default_factory=list)
    implemented_files: list[str] = field(default_factory=list)
    test_status: dict[str, int] = field(default_factory=dict)
    active_findings: list[dict[str, Any]] = field(default_factory=list)
    acceptance_criteria: list[dict[str, Any]] = field(default_factory=list)
    decisions: list[dict[str, Any]] = field(default_factory=list)
    preempt_items: list[dict[str, Any]] = field(default_factory=list)
    user_dont_statements: list[str] = field(default_factory=list)
    next_action_description: str = ""
    convergence_trajectory: list[dict[str, Any]] = field(default_factory=list)
    critical_files: list[str] = field(default_factory=list)
    open_questions: list[str] = field(default_factory=list)


def _header(title: str) -> str:
    return f"## {title}\n\n"


def render_goal(inp: SectionInputs, variant: Variant) -> str:
    return _header("Goal") + (inp.requirement.strip() or "_(no requirement recorded)_") + "\n"


def render_progress(inp: SectionInputs, variant: Variant) -> str:
    out = [_header("Progress")]
    if variant == "light":
        ac_count = len(inp.completed_acs)
        file_count = len(inp.implemented_files)
        tests = inp.test_status
        out.append(
            f"Completed {ac_count} acceptance criteria across {file_count} files. "
            f"Tests: {tests.get('passed', 0)} passed, {tests.get('failed', 0)} failed, "
            f"{tests.get('skipped', 0)} skipped.\n"
        )
    else:
        if inp.completed_acs:
            out.append("**Acceptance criteria completed:**\n")
            for ac in inp.completed_acs:
                out.append(f"- `{ac.get('id', '?')}` — {ac.get('text', '')}\n")
        if inp.implemented_files:
            out.append("\n**Files implemented:**\n")
            for f in inp.implemented_files:
                out.append(f"- `{f}`\n")
        if inp.test_status:
            out.append(f"\n**Test status:** {inp.test_status}\n")
    return "".join(out)


def render_active_findings(inp: SectionInputs, variant: Variant) -> str:
    findings = sorted(
        inp.active_findings,
        key=lambda f: (SEVERITY_ORDER.get(str(f.get("severity")), 3), f.get("file", ""), f.get("line", 0)),
    )
    if variant == "light":
        findings = findings[:5]
    out = [_header("Active Findings")]
    if not findings:
        out.append("_(none)_\n")
        return "".join(out)
    for f in findings:
        out.append(
            f"- **{f.get('severity', '?')}** `{f.get('category', '?')}` "
            f"{f.get('file', '?')}:{f.get('line', '?')} — {f.get('message', '')}\n"
        )
    return "".join(out)


def render_acceptance_criteria(inp: SectionInputs, variant: Variant) -> str:
    if variant == "light":
        return ""
    out = [_header("Acceptance Criteria Status")]
    if not inp.acceptance_criteria:
        out.append("_(no ACs recorded)_\n")
        return "".join(out)
    out.append("| ID | Status | Evidence |\n|---|---|---|\n")
    for ac in inp.acceptance_criteria:
        out.append(f"| {ac.get('id', '?')} | {ac.get('status', '?')} | {ac.get('evidence') or '_(none)_'} |\n")
    return "".join(out)


def render_key_decisions(inp: SectionInputs, variant: Variant) -> str:
    if variant == "light":
        return ""
    decisions = inp.decisions[-20:]
    out = [_header("Key Decisions")]
    if not decisions:
        out.append("_(none recorded)_\n")
        return "".join(out)
    for d in decisions:
        out.append(f"- **{d.get('ts', '?')}** — {d.get('decision', '')}  \n  _Rationale:_ {d.get('rationale', '')}\n")
    return "".join(out)


def render_do_not_touch(inp: SectionInputs, variant: Variant) -> str:
    out = [_header("Do Not Touch")]
    items = 0
    for p in inp.preempt_items:
        out.append(f"- {p.get('text', '')}  _(PREEMPT, {p.get('confidence', '?')})_\n")
        items += 1
    for s in inp.user_dont_statements:
        out.append(f"- {s}  _(user directive)_\n")
        items += 1
    if items == 0:
        out.append("_(none)_\n")
    return "".join(out)


def render_next_action(inp: SectionInputs, variant: Variant) -> str:
    return _header("Next Action") + (inp.next_action_description.strip() or "_(state machine has no pending action)_") + "\n"


def render_convergence_trajectory(inp: SectionInputs, variant: Variant) -> str:
    if variant == "light":
        return ""
    out = [_header("Convergence Trajectory")]
    if not inp.convergence_trajectory:
        out.append("_(no iterations recorded)_\n")
        return "".join(out)
    for it in inp.convergence_trajectory:
        out.append(f"- iter {it.get('iteration')}: score {it.get('score')}, findings {it.get('findings')}\n")
    return "".join(out)


def render_critical_files(inp: SectionInputs, variant: Variant) -> str:
    files = inp.critical_files if variant == "full" else inp.critical_files[:10]
    out = [_header("Critical Files")]
    if not files:
        out.append("_(none)_\n")
        return "".join(out)
    for f in files:
        out.append(f"- `{f}`\n")
    return "".join(out)


def render_open_questions(inp: SectionInputs, variant: Variant) -> str:
    out = [_header("Open Questions / Blockers")]
    if not inp.open_questions:
        out.append("_(none)_\n")
        return "".join(out)
    for q in inp.open_questions:
        out.append(f"- {q}\n")
    return "".join(out)


def render_user_directive(inp: SectionInputs, variant: Variant) -> str:
    return _header("User Directive") + "_(empty — fill in before paste)_\n"
