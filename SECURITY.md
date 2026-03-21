# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this plugin or its agents, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, contact the team directly:
- Email: security@wellplanned.app
- Or use GitHub's private vulnerability reporting (Settings > Security > Advisories > New draft advisory)

We will acknowledge receipt within 48 hours and provide an initial assessment within 5 business days.

## Security Practices

### No secrets in the plugin

This plugin is installed as a submodule in consuming projects. It must never contain:
- API keys, tokens, or credentials
- Hard-coded URLs to internal services
- Environment-specific configuration

All project-specific config lives in the consuming repo's `.claude/` directory.

### Agent permissions

- Agents declare their required tools in YAML frontmatter (`tools` field)
- The orchestrator dispatches agents with only the declared tools
- Review agents (quality gate, security reviewer) should have read-only access where possible

### Pipeline state is local

- `.pipeline/` is gitignored and never committed
- State files contain run metadata (story IDs, timestamps, scores) but no secrets
- Feedback files may contain user corrections -- these stay local

### Module scripts and hooks

- All scripts must be executable with explicit shebang lines (`#!/usr/bin/env bash`)
- Guard hooks run in the consuming project's context -- they should not make network calls
- Verification scripts should be read-only (grep/find patterns, not modify files)

## Supported Versions

Only the latest version on `master` is actively maintained.
