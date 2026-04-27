"""Contract test: probe sandbox enforces forbidden_probe_hosts and budget."""
from __future__ import annotations

import pytest

from hooks._py.intent_probe import (
    IntentProbe,
    ProbeBudgetExceededError,
    ProbeDeniedError,
)

CFG = {
    "intent_verification": {
        "forbidden_probe_hosts": [
            "*.prod.*", "*.production.*", "*.live.*",
            "*.amazonaws.com", "10.*", "172.16.*-172.31.*", "192.168.*",
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
    assert p._host_forbidden("172.20.1.1") == "172.16.*-172.31.*"
    assert p._host_forbidden("172.15.0.1") is None  # outside range
    assert p._host_forbidden("172.32.0.1") is None


def test_localhost_allowed():
    p = IntentProbe(CFG, ac_id="AC-005")
    assert p._host_forbidden("localhost") is None
    assert p._host_forbidden("127.0.0.1") is None


def test_budget_exceeded():
    tight = {
        **CFG,
        "intent_verification": {**CFG["intent_verification"], "max_probes_per_ac": 1},
    }
    p = IntentProbe(tight, ac_id="AC-006")
    p._bump()  # count=1
    with pytest.raises(ProbeBudgetExceededError):
        p._bump()
