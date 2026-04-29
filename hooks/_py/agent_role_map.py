"""Agent-name → learning-role-key mapping. Single source of truth.

Phase 4 spec §3 authoritative table. Frozen at import — no runtime mutation.
Anywhere else in the codebase that needs to translate an ``fg-*`` identifier
to a ``applies_to`` role key MUST import this module.
"""
from __future__ import annotations

from types import MappingProxyType

_RAW = {
    "fg-200-planner": "planner",
    "fg-300-implementer": "implementer",
    "fg-400-quality-gate": "quality_gate",
    "fg-410-code-reviewer": "reviewer.code",
    "fg-411-security-reviewer": "reviewer.security",
    "fg-412-architecture-reviewer": "reviewer.architecture",
    "fg-413-frontend-reviewer": "reviewer.frontend",
    "fg-414-license-reviewer": "reviewer.license",
    "fg-416-performance-reviewer": "reviewer.performance",
    "fg-417-dependency-reviewer": "reviewer.dependency",
    "fg-418-docs-consistency-reviewer": "reviewer.docs",
    "fg-419-infra-deploy-reviewer": "reviewer.infra",
}

AGENT_ROLE_MAP: MappingProxyType[str, str] = MappingProxyType(dict(_RAW))


def role_for_agent(agent: str) -> str | None:
    """Return the role key for ``agent`` or ``None`` if unmapped."""
    return AGENT_ROLE_MAP.get(agent)
