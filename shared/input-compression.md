# Input Compression

Per-file compression system that reduces input tokens in agent system prompts, convention stacks, and config templates. Applied offline via `/forge-admin compress` — not runtime post-processing.

## Compression Rules

### Remove
- Articles: a, an, the
- Filler: just, really, basically, actually, simply, essentially, generally
- Pleasantries: "sure", "certainly", "of course", "happy to", "I'd recommend"
- Hedging: "it might be worth", "you could consider", "it would be good to"
- Redundant phrasing: "in order to" → "to", "make sure to" → "ensure", "the reason is because" → "because", "at the end of the day" → (delete)
- Connective fluff: "however", "furthermore", "additionally", "in addition"
- Imperative softeners: "you should", "make sure to", "remember to" → state action directly
- Duplicate examples showing same pattern → keep one

### Preserve EXACTLY (never modify)
- Code blocks (fenced ``` and indented 4+ spaces)
- Inline code (`backtick content`)
- URLs, markdown links, file paths
- Commands (npm install, git commit, docker build, etc.)
- Technical terms (library names, API names, protocols, algorithms)
- Proper nouns (project names, companies, agent IDs like fg-100)
- Dates, version numbers, numeric values, thresholds, formulas
- Environment variables ($HOME, NODE_ENV, CLAUDE_PLUGIN_ROOT)
- YAML/JSON frontmatter blocks
- Table structure (compress cell text, keep pipes and alignment)
- Markdown headings (keep exact heading text, compress body below)
- Bullet hierarchy and numbered list structure
- Finding format strings (pipe-delimited output-format.md patterns)
- Severity levels (CRITICAL, WARNING, INFO)
- Category codes (SEC-*, ARCH-*, QUAL-*, TEST-*, etc.)

### Compress
- Short synonyms: "big" not "extensive", "fix" not "implement a solution for", "use" not "utilize", "run" not "execute", "check" not "verify and validate"
- Fragments OK: "Run tests before commit" not "You should always run tests before committing"
- Merge redundant bullets saying same thing differently
- Arrows for causality: "X causes Y" → "X → Y"
- Abbreviate on second use: "quality gate" → "QG" (first use full, then abbrev)

## Intensity Levels

| Level | Name | Target Reduction | Use Case |
|-------|------|-----------------|----------|
| 1 | `conservative` | ~20% | Convention stacks, user-editable config templates |
| 2 | `aggressive` | ~45% | Agent `.md` system prompts, shared core docs |
| 3 | `ultra` | ~65% | Inner-loop agent prompts, transient context |

## Level Selection Per File Type

| File Type | Default Level | Rationale |
|-----------|--------------|-----------|
| `agents/*.md` | `aggressive` (2) | Loaded once per dispatch; high token cost |
| `modules/frameworks/*/conventions.md` | `conservative` (1) | User-readable reference |
| `modules/frameworks/*/testing/*.md` | `aggressive` (2) | Agent consumption only |
| `shared/*.md` (core docs) | `aggressive` (2) | Agent consumption, cross-referenced |
| `forge.local.md` | `conservative` (1) | User edits directly |
| `forge-config.md` | `conservative` (1) | User edits, auto-tuned by retrospective |
| `skills/*/SKILL.md` | `conservative` (1) | User-visible in skill invocation |

## Examples

### Before (verbose):
> You should always make sure to run the test suite before pushing any changes to the main branch. This is important because it helps catch bugs early and prevents broken builds from being deployed to production.

### After (aggressive):
> Run tests before push to main. Catches bugs early, prevents broken prod deploys.

### Before (verbose):
> The application uses a microservices architecture with the following components. The API gateway handles all incoming requests and routes them to the appropriate service.

### After (aggressive):
> Microservices architecture. API gateway routes all requests to services.

## Relationship to Output Compression

- **Input compression** (this doc): Compresses files loaded as system prompt context. Applied offline via `/forge-admin compress`.
- **Output compression** (`output-compression.md`): Constrains agent output verbosity. Applied via system prompt injection at runtime.
- **Caveman mode** (`skills/forge-admin/SKILL.md` §Subcommand: compress): User-configurable terseness for Forge's own user-facing messages.

These three layers are independent. No double-compression occurs because each operates at a different boundary.
