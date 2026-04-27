"""Pure selector for learnings injection. Phase 4.

Stdlib-only. No I/O; callers supply ``candidates`` via ``learnings_io``.
Deterministic ranking: ``score = confidence_now * domain_match *
recency_bonus * cross_project_penalty``. Tie-breaker is ``id`` ascending.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from hooks._py.agent_role_map import role_for_agent
from hooks._py.memory_decay import SPARSE_THRESHOLD


@dataclass(frozen=True)
class LearningItem:
    id: str
    source_path: str
    body: str
    base_confidence: float
    confidence_now: float
    half_life_days: int
    applied_count: int
    last_applied: str | None
    applies_to: tuple[str, ...]
    domain_tags: tuple[str, ...]
    archived: bool


def _parse_iso(s: str) -> datetime:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s).astimezone(timezone.utc)


def _recency_bonus(last_applied: str | None, now: datetime) -> float:
    if last_applied is None:
        return 0.7
    days = (now - _parse_iso(last_applied)).days
    match days:
        case d if d < 30:
            return 1.0
        case d if d < 90:
            return 0.85
        case _:
            return 0.7


def _domain_match_score(
    item_tags: tuple[str, ...], task_tags: list[str]
) -> float:
    if not task_tags:
        return 0.5  # caller had no domain signal — don't totally suppress
    if not item_tags:
        return 0.5
    overlap = len(set(item_tags) & set(task_tags))
    return overlap / max(1, len(item_tags))


def _cross_project_penalty(
    source_path: str, local_density: int, sparse_threshold: int
) -> float:
    if "forge-learnings" in source_path and local_density > sparse_threshold:
        return 0.85
    return 1.0


def _role_matches(agent: str, applies_to: tuple[str, ...]) -> bool:
    role = role_for_agent(agent)
    if role is None:
        return False
    return role in applies_to


def select_for_dispatch(
    agent: str,
    stage: str,
    domain_tags: list[str],
    component: str | None,
    candidates: list[LearningItem],
    now: datetime,
    max_items: int = 6,
    min_confidence: float = 0.4,
    sparse_threshold: int = SPARSE_THRESHOLD,
) -> list[LearningItem]:
    """Return up to ``max_items`` relevant learnings for this dispatch."""
    local_density = sum(
        1 for c in candidates if "forge-learnings" not in c.source_path
    )
    filtered = [
        c for c in candidates
        if not c.archived
        and c.confidence_now >= min_confidence
        and _role_matches(agent, c.applies_to)
    ]

    def score(item: LearningItem) -> tuple[float, str]:
        s = (
            item.confidence_now
            * _domain_match_score(item.domain_tags, domain_tags)
            * _recency_bonus(item.last_applied, now)
            * _cross_project_penalty(
                item.source_path, local_density, sparse_threshold
            )
        )
        return (-s, item.id)  # negative for descending primary, id ascending tiebreak

    filtered.sort(key=score)
    return filtered[:max_items]
