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
import hashlib
import ipaddress
import logging
import socket
import ssl
import subprocess
import time
import urllib.error
import urllib.request
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


# Custom opener that ONLY registers HTTP/HTTPS handlers — file:// and ftp://
# fall through to the default opener's "unknown scheme" path and raise. Built
# once at import time; reused per http_get to avoid the global default opener
# (which DOES include file/ftp handlers).
_HTTP_ONLY_OPENER = urllib.request.build_opener(
    urllib.request.HTTPHandler(),
    urllib.request.HTTPSHandler(),
)


def _strip_ipv6_scope(host: str) -> str:
    """Strip the ``%scope`` suffix from an IPv6 hostname (urlparse leaves it on)."""
    return host.split("%", 1)[0] if "%" in host else host


class IntentProbe:
    def __init__(self, config: dict[str, Any], ac_id: str):
        iv = config.get("intent_verification", {})
        try:
            self.max_probes: int = int(iv.get("max_probes_per_ac", 20))
        except (TypeError, ValueError) as e:
            raise ValueError("max_probes_per_ac must be an integer") from e
        try:
            self.timeout: int = int(iv.get("probe_timeout_seconds", 30))
        except (TypeError, ValueError) as e:
            raise ValueError("probe_timeout_seconds must be an integer") from e
        if not (1 <= self.max_probes <= 1000):
            raise ValueError(
                f"max_probes_per_ac must be in [1, 1000]; got {self.max_probes}"
            )
        if not (1 <= self.timeout <= 300):
            raise ValueError(
                f"probe_timeout_seconds must be in [1, 300]; got {self.timeout}"
            )
        self.allow_runtime: bool = bool(iv.get("allow_runtime_probes", True))
        self.ac_id = ac_id
        self.count = 0

        # Parse forbidden patterns once: split into IP networks vs glob patterns.
        # Range patterns "A.B.*-A.C.*" expand into a CIDR-equivalent list.
        raw_forbidden: list[str] = iv.get("forbidden_probe_hosts", []) or []
        self._glob_patterns: list[str] = []
        self._networks: list[
            ipaddress.IPv4Network | ipaddress.IPv6Network
        ] = []
        for pat in raw_forbidden:
            self._ingest_pattern(pat)

    # ---- pattern parsing ---------------------------------------------------

    def _ingest_pattern(self, pat: str) -> None:
        """Classify a forbidden pattern as either an IP network or fnmatch glob.

        Logs and skips unparseable entries rather than failing __init__ (a
        single bad config line shouldn't kill the run).
        """
        try:
            # CIDR like "10.0.0.0/8" or "fc00::/7", or single literal IPs.
            if "/" in pat or self._looks_like_bare_ip(pat):
                self._networks.append(ipaddress.ip_network(pat, strict=False))
                return
            # Range pattern "172.16.*-172.31.*" -> expand to networks.
            if "-" in pat and "*" in pat:
                expanded = self._expand_range_pattern(pat)
                if expanded is None:
                    log.warning(
                        "forbidden_pattern_unparseable",
                        extra={"pattern": pat},
                    )
                    return
                self._networks.extend(expanded)
                return
            # Otherwise treat as glob (e.g. "*.prod.*", "*.amazonaws.com").
            self._glob_patterns.append(pat)
        except (ValueError, TypeError):
            log.warning(
                "forbidden_pattern_unparseable",
                extra={"pattern": pat},
            )

    @staticmethod
    def _looks_like_bare_ip(pat: str) -> bool:
        """True if pat parses as a literal IP address (no glob metacharacters)."""
        if any(c in pat for c in "*?[]"):
            return False
        try:
            ipaddress.ip_address(pat)
            return True
        except ValueError:
            return False

    @staticmethod
    def _expand_range_pattern(
        pat: str,
    ) -> list[ipaddress.IPv4Network] | None:
        """Expand patterns like ``A.B.*-A.C.*`` (e.g. ``172.16.*-172.31.*``)
        into a list of /16 networks covering second-octets ``B..C``. Returns
        ``None`` on parse failure so the caller can warn-and-skip.
        """
        try:
            left, right = pat.split("-", 1)
        except ValueError:
            return None
        left_parts = left.split(".")
        right_parts = right.split(".")
        # Expect exactly ``base.octet.*`` on each side (3 parts).
        if len(left_parts) != 3 or len(right_parts) != 3:
            return None
        if left_parts[0] != right_parts[0]:
            return None
        if left_parts[2] != "*" or right_parts[2] != "*":
            return None
        try:
            base = int(left_parts[0])
            lo = int(left_parts[1])
            hi = int(right_parts[1])
        except ValueError:
            return None
        if not (0 <= base <= 255 and 0 <= lo <= hi <= 255):
            return None
        nets: list[ipaddress.IPv4Network] = []
        for second in range(lo, hi + 1):
            try:
                nets.append(
                    ipaddress.ip_network(f"{base}.{second}.0.0/16", strict=False)
                )
            except ValueError:
                continue
        return nets

    # ---- host validation ---------------------------------------------------

    def _host_forbidden(self, host: str) -> str | None:
        """Return a description of the matching pattern if forbidden, else None."""
        host_clean = _strip_ipv6_scope(host)
        # Try IP-network match first (covers v4 and v6 literals + CIDR seeds).
        try:
            ip = ipaddress.ip_address(host_clean)
        except ValueError:
            ip = None
        if ip is not None:
            for net in self._networks:
                if ip.version == net.version and ip in net:
                    return f"ip-network:{net}"
        # Fall through to glob patterns (DNS hostnames, wildcards).
        for pat in self._glob_patterns:
            if fnmatch.fnmatchcase(host_clean.lower(), pat.lower()):
                return f"glob:{pat}"
        return None

    def _check_host(self, host: str) -> None:
        matched = self._host_forbidden(host)
        if matched is not None:
            log.warning(
                "probe_denied",
                extra={"ac": self.ac_id, "host": host, "pattern": matched},
            )
            raise ProbeDeniedError(
                f"ac={self.ac_id} host={host!r} matches forbidden pattern {matched!r}"
            )
        # DNS-rebind defense: literal-name passes the static check but might
        # resolve to a forbidden network.
        if self.resolve_host_for_denylist(host):
            log.warning(
                "probe_denied_dns",
                extra={"ac": self.ac_id, "host": host},
            )
            raise ProbeDeniedError(
                f"ac={self.ac_id} host {host!r} resolves to forbidden network"
            )

    def _bump(self) -> None:
        self.count += 1
        if self.count > self.max_probes:
            log.warning(
                "probe_budget_exceeded",
                extra={
                    "ac": self.ac_id,
                    "max_probes": self.max_probes,
                    "count": self.count,
                },
            )
            raise ProbeBudgetExceededError(
                f"ac={self.ac_id} exceeded max_probes_per_ac={self.max_probes}"
            )

    # ---- probes ------------------------------------------------------------

    def http_get(self, url: str) -> ProbeResult:
        if not self.allow_runtime:
            return ProbeResult(False, None, None, 0, url, error="runtime_probes_disabled")
        # Validate URL FIRST — never spend budget on a malformed/forbidden URL.
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            raise ProbeDeniedError(
                f"ac={self.ac_id} scheme {parsed.scheme!r} not allowed"
            )
        if parsed.username or parsed.password:
            raise ProbeDeniedError(
                f"ac={self.ac_id} userinfo not allowed in probe URL"
            )
        host = (parsed.hostname or "").lower()
        if not host:
            raise ProbeDeniedError(f"ac={self.ac_id} empty hostname")
        host = _strip_ipv6_scope(host)
        self._check_host(host)
        # Only after host validation passes do we charge the probe budget.
        self._bump()
        t0 = time.monotonic()
        try:
            with _HTTP_ONLY_OPENER.open(url, timeout=self.timeout) as r:
                body = r.read()
                return ProbeResult(
                    True, r.status,
                    "sha256:" + hashlib.sha256(body).hexdigest(),
                    int((time.monotonic() - t0) * 1000),
                    f"GET {url}",
                )
        except (
            urllib.error.URLError,
            socket.timeout,
            socket.gaierror,
            ssl.SSLError,
            ConnectionError,
        ) as e:
            return ProbeResult(False, None, None,
                               int((time.monotonic() - t0) * 1000),
                               f"GET {url}", error=str(e))

    def shell_probe(self, argv: list[str], host_hint: str | None = None) -> ProbeResult:
        """Run a shell probe with shell=False. host_hint used for deny-check
        when the command doesn't expose a URL (e.g. psql -h localhost)."""
        if not self.allow_runtime:
            return ProbeResult(False, None, None, 0, " ".join(argv),
                               error="runtime_probes_disabled")
        # Validate host_hint FIRST so a forbidden hint doesn't burn budget.
        if host_hint:
            self._check_host(host_hint.lower())
        self._bump()
        t0 = time.monotonic()
        try:
            cp = subprocess.run(argv, capture_output=True, timeout=self.timeout,
                                check=False, shell=False)
            body_sha = "sha256:" + hashlib.sha256(cp.stdout).hexdigest()
            return ProbeResult(
                cp.returncode == 0, cp.returncode, body_sha,
                int((time.monotonic() - t0) * 1000), " ".join(argv),
                error=(cp.stderr.decode(errors="replace")[:200] if cp.returncode else None),
            )
        except subprocess.TimeoutExpired:
            return ProbeResult(False, None, None, self.timeout * 1000,
                               " ".join(argv), error="timeout")
        except (OSError, subprocess.SubprocessError) as e:
            return ProbeResult(False, None, None,
                               int((time.monotonic() - t0) * 1000),
                               " ".join(argv), error=str(e))

    # ---- convenience -------------------------------------------------------

    def resolve_host_for_denylist(self, host: str) -> bool:
        """Return True if DNS resolves to a network that matches any
        forbidden seed. Defensive against DNS-rebind tricks where a
        DNS name is used to evade the literal-host denylist."""
        try:
            addrs = {ai[4][0] for ai in socket.getaddrinfo(host, None)}
        except socket.gaierror:
            return False
        for ip in addrs:
            ip_clean = _strip_ipv6_scope(ip)
            try:
                parsed_ip = ipaddress.ip_address(ip_clean)
            except ValueError:
                continue
            for net in self._networks:
                if parsed_ip.version == net.version and parsed_ip in net:
                    return True
        return False
