# shared/platform_adapters/__init__.py
"""Per-VCS adapters for posting comments. D5 fills in the bodies.

Each adapter exposes a callable matching `PlatformAdapter.post_comment`.
"""
from __future__ import annotations

from typing import Protocol, TypedDict


class PostResult(TypedDict):
    posted: bool
    response: dict | str
    error: str | None


class PlatformAdapter(Protocol):
    def post_comment(self, pr_url: str, body: str, auth: dict) -> PostResult: ...


__all__ = ["github", "gitlab", "bitbucket", "gitea", "PlatformAdapter", "PostResult"]
