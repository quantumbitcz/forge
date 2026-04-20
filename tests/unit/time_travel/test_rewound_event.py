import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from hooks._py.time_travel.events import RewoundEvent

FIXTURE = pathlib.Path(__file__).parent / "fixtures" / "rewound-event.golden.json"


def test_rewound_event_matches_golden():
    ev = RewoundEvent(
        timestamp="2026-04-19T12:00:00Z",
        run_id="run-abc123",
        from_sha="a1b2c3d4e5f60718293a4b5c6d7e8f901122334455667788aabbccddeeff0011",
        to_sha="deadbeefcafe0102030405060708090a0b0c0d0e0f1011121314151617181920",
        to_human_id="PLAN.-.003",
        triggered_by="user",
        forced=False,
        dirty_paths=[],
    )
    encoded = json.loads(ev.to_canonical_json())
    expected = json.loads(FIXTURE.read_text())
    assert encoded == expected


def test_rewound_event_forced_with_dirty_paths():
    ev = RewoundEvent(
        timestamp="2026-04-19T12:00:00Z",
        run_id="run-abc123",
        from_sha="a" * 64,
        to_sha="b" * 64,
        to_human_id="IMPLEMENT.T1.004",
        triggered_by="auto",
        forced=True,
        dirty_paths=["src/a.py", "src/b.py"],
    )
    d = json.loads(ev.to_canonical_json())
    assert d["forced"] is True
    assert d["dirty_paths"] == ["src/a.py", "src/b.py"]
    assert d["triggered_by"] == "auto"


def test_canonical_json_is_sorted_and_compact():
    ev = RewoundEvent(
        timestamp="2026-04-19T12:00:00Z",
        run_id="r",
        from_sha="a" * 64,
        to_sha="b" * 64,
        to_human_id="X.-.001",
        triggered_by="user",
        forced=False,
        dirty_paths=[],
    )
    out = ev.to_canonical_json()
    assert " " not in out
    assert out.index('"dirty_paths"') < out.index('"forced"') < out.index('"from_sha"')
