# Scenario 02 — FastAPI off-by-one bugfix

The failing test `tests/test_items.py::test_pagination_returns_size_items` asserts that `GET /items?page=0&size=10` returns exactly 10 items but gets 11.

Root-cause the off-by-one in `app/main.py`, fix it, and make the test pass. Add one additional regression test for `size=1, page=5` returning exactly one item.

Do not introduce new dependencies.

Pipeline mode: `bugfix`.
