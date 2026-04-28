# shared/platform_adapters/bitbucket.py
"""Bitbucket Cloud adapter — pure stdlib urllib.request against REST v2.0."""
from __future__ import annotations


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    raise NotImplementedError("D5 wires this up — see fg-710-post-run rewrite")
