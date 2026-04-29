"""Contract test: probe sandbox enforces forbidden_probe_hosts and budget."""
from __future__ import annotations

import socket

import pytest

from hooks._py.intent_probe import (
    IntentProbe,
    ProbeBudgetExceededError,
    ProbeDeniedError,
)

CFG = {
    "intent_verification": {
        "forbidden_probe_hosts": [
            # Glob-style hostname denials
            "*.prod.*", "*.production.*", "*.live.*",
            "*.amazonaws.com",
            # IPv4 ranges (CIDR-equivalent and explicit)
            "10.0.0.0/8",
            "172.16.*-172.31.*",
            "192.168.0.0/16",
            "169.254.0.0/16",  # link-local / cloud metadata
            # IPv6 ranges (link-local, unique-local, loopback)
            "::1/128",
            "fc00::/7",
            "fd00::/8",
            "fe80::/10",
        ],
        "max_probes_per_ac": 20,
        "probe_timeout_seconds": 5,
        "allow_runtime_probes": True,
    }
}


def test_prod_host_denied():
    p = IntentProbe(CFG, ac_id="AC-001")
    with pytest.raises(ProbeDeniedError):
        p.http_get("https://api.prod.example.com/health")


def test_aws_host_denied():
    p = IntentProbe(CFG, ac_id="AC-002")
    with pytest.raises(ProbeDeniedError):
        p.http_get("https://s3.us-east-1.amazonaws.com/bucket/key")


def test_private_ip_denied():
    p = IntentProbe(CFG, ac_id="AC-003")
    with pytest.raises(ProbeDeniedError):
        p.http_get("http://10.0.0.5/probe")


def test_ip_range_172_16_denied():
    p = IntentProbe(CFG, ac_id="AC-004")
    assert p._host_forbidden("172.20.1.1") is not None
    assert p._host_forbidden("172.15.0.1") is None  # outside range
    assert p._host_forbidden("172.32.0.1") is None


def test_localhost_allowed():
    p = IntentProbe(CFG, ac_id="AC-005")
    assert p._host_forbidden("localhost") is None
    assert p._host_forbidden("127.0.0.1") is None


def test_metadata_link_local_denied():
    """169.254.169.254 (cloud instance metadata) must be blocked."""
    p = IntentProbe(CFG, ac_id="AC-METADATA")
    assert p._host_forbidden("169.254.169.254") is not None
    with pytest.raises(ProbeDeniedError):
        p.http_get("http://169.254.169.254/latest/meta-data/")


def test_ipv6_loopback_denied():
    p = IntentProbe(CFG, ac_id="AC-IPV6-LB")
    assert p._host_forbidden("::1") is not None


def test_ipv6_link_local_denied():
    p = IntentProbe(CFG, ac_id="AC-IPV6-LL")
    assert p._host_forbidden("fe80::1") is not None
    assert p._host_forbidden("fe80::1%eth0") is not None  # scope is stripped


def test_ipv6_unique_local_denied():
    p = IntentProbe(CFG, ac_id="AC-IPV6-UL")
    assert p._host_forbidden("fc00::1") is not None
    assert p._host_forbidden("fd12:3456:789a::1") is not None


def test_budget_exceeded():
    tight = {
        **CFG,
        "intent_verification": {**CFG["intent_verification"], "max_probes_per_ac": 1},
    }
    p = IntentProbe(tight, ac_id="AC-006")
    p._bump()  # count=1
    with pytest.raises(ProbeBudgetExceededError):
        p._bump()


def test_scheme_allowlist():
    p = IntentProbe(CFG, ac_id="AC-SCHEME")
    for url in (
        "file:///etc/passwd",
        "ftp://example.com/file",
        "javascript:alert(1)",
        "data:text/plain,hi",
        "gopher://example.com/",
    ):
        with pytest.raises(ProbeDeniedError):
            p.http_get(url)


def test_userinfo_rejected():
    p = IntentProbe(CFG, ac_id="AC-USERINFO")
    with pytest.raises(ProbeDeniedError):
        p.http_get("http://attacker:secret@example.com/")


def test_empty_hostname_rejected():
    p = IntentProbe(CFG, ac_id="AC-EMPTY")
    with pytest.raises(ProbeDeniedError):
        p.http_get("http:///nopath")


def test_dns_rebind_defense(monkeypatch):
    """A literal name passes the static check but resolves to a forbidden
    network — DNS-rebind defense must catch it."""

    def _fake_getaddrinfo(host, port, *args, **kwargs):
        # AF_INET, SOCK_STREAM, proto, canonname, sockaddr
        return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("127.0.0.1", 0))]

    p = IntentProbe(
        {
            "intent_verification": {
                "forbidden_probe_hosts": ["127.0.0.0/8"],
                "max_probes_per_ac": 5,
                "probe_timeout_seconds": 2,
                "allow_runtime_probes": True,
            }
        },
        ac_id="AC-REBIND",
    )
    monkeypatch.setattr(socket, "getaddrinfo", _fake_getaddrinfo)
    with pytest.raises(ProbeDeniedError):
        p._check_host("attacker-controlled.example.com")


def test_forbidden_url_does_not_burn_budget():
    """Reordering: validate scheme/host BEFORE _bump so a forbidden URL
    can be rejected without consuming a budget slot."""
    p = IntentProbe(
        {
            "intent_verification": {
                "forbidden_probe_hosts": ["*.prod.*"],
                "max_probes_per_ac": 1,
                "probe_timeout_seconds": 2,
                "allow_runtime_probes": True,
            }
        },
        ac_id="AC-NODOS",
    )
    with pytest.raises(ProbeDeniedError):
        p.http_get("https://api.prod.example.com/")
    assert p.count == 0  # budget intact


def test_negative_max_probes_rejected():
    with pytest.raises(ValueError):
        IntentProbe(
            {
                "intent_verification": {
                    "forbidden_probe_hosts": [],
                    "max_probes_per_ac": -1,
                    "probe_timeout_seconds": 5,
                }
            },
            ac_id="AC-CFG",
        )


def test_zero_timeout_rejected():
    with pytest.raises(ValueError):
        IntentProbe(
            {
                "intent_verification": {
                    "forbidden_probe_hosts": [],
                    "max_probes_per_ac": 5,
                    "probe_timeout_seconds": 0,
                }
            },
            ac_id="AC-CFG2",
        )


def test_unparseable_pattern_logged_not_raised(caplog):
    """A malformed forbidden pattern should warn-and-skip rather than break
    initialization."""
    import logging
    caplog.set_level(logging.WARNING)
    p = IntentProbe(
        {
            "intent_verification": {
                "forbidden_probe_hosts": ["not-a-cidr/wat", "*.prod.*"],
                "max_probes_per_ac": 5,
                "probe_timeout_seconds": 5,
            }
        },
        ac_id="AC-PATTERN",
    )
    # The valid glob still works.
    assert p._host_forbidden("api.prod.example.com") is not None
    assert any("forbidden_pattern_unparseable" in r.message for r in caplog.records)
