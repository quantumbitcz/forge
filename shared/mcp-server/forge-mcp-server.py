#!/usr/bin/env python3
"""Forge MCP Server — exposes pipeline intelligence to any MCP-capable AI client.

Read-only server. Queries .forge/ files and run-history.db.
No writes, no network, no dynamic code paths.
"""

import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

from mcp.server import Server
from mcp.server.stdio import stdio_server


# ---------------------------------------------------------------------------
# Project Discovery
# ---------------------------------------------------------------------------

def find_project_root() -> Path:
    """Locate the Forge project root directory."""
    # 1. Environment variable (set by /forge-init in .mcp.json)
    env_root = os.environ.get("FORGE_PROJECT_ROOT")
    if env_root:
        p = Path(env_root)
        if (p / ".forge").is_dir() or (p / ".claude").is_dir():
            return p

    # 2. Git root
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            p = Path(result.stdout.strip())
            if p.is_dir():
                return p
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # 3. Walk up from CWD
    current = Path.cwd()
    for parent in [current, *current.parents]:
        if (parent / ".forge").is_dir():
            return parent

    raise RuntimeError(
        "Could not locate Forge project. "
        "Set FORGE_PROJECT_ROOT or run from within a Forge-initialized repository."
    )


PROJECT_ROOT = find_project_root()
FORGE_DIR = PROJECT_ROOT / ".forge"
CLAUDE_DIR = PROJECT_ROOT / ".claude"


# ---------------------------------------------------------------------------
# Data Access Helpers
# ---------------------------------------------------------------------------

