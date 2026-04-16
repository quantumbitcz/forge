-- Run History Store Schema v1
-- Location: .forge/run-history.db
-- Written by: fg-700-retrospective (Stage 9 LEARN)
-- Survives: /forge-reset (same as explore-cache.json)

PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
PRAGMA user_version=1;

CREATE TABLE IF NOT EXISTS runs (
    id              TEXT    PRIMARY KEY,
    story_id        TEXT    NOT NULL,
    requirement     TEXT    NOT NULL,
    mode            TEXT    NOT NULL,
    domain_area     TEXT,
    risk_level      TEXT,
    started_at      TEXT    NOT NULL,
    finished_at     TEXT,
    verdict         TEXT    NOT NULL,
    score           INTEGER NOT NULL,
    score_trajectory TEXT,
    total_iterations INTEGER NOT NULL DEFAULT 1,
    wall_time_seconds REAL,
    estimated_cost_usd REAL,
    playbook_id     TEXT,
    branch_name     TEXT,
    pr_url          TEXT,
    language        TEXT,
    framework       TEXT,
    config_snapshot TEXT,
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%f', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_runs_started_at ON runs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_verdict ON runs(verdict);
CREATE INDEX IF NOT EXISTS idx_runs_playbook ON runs(playbook_id);

CREATE TABLE IF NOT EXISTS findings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id      TEXT    NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    category    TEXT    NOT NULL,
    severity    TEXT    NOT NULL,
    confidence  TEXT    NOT NULL DEFAULT 'HIGH',
    file_path   TEXT,
    line        INTEGER,
    message     TEXT    NOT NULL,
    suggested_fix TEXT,
    agent       TEXT    NOT NULL,
    resolved    INTEGER NOT NULL DEFAULT 0,
    dedup_key   TEXT
);

CREATE INDEX IF NOT EXISTS idx_findings_run_id ON findings(run_id);
CREATE INDEX IF NOT EXISTS idx_findings_category ON findings(category);
CREATE INDEX IF NOT EXISTS idx_findings_severity ON findings(severity);
CREATE INDEX IF NOT EXISTS idx_findings_recurring ON findings(category, file_path);

CREATE TABLE IF NOT EXISTS stage_timings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id          TEXT    NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    stage           TEXT    NOT NULL,
    agent           TEXT    NOT NULL,
    duration_seconds REAL,
    tokens_in       INTEGER,
    tokens_out      INTEGER,
    outcome         TEXT,
    iteration       INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_timings_run_id ON stage_timings(run_id);
CREATE INDEX IF NOT EXISTS idx_timings_stage ON stage_timings(stage);

CREATE TABLE IF NOT EXISTS learnings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id          TEXT    NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    type            TEXT    NOT NULL,
    content         TEXT    NOT NULL,
    domain          TEXT,
    confidence      TEXT    NOT NULL DEFAULT 'MEDIUM',
    source_agent    TEXT,
    applied_count   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_learnings_run_id ON learnings(run_id);
CREATE INDEX IF NOT EXISTS idx_learnings_type ON learnings(type);

CREATE TABLE IF NOT EXISTS playbook_runs (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id                  TEXT    NOT NULL UNIQUE REFERENCES runs(id) ON DELETE CASCADE,
    playbook_id             TEXT    NOT NULL,
    playbook_version        TEXT    NOT NULL,
    parameters              TEXT,
    score_delta             INTEGER,
    stages_skipped          TEXT,
    acceptance_results      TEXT,
    refinement_suggestions  TEXT
);

CREATE INDEX IF NOT EXISTS idx_playbook_runs_playbook_id ON playbook_runs(playbook_id);

CREATE VIRTUAL TABLE IF NOT EXISTS run_search USING fts5(
    run_id,
    requirement,
    findings_text,
    learnings_text,
    verdict,
    domain_area,
    language,
    framework,
    tokenize='unicode61 remove_diacritics 1'
);
