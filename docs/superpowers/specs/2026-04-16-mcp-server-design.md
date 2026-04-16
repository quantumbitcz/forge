# Spec 1: Forge MCP Server (Python)

**Status:** Approved
**Author:** Denis Sajnar
**Date:** 2026-04-16
**Depends on:** Spec 2 (Run History Store)
**Depended on by:** Spec 3 (Self-Improving Playbooks) — exposes playbook analytics

---

## Problem

Forge's pipeline intelligence — findings, learnings, run history, playbook analytics, code graph — is locked inside Claude Code's plugin system. Developers using Gemini CLI, VS Code Copilot, Cursor, Windsurf, JetBrains AI, or any other MCP-capable client cannot query Forge's accumulated knowledge. The data exists in `.forge/` but there is no standard interface to access it.

MCP (Model Context Protocol) has become the universal tool integration standard. Every major AI coding client supports it. A Forge MCP server makes all pipeline intelligence queryable from any platform.

## Solution

A lightweight Python MCP server (`forge-mcp-server.py`) that exposes Forge's data as MCP tools. Runs as a stdio server — the AI client spawns the process on demand and communicates via stdin/stdout. No persistent daemon, no ports, no auth, no networking.

## Non-Goals

- **Not running the pipeline** — the MCP server is read-only. Pipeline execution stays in Claude Code skills.
- **Not replacing Claude Code skills** — `forge-insights`, `forge-ask`, `forge-history` continue to work. The MCP server provides the same data to non-Claude-Code clients.
- **Not a REST API** — stdio MCP is the transport. If HTTP is needed later, the `mcp` SDK supports StreamableHTTP with minimal changes.

## Architecture

The server sits between AI clients and Forge's data files:

- AI Client (Gemini CLI, Cursor, VS Code Copilot, etc.) communicates via stdio (stdin/stdout, JSON-RPC 2.0) with forge-mcp-server.py
- The server reads from: `.forge/state.json`, `.forge/run-history.db`, `.forge/evidence.json`, `.forge/agent-card.json`, `.forge/playbook-analytics.json`, `.forge/playbook-refinements/`, `.forge/code-graph.db`, `.claude/forge-log.md`

### Runtime Model

- **Transport:** stdio (universal MCP support)
- **Lifecycle:** Spawned by AI client per session, killed when session ends
- **State:** Stateless — every tool call reads fresh data from disk
- **Concurrency:** Single-threaded (one client at a time per spawned process). Multiple clients can spawn separate processes.

## Requirements

