-- Migration 002: feature_usage table for feature activation tracking
-- Applied by fg-700-retrospective at LEARN stage (idempotent via IF NOT EXISTS)
-- Consumed by shared/feature_matrix_generator.py and shared/feature_deprecation_check.py

CREATE TABLE IF NOT EXISTS feature_usage (
    feature_id TEXT NOT NULL,
    ts DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    run_id TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_feature_usage_fid_ts
    ON feature_usage (feature_id, ts DESC);

CREATE INDEX IF NOT EXISTS idx_feature_usage_run
    ON feature_usage (run_id);
