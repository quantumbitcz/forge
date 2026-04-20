import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from hooks._py.time_travel.cas import CheckpointStore
from hooks._py.time_travel.gc import GCPolicy, gc


def _init_git(d):
    subprocess.run(["git", "init", "-q", str(d)], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.email", "a@b"], check=True)
    subprocess.run(["git", "-C", str(d), "config", "user.name", "a"], check=True)
    (d / "f.txt").write_text("x")
    subprocess.run(["git", "-C", str(d), "add", "."], check=True)
    subprocess.run(["git", "-C", str(d), "commit", "-q", "-m", "c"], check=True)


def _mk_store(tmp, run_id="r1"):
    run = tmp / ".forge" / "runs" / run_id
    run.mkdir(parents=True)
    wt = tmp / f"wt-{run_id}"; wt.mkdir()
    _init_git(wt)
    return CheckpointStore(run_dir=run, worktree_dir=wt), run


def test_gc_refuses_to_delete_checkpoint_on_path_to_active_head(tmp_path):
    store, run = _mk_store(tmp_path)
    h1 = store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    h2 = store.write_checkpoint("A.-.002", "PLANNING", "-", {"x": 2}, [], {})  # HEAD = h2
    # mark run as RUNNING
    (run / "state.json").write_text(json.dumps({"status": "RUNNING", "head_checkpoint": h2}))
    removed = gc(store, GCPolicy(retention_days=0, max_per_run=100,
                                 runs_root=tmp_path / ".forge" / "runs"))
    # h1 is on path to HEAD -> protected; h2 is HEAD -> protected
    assert removed == []


def test_gc_reclaims_orphan_subtree_when_ttl_expired(tmp_path):
    store, run = _mk_store(tmp_path)
    h1 = store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    h2 = store.write_checkpoint("A.-.002", "PLANNING", "-", {"x": 2}, [], {})
    # simulate rewind: HEAD back to h1
    (store.ck_dir / "HEAD").write_text(h1 + "\n")
    # run marked COMPLETE and TTL expired
    (run / "state.json").write_text(json.dumps({"status": "COMPLETE", "head_checkpoint": h1}))
    # Force created_at to ancient
    tree = json.loads((store.ck_dir / "tree.json").read_text())
    tree[h2]["created_at"] = "2000-01-01T00:00:00Z"
    (store.ck_dir / "tree.json").write_text(json.dumps(tree))
    removed = gc(store, GCPolicy(retention_days=7, max_per_run=100,
                                 runs_root=tmp_path / ".forge" / "runs"))
    assert h2 in removed
    assert h1 not in removed


def test_gc_skips_active_runs_entirely(tmp_path):
    store_a, run_a = _mk_store(tmp_path, "runA")
    ha = store_a.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    (run_a / "state.json").write_text(json.dumps({"status": "RUNNING", "head_checkpoint": ha}))

    store_b, run_b = _mk_store(tmp_path, "runB")
    hb1 = store_b.write_checkpoint("B.-.001", "PLANNING", "-", {"y": 1}, [], {})
    hb2 = store_b.write_checkpoint("B.-.002", "PLANNING", "-", {"y": 2}, [], {})
    (store_b.ck_dir / "HEAD").write_text(hb1 + "\n")
    (run_b / "state.json").write_text(json.dumps({"status": "COMPLETE", "head_checkpoint": hb1}))
    tree = json.loads((store_b.ck_dir / "tree.json").read_text())
    tree[hb2]["created_at"] = "2000-01-01T00:00:00Z"
    (store_b.ck_dir / "tree.json").write_text(json.dumps(tree))

    removed = gc(store_b, GCPolicy(retention_days=7, max_per_run=100,
                                   runs_root=tmp_path / ".forge" / "runs"))
    assert hb2 in removed  # only runB's orphan
    assert ha not in removed  # runA untouched


def test_gc_enforces_max_per_run_cap(tmp_path):
    store, run = _mk_store(tmp_path)
    hashes = []
    for i in range(5):
        hashes.append(store.write_checkpoint(f"A.-.{i:03d}", "PLANNING", "-",
                                             {"x": i}, [], {}))
    (run / "state.json").write_text(json.dumps({"status": "COMPLETE",
                                                "head_checkpoint": hashes[-1]}))
    removed = gc(store, GCPolicy(retention_days=365, max_per_run=3,
                                 runs_root=tmp_path / ".forge" / "runs"))
    # oldest 2 collected; HEAD path preserved
    assert len(removed) == 2
    assert hashes[-1] not in removed