- **Python 3.10+** (3.10 is the floor for `match` statements and modern typing; 3.14 is the latest stable as of April 2026 but no 3.14-specific features are required)
- **`mcp` SDK** (`pip install mcp` — official Anthropic MCP Python package, sole external dependency)
- **`sqlite3`** (Python stdlib — for run history and code graph queries)
- **`json`** (Python stdlib — for .forge/*.json reads)

### Dependency Management

`shared/mcp-server/requirements.txt`:
```
mcp>=1.0.0
```

No virtual environment required for a single dependency. The server imports `mcp` and stdlib modules only.

## Project Discovery

The server must locate `.forge/` and `.claude/` directories. Discovery order:

1. `FORGE_PROJECT_ROOT` environment variable (set by `/forge-init` in `.mcp.json`)
2. `git rev-parse --show-toplevel` from CWD
3. Walk up from CWD looking for `.forge/` directory
4. Exit with clear error: "Could not locate Forge project. Set FORGE_PROJECT_ROOT or run from within a Forge-initialized repository."

## Server Metadata

The MCP `initialize` response includes:
- `server_info.name`: `"forge-mcp-server"`
- `server_info.version`: Read from `plugin.json` version field (e.g., `"2.7.0"`)

## Tools (11 tools, 4 categories)

### Category 1: Pipeline State (3 tools)

#### `forge_pipeline_status`

Returns current pipeline state including stage, score, verdict, and convergence info.

**Parameters:** None

**Source:** `.forge/state.json`
**Returns:** JSON with `story_id`, `story_state`, `score`, `verdict`, `total_iterations`, `convergence_state`, `active_component`, `wall_time_seconds`, `estimated_cost_usd`. Returns `{"status": "no_active_run"}` if `state.json` absent.

#### `forge_pipeline_evidence`

Returns pre-ship verification results from the last completed run.

**Parameters:** None

**Source:** `.forge/evidence.json`
**Returns:** Full evidence JSON (verdict, build/test/lint/review results, timestamp). Returns `{"status": "no_evidence"}` if absent.

#### `forge_agent_card`

Returns project capabilities and available skills.

**Parameters:** None

**Source:** `.forge/agent-card.json`
**Returns:** Agent card JSON (name, version, capabilities, skills). Returns `{"status": "not_initialized", "hint": "Run /forge-init first"}` if absent.

### Category 2: Run History (3 tools)

Requires `.forge/run-history.db` from Spec 2.

#### `forge_runs_list`

Lists recent pipeline runs with key metrics.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `limit` | integer | no | 10 | Max runs to return (1-100) |
| `verdict` | string | no | all | Filter: PASS, CONCERNS, FAIL, ABORTED |
| `mode` | string | no | all | Filter: standard, bugfix, migration, bootstrap, testing, refactor, performance |
| `since` | string | no | | ISO 8601 date — only runs after this date |

**Source:** `run-history.db` -> `runs` table
**Returns:** JSON array of run summaries: `[{id, story_id, requirement, mode, started_at, verdict, score, total_iterations, wall_time_seconds, playbook_id}]`

#### `forge_runs_search`

Full-text search across all pipeline runs — requirements, findings, learnings.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `query` | string | yes | | Search text (FTS5 syntax: plain words, phrases in quotes, OR/AND/NOT) |
| `limit` | integer | no | 10 | Max results (1-50) |

**Source:** `run-history.db` -> `run_search` FTS5 virtual table
**Returns:** JSON array of matching runs with relevance snippets: `[{run_id, requirement, verdict, score, snippet}]` where `snippet` is the FTS5 `snippet()` output highlighting matched terms.

#### `forge_run_detail`

Deep dive into a specific run — all findings, timings, learnings.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `run_id` | string | yes | The run ID to inspect |

**Source:** `run-history.db` -> joined query across `runs`, `findings`, `stage_timings`, `learnings`, `playbook_runs`
**Returns:** JSON object with full run data including run metadata, all findings with severity summary, stage timings, extracted learnings, and playbook data if applicable.

### Category 3: Quality Intelligence (2 tools)

#### `forge_findings_recurring`

Findings that recur across multiple runs — these are convention candidates.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `min_occurrences` | integer | no | 3 | Minimum times a finding category must appear |
| `severity` | string | no | all | Filter by severity |
| `limit` | integer | no | 20 | Max results |

**Source:** `run-history.db` -> `findings` aggregated by `(category, file_path)`
**Returns:** JSON array: `[{category, file_path, occurrence_count, severities, first_seen, last_seen, sample_message, resolved_rate}]` ordered by `occurrence_count DESC`.

#### `forge_learnings_active`

Active PREEMPT items with effectiveness statistics.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `type` | string | no | all | Filter: PREEMPT, PATTERN, TUNING, PREEMPT_CRITICAL |
| `confidence` | string | no | all | Filter: HIGH, MEDIUM, LOW |
| `limit` | integer | no | 20 | Max results |

**Source:** `run-history.db` -> `learnings` table + `.claude/forge-log.md` for PREEMPT effectiveness
**Returns:** JSON array: `[{type, content, domain, confidence, source_agent, applied_count, first_seen, last_seen}]`

#### `forge_log_search`

Keyword search across the institutional memory (`forge-log.md`).

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `query` | string | yes | | Search keywords (case-insensitive substring match) |
| `limit` | integer | no | 20 | Max matching lines to return |

**Source:** `.claude/forge-log.md`
**Returns:** JSON array of matching line groups: `[{line_number, context}]` where `context` includes 2 lines before and after each match. This covers historical data predating the SQLite run history store.

### Category 4: Playbook Analytics (2 tools)

#### `forge_playbooks_list`

Available playbooks with usage statistics.

**Parameters:** None

**Source:** `.forge/playbook-analytics.json` + `run-history.db` -> `playbook_runs`
**Returns:** JSON array: `[{playbook_id, description, run_count, success_count, avg_score, last_used}]`

#### `forge_playbook_effectiveness`

Per-playbook effectiveness analysis including refinement proposals.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `playbook_id` | string | yes | The playbook to analyze |

**Source:** `run-history.db` -> `playbook_runs` + `.forge/playbook-refinements/{playbook_id}.json`
**Returns:** JSON object with playbook_id, total_runs, success_rate, avg_score, score_trend, common_findings array, refinement_proposals from Spec 3, and version_history.

## Auto-Provisioning

`/forge-init` is extended to set up the MCP server.

### Provisioning Steps

1. **Check Python 3.10+:** Run `python3 --version`, parse output. If unavailable or older than 3.10, log INFO: "Python 3.10+ not found. MCP server skipped. Forge works without it." and skip remaining steps.

2. **Check `mcp` package:** Run `python3 -c "import mcp"`. If import fails, attempt install:
   - Try `pip install --user mcp` (or `pip3 install --user mcp`) — `--user` avoids PEP 668 externally-managed-environment errors
   - If pip unavailable or fails, try `uv pip install mcp`
   - If all install attempts fail, log INFO and skip

3. **Write `.mcp.json` entry:** Add to project root `.mcp.json` (create if absent, merge if exists):
   ```json
   {
     "mcpServers": {
       "forge": {
         "command": "python3",
         "args": ["{plugin_path}/shared/mcp-server/forge-mcp-server.py"],
         "env": {
           "FORGE_PROJECT_ROOT": "{project_root}"
         }
       }
     }
   }
   ```

4. **Verify:** Attempt to spawn the server with a `tools/list` request. If it responds, log success. If not, log WARNING with diagnostic info.

### Idempotency

Running `/forge-init` again does not duplicate the entry. It updates the `args` path if the plugin location changed.

## Graceful Degradation

Each tool degrades independently — a failure in one never crashes the server or affects other tools.

| Condition | Behavior |
|-----------|----------|
| `.forge/state.json` missing | `forge_pipeline_status` returns `{"status": "no_active_run"}` |
| `.forge/run-history.db` missing | Run history tools return `{"error": "No run history yet. Complete a pipeline run first."}` |
| `.forge/evidence.json` missing | `forge_pipeline_evidence` returns `{"status": "no_evidence"}` |
| `.forge/agent-card.json` missing | `forge_agent_card` returns `{"status": "not_initialized"}` |
| `.forge/playbook-analytics.json` missing | Playbook tools return empty results |
| `.forge/playbook-refinements/` missing | `forge_playbook_effectiveness` returns proposals as `[]` |
| SQLite database locked | Retry once (5s busy_timeout via WAL mode), then return `{"error": "Database busy. Try again."}` |
| Malformed JSON in `.forge/*.json` | Return `{"error": "Corrupt file: {filename}. Re-run the pipeline."}` |

## Security

- **Read-only:** The server never writes to `.forge/`, `.claude/`, or any project files. No tool has write capability.
- **No network access:** stdio transport only. The process has no listeners, no sockets, no HTTP.
- **No secrets exposure:** The server filters `forge-config.md` content — API keys, tokens, and credential fields are never returned. Config snapshot in `runs` table only includes scoring/convergence/model settings.
- **File access scope:** Only reads from `.forge/` and `.claude/forge-*.md`. No access to source code, `.env`, credentials, or files outside the project.
- **No dynamic code execution:** All tools are pure data reads. Only safe stdlib operations (json.load, sqlite3 parameterized queries, pathlib reads). No shell invocations except initial `git rev-parse` for project discovery.

## File Layout

```
shared/mcp-server/
    forge-mcp-server.py          # Main server (single file)
    requirements.txt             # mcp>=1.0.0

shared/run-history/
    run-history.md               # Schema reference + query cookbook
    migrations/
        001-initial.sql          # Run history schema DDL (owned by Spec 2)
```

## Server Structure

The server is a single Python file with clear sections:

1. Project Discovery — find_project_root()
2. Data Access Helpers — read_json(), query_db(), query_fts()
3. Tool Implementations — 11 async tool functions decorated with @server.tool()
4. Entry Point — server.run(transport=stdio_server)

## Configuration

New section in `forge-config.md`:

```yaml
mcp_server:
  enabled: true                # Master switch for MCP server provisioning
  python_min_version: "3.10"   # Minimum Python version (3.10+ for match statements)
```

The MCP server itself reads `run_history.*` config from `forge-config.md` for retention and query defaults.

## Integration with Existing Systems

| System | Integration |
|--------|-------------|
| `/forge-init` | Provisions MCP server entry in `.mcp.json` |
| `fg-700-retrospective` | Writes to `run-history.db` (Spec 2) which the MCP server reads |
| `forge-insights` | Can optionally delegate to MCP server tools or query DB directly |
| `forge-ask` | FTS5 queries available both via skill and MCP tool |
| `shared/mcp-detection.md` | No change — this is a Forge-provided MCP server, not an external one |
| A2A HTTP transport | Complementary — A2A is for cross-repo pipeline coordination, MCP is for AI client queries |

## Testing

- Structural test: verify `shared/mcp-server/forge-mcp-server.py` exists and has valid Python syntax
- Structural test: verify `requirements.txt` contains `mcp`
- Structural test: verify all 11 tools are defined (grep for `@server.tool`)
- Contract test: verify `forge-init` skill references MCP server provisioning
- Contract test: verify `state-schema.md` documents `.mcp.json` generation
