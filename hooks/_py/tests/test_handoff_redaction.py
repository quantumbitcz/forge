from hooks._py.handoff.redaction import redact_handoff_text


def test_api_key_redacted():
    src = "Authorization: Bearer sk-ant-abc123def456ghi789"
    out = redact_handoff_text(src)
    assert "sk-ant-abc123def456ghi789" not in out
    assert "[REDACTED:" in out


def test_email_redacted():
    src = "Contact: denis.sajnar@gmail.com"
    out = redact_handoff_text(src)
    assert "denis.sajnar@gmail.com" not in out


def test_plain_prose_unchanged():
    src = "The pipeline reached stage REVIEWING at score 82."
    assert redact_handoff_text(src) == src


def test_fail_closed_on_redactor_error(monkeypatch):
    import pytest
    from hooks._py.handoff import redaction

    def boom(_: str) -> str:
        raise RuntimeError("redactor broke")

    monkeypatch.setattr(redaction, "_redact_impl", boom)
    with pytest.raises(RuntimeError):
        redact_handoff_text("anything")


def test_aws_access_key_redacted():
    src = "key = AKIAIOSFODNN7EXAMPLE here"
    out = redact_handoff_text(src)
    assert "AKIAIOSFODNN7EXAMPLE" not in out
    assert "[REDACTED:aws_access_key]" in out


def test_jwt_redacted():
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    out = redact_handoff_text(f"Token: {jwt}")
    assert jwt not in out
    assert "[REDACTED:jwt]" in out


def test_slack_token_redacted():
    src = "webhook = xoxb-1234567890-abcdef"
    out = redact_handoff_text(src)
    assert "xoxb-1234567890-abcdef" not in out


def test_private_key_block_redacted():
    src = "-----BEGIN RSA PRIVATE KEY-----\nMIIEvQIBAD...fakekey...\n-----END RSA PRIVATE KEY-----"
    out = redact_handoff_text(src)
    assert "fakekey" not in out
    assert "[REDACTED:private_key_block]" in out


def test_generic_secret_env_redacted():
    src = "DATABASE_SECRET=supersecret123 and API_KEY=sometoken"
    out = redact_handoff_text(src)
    assert "supersecret123" not in out
    assert "sometoken" not in out


def test_lowercase_prose_not_redacted():
    src = "The token = abc123 was fine. Next token: something."
    out = redact_handoff_text(src)
    # Lowercase prose should NOT be mangled
    assert out == src


def test_mixed_case_prose_unchanged():
    src = "Api_key management requires careful review."
    out = redact_handoff_text(src)
    # Non-assignment prose should NOT be redacted
    assert "Api_key" in out
