# Forge MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Python MCP server that exposes Forge's pipeline intelligence (state, run history, findings, playbook analytics) as 11 queryable tools accessible from any MCP-capable AI client.

**Architecture:** Single-file Python server (`forge-mcp-server.py`) using the `mcp` SDK. Runs as stdio server spawned by the AI client. Read-only — queries `.forge/` files and `run-history.db`. Auto-provisioned by `/forge-init` into `.mcp.json`.

**Tech Stack:** Python 3.10+, `mcp` SDK, `sqlite3` stdlib, `json` stdlib

**Spec:** `docs/superpowers/specs/2026-04-16-mcp-server-design.md`
**Depends on:** Run History Store plan (must be complete first — `run-history.db` schema needed)

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `shared/mcp-server/forge-mcp-server.py` | MCP server (single file, ~400 lines) |
| Create | `shared/mcp-server/requirements.txt` | Python dependencies (`mcp>=1.0.0`) |
| Modify | `skills/forge-init/SKILL.md` | Add MCP server provisioning steps |
| Create | `tests/contract/mcp-server.bats` | Contract tests |
| Modify | `shared/state-schema.md` | Document `.mcp.json` generation |
| Modify | `CLAUDE.md` | Add MCP server feature documentation |

---

### Task 1: Create requirements.txt

**Files:**
- Create: `shared/mcp-server/requirements.txt`

- [ ] **Step 1: Create directory and requirements file**

```bash
mkdir -p shared/mcp-server
```

Write `shared/mcp-server/requirements.txt`:

```
mcp>=1.0.0
```

- [ ] **Step 2: Commit**

```bash
git add shared/mcp-server/requirements.txt
git commit -m "feat(mcp-server): add Python requirements"
```

---

### Task 2: Write the MCP Server

**Files:**
- Create: `shared/mcp-server/forge-mcp-server.py`

This is the core deliverable. The server is a single Python file with 4 sections: project discovery, data access helpers, 11 tool implementations, and entry point.

- [ ] **Step 1: Write project discovery and data access helpers**

Write the first section of `shared/mcp-server/forge-mcp-server.py`:

```python
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
```

- [ ] **Step 2: Write Category 1 tools (Pipeline State)**

Append to `forge-mcp-server.py`:

```python
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
```

- [ ] **Step 3: Write Category 2 tools (Run History)**

Append to `forge-mcp-server.py`:

```python
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
```

- [ ] **Step 4: Write Category 3 tools (Quality Intelligence)**

Append to `forge-mcp-server.py`:

```python
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
```

- [ ] **Step 5: Write Category 4 tools (Playbook Analytics) and entry point**

Append to `forge-mcp-server.py`:

```python
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
```

- [ ] **Step 6: Validate Python syntax**

```bash
python3 -c "import ast; ast.parse(open('shared/mcp-server/forge-mcp-server.py').read()); print('OK')"
```

Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add shared/mcp-server/forge-mcp-server.py
git commit -m "feat(mcp-server): implement Forge MCP server with 11 tools"
```

---

### Task 3: Update forge-init Skill

**Files:**
- Modify: `skills/forge-init/SKILL.md`

- [ ] **Step 1: Add MCP server provisioning section**

In the forge-init skill, after the existing MCP Integration Detection section and before the final summary, add:

```markdown
### MCP Server Provisioning

After detecting the environment, provision the Forge MCP server for cross-platform AI client access:

1. **Check Python version:**
   ```bash
   python3 --version 2>/dev/null
   ```
   Parse the output. If Python 3.10+ is available, proceed. Otherwise log:
   `"ℹ️ Python 3.10+ not found. Forge MCP server skipped. Forge works without it."`
   and skip steps 2-4.

2. **Check mcp package:**
   ```bash
   python3 -c "import mcp" 2>/dev/null
   ```
   If import fails, attempt install:
   - `pip install --user mcp 2>/dev/null || pip3 install --user mcp 2>/dev/null || uv pip install mcp 2>/dev/null`
   If all fail, log INFO and skip.

3. **Write .mcp.json entry:**
   Read existing `.mcp.json` at project root (create `{}` if absent). Merge the `forge` server entry:
   ```json
   {
     "mcpServers": {
       "forge": {
         "command": "python3",
         "args": ["{CLAUDE_PLUGIN_ROOT}/shared/mcp-server/forge-mcp-server.py"],
         "env": {
           "FORGE_PROJECT_ROOT": "{project_root}"
         }
       }
     }
   }
   ```
   If `forge` entry already exists, update the `args` path (idempotent).

4. **Display result:**
   ```
   ✅ Forge MCP server provisioned in .mcp.json
      Any MCP-capable AI client can now query pipeline state, run history, and findings.
   ```
   Or if skipped:
   ```
   ℹ️ MCP server not provisioned (Python 3.10+ or mcp package unavailable)
   ```

**Config gate:** Skip if `mcp_server.enabled: false` in `forge-config.md`.
```

- [ ] **Step 2: Commit**

```bash
git add skills/forge-init/SKILL.md
git commit -m "feat(forge-init): add MCP server auto-provisioning"
```

---

### Task 4: Add Config Validation

**Files:**
- Modify: `shared/preflight-constraints.md`

- [ ] **Step 1: Add `mcp_server.*` validation rules**

In `shared/preflight-constraints.md`, add a new section:

```markdown
### MCP Server

| Field | Type | Default | Valid Range | Validation |
|-------|------|---------|-------------|------------|
| `mcp_server.enabled` | boolean | `true` | true/false | — |
| `mcp_server.python_min_version` | string | `"3.10"` | Semver string | WARN if set below 3.10 |
```

- [ ] **Step 2: Commit**

```bash
git add shared/preflight-constraints.md
git commit -m "docs(preflight): add mcp_server config validation rules"
```

---

### Task 5: Write Contract Tests

**Files:**
- Create: `tests/contract/mcp-server.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# Contract tests: Forge MCP server structure and integration.

