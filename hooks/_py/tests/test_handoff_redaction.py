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
