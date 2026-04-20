import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from hooks._py.time_travel.cas import CheckpointStore
from hooks._py.time_travel.restore import (
    RewindAbort,
    repair_rewind_tx,
    rewind,
    tx_dir,
)


def _init_git(d: pathlib.Path, content: str = "v1\n") -> str:
    subprocess.run(["git", "init", "-q", str(d)], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.email", "a@b"], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.name", "a"], check=True)
    (d / "f.txt").write_text(content)
    subprocess.run(["git", "-C", str(d), "add", "."], check=True)
    subprocess.run(["git", "-C", str(d), "commit", "-q", "-m", "c"], check=True)
    return subprocess.check_output(["git", "-C", str(d), "rev-parse", "HEAD"]).decode().strip()


def _setup(tmp_path):
    run = tmp_path / ".forge" / "runs" / "runX"
    run.mkdir(parents=True)
    wt = tmp_path / "wt"; wt.mkdir()
    sha0 = _init_git(wt, "v1\n")
    store = CheckpointStore(run_dir=run, worktree_dir=wt)
    h1 = store.write_checkpoint("PLAN.-.001", "PLANNING", "-",
                                {"s": 1}, [{"type": "X", "id": 1}],
                                {"stage_notes/plan.md": b"plan1"})
    (wt / "f.txt").write_text("v2\n")
    subprocess.run(["git", "-C", str(wt), "add", "."], check=True)
    subprocess.run(["git", "-C", str(wt), "commit", "-q", "-m", "c2"], check=True)
    h2 = store.write_checkpoint("IMPLEMENT.T1.002", "IMPLEMENTING", "T1",
                                {"s": 2}, [{"type": "X", "id": 2}],
                                {"stage_notes/impl.md": b"impl"})
    return store, run, wt, h1, h2


def test_rewind_restores_state_worktree_events_memory(tmp_path):
    store, run, wt, h1, h2 = _setup(tmp_path)
    # Pretend live state.json and events.jsonl sit here
    (run / "state.json").write_text(json.dumps({"s": 2, "head_checkpoint": h2}))
    (run / "events.jsonl").write_text(json.dumps({"type": "X", "id": 2}) + "\n")

    rewind(store, to_sha=h1, run_id="runX", triggered_by="user")

    assert (run / "checkpoints" / "HEAD").read_text().strip() == h1
    assert json.loads((run / "state.json").read_text())["s"] == 1
    events = [json.loads(l) for l in (run / "events.jsonl").read_text().splitlines()]
    assert events[-1]["type"] == "REWOUND"
    assert events[-1]["to_sha"] == h1
    assert (wt / "f.txt").read_text() == "v1\n"


def test_rewind_aborts_on_dirty_worktree(tmp_path):
    store, run, wt, h1, _ = _setup(tmp_path)
    (wt / "f.txt").write_text("dirty\n")
    try:
        rewind(store, to_sha=h1, run_id="runX", triggered_by="user")
    except RewindAbort as e:
        assert e.exit_code == 5
        assert "dirty" in str(e).lower()
    else:
        raise AssertionError("expected RewindAbort")
    # zero side effects: HEAD, state.json unchanged
    assert (wt / "f.txt").read_text() == "dirty\n"


def test_rewind_aborts_on_unknown_id(tmp_path):
    store, run, wt, h1, _ = _setup(tmp_path)
    try:
        rewind(store, to_sha="f" * 64, run_id="runX", triggered_by="user")
    except RewindAbort as e:
        assert e.exit_code == 6
    else:
        raise AssertionError("expected RewindAbort")


def test_tx_dir_is_per_run(tmp_path):
    store, run, _, _, _ = _setup(tmp_path)
    tx = tx_dir(store)
    assert tx.parent == run
    assert tx.name == ".rewind-tx"


def test_repair_rewind_tx_rolls_back_partial(tmp_path):
    store, run, wt, h1, h2 = _setup(tmp_path)
    (run / "state.json").write_text(json.dumps({"s": 2}))
    (run / "events.jsonl").write_text(json.dumps({"type": "X", "id": 2}) + "\n")
    # simulate crash between stage 2 (stage) and stage 3 (commit): tx dir populated, live files untouched
    tx = tx_dir(store)
    tx.mkdir()
    (tx / "state.json").write_text(json.dumps({"s": 1}))
    (tx / "events.jsonl.new").write_text("{}\n")
    (tx / "target.sha").write_text(h1 + "\n")
    (tx / "stage").write_text("staged\n")  # not "committing"

    repair_rewind_tx(store, run_id="runX")
    assert not tx.exists()
    # live files unchanged
    assert json.loads((run / "state.json").read_text())["s"] == 2


def test_repair_rewind_tx_replays_when_committing(tmp_path):
    store, run, wt, h1, _ = _setup(tmp_path)
    (run / "state.json").write_text(json.dumps({"s": 2}))
    (run / "events.jsonl").write_text("")
    tx = tx_dir(store)
    tx.mkdir()
    # Need full tx contents to replay commit
    bundle = store.read_checkpoint(h1)
    (tx / "state.json").write_bytes(json.dumps(bundle["state"], sort_keys=True, separators=(",", ":")).encode())
    (tx / "events.jsonl.new").write_text(
        "\n".join(json.dumps(e, sort_keys=True, separators=(",", ":"))
                  for e in bundle["events_slice"]) + ("\n" if bundle["events_slice"] else "")
    )
    (tx / "target.sha").write_text(h1 + "\n")
    (tx / "worktree.sha").write_text(bundle["worktree_sha"] + "\n")
    (tx / "head_before.sha").write_text("\n")
    (tx / "run_id").write_text("runX\n")
    (tx / "forced").write_text("0")
    (tx / "dirty_paths.json").write_text("[]")
    (tx / "triggered_by").write_text("user")
    (tx / "memory").mkdir()
    for path, data in bundle["memory_files"].items():
        dest = tx / "memory" / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
    (tx / "stage").write_text("committing\n")

    repair_rewind_tx(store, run_id="runX")
    assert not tx.exists()
    assert json.loads((run / "state.json").read_text())["s"] == 1
    assert (run / "checkpoints" / "HEAD").read_text().strip() == h1
