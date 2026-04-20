# Reviewer Ownership Boundaries

Defines which reviewer owns which domain. Referenced by each reviewer agent and the quality gate. Prevents duplicate findings and contradictory recommendations.

## Ownership Matrix

| Reviewer | Owns | Does NOT Own |
|----------|------|-------------|
| fg-410-code-reviewer | Code quality, naming, DRY/KISS, test quality vs. AC, error handling, plan alignment | Caching strategy (→ fg-416), dependency CVEs (→ fg-417) |
| fg-411-security-reviewer | OWASP Top 10, auth gaps, injection, secrets, runtime policy | License compliance (→ fg-417) |
| fg-412-architecture-reviewer | Layer boundaries, dependency direction, module structure, structural violations | Code-level DRY (→ fg-410), runtime performance (→ fg-416) |
| fg-413-frontend-reviewer | A11y (WCAG 2.2 AA), design system, responsive, dark mode, visual regression | Backend caching (→ fg-416), FE performance (→ fg-416) |
| fg-414-license-reviewer | SPDX policy compliance, copyleft-in-proprietary detection, license-change detection between base and HEAD | CVEs (→ fg-417), runtime security (→ fg-411) |
| fg-416-performance-reviewer | N+1 queries, missing indexes, connection pools, caching strategy, caching library choice, concurrency, frontend bundle/render/load/network | Dependency CVEs (→ fg-417), security implications (→ fg-411) |
| fg-417-dependency-reviewer | Dependency health, CVEs, version conflicts, outdated/unmaintained packages | License compliance (→ fg-414), runtime performance (→ fg-416), architecture fit (→ fg-412) |
| fg-418-docs-consistency-reviewer | Documentation accuracy, README, ADRs, API specs, decision consistency | Code comments (→ fg-410) |
| fg-419-infra-deploy-reviewer | Helm, K8s, Terraform, Dockerfiles, deployment security | Application code (→ fg-410) |

## Category Ownership

| Category Prefix | Primary Reviewer | Secondary |
|----------------|-----------------|-----------|
| ARCH-*, STRUCT-* | fg-412 | — |
| SEC-* | fg-411 | — |
| PERF-* | fg-416 | — |
| DEP-* | fg-417 | — |
| LICENSE-* | fg-414 | fg-417 (migration note, fg-420) |
| I18N-* | fg-155 | fg-413 (FE context) |
| MIGRATION-* | fg-506 | — |
| RESILIENCE-* | fg-555 | — |
| OBS-* | fg-143 | — |
| TEST-* | fg-410 | fg-500 (execution) |
| QUAL-* | fg-410 | — |
| DOC-* | fg-418 | — |
| INFRA-* | fg-419 | — |
| A11Y-* | fg-413 | — |
| FE-PERF-* | fg-416 | — |
| CONV-* | fg-410 | fg-413 (frontend) |
| SCOUT-* | fg-410 | — |
| APPROACH-* | fg-410 | — |

## Conflict Resolution

When two reviewers flag the same issue:
1. Primary reviewer's finding takes precedence (per table above)
2. Secondary reviewer's finding is deduplicated by quality gate
3. If both are primary for different categories on the same file+line: keep both, document overlap in stage notes

## Migration Note

fg-420-dependency-reviewer was removed in v2.3.0. Its responsibilities were split:
- CVE detection, outdated packages, unmaintained libraries → fg-417-dependency-reviewer
- Caching library evaluation → fg-416-performance-reviewer

In Phase 07, license compliance was split out of fg-417 into fg-414-license-reviewer:
- SPDX policy buckets, copyleft detection, license-change detection → fg-414-license-reviewer
- Frontend performance (FE-PERF-*) was moved from fg-413 to fg-416-performance-reviewer.
