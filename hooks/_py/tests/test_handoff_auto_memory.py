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


def test_yaml_injection_attempt_is_quoted(tmp_path, monkeypatch):
    """Adversarial PREEMPT text containing : and newlines must not break frontmatter."""
    from shared.config_validator import parse_yaml_subset, extract_yaml

    memory_root = tmp_path / "memory"
    memory_root.mkdir()
    monkeypatch.setenv("FORGE_AUTO_MEMORY_ROOT", str(memory_root))

    evil_preempt = [{
        "text": "attack: newline\n---\ninjected: pwned",
        "confidence": "HIGH",
    }]
    evil_decision = ["don't: use\nname: rogue"]

    promote_from_terminal_handoff(run_id="r-evil", preempts=evil_preempt, user_decisions=evil_decision)

    files = list(memory_root.glob("forge_handoff_*.md"))
    assert len(files) >= 2

    # Every file must parse cleanly and have NO "injected" or "rogue" top-level key
    for f in files:
        yaml_text = extract_yaml(f)
        assert yaml_text is not None, f"frontmatter block not found in {f}"
        data = parse_yaml_subset(yaml_text)
        assert isinstance(data, dict), f"frontmatter did not parse to mapping in {f}"
        assert "injected" not in data, f"injection key leaked in {f}"
        assert "rogue" not in data, f"injection key leaked in {f}"


def test_default_memory_root_uses_project_hash(tmp_path, monkeypatch):
    """With no env override, memory root is ~/.claude/projects/<cwd-hash>/memory/."""
    import os as _os
    from hooks._py.handoff.auto_memory import _memory_root

    monkeypatch.delenv("FORGE_AUTO_MEMORY_ROOT", raising=False)
    fake_home = tmp_path / "home"
    fake_home.mkdir()
    monkeypatch.setenv("HOME", str(fake_home))

    # Pick a fake cwd and chdir into it (must be real for Path.cwd().resolve())
    fake_cwd = tmp_path / "project" / "foo"
    fake_cwd.mkdir(parents=True)
    monkeypatch.chdir(fake_cwd)

    root = _memory_root()
    # root should be inside ~/.claude/projects/<cwd-hash>/memory/
    assert str(root).startswith(str(fake_home / ".claude" / "projects"))
    assert root.name == "memory"
    # The hash component should reflect the cwd path with / → -
    assert "-project-foo" in root.parts[-2]
