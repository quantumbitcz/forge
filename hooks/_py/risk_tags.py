"""Canonical risk_tags enum for Phase 7 F36 voting gate.

Producer: agents/fg-200-planner.md emits task.risk_tags[].
Consumer: agents/fg-100-orchestrator.md voting gate reads task.risk_tags.
Mode overlays may extend; bugfix overlay adds "bugfix".
"""
from __future__ import annotations

BASE_RISK_TAGS: frozenset[str] = frozenset({
    "high", "data-mutation", "auth", "payment", "concurrency", "migration",
})

# Mode overlay extensions. Each overlay may extend with extra tags;
# planner emits + validator warns on tags outside (BASE | overlay).
OVERLAY_EXTENSIONS: dict[str, frozenset[str]] = {
    "bugfix": frozenset({"bugfix"}),
}


def allowed_tags(mode: str = "standard") -> frozenset[str]:
    return BASE_RISK_TAGS | OVERLAY_EXTENSIONS.get(mode, frozenset())
