import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from hooks._py.time_travel.cas import CheckpointStore


def _init_git(dir_: pathlib.Path) -> str:
    subprocess.run(["git", "init", "-q", str(dir_)], check=True)
    subprocess.run(["git", "-C", str(dir_), "config", "user.email", "a@b"], check=True)
    subprocess.run(["git", "-C", str(dir_), "config", "user.name", "a"], check=True)
    (dir_ / "f.txt").write_text("v1\n")
    subprocess.run(["git", "-C", str(dir_), "add", "."], check=True)
    subprocess.run(["git", "-C", str(dir_), "commit", "-q", "-m", "init"], check=True)
    sha = subprocess.check_output(["git", "-C", str(dir_), "rev-parse", "HEAD"]).decode().strip()
    return sha


def test_write_then_read_round_trip(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "run1"
    forge.mkdir(parents=True)
    worktree = tmp_path / "wt"
    worktree.mkdir()
    sha = _init_git(worktree)

    store = CheckpointStore(run_dir=forge, worktree_dir=worktree)
    cp_hash = store.write_checkpoint(
        human_id="PLAN.-.003",
        stage="PLANNING",
        task="-",
        state={"story_state": "PLANNING", "score": 0},
        events_slice=[{"type": "STAGE_TRANSITION", "id": 1}],
        memory_files={"stage_notes/plan.md": b"hello"},
    )
    assert len(cp_hash) == 64
    bundle = store.read_checkpoint(cp_hash)
    assert bundle["state"]["story_state"] == "PLANNING"
    assert bundle["worktree_sha"] == sha
    assert bundle["events_slice"][0]["type"] == "STAGE_TRANSITION"
    assert bundle["memory_files"]["stage_notes/plan.md"] == b"hello"
    assert (forge / "checkpoints" / "HEAD").read_text().strip() == cp_hash
    assert json.loads((forge / "checkpoints" / "index.json").read_text())["PLAN.-.003"] == cp_hash


def test_identical_checkpoints_dedup(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "run1"
    forge.mkdir(parents=True)
    worktree = tmp_path / "wt"
    worktree.mkdir()
    _init_git(worktree)
    store = CheckpointStore(run_dir=forge, worktree_dir=worktree)
    h1 = store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    h2 = store.write_checkpoint("A.-.002", "PLANNING", "-", {"x": 1}, [], {})
    assert h1 == h2
    by_hash = forge / "checkpoints" / "by-hash"
    dirs = [p for p in by_hash.rglob("manifest.json")]
    assert len(dirs) == 1
