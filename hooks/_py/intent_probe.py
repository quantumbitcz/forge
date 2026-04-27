"""Intent-verification probe sandbox.

Gatekeeper for runtime probes issued on fg-540's behalf. Enforces
forbidden-host allow/deny, probe budget, and timeout. Cross-platform
(pathlib.Path, subprocess with shell=False, Python 3.10+).

Usage (called by orchestrator, never by agent directly):
    from hooks._py.intent_probe import IntentProbe
    probe = IntentProbe(config, ac_id="AC-003")
    result = probe.http_get("http://localhost:8080/users")
    # or probe.psql("SELECT count(*) FROM users"), etc.
"""
from __future__ import annotations

import dataclasses
import fnmatch
import logging
import re
import socket
import subprocess
import time
from typing import Any
from urllib.parse import urlparse

log = logging.getLogger(__name__)


class ProbeDeniedError(Exception):
    """Raised when a probe targets a forbidden host. CRITICAL — pipeline aborts."""


class ProbeBudgetExceededError(Exception):
    """Raised when per-AC probe count exceeds max_probes_per_ac."""


@dataclasses.dataclass
class ProbeResult:
    ok: bool
    status: int | None
    body_sha: str | None
    duration_ms: int
    command: str
    error: str | None = None


class IntentProbe:
    def __init__(self, config: dict[str, Any], ac_id: str):
        iv = config.get("intent_verification", {})
        self.forbidden: list[str] = iv.get("forbidden_probe_hosts", [])
        self.max_probes: int = int(iv.get("max_probes_per_ac", 20))
        self.timeout: int = int(iv.get("probe_timeout_seconds", 30))
        self.allow_runtime: bool = bool(iv.get("allow_runtime_probes", True))
        self.ac_id = ac_id
        self.count = 0

    # ---- host validation ---------------------------------------------------

    def _host_forbidden(self, host: str) -> str | None:
        """Return the matching pattern if host is forbidden, else None."""
        # IP-range patterns like "172.16.*-172.31.*" handled via first-octet match
        for pat in self.forbidden:
            if "-" in pat and "*" in pat:
                # Range pattern: expand the second octet range
                if self._match_ip_range(host, pat):
                    return pat
            elif fnmatch.fnmatchcase(host.lower(), pat.lower()):
                return pat
        return None

    @staticmethod
    def _match_ip_range(host: str, pattern: str) -> bool:
        # pattern example: "172.16.*-172.31.*"
        m = re.match(r"(\d+)\.(\d+)\.\*-\1\.(\d+)\.\*", pattern)
        if not m:
            return False
        base_a, lo, hi = m.group(1), int(m.group(2)), int(m.group(3))
        parts = host.split(".")
        if len(parts) < 2 or parts[0] != base_a:
            return False
        try:
            return lo <= int(parts[1]) <= hi
        except ValueError:
            return False

    def _check_host(self, host: str) -> None:
        matched = self._host_forbidden(host)
        if matched is not None:
            raise ProbeDeniedError(
                f"ac={self.ac_id} host={host!r} matches forbidden pattern {matched!r}"
            )

    def _bump(self) -> None:
        self.count += 1
        if self.count > self.max_probes:
            raise ProbeBudgetExceededError(
                f"ac={self.ac_id} exceeded max_probes_per_ac={self.max_probes}"
            )

    # ---- probes ------------------------------------------------------------

    def http_get(self, url: str) -> ProbeResult:
        if not self.allow_runtime:
            return ProbeResult(False, None, None, 0, url, error="runtime_probes_disabled")
        self._bump()
        host = (urlparse(url).hostname or "").lower()
        self._check_host(host)
        # Use urllib (stdlib) — no requests dep, cross-platform, deterministic.
        import hashlib
        import urllib.request
        t0 = time.monotonic()
        try:
            with urllib.request.urlopen(url, timeout=self.timeout) as r:
                body = r.read()
                return ProbeResult(
                    True, r.status,
                    "sha256:" + hashlib.sha256(body).hexdigest(),
                    int((time.monotonic() - t0) * 1000),
                    f"GET {url}",
                )
        except Exception as e:  # noqa: BLE001 — probe must report all failures uniformly
            return ProbeResult(False, None, None,
                               int((time.monotonic() - t0) * 1000),
                               f"GET {url}", error=str(e))

    def shell_probe(self, argv: list[str], host_hint: str | None = None) -> ProbeResult:
        """Run a shell probe with shell=False. host_hint used for deny-check
        when the command doesn't expose a URL (e.g. psql -h localhost)."""
        if not self.allow_runtime:
            return ProbeResult(False, None, None, 0, " ".join(argv),
                               error="runtime_probes_disabled")
        self._bump()
        if host_hint:
            self._check_host(host_hint.lower())
        t0 = time.monotonic()
        try:
            cp = subprocess.run(argv, capture_output=True, timeout=self.timeout,
                                check=False, shell=False)
            import hashlib
            body_sha = "sha256:" + hashlib.sha256(cp.stdout).hexdigest()
            return ProbeResult(
                cp.returncode == 0, cp.returncode, body_sha,
                int((time.monotonic() - t0) * 1000), " ".join(argv),
                error=(cp.stderr.decode(errors="replace")[:200] if cp.returncode else None),
            )
        except subprocess.TimeoutExpired:
            return ProbeResult(False, None, None, self.timeout * 1000,
                               " ".join(argv), error="timeout")
        except Exception as e:  # noqa: BLE001 — probe must report all failures uniformly
            return ProbeResult(False, None, None,
                               int((time.monotonic() - t0) * 1000),
                               " ".join(argv), error=str(e))

    # ---- convenience -------------------------------------------------------

    def resolve_host_for_denylist(self, host: str) -> bool:
        """Return True if DNS resolves to a private network that matches
        forbidden_probe_hosts. Defensive against DNS-rebind tricks."""
        try:
            addrs = {ai[4][0] for ai in socket.getaddrinfo(host, None)}
        except socket.gaierror:
            return False
        for ip in addrs:
            if self._host_forbidden(ip):
                return True
        return False
