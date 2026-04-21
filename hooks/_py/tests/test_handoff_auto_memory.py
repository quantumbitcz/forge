from pathlib import Path

from hooks._py.handoff.auto_memory import promote_from_terminal_handoff


def test_promotes_top_preempts(tmp_path, monkeypatch):
    memory_root = tmp_path / "memory"
    memory_root.mkdir()
    monkeypatch.setenv("FORGE_AUTO_MEMORY_ROOT", str(memory_root))

    preempts = [
        {"text": "always search for latest version", "confidence": "HIGH"},
        {"text": "do not mock databases", "confidence": "HIGH"},
        {"text": "minor tip", "confidence": "MEDIUM"},
    ]
    user_decisions = ["don't add rate limiting — out of scope"]

    promote_from_terminal_handoff(run_id="r1", preempts=preempts, user_decisions=user_decisions)

    files = list(memory_root.glob("forge_handoff_*.md"))
    assert len(files) >= 2  # top 2 HIGH-conf + at least the user decision block
