# shared/platform_adapters/__init__.py
"""Per-VCS adapters for posting comments. D5 fills in the bodies.

Each adapter exposes:
    post_comment(pr_url: str, body: str, auth: dict) -> dict

Returning {posted: bool, response: dict | str, error: str | None}.
"""

__all__ = ["github", "gitlab", "bitbucket", "gitea"]
