"""Interactive corpus curation. User-assisted: never scrapes, always confirms.

Flow (spec §Component 1):
  1. Query .forge/run-history.db for eligible runs.
  2. For each candidate: print summary, prompt y/N/s/q.
  3. On y: prompt slug, complexity, tags; auto-detect requires_docker (user confirm);
     scrub PII; write corpus/<date>-<slug>/.
  4. Reject on tarball > 50MB, missing SHA, or unacknowledged PII match.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path
from typing import Any

import yaml

from tests.evals.benchmark.pii_scrub import scan, scrub

_SLUG_RE = re.compile(r"^[a-z0-9-]+$")
_COMPLEXITIES = frozenset({"S", "M", "L"})

_CORPUS_ROOT = Path(__file__).resolve().parents[1] / "corpus"
_MAX_TARBALL_MB = 50


class CurationError(RuntimeError):
    pass


_ELIGIBILITY_SQL = """
SELECT id, requirement, language, framework, verdict, score,
       started_at, finished_at, branch_name, pr_url, config_snapshot
  FROM runs
 WHERE verdict IN ('PASS', 'CONCERNS')
   AND score >= 70
   AND started_at >= date('now', '-365 days')
 ORDER BY score DESC, started_at DESC
 LIMIT 100
"""


def _query_candidates(db_path: Path) -> list[dict[str, Any]]:
    if not db_path.is_file():
        return []
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in conn.execute(_ELIGIBILITY_SQL).fetchall()]
    finally:
        conn.close()


def _ask(prompt: str, choices: str = "yNsq") -> str:
    while True:
        resp = input(f"{prompt} [{choices}]: ").strip().lower() or "n"
        if resp and resp[0] in choices.lower():
            return resp[0]


def _detect_requires_docker(source_dir: Path) -> bool:
    probes = ["docker-compose.yml", "compose.yaml", "Dockerfile"]
    return any((source_dir / p).exists() for p in probes)


def _archive(source_dir: Path, target: Path) -> None:
    subprocess.run(
        ["git", "archive", "--format=tar.gz", "-o", str(target), "HEAD"], cwd=source_dir, check=True
    )
    size_mb = target.stat().st_size / (1024 * 1024)
    if size_mb > _MAX_TARBALL_MB:
        raise CurationError(f"tarball {size_mb:.1f} MB exceeds {_MAX_TARBALL_MB} MB cap")


def _write_entry(
    *,
    corpus_root: Path,
    target_dir: Path,
    requirement: str,
    ac_list: list[dict],
    expected: dict,
    metadata: dict,
    seed_tarball: Path,
) -> None:
    corpus_root = corpus_root.resolve()
    target_dir = target_dir.resolve()
    try:
        target_dir.relative_to(corpus_root)
    except ValueError as e:
        raise CurationError(f"refuse: target {target_dir} outside corpus root {corpus_root}") from e

    target_dir.mkdir(parents=True, exist_ok=True)
    (target_dir / "requirement.md").write_text(scrub(requirement), encoding="utf-8")
    (target_dir / "acceptance-criteria.yaml").write_text(
        yaml.safe_dump({"version": 1, "ac_list": ac_list}, sort_keys=False), encoding="utf-8"
    )
    (target_dir / "expected-deliverables.yaml").write_text(
        yaml.safe_dump(expected, sort_keys=False), encoding="utf-8"
    )
    (target_dir / "metadata.yaml").write_text(
        yaml.safe_dump(metadata, sort_keys=False), encoding="utf-8"
    )
    # Move seed tarball in place
    (target_dir / "seed-project.tar.gz").write_bytes(seed_tarball.read_bytes())


def _prompt_pii(text: str) -> str:
    """Apply auto scrub, then prompt per interactive match."""
    text = scrub(text)
    hits = list(scan(text))
    for h in hits:
        print(f"[PII] {h.kind} at char {h.span[0]}: {h.text!r}")
        resp = _ask("redact this match?", "yn")
        if resp == "y":
            text = text.replace(h.text, f"<redacted-{h.kind}>")
        else:
            raise CurationError(
                f"unacknowledged {h.kind} in requirement; aborting (run curate.py again)"
            )
    return text


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python -m tests.evals.benchmark.curate",
        description="Interactively curate benchmark corpus entries.",
    )
    p.add_argument(
        "--db",
        type=Path,
        default=Path.home() / ".forge" / "run-history.db",
        help="Path to .forge/run-history.db",
    )
    p.add_argument("--corpus-root", type=Path, default=_CORPUS_ROOT)
    p.add_argument(
        "--source-repo",
        type=Path,
        required=False,
        help="Path to git repo matching source_run_id (for git archive)",
    )
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    candidates = _query_candidates(args.db)
    if not candidates:
        print(f"no eligible runs in {args.db}", file=sys.stderr)
        return 0

    for cand in candidates:
        print(f"\n--- candidate run {cand['id']} ---")
        print(f"requirement: {(cand['requirement'] or '')[:200]}")
        print(f"language/framework: {cand['language']}/{cand['framework']}")
        print(f"verdict={cand['verdict']} score={cand['score']} branch={cand['branch_name']}")
        resp = _ask("Include in corpus?")
        if resp == "q":
            break
        if resp != "y":
            continue
        slug = input("slug (kebab-case): ").strip()
        if not _SLUG_RE.match(slug):
            print("error: slug must match ^[a-z0-9-]+$", file=sys.stderr)
            continue
        complexity = input("complexity [S/M/L]: ").strip().upper()
        if complexity not in _COMPLEXITIES:
            print("error: complexity must be S/M/L", file=sys.stderr)
            continue
        domain = [
            s.strip() for s in input("domain tags (comma-separated): ").split(",") if s.strip()
        ]
        if args.source_repo is None:
            print("error: --source-repo required to archive seed; skipping", file=sys.stderr)
            continue
        requires_docker = _detect_requires_docker(args.source_repo)
        confirm = _ask(f"detected requires_docker={requires_docker}; confirm?", "yn")
        if confirm != "y":
            requires_docker = not requires_docker

        today = date.today().isoformat()
        target = args.corpus_root / f"{today}-{slug}"
        with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as tmp:
            tarball = Path(tmp.name)
        try:
            _archive(args.source_repo, tarball)
            clean_req = _prompt_pii(cand["requirement"] or "")
            _write_entry(
                corpus_root=args.corpus_root,
                target_dir=target,
                requirement=clean_req,
                ac_list=[],  # user hand-writes; seed empty per spec
                expected={
                    "version": 1,
                    "files_touched": {"expected_any_of": [], "must_not_touch": []},
                },
                metadata={
                    "version": 1,
                    "complexity": complexity,
                    "domain": domain or ["unknown"],
                    "language": cand["language"] or "unknown",
                    "framework": cand["framework"] or "unknown",
                    "source_run_id": cand["id"],
                    "requires_docker": requires_docker,
                    "os_compat": ["ubuntu-latest", "macos-latest", "windows-latest"],
                    "notes": f"PR: {cand.get('pr_url') or 'n/a'}",
                },
                seed_tarball=tarball,
            )
            print(f"wrote {target}")
        finally:
            tarball.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
