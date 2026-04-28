"""Regenerate the synthetic seed tarball. Run manually, commit result."""

from __future__ import annotations

import subprocess
import tarfile
import tempfile
from pathlib import Path

FIXTURE = Path(__file__).parent / "synthetic-corpus" / "2026-01-01-hello-health"
TARGET = FIXTURE / "seed-project.tar.gz"


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.md").write_text("synthetic seed\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
        subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
        subprocess.run(
            ["git", "-c", "user.email=b@b", "-c", "user.name=b", "commit", "-q", "-m", "seed"],
            cwd=tmp_path,
            check=True,
        )
        with tarfile.open(TARGET, "w:gz") as tf:
            for p in sorted(tmp_path.rglob("*")):
                tf.add(p, arcname=str(p.relative_to(tmp_path)))
    print(f"wrote {TARGET}")


if __name__ == "__main__":
    main()