def read_json_file(path: Path) -> dict | None:
    """Read a JSON file, returning None if missing or corrupt."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def query_db(sql: str, params: tuple = (), db_name: str = "run-history.db") -> list[dict]:
    """Execute a SQL query against a .forge/ SQLite database."""
    db_path = FORGE_DIR / db_name
    if not db_path.is_file():
        return []
    try:
        conn = sqlite3.connect(str(db_path), timeout=5)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(sql, params).fetchall()
        conn.close()
        return [dict(row) for row in rows]
    except sqlite3.Error:
        return []


def query_fts(query: str, limit: int = 10) -> list[dict]:
    """Full-text search on run_search table."""
    db_path = FORGE_DIR / "run-history.db"
    if not db_path.is_file():
        return []
    try:
        conn = sqlite3.connect(str(db_path), timeout=5)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT run_id, requirement, verdict, score, "
            "snippet(run_search, 2, '**', '**', '...', 20) as snippet "
            "FROM run_search WHERE run_search MATCH ? LIMIT ?",
            (query, limit)
        ).fetchall()
        conn.close()
        return [dict(row) for row in rows]
    except sqlite3.Error:
        return []


def read_forge_log(query: str, limit: int = 20) -> list[dict]:
    """Keyword search in forge-log.md with context lines."""
    log_path = CLAUDE_DIR / "forge-log.md"
    if not log_path.is_file():
        return []
    try:
        lines = log_path.read_text(encoding="utf-8").splitlines()
        pattern = re.compile(re.escape(query), re.IGNORECASE)
        results = []
        for i, line in enumerate(lines):
            if pattern.search(line):
                start = max(0, i - 2)
                end = min(len(lines), i + 3)
                results.append({
                    "line_number": i + 1,
                    "context": "\n".join(lines[start:end])
                })
                if len(results) >= limit:
                    break
        return results
    except OSError:
        return []


def get_plugin_version() -> str:
    """Read Forge plugin version from plugin.json."""
    # Walk up from this script to find plugin.json
    script_dir = Path(__file__).resolve().parent
    for parent in [script_dir, *script_dir.parents]:
        pj = parent / "plugin.json"
        if pj.is_file():
            data = read_json_file(pj)
            if data and "version" in data:
                return data["version"]
    return "unknown"


# ---------------------------------------------------------------------------
# Server Instance
# ---------------------------------------------------------------------------

server = Server("forge-mcp-server", version=get_plugin_version())


# ---------------------------------------------------------------------------
# Category 1: Pipeline State (3 tools)
# ---------------------------------------------------------------------------

@server.tool()
async def forge_pipeline_status() -> str:
    """Current pipeline state — stage, score, verdict, convergence info."""
    state = read_json_file(FORGE_DIR / "state.json")
    if state is None:
        return json.dumps({"status": "no_active_run"})
    return json.dumps({
        "story_id": state.get("story_id"),
        "story_state": state.get("story_state"),
        "score": state.get("score"),
        "verdict": state.get("verdict"),
        "total_iterations": state.get("total_iterations"),
        "convergence_state": state.get("convergence_state"),
        "active_component": state.get("active_component"),
        "wall_time_seconds": state.get("wall_time_seconds"),
        "estimated_cost_usd": state.get("estimated_cost_usd"),
    })


@server.tool()
async def forge_pipeline_evidence() -> str:
    """Pre-ship verification results from the last completed run."""
    evidence = read_json_file(FORGE_DIR / "evidence.json")
    if evidence is None:
        return json.dumps({"status": "no_evidence"})
    return json.dumps(evidence)


@server.tool()
async def forge_agent_card() -> str:
    """Project capabilities and available Forge skills."""
    card = read_json_file(FORGE_DIR / "agent-card.json")
    if card is None:
        return json.dumps({"status": "not_initialized", "hint": "Run /forge-init first"})
    return json.dumps(card)


# ---------------------------------------------------------------------------
# Category 2: Run History (3 tools)
# ---------------------------------------------------------------------------

@server.tool()
async def forge_runs_list(
    limit: int = 10,
    verdict: str = "",
    mode: str = "",
    since: str = "",
) -> str:
    """List recent pipeline runs with key metrics.

    Args:
        limit: Max runs to return (1-100, default 10)
        verdict: Filter by verdict (PASS, CONCERNS, FAIL, ABORTED)
        mode: Filter by mode (standard, bugfix, migration, bootstrap, testing, refactor, performance)
        since: ISO 8601 date — only runs after this date
    """
    if not (FORGE_DIR / "run-history.db").is_file():
        return json.dumps({"error": "No run history yet. Complete a pipeline run first."})

    clauses = []
    params: list = []
    if verdict:
        clauses.append("verdict = ?")
        params.append(verdict.upper())
    if mode:
        clauses.append("mode = ?")
        params.append(mode.lower())
    if since:
        clauses.append("started_at >= ?")
        params.append(since)

    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    limit = max(1, min(limit, 100))
    params.append(limit)

    sql = (
        "SELECT id, story_id, requirement, mode, started_at, verdict, "
        "score, total_iterations, wall_time_seconds, playbook_id "
        f"FROM runs{where} ORDER BY started_at DESC LIMIT ?"
    )
    return json.dumps(query_db(sql, tuple(params)))


@server.tool()
async def forge_runs_search(query: str, limit: int = 10) -> str:
    """Full-text search across all pipeline runs.

    Args:
        query: Search text (FTS5 syntax — plain words, "phrases", OR/AND/NOT)
        limit: Max results (1-50, default 10)
    """
    if not (FORGE_DIR / "run-history.db").is_file():
        return json.dumps({"error": "No run history yet. Complete a pipeline run first."})
    limit = max(1, min(limit, 50))
    return json.dumps(query_fts(query, limit))


@server.tool()
async def forge_run_detail(run_id: str) -> str:
    """Deep dive into a specific run — findings, timings, learnings.

    Args:
        run_id: The run ID to inspect
    """
    if not (FORGE_DIR / "run-history.db").is_file():
        return json.dumps({"error": "No run history yet. Complete a pipeline run first."})

    runs = query_db("SELECT * FROM runs WHERE id = ?", (run_id,))
    if not runs:
        return json.dumps({"error": f"Run '{run_id}' not found"})

    findings = query_db("SELECT * FROM findings WHERE run_id = ?", (run_id,))
    timings = query_db("SELECT * FROM stage_timings WHERE run_id = ?", (run_id,))
    learnings_rows = query_db("SELECT * FROM learnings WHERE run_id = ?", (run_id,))
    playbook = query_db("SELECT * FROM playbook_runs WHERE run_id = ?", (run_id,))

    severity_counts = {"CRITICAL": 0, "WARNING": 0, "INFO": 0}
    for f in findings:
        sev = f.get("severity", "INFO")
        if sev in severity_counts:
            severity_counts[sev] += 1

    return json.dumps({
        "run": runs[0],
        "findings": findings,
        "findings_summary": severity_counts,
        "stage_timings": timings,
        "learnings": learnings_rows,
        "playbook_run": playbook[0] if playbook else None,
    })


# ---------------------------------------------------------------------------
# Category 3: Quality Intelligence (3 tools)
# ---------------------------------------------------------------------------

@server.tool()
async def forge_findings_recurring(
    min_occurrences: int = 3,
    severity: str = "",
    limit: int = 20,
) -> str:
    """Findings recurring across multiple runs — convention candidates.

    Args:
        min_occurrences: Minimum times a category must appear (default 3)
        severity: Filter by severity (CRITICAL, WARNING, INFO)
        limit: Max results (default 20)
    """
    if not (FORGE_DIR / "run-history.db").is_file():
        return json.dumps({"error": "No run history yet. Complete a pipeline run first."})

    sev_filter = "AND severity = ? " if severity else ""
    params: list = []
    if severity:
        params.append(severity.upper())
    params.extend([min_occurrences, limit])

    sql = (
        "SELECT category, file_path, COUNT(*) as occurrence_count, "
        "GROUP_CONCAT(DISTINCT severity) as severities, "
        "MIN(r.started_at) as first_seen, MAX(r.started_at) as last_seen, "
        "MAX(f.message) as sample_message, "
        "ROUND(AVG(f.resolved) * 100, 1) as resolved_rate_pct "
        "FROM findings f JOIN runs r ON f.run_id = r.id "
        f"{sev_filter}"
        "GROUP BY category, file_path "
        "HAVING COUNT(*) >= ? "
        "ORDER BY occurrence_count DESC LIMIT ?"
    )
    return json.dumps(query_db(sql, tuple(params)))


@server.tool()
async def forge_learnings_active(
    type: str = "",
    confidence: str = "",
    limit: int = 20,
) -> str:
    """Active PREEMPT items with effectiveness stats.

    Args:
        type: Filter by type (PREEMPT, PATTERN, TUNING, PREEMPT_CRITICAL)
        confidence: Filter by confidence (HIGH, MEDIUM, LOW)
        limit: Max results (default 20)
    """
    if not (FORGE_DIR / "run-history.db").is_file():
        return json.dumps({"error": "No run history yet. Complete a pipeline run first."})

    clauses = []
    params: list = []
    if type:
        clauses.append("l.type = ?")
        params.append(type.upper())
    if confidence:
        clauses.append("l.confidence = ?")
        params.append(confidence.upper())

    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    params.append(limit)

    sql = (
        "SELECT l.type, l.content, l.domain, l.confidence, l.source_agent, "
        "SUM(l.applied_count) as total_applied, "
        "MIN(r.started_at) as first_seen, MAX(r.started_at) as last_seen "
        f"FROM learnings l JOIN runs r ON l.run_id = r.id{where} "
        "GROUP BY l.type, l.content "
        "ORDER BY total_applied DESC LIMIT ?"
    )
    return json.dumps(query_db(sql, tuple(params)))


@server.tool()
async def forge_log_search(query: str, limit: int = 20) -> str:
    """Search the institutional memory (forge-log.md) by keyword.

    Args:
        query: Search keywords (case-insensitive substring match)
        limit: Max matching line groups (default 20)
    """
    results = read_forge_log(query, limit)
    if not results:
        return json.dumps({"results": [], "hint": "No matches. Try different keywords."})
    return json.dumps({"results": results})


# ---------------------------------------------------------------------------
# Category 4: Playbook Analytics (2 tools)
# ---------------------------------------------------------------------------

@server.tool()
async def forge_playbooks_list() -> str:
    """Available playbooks with usage statistics."""
    analytics = read_json_file(FORGE_DIR / "playbook-analytics.json")
    if analytics is None:
        # Fall back to DB if analytics file missing
        if (FORGE_DIR / "run-history.db").is_file():
            return json.dumps(query_db(
                "SELECT playbook_id, COUNT(*) as run_count, "
                "SUM(CASE WHEN r.verdict='PASS' THEN 1 ELSE 0 END) as success_count, "
                "ROUND(AVG(r.score), 1) as avg_score, MAX(r.started_at) as last_used "
                "FROM playbook_runs pr JOIN runs r ON pr.run_id = r.id "
                "GROUP BY playbook_id ORDER BY run_count DESC"
            ))
        return json.dumps([])

    # Merge analytics JSON with DB data if available
    return json.dumps(analytics)


@server.tool()
async def forge_playbook_effectiveness(playbook_id: str) -> str:
    """Per-playbook effectiveness analysis including refinement proposals.

    Args:
        playbook_id: The playbook to analyze
    """
    result: dict = {"playbook_id": playbook_id}

    # DB stats
    if (FORGE_DIR / "run-history.db").is_file():
        runs = query_db(
            "SELECT r.score, r.verdict, r.started_at "
            "FROM playbook_runs pr JOIN runs r ON pr.run_id = r.id "
            "WHERE pr.playbook_id = ? ORDER BY r.started_at",
            (playbook_id,)
        )
        if runs:
            scores = [r["score"] for r in runs]
            result["total_runs"] = len(runs)
            result["success_rate"] = round(
                sum(1 for r in runs if r["verdict"] == "PASS") / len(runs), 2
            )
            result["avg_score"] = round(sum(scores) / len(scores), 1)
            result["score_trend"] = (
                "improving" if len(scores) >= 2 and scores[-1] > scores[0]
                else "declining" if len(scores) >= 2 and scores[-1] < scores[0]
                else "stable"
            )

        # Common findings for this playbook
        common = query_db(
            "SELECT f.category, COUNT(*) as cnt "
            "FROM findings f JOIN playbook_runs pr ON f.run_id = pr.run_id "
            "WHERE pr.playbook_id = ? GROUP BY f.category "
            "HAVING cnt >= 2 ORDER BY cnt DESC LIMIT 10",
            (playbook_id,)
        )
        result["common_findings"] = common

    # Refinement proposals
    refinement_path = FORGE_DIR / "playbook-refinements" / f"{playbook_id}.json"
    proposals = read_json_file(refinement_path)
    result["refinement_proposals"] = proposals.get("proposals", []) if proposals else []

    return json.dumps(result)


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------
# Note: The mcp SDK auto-discovers @server.tool() decorated functions.
# No manual @server.list_tools() handler needed.

async def main():
    async with stdio_server() as (read_stream, write_stream):
        init_options = server.create_initialization_options()
        await server.run(read_stream, write_stream, init_options)


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
