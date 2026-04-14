// Migration 001: Add schema version tracking
// Idempotent — safe to re-run

MERGE (v:SchemaVersion {project_id: $project_id})
SET v.version = '1.0', v.updated_at = datetime();
