# Scenario 11 — Django auth middleware refactor (repo-map A/B)

Refactor the authentication middleware in an existing Django 5.1.x project (Python 3.12+, pytest 8.x) to delegate session lookups to a new shared `SessionCache` helper. The refactor must trace imports across the project and update every call-site consistently so `pytest` still passes with no behavioural change.

Target scope (≥ 8 files will need edits — the implementer must follow imports across the project, which is exactly what the repo-map pack-assembly code path is designed to accelerate):

- `accounts/middleware/authentication.py` — inline cache reads are lifted into the new helper.
- `accounts/session_cache.py` — new module exposing `SessionCache.get(session_key) -> SessionData | None` with TTL + negative-cache semantics.
- `accounts/views/login.py`, `accounts/views/logout.py`, `accounts/views/profile.py` — switch from direct cache access to `SessionCache`.
- `accounts/api/serializers.py`, `accounts/api/viewsets.py` — same call-site migration inside the DRF API layer.
- `accounts/tests/test_middleware.py`, `accounts/tests/test_session_cache.py` — existing middleware tests updated, new helper tests added (TTL, cache miss, negative cache, invalidation).
- `accounts/apps.py` — register the cache singleton on `AppConfig.ready`.

Constraints:
- Django 5.1.x, Python 3.12+, pytest 8.x, pytest-django 4.x. Do not bump or add dependencies.
- Preserve public HTTP behaviour: every endpoint returns the same status codes and bodies as before.
- Do not widen imports into `.claude/**` or `tests/evals/**`.

Pipeline mode: `standard`.

**Why this scenario exists:** it deliberately targets the `{{REPO_MAP_PACK}}` substitution path (Phase 10 Task 10) — multi-file import tracing across ~10 project files is where biased PageRank should outperform a raw directory listing. Paired with the A/B workflow in `.github/workflows/evals-compaction-ab.yml`, it measures the effect of `code_graph.prompt_compaction.enabled` on `actual_tokens` and `pipeline_score`.
