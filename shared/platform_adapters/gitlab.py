# shared/platform_adapters/gitlab.py
"""GitLab adapter — `glab api` CLI when present, else stdlib urllib REST.

Wired up in D5 (mega-consolidation). Called by `agents/fg-710-post-run.md`
once per non-actionable verdict.

Contract: see `shared/platform_adapters/__init__.py` (`PlatformAdapter`).
- `pr_url` — full HTTPS URL to the MR (e.g.
  `https://gitlab.com/group/proj/-/merge_requests/42`).
- `body` — markdown note body.
- `auth` — `{"method": "glab-cli" | "none", "token": "<optional>"}`.
  Resolves token from `GITLAB_TOKEN` env when CLI unavailable.

Never raises for expected failure modes — returns `posted=False` with an
`error` string instead.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request

_MR_URL_RE = re.compile(
    r"^https?://(?P<host>[^/]+)/(?P<path>.+?)/-/merge_requests/(?P<iid>\d+)"
)


def _parse_mr_url(mr_url: str) -> tuple[str, str, str, str]:
    m = _MR_URL_RE.match(mr_url.strip())
    if not m:
        raise ValueError(f"gitlab adapter: cannot parse MR URL: {mr_url}")
    host = m.group("host")
    api_base = f"https://{host}/api/v4"
    project_path = m.group("path")  # e.g. "group/subgroup/proj"
    return api_base, host, project_path, m.group("iid")


def _post_via_glab_cli(host: str, project_path: str, iid: str, body: str) -> dict:
    cmd = [
        "glab",
        "api",
        "--method",
        "POST",
        "--hostname",
        host,
        f"projects/{urllib.parse.quote(project_path, safe='')}/merge_requests/{iid}/notes",
        "-f",
        f"body={body}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if proc.returncode != 0:
        raise RuntimeError(f"glab api failed: {proc.stderr.strip() or proc.stdout.strip()}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"raw": proc.stdout}


def _post_via_urllib(api_base: str, project_path: str, iid: str, body: str, token: str) -> dict:
    encoded = urllib.parse.quote(project_path, safe="")
    url = f"{api_base}/projects/{encoded}/merge_requests/{iid}/notes"
    payload = json.dumps({"body": body}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("PRIVATE-TOKEN", token)
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    """Post a note on a GitLab MR. Returns a `PostResult` dict."""
    try:
        api_base, host, project_path, iid = _parse_mr_url(pr_url)
    except ValueError as e:
        return {"posted": False, "response": "", "error": str(e)}

    method = (auth or {}).get("method", "none")
    token = (auth or {}).get("token") or os.environ.get("GITLAB_TOKEN", "")

    if method in ("glab-cli", "none") and shutil.which("glab"):
        try:
            response = _post_via_glab_cli(host, project_path, iid, body)
            return {"posted": True, "response": response, "error": None}
        except (subprocess.TimeoutExpired, RuntimeError, OSError) as e:
            if not token:
                return {"posted": False, "response": "", "error": f"glab-cli failed: {e}"}

    if not token:
        return {
            "posted": False,
            "response": "",
            "error": "no GITLAB_TOKEN and glab CLI unavailable/failed",
        }

    try:
        response = _post_via_urllib(api_base, project_path, iid, body, token)
        return {"posted": True, "response": response, "error": None}
    except urllib.error.HTTPError as e:
        return {"posted": False, "response": "", "error": f"HTTP {e.code}: {e.reason}"}
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return {"posted": False, "response": "", "error": f"network: {e}"}
