"""PII scrub patterns: paths, hostnames, IPs, fingerprints + SEC inheritance."""

from __future__ import annotations

import pytest

from tests.evals.benchmark.pii_scrub import scan, scrub


@pytest.mark.parametrize(
    "dirty,clean",
    [
        ("/Users/denis/secret/file.py", "<redacted-home>/secret/file.py"),
        ("/home/denis/repo", "<redacted-home>/repo"),
        (r"C:\Users\Denis\Desktop", r"<redacted-home>\Desktop"),
        ("ssh api-gateway.internal", "ssh <internal-host>"),
        ("reach db.prod.example", "reach <internal-host>.example"),
        ("10.0.4.7 is the lb", "<private-ip> is the lb"),
        ("172.16.5.9", "<private-ip>"),
        ("192.168.1.2", "<private-ip>"),
        ("SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGh", "<ssh-fp>"),
    ],
)
def test_auto_scrub(dirty: str, clean: str) -> None:
    assert scrub(dirty) == clean


def test_preserves_public_ip() -> None:
    assert scrub("reach 8.8.8.8 ok") == "reach 8.8.8.8 ok"


@pytest.mark.parametrize(
    "text,pattern",
    [
        ('api_key="sk-abc12345678"', "api_key"),
        ("password = 'hunter2longenough'", "password"),
        ("-----BEGIN PRIVATE KEY-----\ndata\n-----END PRIVATE KEY-----", "private_key"),
        ("denis@example.com contacted support", "email"),
    ],
)
def test_scan_detects_interactive_patterns(text: str, pattern: str) -> None:
    hits = scan(text)
    assert any(h.kind == pattern for h in hits), f"expected {pattern} in {hits}"
