-- ============================================================================
-- code-graph-schema.sql — SQLite schema for the AST-based code graph
--
-- Used by build-code-graph.sh to create .forge/code-graph.db
-- Schema version: 1.1.0
-- ============================================================================

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Node types: File, Module, Class, Interface, Function, Method, Variable,
--             Import, Export, Type, Enum, Constant, Decorator, Test, Fixture
CREATE TABLE IF NOT EXISTS nodes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    kind        TEXT NOT NULL,
    name        TEXT NOT NULL,
    file_path   TEXT NOT NULL,
    start_line  INTEGER NOT NULL DEFAULT 0,
    end_line    INTEGER NOT NULL DEFAULT 0,
    start_col   INTEGER NOT NULL DEFAULT 0,
    end_col     INTEGER NOT NULL DEFAULT 0,
    language    TEXT,
    component   TEXT,
    signature   TEXT,
    visibility  TEXT,
    is_test     INTEGER NOT NULL DEFAULT 0,
    properties  TEXT,
    UNIQUE(kind, name, file_path, start_line)
);

-- Edge types: CALLS, IMPLEMENTS, INHERITS, IMPORTS, EXPORTS, CONTAINS,
--             REFERENCES, THROWS, READS, WRITES, TESTS, DEPENDS_ON,
--             OVERRIDES, ANNOTATED_BY, RETURNS, PARAMETERIZED_BY, INSTANTIATES
CREATE TABLE IF NOT EXISTS edges (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    edge_type   TEXT NOT NULL,
    source_id   INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    target_id   INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    weight      REAL NOT NULL DEFAULT 1.0,
    properties  TEXT,
    UNIQUE(edge_type, source_id, target_id)
);

-- File-level tracking for incremental updates
CREATE TABLE IF NOT EXISTS file_hashes (
    file_path       TEXT PRIMARY KEY,
    content_hash    TEXT NOT NULL,
    last_parsed_at  TEXT NOT NULL,
    parse_duration_ms INTEGER,
    node_count      INTEGER NOT NULL DEFAULT 0,
    edge_count      INTEGER NOT NULL DEFAULT 0
);

-- Community detection results (Louvain clustering)
CREATE TABLE IF NOT EXISTS communities (
    node_id       INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    community_id  INTEGER NOT NULL,
    modularity    REAL,
    computed_at   TEXT NOT NULL,
    PRIMARY KEY(node_id)
);

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_nodes_kind ON nodes(kind);
CREATE INDEX IF NOT EXISTS idx_nodes_name ON nodes(name);
CREATE INDEX IF NOT EXISTS idx_nodes_file ON nodes(file_path);
CREATE INDEX IF NOT EXISTS idx_nodes_kind_name ON nodes(kind, name);
CREATE INDEX IF NOT EXISTS idx_nodes_component ON nodes(component);
CREATE INDEX IF NOT EXISTS idx_nodes_language ON nodes(language);
CREATE INDEX IF NOT EXISTS idx_nodes_is_test ON nodes(is_test);
CREATE INDEX IF NOT EXISTS idx_edges_type ON edges(edge_type);
CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_type_source ON edges(edge_type, source_id);
CREATE INDEX IF NOT EXISTS idx_edges_type_target ON edges(edge_type, target_id);
CREATE INDEX IF NOT EXISTS idx_file_hashes_hash ON file_hashes(content_hash);

-- === Repo-Map PageRank Cache (schema 1.1.0) ===
-- Durable mirror of .forge/ranked-files-cache.json. 4-tuple PK matches the
-- JSON cache key. The JSON file is primary; this table is an optional audit
-- mirror populated by repomap.py when PACK_CACHE_DB_MIRROR=1.
CREATE TABLE IF NOT EXISTS ranked_files_cache (
    graph_sha TEXT NOT NULL,
    keywords_hash TEXT NOT NULL,
    budget INTEGER NOT NULL,
    top_k INTEGER NOT NULL,
    ranked_json TEXT NOT NULL,
    computed_at TEXT NOT NULL,
    PRIMARY KEY (graph_sha, keywords_hash, budget, top_k)
);

-- Index powers the recency_multiplier lookup in score_files().
CREATE INDEX IF NOT EXISTS idx_nodes_last_modified
    ON nodes (json_extract(properties, '$.last_modified_ts'));

-- Bump schema version row. Uses existing schema_meta table (existing convention).
INSERT OR REPLACE INTO schema_meta(key, value)
VALUES ('schema_version', '1.1.0');
