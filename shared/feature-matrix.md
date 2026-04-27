# Feature Activation Matrix

Auto-generated — do not edit the rows between the sentinel comments by hand.
Run `python shared/feature_matrix_generator.py` after any change to feature
defaults in `CLAUDE.md` or the `FEATURES` dict in the generator.

Usage counts are sourced from `.forge/run-history.db` (`feature_usage` table).
Missing DB or table → every cell is `unknown`.

<!-- FEATURE_MATRIX_START -->
| ID | Feature | Default | Last-30d Usage |
|----|---------|---------|----------------|
| F05 | Living specifications | conditional (living_specs.enabled) | unknown |
| F07 | Event-sourced log | conditional (events.enabled) | unknown |
| F08 | Context condensation | conditional (condensation.enabled) | unknown |
| F09 | Active knowledge base | conditional (active_knowledge.enabled) | unknown |
| F10 | Enhanced security | conditional (security.enabled) | unknown |
| F11 | Playbooks | conditional (playbooks.enabled) | unknown |
| F12 | Spec inference | conditional (spec_inference.enabled) | unknown |
| F13 | Property-based testing | conditional (property_testing.enabled) | unknown |
| F14 | Flaky test management | conditional (flaky_tests.enabled) | unknown |
| F15 | Dynamic accessibility | conditional (accessibility.enabled) | unknown |
| F16 | i18n validation | enabled (i18n.enabled default true) | unknown |
| F17 | Performance regression | conditional (performance_tracking.enabled) | unknown |
| F18 | Next-task prediction | conditional (predictions.enabled) | unknown |
| F19 | DX metrics | conditional (dx_metrics.enabled) | unknown |
| F20 | Monorepo tooling | conditional (monorepo.enabled) | unknown |
| F21 | A2A HTTP transport | conditional (a2a.enabled) | unknown |
| F22 | AI/ML pipelines | conditional (ml_ops.enabled) | unknown |
| F23 | Feature flags | conditional (feature_flags.enabled) | unknown |
| F24 | Deployment strategies | conditional (deployment.enabled) | unknown |
| F25 | Consumer-driven contracts | conditional (contract_testing.enabled) | unknown |
| F26 | Output compression | conditional (output_compression.enabled) | unknown |
| F27 | AI quality | conditional (ai_quality.enabled) | unknown |
| F28 | Cross-project learnings | conditional (cross_project.enabled) | unknown |
| F29 | Run history store | conditional (run_history.enabled) | unknown |
| F30 | MCP server | conditional (mcp_server.enabled) | unknown |
| F31 | Self-improving playbooks | conditional (playbooks.refinement.enabled) | unknown |
| F32 | Implementer reflection | conditional (implementer.reflection.enabled) | unknown |
| F33 | Self-consistency voting | conditional (consistency.enabled) | unknown |
| F34 | Session handoff | conditional (handoff.enabled) | unknown |
| F35 | Speculative plan branches | conditional (speculation.enabled) | unknown |
<!-- FEATURE_MATRIX_END -->

See `shared/feature-lifecycle.md` for the 90/180-day deprecation policy.
