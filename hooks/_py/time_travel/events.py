"""RewoundEvent schema for Phase 14 time-travel checkpoints.

Appended to .forge/runs/<run_id>/events.jsonl after every successful rewind.
Schema is versioned (schema_version) so future migrations are explicit.
"""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import List, Literal

SCHEMA_VERSION = 1
EVENT_TYPE = "REWOUND"


@dataclass(frozen=True)
class RewoundEvent:
    timestamp: str                      # ISO 8601 UTC, e.g. 2026-04-19T12:00:00Z
    run_id: str                         # matches .forge/runs/<run_id>/
    from_sha: str                       # 64-hex previous HEAD checkpoint sha
    to_sha: str                         # 64-hex target checkpoint sha
    to_human_id: str                    # e.g. "PLAN.-.003"
    triggered_by: Literal["user", "auto"]
    forced: bool                        # True iff --force overrode require_clean_worktree
    dirty_paths: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["type"] = EVENT_TYPE
        d["schema_version"] = SCHEMA_VERSION
        return d

    def to_canonical_json(self) -> str:
        """Sorted-keys, no-whitespace JSON — stable across platforms for hashing / golden-file comparison."""
        return json.dumps(self.to_dict(), sort_keys=True, separators=(",", ":"))
