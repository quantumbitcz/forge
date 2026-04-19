# Scenario 08 — Single-file Flask spike

Create a single-file `app.py` Flask throwaway with:

- `GET /` returns plain text "hello from forge"
- `POST /echo` returns the request JSON verbatim
- `pytest` module `test_app.py` with one happy-path test each
- `requirements.txt` pinning Flask 3.0.x + pytest 8.x

Intentionally small scope — this is the cheap smoke scenario.

Pipeline mode: `standard`.