load '../helpers/test-helpers'

SERVER_FILE="$PLUGIN_ROOT/shared/mcp-server/forge-mcp-server.py"
REQUIREMENTS="$PLUGIN_ROOT/shared/mcp-server/requirements.txt"
INIT_SKILL="$PLUGIN_ROOT/skills/forge-init/SKILL.md"

# ---------------------------------------------------------------------------
# 1. Server file exists and has valid Python syntax
# ---------------------------------------------------------------------------
@test "mcp-server: forge-mcp-server.py exists" {
  [[ -f "$SERVER_FILE" ]]
}

@test "mcp-server: forge-mcp-server.py has valid Python syntax" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  python3 -c "import ast; ast.parse(open('$SERVER_FILE').read())"
}

# ---------------------------------------------------------------------------
# 2. Requirements file
# ---------------------------------------------------------------------------
@test "mcp-server: requirements.txt exists" {
  [[ -f "$REQUIREMENTS" ]]
}

@test "mcp-server: requirements.txt contains mcp" {
  grep -q "mcp" "$REQUIREMENTS" \
    || fail "requirements.txt does not list mcp dependency"
}

# ---------------------------------------------------------------------------
# 3. All 11 tools defined
# ---------------------------------------------------------------------------
@test "mcp-server: defines 11 @server.tool() functions" {
  local count
  count=$(grep -c "@server.tool()" "$SERVER_FILE")
  [[ "$count" -eq 11 ]] || fail "Expected 11 tools, found $count"
}

# ---------------------------------------------------------------------------
# 4. Tool names present
# ---------------------------------------------------------------------------
@test "mcp-server: defines forge_pipeline_status tool" {
  grep -q "def forge_pipeline_status" "$SERVER_FILE"
}

@test "mcp-server: defines forge_pipeline_evidence tool" {
  grep -q "def forge_pipeline_evidence" "$SERVER_FILE"
}

@test "mcp-server: defines forge_agent_card tool" {
  grep -q "def forge_agent_card" "$SERVER_FILE"
}

@test "mcp-server: defines forge_runs_list tool" {
  grep -q "def forge_runs_list" "$SERVER_FILE"
}

@test "mcp-server: defines forge_runs_search tool" {
  grep -q "def forge_runs_search" "$SERVER_FILE"
}

@test "mcp-server: defines forge_run_detail tool" {
  grep -q "def forge_run_detail" "$SERVER_FILE"
}

@test "mcp-server: defines forge_findings_recurring tool" {
  grep -q "def forge_findings_recurring" "$SERVER_FILE"
}

@test "mcp-server: defines forge_learnings_active tool" {
  grep -q "def forge_learnings_active" "$SERVER_FILE"
}

@test "mcp-server: defines forge_log_search tool" {
  grep -q "def forge_log_search" "$SERVER_FILE"
}

@test "mcp-server: defines forge_playbooks_list tool" {
  grep -q "def forge_playbooks_list" "$SERVER_FILE"
}

@test "mcp-server: defines forge_playbook_effectiveness tool" {
  grep -q "def forge_playbook_effectiveness" "$SERVER_FILE"
}

# ---------------------------------------------------------------------------
# 5. Security: no write operations
# ---------------------------------------------------------------------------
@test "mcp-server: does not write to files (read-only)" {
  ! grep -qE '\.write\(|open\(.*(w|a)\)|Path.*write_text' "$SERVER_FILE" \
    || fail "Server contains write operations — must be read-only"
}

# ---------------------------------------------------------------------------
# 6. Integration: forge-init references MCP server
# ---------------------------------------------------------------------------
@test "mcp-server: forge-init skill references MCP server provisioning" {
  grep -q "mcp-server" "$INIT_SKILL" || grep -q "MCP Server" "$INIT_SKILL" \
    || fail "forge-init SKILL.md does not reference MCP server provisioning"
}

# ---------------------------------------------------------------------------
# 7. Server reads plugin version
# ---------------------------------------------------------------------------
@test "mcp-server: reads plugin version from plugin.json" {
  grep -q "plugin.json" "$SERVER_FILE" \
    || fail "Server does not reference plugin.json for version"
}
```

- [ ] **Step 2: Verify tests pass**

```bash
./tests/lib/bats-core/bin/bats tests/contract/mcp-server.bats
```

- [ ] **Step 3: Commit**

```bash
git add tests/contract/mcp-server.bats
git commit -m "test(mcp-server): add contract tests for server structure and integration"
```

---

### Task 6: Update CLAUDE.md and State Schema

**Note:** CLAUDE.md was already modified by Plan 1 (Run History Store). Add entries after those from Plan 1.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add MCP server to CLAUDE.md features table**

Add row to v2.0 features table (after the F29 Run History Store row added by Plan 1):

```
| MCP server (F30) | `mcp_server.*` | Python stdio MCP server exposing pipeline intelligence to any AI client. 11 tools. Auto-provisioned by `/forge-init` |
```

- [ ] **Step 2: Add to CLAUDE.md architecture section**

In the Architecture section, after the existing layers, add a note:

```
4. **MCP interface** (`shared/mcp-server/`) — Python MCP server exposing `.forge/` data to any MCP-capable AI client. Read-only. Optional (requires Python 3.10+).
```

- [ ] **Step 3: Update state-schema.md**

In the "Related Files" section, add a note about `.mcp.json`:

```
| `.mcp.json` | Project root | MCP server configuration for AI clients (generated by `/forge-init`) |
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md shared/state-schema.md
git commit -m "docs: add MCP server feature to CLAUDE.md and state-schema"
```
