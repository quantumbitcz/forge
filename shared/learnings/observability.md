---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
---
# Observability Learnings

## Agent: fg-143-observability-bootstrap

`fg-143` runs at PREFLIGHT when `config.agents.observability_bootstrap.enabled == true` (default `false`). Categories: `OBS-MISSING`, `OBS-TRACE-INCOMPLETE`, `OBS-BOOTSTRAP-APPLIED`, `OBS-BOOTSTRAP-UNSAFE`.

Write-capable within `.forge/worktree/`. Common calibration:

| Language | Typical OBS-MISSING false-positive rate | Mitigation |
|---|---|---|
| Java/Spring | ~5% (Micrometer implies OTel) | Probe Micrometer registry before flagging |
| Go | ~10% (stdlib `expvar` counts) | Add `expvar` to accepted-patterns list |
| Python | ~15% (Prometheus client sans OTel) | Accept `prometheus_client` as a valid metric surface |

---

# Cross-Project Learnings: observability

## PREEMPT items
