# Findings Store Protocol

Authoritative contract for the shared findings store used by Stage 6 REVIEW and Phase 7 intent verification.

## 1. Path convention

`.forge/runs/<run_id>/findings/<writer-agent-id>.jsonl` — one file per writer. Line endings LF-only for Windows round-trip safety. Directory created by fg-400 (Stage 6) and fg-540 (Phase 7) on first write; others MUST NOT create it.

## 2. Line schema

See `shared/checks/findings-schema.json`. Required fields: `finding_id`, `dedup_key`, `reviewer`, `severity`, `category`, `message`, `confidence`, `created_at`, `seen_by`. Optional: `file`, `line`, `ac_id` (required when `category` starts with `INTENT-`), `suggested_fix`.

## 3. Dedup key grammar

Two forms are accepted by the schema:

- **3-part (single-component projects):** `<relative-path|"-">:<line|"-">:<CATEGORY-CODE>`.
- **4-part (monorepos):** `<component>:<relative-path|"-">:<line|"-">:<CATEGORY-CODE>`.

Paths normalized via `pathlib.PurePosixPath` for cross-OS determinism. `file == null` → `-`. `line == null` → `-`. The optional leading `<component>:` segment matches the `(component, file, line, category)` aggregation tuple referenced by §scoring.md and is required when a single workspace hosts multiple isolated components — without it, identical findings from different components in the same monorepo would collapse into one.

Writers within a single project MUST use one form consistently. Cross-component reduction at Stage 6 keys off `dedup_key` verbatim, so mixing forms within the same `findings/` directory is undefined behaviour.

## 4. Read-then-write protocol

Every writer MUST:

1. `Read` all JSONL files matching `.forge/runs/<run_id>/findings/*.jsonl` except its own.
2. Compute `seen_keys = {line.dedup_key for line in peer_files}`.
3. For each finding it would produce: if `dedup_key in seen_keys`, append a `seen_by` annotation line (see §5) to its OWN file and skip full emission; else append a full finding line.

## 5. Annotation inheritance rule

When writer B writes a `seen_by` annotation for a finding first-written by writer A, B's line inherits `severity`, `category`, `file`, `line`, `confidence`, and `message` **verbatim** from A. B MUST NOT override severity, upgrade confidence, rewrite the message, or reattribute the category. `suggested_fix` is carried verbatim or omitted. If B disagrees, B MUST write a distinct full finding (different category code) rather than an annotation.

## 6. Append-only semantics

Writers only append. No rewriting of existing lines. Annotation lines carry `seen_by: [<writer-id>]` populated with the writer's own id.

## 7. Concurrency & race tiebreaker

Per-reviewer files eliminate write contention (each writer owns its file). Line atomicity is guaranteed by the 4KB POSIX write limit for our line sizes. Duplicate full-finding race: aggregator keeps (a) highest severity, (b) highest confidence, (c) lowest ASCII `reviewer` string. Loser becomes a `seen_by` annotation retroactively during reduction. This tiebreaker is deterministic across reducer invocations.

## 8. Aggregator reducer contract

The aggregator (Stage 6 fg-400) reads only `fg-41*.jsonl`. Phase 7 fg-540 reads only `fg-540.jsonl`. No stage reduces across foreign writers. Reduction: (1) parse each line; skip malformed lines with WARNING; (2) group by `dedup_key`; (3) collapse via the tiebreaker in §7; (4) merge `seen_by` lists across collapsed lines; (5) return canonical finding set.

## 9. Error handling

- Malformed JSON on a line → WARNING tagged `(reviewer_id, line_number)`, skip, continue. Covered by `tests/scenario/findings-store-corrupt-jsonl.bats`.
- Missing peer files → expected, harmless. First writer reads an empty set.
- Disk full during append → writer emits `SCOUT-STORAGE-FULL` INFO via stage notes and exits. Aggregator treats as partial failure.

## 10. Cross-phase tolerance

The schema is permissive enough that Phase 7's fg-540 writer (INTENT findings with null file/line and required ac_id) validates without modification. See `shared/checks/findings-schema.json` `allOf` conditional.
