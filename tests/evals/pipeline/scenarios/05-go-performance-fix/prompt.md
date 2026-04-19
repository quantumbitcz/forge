# Scenario 05 — Go N+1 HTTP loop

`main.go` fetches user profiles inside a `for` loop — one HTTP call per user. Refactor to a single batched call to `/users?ids=...`. The existing benchmark `BenchmarkGetProfiles` must improve by at least 5×.

Pipeline mode: `bugfix`.
