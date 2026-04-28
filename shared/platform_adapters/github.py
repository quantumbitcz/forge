# shared/platform_adapters/github.py
"""GitHub adapter — uses the GitHub MCP or `gh api` fallback.

D5 fills this in. The detect path constructs the adapter info; runtime
posting lives in fg-710-post-run.
"""
from __future__ import annotations


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    raise NotImplementedError("D5 wires this up — see fg-710-post-run rewrite")
