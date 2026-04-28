# shared/platform_adapters/gitlab.py
"""GitLab adapter — `glab api` CLI when present, else stdlib urllib REST."""
from __future__ import annotations


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    raise NotImplementedError("D5 wires this up — see fg-710-post-run rewrite")
