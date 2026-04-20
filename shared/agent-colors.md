# Agent Color Map

Authoritative source for agent `color:` assignments. Enforced by cluster-scoped uniqueness in `tests/contract/ui-frontmatter-consistency.bats`.

## 1. Palette (18 hues)

Chosen for terminal rendering with ≥3:1 contrast against common backgrounds.

| Name | ANSI-256 | Approx hex |
|------|----------|------------|
| magenta | 201 | #ff00ff |
| pink | 205 | #ff4fa0 |
| purple | 93 | #875fff |
| orange | 208 | #ff8700 |
| coral | 209 | #ff875f |
| cyan | 51 | #00ffff |
| navy | 17 | #00005f |
| teal | 30 | #008787 |
| olive | 58 | #5f5f00 |
| blue | 33 | #0087ff |
| crimson | 161 | #d7005f |
| yellow | 226 | #ffff00 |
| green | 46 | #00ff00 |
| lime | 119 | #87ff5f |
| red | 196 | #ff0000 |
| amber | 214 | #ffaf00 |
| brown | 130 | #af5f00 |
| white | 15 | #ffffff |
| gray | 245 | #8a8a8a |

## 2. Dispatch clusters

Agents that can appear in the same TaskCreate cluster must have distinct colors. Cluster definitions mirror the dispatch-layer tables in `shared/agent-role-hierarchy.md`.

| Cluster | Members |
|---|---|
| Pre-pipeline | fg-010, fg-015, fg-020, fg-050, fg-090 |
| Orchestrator + helpers | fg-100, fg-101, fg-102, fg-103 |
| PREFLIGHT | fg-130, fg-135, fg-140, fg-143, fg-150, fg-155 |
| Migration / Planning | fg-160, fg-200, fg-205, fg-210, fg-250 |
| Implement | fg-300, fg-310, fg-320, fg-350 |
| Review | fg-400, fg-410, fg-411, fg-412, fg-413, fg-414, fg-416, fg-417, fg-418, fg-419 |
| Verify / Test | fg-500, fg-505, fg-506, fg-510, fg-515, fg-555 |
| Ship | fg-590, fg-600, fg-610, fg-620, fg-650 |
| Learn | fg-700, fg-710 |

## 3. Full 48-agent color map

| Agent | Cluster | Old color | New color |
|---|---|---|---|
| `fg-010-shaper` | Pre-pipeline | magenta | magenta |
| `fg-015-scope-decomposer` | Pre-pipeline | magenta | pink |
| `fg-020-bug-investigator` | Pre-pipeline | purple | purple |
| `fg-050-project-bootstrapper` | Pre-pipeline | magenta | orange |
| `fg-090-sprint-orchestrator` | Pre-pipeline | magenta | coral |
| `fg-100-orchestrator` | Orch+helpers | cyan | cyan |
| `fg-101-worktree-manager` | Orch+helpers | gray | gray |
| `fg-102-conflict-resolver` | Orch+helpers | gray | olive |
| `fg-103-cross-repo-coordinator` | Orch+helpers | gray | brown |
| `fg-130-docs-discoverer` | PREFLIGHT | cyan | cyan |
| `fg-135-wiki-generator` | PREFLIGHT | cyan | navy |
| `fg-140-deprecation-refresh` | PREFLIGHT | cyan | teal |
| `fg-143-observability-bootstrap` | PREFLIGHT | *(new)* | magenta |
| `fg-150-test-bootstrapper` | PREFLIGHT | cyan | olive |
| `fg-155-i18n-validator` | PREFLIGHT | *(new)* | crimson |
| `fg-160-migration-planner` | Migration/Plan | orange | orange |
| `fg-200-planner` | Migration/Plan | blue | blue |
| `fg-205-planning-critic` | Migration/Plan | *(none)* | crimson |
| `fg-210-validator` | Migration/Plan | yellow | yellow |
| `fg-250-contract-validator` | Migration/Plan | yellow | amber |
| `fg-300-implementer` | Implement | green | green |
| `fg-310-scaffolder` | Implement | green | lime |
| `fg-320-frontend-polisher` | Implement | magenta | coral |
| `fg-350-docs-generator` | Implement | green | teal |
| `fg-400-quality-gate` | Review | red | red |
| `fg-410-code-reviewer` | Review | cyan | cyan |
| `fg-411-security-reviewer` | Review | red | crimson |
| `fg-412-architecture-reviewer` | Review | cyan | navy |
| `fg-413-frontend-reviewer` | Review | teal | teal |
| `fg-414-license-reviewer` | Review | *(new)* | lime |
| `fg-416-performance-reviewer` | Review | yellow | amber |
| `fg-417-dependency-reviewer` | Review | cyan | purple |
| `fg-418-docs-consistency-reviewer` | Review | white | white |
| `fg-419-infra-deploy-reviewer` | Review | green | olive |
| `fg-500-test-gate` | Verify/Test | yellow | yellow |
| `fg-505-build-verifier` | Verify/Test | yellow | brown |
| `fg-506-migration-verifier` | Verify/Test | *(new)* | coral |
| `fg-510-mutation-analyzer` | Verify/Test | cyan | cyan |
| `fg-515-property-test-generator` | Verify/Test | cyan | pink |
| `fg-555-resilience-tester` | Verify/Test | *(new)* | navy |
| `fg-590-pre-ship-verifier` | Ship | red | red |
| `fg-600-pr-builder` | Ship | blue | blue |
| `fg-610-infra-deploy-verifier` | Ship | green | green |
| `fg-620-deploy-verifier` | Ship | green | olive |
| `fg-650-preview-validator` | Ship | green | amber |
| `fg-700-retrospective` | Learn | magenta | magenta |
| `fg-710-post-run` | Learn | magenta | pink |

## 4. Adding a new agent

New agents must pick an unused color within their target cluster. If no hue is free, extend the §1 palette and document the AAA contrast check in the PR description.
