# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this plugin or its agents, report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Contact the team directly:
- **Email:** security@quantumbit.cz
- **GitHub:** Use private vulnerability reporting (Settings > Security > Advisories > New draft advisory)

We acknowledge receipt within 48 hours and provide an initial assessment within 5 business days.

## Security Practices

### No secrets in the plugin

This plugin ships as a submodule or marketplace install. It must never contain:
- API keys, tokens, or credentials
- Hard-coded URLs to internal services
- Environment-specific configuration

All project-specific config lives in the consuming repo's `.claude/` directory.

### Agent permissions

- Agents declare required tools in YAML frontmatter (`tools` field). The orchestrator dispatches agents with only those declared tools.
- Review agents (quality gate, security reviewer) use read-only access where possible.
- The `fg-411-security-reviewer` agent checks for OWASP top 10 vulnerabilities, hardcoded secrets, and injection risks during every pipeline run (Stage 6: Review).

### Automated security checks

- The 3-layer check engine runs on every `Edit`/`Write` via PostToolUse hook. Layer 1 patterns detect hardcoded secrets and common vulnerability patterns.
- The `/security-audit` skill runs module-appropriate security scanners (`npm audit`, `cargo audit`, `govulncheck`, `trivy`, etc.) on demand.

### Pipeline state is local

- `.forge/` is gitignored and never committed.
- State files contain run metadata (story IDs, timestamps, scores) but no secrets.
- Feedback files may contain user corrections -- these stay local.

### Module scripts and hooks

- All scripts require explicit shebang lines (`#!/usr/bin/env bash`) and executable permissions.
- Guard hooks run in the consuming project's context and must not make network calls.
- Verification scripts are read-only (grep/find patterns, never modify files).

## Supported Versions

Only the latest version on `master` is actively maintained.
