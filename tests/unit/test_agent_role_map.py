"""Structural test: agent_role_map is frozen, complete, and unambiguous."""
from __future__ import annotations

import types

from hooks._py import agent_role_map


def test_map_is_read_only():
    assert isinstance(agent_role_map.AGENT_ROLE_MAP, types.MappingProxyType)


def test_every_reviewer_has_mapping():
    for fg in (
        "fg-410-code-reviewer",
        "fg-411-security-reviewer",
        "fg-412-architecture-reviewer",
        "fg-413-frontend-reviewer",
        "fg-414-license-reviewer",
        "fg-416-performance-reviewer",
        "fg-417-dependency-reviewer",
        "fg-418-docs-consistency-reviewer",
        "fg-419-infra-deploy-reviewer",
    ):
        assert fg in agent_role_map.AGENT_ROLE_MAP


def test_unknown_agent_returns_none():
    assert agent_role_map.role_for_agent("fg-999-nope") is None


def test_known_agent_returns_role_key():
    assert agent_role_map.role_for_agent("fg-411-security-reviewer") == "reviewer.security"
    assert agent_role_map.role_for_agent("fg-200-planner") == "planner"
    assert agent_role_map.role_for_agent("fg-300-implementer") == "implementer"


def test_mapping_has_no_duplicate_role_keys():
    roles = list(agent_role_map.AGENT_ROLE_MAP.values())
    assert len(roles) == len(set(roles))
