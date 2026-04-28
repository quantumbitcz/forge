# shared/platform_adapters/gitea.py
"""Gitea/Forgejo adapter — pure stdlib urllib.request against REST v1.

Wired up in D5 (mega-consolidation). Called by `agents/fg-710-post-run.md`
once per non-actionable verdict.

Contract: see `shared/platform_adapters/__init__.py` (`PlatformAdapter`).
- `pr_url` — full HTTPS URL to the PR (e.g.
  `https://gitea.example.com/owner/repo/pulls/12`).
- `body` — markdown comment body.
- `auth` — `{"method": "gitea-token" | "none", "token": "<api token>"}`.
  Falls back to env var `GITEA_TOKEN` (or `FORGEJO_TOKEN`) when not
  provided. Gitea's PR comments use the issue-comments endpoint by design.

Never raises for expected failure modes — returns `posted=False` with an
`error` string instead.
"""
from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request

_PR_URL_RE = re.compile(
    r"^https?://(?P<host>[^/]+)/(?P<owner>[^/]+)/(?P<repo>[^/]+)/pulls/(?P<num>\d+)"
)


def _parse_pr_url(pr_url: str) -> tuple[str, str, str, str]:
    m = _PR_URL_RE.match(pr_url.strip())
    if not m:
        raise ValueError(f"gitea adapter: cannot parse PR URL: {pr_url}")
    host = m.group("host")
    api_base = f"https://{host}/api/v1"
    return api_base, m.group("owner"), m.group("repo"), m.group("num")


def _post_via_urllib(api_base: str, owner: str, repo: str, num: str, body: str, token: str) -> dict:
    # Gitea/Forgejo PR comments use the issues endpoint (issue + PR share IDs).
    url = f"{api_base}/repos/{owner}/{repo}/issues/{num}/comments"
    payload = json.dumps({"body": body}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Authorization", f"token {token}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    """Post a comment on a Gitea/Forgejo PR. Returns a `PostResult` dict."""
    try:
        api_base, owner, repo, num = _parse_pr_url(pr_url)
    except ValueError as e:
        return {"posted": False, "response": "", "error": str(e)}

    auth = auth or {}
    token = auth.get("token") or os.environ.get("GITEA_TOKEN") or os.environ.get(
        "FORGEJO_TOKEN", ""
    )

    if not token:
        return {
            "posted": False,
            "response": "",
            "error": "missing GITEA_TOKEN / FORGEJO_TOKEN",
        }

    try:
        response = _post_via_urllib(api_base, owner, repo, num, body, token)
        return {"posted": True, "response": response, "error": None}
    except urllib.error.HTTPError as e:
        return {"posted": False, "response": "", "error": f"HTTP {e.code}: {e.reason}"}
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return {"posted": False, "response": "", "error": f"network: {e}"}
