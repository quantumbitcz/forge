-- Migration 003: Phase 6 cost governance columns on runs.
-- Applied when user_version < 3. PRAGMA user_version = 3 at end.
-- Note: plan referenced "run_summary"; actual table per 001-initial.sql is `runs`.

BEGIN TRANSACTION;

ALTER TABLE runs ADD COLUMN ceiling_usd REAL DEFAULT 0.0;
ALTER TABLE runs ADD COLUMN spent_usd REAL DEFAULT 0.0;
ALTER TABLE runs ADD COLUMN ceiling_breaches INTEGER DEFAULT 0;
ALTER TABLE runs ADD COLUMN throttle_events INTEGER DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_runs_spent_usd ON runs(spent_usd);
CREATE INDEX IF NOT EXISTS idx_runs_breaches ON runs(ceiling_breaches)
  WHERE ceiling_breaches > 0;

PRAGMA user_version = 3;

COMMIT;
