# F10: Enhanced Security — Supply Chain, Memory Poisoning, Language-Aware Secret Detection

## Status
DRAFT — 2026-04-13

## Problem Statement

GitGuardian's 2026 State of Secrets Sprawl report reveals that AI-assisted commits leak secrets at 2x the human rate — autonomous pipelines that write code are prime vectors for accidental credential exposure. Forge's existing SEC-SECRET regex patterns (`shared/data-classification.md`) catch obvious cases (API keys, private key blocks, email PII) but lack (1) language-aware context to reduce false positives, (2) high-entropy string detection for obfuscated secrets, and (3) supply chain verification for dependencies added during autonomous implementation.

OWASP Agentic Security risks ASI04 (Supply Chain Compromise) and ASI06 (Memory Poisoning) are documented in `shared/security-posture.md` but mitigations are incomplete:
- **ASI04:** Convention file SHA256 signatures exist, but MCP servers are not vetted against an allowlist. Any connected MCP server is trusted implicitly after detection (`shared/mcp-detection.md`).
- **ASI06:** Explore cache and plan cache are written and read without integrity verification. A malicious or corrupted cache entry could poison the pipeline's understanding of the codebase, leading to incorrect plans and implementations.

The gap: Forge detects 7 MCP servers, verifies convention file hashes, and runs SEC-SECRET regex on writes — but does not govern which MCP servers are allowed, does not verify cache integrity, does not use AST context to classify secret severity, does not detect high-entropy strings, and does not verify dependency provenance.

## Proposed Solution

Four security enhancements that address the identified gaps:

1. **MCP Governance (ASI04):** Allowlist-based MCP server authorization with audit logging
2. **Cache Integrity Verification (ASI06):** SHA256 checksums on explore-cache and plan-cache with tamper detection
3. **Tree-sitter-Aware Secret Detection:** AST context from F01's code graph to classify secret severity by code context (production vs. test vs. config)
4. **Enhanced Secret Patterns + Supply Chain:** High-entropy detection, cloud credential patterns, JWT detection, and dependency provenance verification

## Detailed Design

### 1. MCP Governance (ASI04)

#### Architecture

```
At /forge-init:
  +--------------------+
  | MCP Detection      |  (existing: shared/mcp-detection.md)
  +--------------------+
           |
           v
  +--------------------+
  | MCP Governance     |  (new: allowlist check)
  +--------------------+
           |
  allowed? --yes--> state.json.integrations.{mcp}.available = true
           |
           --no---> CRITICAL finding + state.json.integrations.{mcp}.available = false
                    + state.json.integrations.{mcp}.blocked_reason = "not in allowlist"
```

#### Allowlist Design

The allowlist is defined in `forge-config.md`:

```yaml
security:
  mcp_governance:
    enabled: true
    mode: allowlist              # allowlist | audit | disabled
    allowlist:
      - name: context7
        prefix: "mcp__plugin_context7_context7__"
        risk_level: LOW
      - name: playwright
        prefix: "mcp__plugin_playwright_playwright__"
        risk_level: LOW
      - name: neo4j
        prefix: "neo4j-mcp"
        risk_level: LOW
      - name: linear
        prefix: "mcp__claude_ai_Linear__"
        risk_level: MEDIUM
      - name: slack
        prefix: "mcp__claude_ai_Slack__"
        risk_level: MEDIUM
      - name: figma
        prefix: "mcp__claude_ai_Figma__"
        risk_level: LOW
      - name: excalidraw
        prefix: "mcp__claude_ai_Excalidraw__"
        risk_level: LOW
    block_unknown: true
    audit_all_calls: false
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | Master toggle for MCP governance |
| `mode` | string | `allowlist` | `allowlist`: block non-listed MCPs. `audit`: allow all but log. `disabled`: no checks. |
| `allowlist` | array | (7 known MCPs) | List of approved MCP servers with name, prefix, and risk level |
| `allowlist[].name` | string | -- | Human-readable MCP name |
| `allowlist[].prefix` | string | -- | Tool name prefix (from `shared/mcp-detection.md` Detection Table) |
| `allowlist[].risk_level` | string | `LOW` | `LOW`, `MEDIUM`, `HIGH` — affects audit verbosity |
| `block_unknown` | boolean | `true` | Block MCP servers not in the allowlist |
| `audit_all_calls` | boolean | `false` | Log every MCP tool invocation (verbose, for compliance) |

#### Governance Flow

At PREFLIGHT, after MCP detection:

1. For each detected MCP (tool prefix found in available tools):
   a. Look up prefix in `allowlist`
   b. If found: mark as allowed, set `state.json.integrations.{name}.available = true`
   c. If not found and `block_unknown: true`:
      - Set `state.json.integrations.{name}.available = false`
      - Set `state.json.integrations.{name}.blocked_reason = "not in mcp_governance.allowlist"`
      - Emit finding: `PREFLIGHT:0 | SEC-MCP-BLOCKED | CRITICAL | MCP server '{name}' (prefix: {prefix}) is not in the security allowlist | Add to security.mcp_governance.allowlist in forge-config.md or set block_unknown: false`
   d. If not found and `block_unknown: false`:
      - Allow with WARNING: `SEC-MCP-UNKNOWN | WARNING | MCP server '{name}' is not in the allowlist | Consider adding to allowlist for explicit approval`
2. When `mode: audit`: all MCPs are allowed but findings are emitted as INFO for non-listed servers
3. All governance decisions are logged to `.forge/security-audit.jsonl`

#### MCP Audit Trail

When `audit_all_calls: true`, every MCP tool invocation is logged:

```json
{
  "timestamp": "2026-04-13T10:15:00Z",
  "event": "mcp_tool_call",
  "mcp_name": "linear",
  "tool_name": "mcp__claude_ai_Linear__save_issue",
  "agent": "fg-200-planner",
  "stage": "PLANNING",
  "risk_level": "MEDIUM"
}
```

This provides a complete audit trail of external system interactions during the pipeline run.

### 2. Cache Integrity Verification (ASI06)

#### Architecture

```
At cache write:
  data --> compute SHA256 --> store {data, checksum} in cache file
                             store checksum in .forge/integrity.json

At cache read:
  read {data, checksum} from cache file
  verify SHA256(data) == checksum
       |
  match? --yes--> use cached data
       |
       --no---> TAMPER detected: reject cache, log WARNING, re-explore/re-plan
```

#### Integrity Store

`.forge/integrity.json`:

```json
{
  "schema_version": "1.0.0",
  "checksums": {
    "explore-cache.json": {
      "sha256": "a1b2c3d4e5f6...",
      "computed_at": "2026-04-13T09:00:00Z",
      "file_size_bytes": 45678
    },
    "plan-cache/index.json": {
      "sha256": "f6e5d4c3b2a1...",
      "computed_at": "2026-04-13T09:30:00Z",
      "file_size_bytes": 1234
    },
    "plan-cache/plan-2026-04-10-add-comments.json": {
      "sha256": "1a2b3c4d5e6f...",
      "computed_at": "2026-04-10T10:00:00Z",
      "file_size_bytes": 8901
    },
    "knowledge/rules.json": {
      "sha256": "6f5e4d3c2b1a...",
      "computed_at": "2026-04-13T10:30:00Z",
      "file_size_bytes": 5678
    },
    "code-graph.db": {
      "sha256": "b1c2d3e4f5a6...",
      "computed_at": "2026-04-13T08:00:00Z",
      "file_size_bytes": 5242880
    }
  },
  "last_verified": "2026-04-13T10:00:00Z",
  "verification_count": 15,
  "tamper_detections": 0
}
```

#### Protected Files

| File | Write Point | Read Point | On Tamper |
|---|---|---|---|
| `.forge/explore-cache.json` | EXPLORE stage completion | PREFLIGHT | Full re-explore (invalidate cache) |
| `.forge/plan-cache/index.json` | SHIP stage (plan caching) | PLAN stage | Rebuild index from plan files |
| `.forge/plan-cache/plan-*.json` | SHIP stage | PLAN stage | Delete tampered plan entry |
| `.forge/knowledge/rules.json` | LEARN stage | PREFLIGHT | Rebuild from inbox history |
| `.forge/knowledge/patterns.json` | LEARN stage | PREFLIGHT | Rebuild from inbox history |
| `.forge/knowledge/root-causes.json` | LEARN stage | PREFLIGHT | Rebuild from inbox history |
| `.forge/code-graph.db` | PREFLIGHT | PLAN, IMPLEMENT, REVIEW | Full graph rebuild |

#### Verification Algorithm

```bash
# At write time:
checksum=$(sha256sum "$file" | cut -d' ' -f1)
file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
# Store in integrity.json via forge-state-write.sh pattern (atomic JSON update)

# At read time:
stored_checksum=$(jq -r ".checksums[\"$file\"].sha256" .forge/integrity.json)
actual_checksum=$(sha256sum "$file" | cut -d' ' -f1)
if [ "$stored_checksum" != "$actual_checksum" ]; then
  # TAMPER DETECTED
  echo "WARNING: Integrity check failed for $file"
  echo "  Expected: $stored_checksum"
  echo "  Actual:   $actual_checksum"
  # Execute tamper response per file type
fi
```

#### Size Verification

In addition to SHA256, file size is tracked. If file size changes by more than 50% without a corresponding pipeline write (no integrity.json update), this is flagged as suspicious even before hash comparison — faster detection for large files like `code-graph.db`.

### 3. Tree-sitter-Aware Secret Detection

#### Architecture

Depends on F01 (Tree-sitter Code Graph). When the code graph is available, secret detection runs a two-phase pipeline:

```
Phase 1: L1 regex detection (existing, sub-second)
  Matches SEC-SECRET and SEC-PII patterns
       |
       v
Phase 2: AST context classification (new, requires code graph)
  For each L1 match:
    1. Look up the file + line in code-graph.db
    2. Determine code context from enclosing node:
       - Test code: node is_test=1 or in test/ directory
       - Config code: file is *.config.*, *.properties, *.env.*
       - Production code: everything else
       - Documentation: file is *.md, *.rst, *.txt
    3. Adjust severity based on context
       |
       v
  Context-adjusted finding with appropriate severity
```

#### Context Classification

| Context | Detection Method | Severity Adjustment |
|---|---|---|
| **Production code** | File not in test tree, not config, not docs | No adjustment (original severity) |
| **Configuration** | File matches `*.config.*`, `*.properties`, `*.yaml`, `*.yml`, `*.toml`, `*.env*`, `docker-compose.*` | No adjustment (config secrets are serious) |
| **Test code** | `nodes.is_test = 1` in code graph, or file path matches `**/test/**`, `**/tests/**`, `**/__tests__/**`, `**/spec/**`, `**/*_test.*`, `**/*.spec.*`, `**/*.test.*` | SEC-SECRET CRITICAL → WARNING. SEC-PII INFO → INFO (unchanged). |
| **Test fixtures** | File path matches `**/fixtures/**`, `**/testdata/**`, `**/__fixtures__/**`, or node kind = `Fixture` in code graph | SEC-SECRET CRITICAL → INFO. Test fixtures often contain fake credentials. |
| **Documentation** | File matches `*.md`, `*.rst`, `*.txt`, `*.adoc` | SEC-SECRET CRITICAL → WARNING (example credentials in docs). SEC-PII INFO → INFO. |
| **Generated code** | File matches `*.generated.*`, `*.g.*`, `*.pb.*` or file_path in code_graph with `properties.generated = true` | SEC-SECRET CRITICAL → INFO (likely example/template). |

**Important:** Context adjustment reduces severity but never suppresses findings entirely. A secret in test code is still flagged — just as WARNING instead of CRITICAL.

#### AST-Aware Patterns

The code graph enables patterns that regex alone cannot express:

| Pattern | AST Detection | Without AST (regex fallback) |
|---|---|---|
| String literal assigned to variable named `password`, `secret`, `api_key` | Query nodes table: Variable node where name matches secret-like pattern AND has string literal initializer | Regex: `(password\|secret\|api_key)\s*[:=]\s*['"]` (existing, more false positives) |
| Hardcoded credential in function parameter default | Query: Function/Method node with parameter that has default value matching secret pattern | Not detectable with regex |
| Secret in environment variable read with fallback | Query: function call to `getenv`/`os.environ`/`process.env` with string literal fallback | Regex: partial detection (high false positive rate) |
| Credential in class field initialization | Query: Class node CONTAINS Variable node with secret-like name and literal initializer | Regex: limited context |

### 4. Enhanced Secret Patterns and Supply Chain

#### New Detection Patterns

Added to the L1 check engine (`shared/checks/engine.sh`):

##### High-Entropy String Detection

```regex
# Strings with Shannon entropy > 4.5 and length >= 16
# Computed per-string, not via regex — requires entropy calculation
```

Implementation — **Python** (not bash — bash character-by-character iteration with `bc` subprocess calls is orders of magnitude too slow for production use):

```python
import math
from collections import Counter

def entropy(s: str) -> float:
    """Shannon entropy of a string. O(n) time, no external dependencies."""
    if not s:
        return 0.0
    counts = Counter(s)
    length = len(s)
    return -sum((c / length) * math.log2(c / length) for c in counts.values())

# Apply to string literals extracted by L1 regex patterns
# Threshold: entropy > 4.5 AND length >= 16 AND not in test/fixture context
# This catches base64-encoded secrets, hex strings, and random tokens
# Exclusions: UUIDs (known format), SHA hashes (known context), hex color codes
```

This function is called from `shared/checks/l1-security/entropy-check.py` as a post-filter on L1 regex matches. It processes only candidate strings already flagged by L1, not all strings in the file. Typical invocation: <50 strings per file, <1ms total.

**False positive mitigation:** Exclude strings that match known non-secret high-entropy patterns:
- UUIDs: `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`
- SHA hashes: `[0-9a-f]{40}` or `[0-9a-f]{64}` (git SHAs, integrity checksums)
- Package version hashes: strings following `integrity="sha256-` or `integrity="sha512-`
- CSS/HTML color codes: `#[0-9a-fA-F]{6,8}`
- Locale strings and i18n keys

##### JWT Token Detection

```regex
eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
```

Category: `SEC-SECRET-JWT`. Severity: CRITICAL in production code, WARNING in test code.

##### Private Key Detection (expanded)

```regex
-----BEGIN (RSA |EC |DSA |OPENSSH |PGP |Ed25519 )?PRIVATE KEY-----
-----BEGIN (ENCRYPTED )?PRIVATE KEY-----
```

Category: `SEC-SECRET-KEY`. Severity: CRITICAL (always, regardless of context — private keys in test code are still dangerous).

##### Cloud Credential Patterns

| Provider | Pattern | Category |
|---|---|---|
| AWS Access Key | `AKIA[0-9A-Z]{16}` | `SEC-SECRET-AWS` |
| AWS Secret Key | `[0-9a-zA-Z/+=]{40}` near `aws_secret` | `SEC-SECRET-AWS` |
| GCP Service Account | `"type"\s*:\s*"service_account"` in JSON | `SEC-SECRET-GCP` |
| GCP API Key | `AIza[0-9A-Za-z_-]{35}` | `SEC-SECRET-GCP` |
| Azure Connection String | `DefaultEndpointsProtocol=https;AccountName=` | `SEC-SECRET-AZURE` |
| Azure Client Secret | `[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}` near `client_secret` | `SEC-SECRET-AZURE` |
| GitHub Token | `gh[ps]_[A-Za-z0-9_]{36,}` | `SEC-SECRET-GITHUB` |
| Slack Token | `xox[bpras]-[0-9a-zA-Z-]{10,}` | `SEC-SECRET-SLACK` |
| Stripe Key | `[sr]k_(live\|test)_[0-9a-zA-Z]{24,}` | `SEC-SECRET-STRIPE` |
| Generic Bearer Token | `Bearer\s+[A-Za-z0-9._~+/=-]{20,}` | `SEC-SECRET-BEARER` |

##### Configurable Custom Patterns

```yaml
security:
  custom_secret_patterns:
    - pattern: "INTERNAL_API_KEY_[A-Z0-9]{32}"
      category: "SEC-SECRET-INTERNAL"
      severity: "CRITICAL"
      description: "Internal API key detected"
```

#### Dependency Provenance Verification

At IMPLEMENT time (after implementer adds/modifies dependencies), verify provenance:

1. **Detection:** After each IMPLEMENT cycle, diff the dependency manifests (`package.json`, `build.gradle.kts`, `requirements.txt`, `Cargo.toml`, `go.mod`, `Gemfile`, `composer.json`, `pubspec.yaml`, `mix.exs`, `build.sbt`, `pom.xml`, `*.csproj`/`packages.config`)
2. **New dependency check:** For each newly added dependency:
   a. Verify the package name matches the expected registry (npm, PyPI, Maven Central, crates.io, etc.)
   b. Check for typosquatting: is the package name within edit distance 2 of a popular package? Flag if yes.
   c. Verify the version exists in the registry (requires internet access — graceful skip if offline)
   d. Flag if the dependency has fewer than 100 weekly downloads (potential low-trust package)
3. **Finding format:**

```
package.json:15 | SEC-SUPPLY-NEW | WARNING | New dependency 'lodash-utils' added — verify provenance | Check npm registry, compare with known 'lodash' packages
package.json:15 | SEC-SUPPLY-TYPOSQUAT | CRITICAL | Package 'lodassh' is within edit distance 2 of popular package 'lodash' | Verify correct package name
```

#### New Finding Categories

Added to `shared/checks/category-registry.json`:

| Category | Description | Severity | Agent |
|---|---|---|---|
| `SEC-MCP-BLOCKED` | Unapproved MCP server blocked by governance | CRITICAL | Orchestrator (PREFLIGHT) |
| `SEC-MCP-UNKNOWN` | MCP server not in allowlist (audit mode) | WARNING | Orchestrator (PREFLIGHT) |
| `SEC-CACHE-TAMPER` | Cache integrity verification failed | WARNING | Orchestrator (PREFLIGHT) |
| `SEC-SECRET-JWT` | JWT token detected in source code | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-KEY` | Private key material detected | CRITICAL | L1 check engine |
| `SEC-SECRET-AWS` | AWS credential detected | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-GCP` | GCP credential detected | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-AZURE` | Azure credential detected | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-GITHUB` | GitHub token detected | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-SLACK` | Slack token detected | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-STRIPE` | Stripe key detected | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-BEARER` | Bearer token detected | CRITICAL / WARNING | L1 check engine |
| `SEC-SECRET-ENTROPY` | High-entropy string (potential obfuscated secret) | WARNING | L1 check engine |
| `SEC-SUPPLY-NEW` | New dependency added — provenance unverified | WARNING | fg-420-dependency-reviewer |
| `SEC-SUPPLY-TYPOSQUAT` | Dependency name resembles a popular package (typosquatting risk) | CRITICAL | fg-420-dependency-reviewer |
| `SEC-SUPPLY-LOWPOP` | Dependency has very low download count | INFO | fg-420-dependency-reviewer |

All new categories fall under the existing `SEC-*` wildcard prefix. They inherit the priority 1 and affinity to `fg-411-security-reviewer` from the registry.

### Security Audit Trail

All security-relevant events are logged to `.forge/security-audit.jsonl`:

```json
{"timestamp": "2026-04-13T10:00:00Z", "event": "mcp_governance_check", "mcp": "linear", "result": "allowed", "risk_level": "MEDIUM"}
{"timestamp": "2026-04-13T10:00:01Z", "event": "mcp_governance_check", "mcp": "unknown-server", "result": "blocked", "reason": "not in allowlist"}
{"timestamp": "2026-04-13T10:00:02Z", "event": "cache_integrity_check", "file": "explore-cache.json", "result": "valid"}
{"timestamp": "2026-04-13T10:00:03Z", "event": "cache_integrity_check", "file": "plan-cache/index.json", "result": "tampered", "action": "invalidated"}
{"timestamp": "2026-04-13T10:15:00Z", "event": "secret_detected", "category": "SEC-SECRET-AWS", "file": "src/config/aws.ts", "line": 15, "context": "production", "severity": "CRITICAL"}
{"timestamp": "2026-04-13T10:15:01Z", "event": "secret_detected", "category": "SEC-SECRET-JWT", "file": "tests/auth.test.ts", "line": 42, "context": "test", "severity": "WARNING"}
{"timestamp": "2026-04-13T10:20:00Z", "event": "dependency_check", "package": "lodassh", "result": "typosquat_warning", "similar_to": "lodash"}
{"timestamp": "2026-04-13T10:20:01Z", "event": "mcp_tool_call", "mcp": "linear", "tool": "save_issue", "agent": "fg-200-planner", "stage": "PLANNING"}
```

### Configuration

Full configuration in `forge-config.md`:

```yaml
security:
  # Existing settings (unchanged)
  input_sanitization: true
  tool_call_budget:
    default: 50
    overrides:
      fg-300-implementer: 200
      fg-500-test-gate: 150
  anomaly_detection:
    max_calls_per_minute: 30
    max_session_cost_usd: 10
  convention_signatures: true

  # New: MCP Governance (F10)
  mcp_governance:
    enabled: true
    mode: allowlist
    allowlist:
      - name: context7
        prefix: "mcp__plugin_context7_context7__"
        risk_level: LOW
      - name: playwright
        prefix: "mcp__plugin_playwright_playwright__"
        risk_level: LOW
      - name: neo4j
        prefix: "neo4j-mcp"
        risk_level: LOW
      - name: linear
        prefix: "mcp__claude_ai_Linear__"
        risk_level: MEDIUM
      - name: slack
        prefix: "mcp__claude_ai_Slack__"
        risk_level: MEDIUM
      - name: figma
        prefix: "mcp__claude_ai_Figma__"
        risk_level: LOW
      - name: excalidraw
        prefix: "mcp__claude_ai_Excalidraw__"
        risk_level: LOW
    block_unknown: true
    audit_all_calls: false

  # New: Cache Integrity (F10)
  cache_integrity:
    enabled: true
    verify_on_read: true
    protected_files:
      - "explore-cache.json"
      - "plan-cache/**"
      - "knowledge/**"
      - "code-graph.db"

  # New: Enhanced Secret Detection (F10)
  secret_detection:
    entropy_detection: true
    entropy_threshold: 4.5
    entropy_min_length: 16
    ast_context_aware: true
    cloud_patterns: true
    jwt_detection: true
    custom_secret_patterns: []

  # New: Supply Chain (F10)
  supply_chain:
    enabled: true
    typosquat_detection: true
    typosquat_edit_distance: 2
    provenance_check: true
    low_popularity_threshold: 100

  # New: Audit Trail (F10)
  audit_trail:
    enabled: true
    max_file_size_mb: 10
    retention_runs: 50
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `mcp_governance.enabled` | boolean | `true` | -- | Enable MCP governance |
| `mcp_governance.mode` | string | `allowlist` | `allowlist`, `audit`, `disabled` | Governance mode |
| `mcp_governance.block_unknown` | boolean | `true` | -- | Block MCPs not in allowlist |
| `mcp_governance.audit_all_calls` | boolean | `false` | -- | Log every MCP invocation |
| `cache_integrity.enabled` | boolean | `true` | -- | Enable integrity verification |
| `cache_integrity.verify_on_read` | boolean | `true` | -- | Verify checksums on every read |
| `secret_detection.entropy_detection` | boolean | `true` | -- | Enable high-entropy string detection |
| `secret_detection.entropy_threshold` | float | `4.5` | 3.0-6.0 | Shannon entropy threshold |
| `secret_detection.entropy_min_length` | integer | `16` | 8-64 | Minimum string length for entropy check |
| `secret_detection.ast_context_aware` | boolean | `true` | -- | Use AST context for severity adjustment |
| `secret_detection.cloud_patterns` | boolean | `true` | -- | Enable cloud credential patterns |
| `secret_detection.jwt_detection` | boolean | `true` | -- | Enable JWT token detection |
| `secret_detection.custom_secret_patterns` | array | `[]` | -- | Custom regex patterns |
| `supply_chain.enabled` | boolean | `true` | -- | Enable supply chain checks |
| `supply_chain.typosquat_detection` | boolean | `true` | -- | Enable typosquatting detection |
| `supply_chain.typosquat_edit_distance` | integer | `2` | 1-3 | Maximum Levenshtein distance for typosquat alert |
| `supply_chain.provenance_check` | boolean | `true` | -- | Verify new packages exist in registry |
| `supply_chain.low_popularity_threshold` | integer | `100` | 10-10000 | Weekly download count below which INFO is emitted |
| `audit_trail.enabled` | boolean | `true` | -- | Enable security audit logging |
| `audit_trail.max_file_size_mb` | integer | `10` | 1-100 | Max audit log file size before rotation |
| `audit_trail.retention_runs` | integer | `50` | 10-200 | Number of runs to retain audit logs |

### Data Flow

#### At PREFLIGHT

1. **MCP Governance:**
   a. Detect available MCP servers (existing `mcp-detection.md` protocol)
   b. For each detected MCP: check against `mcp_governance.allowlist`
   c. Block or warn per governance mode
   d. Log decisions to `.forge/security-audit.jsonl`

2. **Cache Integrity:**
   a. For each protected file: read stored checksum from `.forge/integrity.json`
   b. Compute current SHA256
   c. Compare. If mismatch: log tamper event, invalidate cache, trigger re-exploration or re-planning
   d. If `.forge/integrity.json` is missing: compute and store baseline checksums (first run)

3. **Secret Detection Setup:**
   a. Load cloud credential patterns
   b. Load custom patterns from config
   c. Check if code graph is available for AST-context-aware detection

#### During IMPLEMENT (PostToolUse hook on Edit/Write)

1. **L1 Phase 1:** Run existing SEC-SECRET and SEC-PII regex patterns (unchanged)
2. **L1 Phase 1b:** Run new patterns (JWT, cloud credentials, high-entropy) on the written content
3. **L1 Phase 2 (if code graph available):** For each L1 match:
   a. Query code-graph.db for the file + line context
   b. Classify context (production/test/fixture/config/docs/generated)
   c. Adjust severity per context classification table
4. Emit findings with context-adjusted severity

#### After IMPLEMENT (dependency check)

1. Diff dependency manifests against pre-IMPLEMENT state
2. For each new dependency:
   a. Check typosquatting (Levenshtein distance against top-1000 packages per ecosystem)
   b. Check provenance (registry existence — requires internet, graceful skip if offline)
   c. Emit SEC-SUPPLY-* findings

#### At Cache Write Points

1. After explore cache update: compute SHA256, store in `.forge/integrity.json`
2. After plan cache update: compute SHA256 for each modified file, store in `.forge/integrity.json`
3. After knowledge base update: compute SHA256, store in `.forge/integrity.json`
4. After code graph rebuild: compute SHA256, store in `.forge/integrity.json`

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `fg-100-orchestrator` | MCP governance check at PREFLIGHT (after MCP detection). Cache integrity verification at PREFLIGHT. | Add governance and integrity steps to orchestrator PREFLIGHT flow. |
| `shared/checks/engine.sh` | Add new regex patterns (JWT, cloud, entropy). Add AST-context phase 2 post-filter. | Extend L1 pattern set. Add optional phase 2 when code graph is available. |
| `shared/mcp-detection.md` | Reference MCP governance after detection. No duplication — governance uses the same detection table. | Add "See security.mcp_governance" reference. |
| `fg-420-dependency-reviewer` | Add supply chain verification (typosquatting, provenance) to review scope. | Extend dependency reviewer with SEC-SUPPLY-* findings. |
| `fg-411-security-reviewer` | Receive context-adjusted SEC-SECRET findings. Aware of new subcategories. | Update security reviewer knowledge of new categories. |
| `shared/checks/category-registry.json` | Add 16 new finding categories. | Registry update. |
| `shared/data-classification.md` | Reference enhanced patterns. Document context-aware severity adjustment. | Add "Enhanced Detection (v2.0)" section. |
| `shared/security-posture.md` | Update ASI04 and ASI06 mitigation columns. | Document new mitigations. |
| `state-schema.md` | Add `integrations.{mcp}.blocked_reason` field. | Schema update (compatible addition). |
| `shared/explore-cache.md` | Document integrity verification. | Add "Integrity Verification" section. |
| `shared/plan-cache.md` | Document integrity verification. | Add "Integrity Verification" section. |

### Error Handling

| Failure Mode | Behavior |
|---|---|
| MCP governance allowlist missing from config | Default to built-in allowlist (7 known MCPs). Log INFO. |
| integrity.json corrupted or missing | Recompute all checksums from current files. Log INFO: "Integrity baseline recomputed." |
| Code graph unavailable for AST context | Skip phase 2 context classification. Use L1 severity (no adjustment). Log INFO. |
| Entropy calculation fails (bc not available) | Skip entropy detection. Log WARNING. |
| Registry check fails (offline) | Skip provenance verification. Log INFO: "Offline — supply chain provenance check skipped." |
| Audit log exceeds max_file_size_mb | Rotate: rename to `.forge/security-audit.{timestamp}.jsonl`, start new file. |
| SHA256 computation fails (file locked) | Retry once after 100ms. If still fails, skip integrity check for that file with WARNING. |

## Performance Characteristics

| Operation | Expected Latency | Token Cost |
|---|---|---|
| MCP governance check (7 MCPs) | <10ms | 0 tokens |
| Cache integrity verification (5 files) | <100ms | 0 tokens (SHA256 computation) |
| L1 regex patterns (existing + new) | <50ms per file | 0 tokens |
| AST context lookup (per finding) | <5ms | 0 tokens (SQLite query) |
| Entropy calculation (per string) | <1ms | 0 tokens |
| Dependency manifest diff | <100ms | 0 tokens |
| Typosquatting check (per dependency) | <50ms | 0 tokens (Levenshtein computation) |
| Audit log write | <1ms | 0 tokens |

**Overall impact:** The enhanced security adds <500ms to PREFLIGHT (governance + integrity) and <10ms per file write (new L1 patterns + optional AST context). No additional token cost — all detection is local computation.

**Storage impact:** Audit log grows ~1KB per MCP call (when `audit_all_calls: true`) or ~100 bytes per security event. At 50 runs with 20 events each: ~100KB. Well within the 10MB default limit.

## Testing Approach

### Unit Tests (`tests/unit/enhanced-security.bats`)

1. **MCP governance:** Verify allowlist matching, blocking of unknown MCPs, audit mode behavior
2. **Cache integrity:** Verify SHA256 computation, tamper detection, re-exploration trigger
3. **Secret patterns:** Test each new pattern (JWT, AWS, GCP, Azure, GitHub, Slack, Stripe, Bearer) against known strings
4. **Entropy detection:** Verify entropy calculation, threshold application, false positive exclusions (UUIDs, SHAs)
5. **AST context:** Verify severity adjustment for test/fixture/production/config/docs/generated contexts
6. **Typosquatting:** Verify Levenshtein distance calculation, known package matching
7. **Audit logging:** Verify JSONL format, rotation at max size

### Integration Tests (`tests/integration/enhanced-security.bats`)

1. **Full PREFLIGHT:** Run with all security features enabled, verify governance + integrity + detection all execute
2. **MCP blocking:** Configure an MCP not in allowlist, verify CRITICAL finding emitted
3. **Cache tampering:** Manually modify explore-cache.json, verify tamper detection and re-explore
4. **Secret in test vs production:** Write a secret to a test file and a production file, verify different severities

### Scenario Tests

1. **AWS key in config:** Write an AWS access key to a config file, verify CRITICAL finding
2. **JWT in test fixture:** Write a JWT to a test fixture, verify INFO finding (context-adjusted)
3. **Typosquatting dependency:** Add a package named "lodassh" to package.json, verify CRITICAL finding
4. **End-to-end audit trail:** Run full pipeline with audit enabled, verify complete event log

## Acceptance Criteria

1. MCP governance blocks unapproved MCP servers in `allowlist` mode and emits SEC-MCP-BLOCKED CRITICAL findings
2. MCP governance logs all decisions to `.forge/security-audit.jsonl`
3. Cache integrity verification detects SHA256 mismatches on explore-cache, plan-cache, knowledge, and code-graph files
4. Tampered caches are invalidated and trigger appropriate re-computation (re-explore, re-plan, re-learn, re-build)
5. High-entropy strings (Shannon entropy > 4.5, length >= 16) are detected with exclusions for UUIDs, SHAs, and color codes
6. JWT tokens, cloud credentials (AWS, GCP, Azure), and platform tokens (GitHub, Slack, Stripe) are detected by new L1 patterns
7. When F01's code graph is available, secret findings in test code receive reduced severity (CRITICAL → WARNING for test, CRITICAL → INFO for fixtures)
8. When the code graph is unavailable, secret detection falls back to L1-only (no severity adjustment)
9. Dependency provenance checks flag typosquatting (edit distance <= 2) as SEC-SUPPLY-TYPOSQUAT CRITICAL
10. All 16 new finding categories are registered in `category-registry.json`
11. Security audit trail captures all governance decisions, integrity checks, and security findings
12. All security features are independently toggleable via config and degrade gracefully when dependencies (code graph, internet) are unavailable
13. `validate-plugin.sh` passes with the new patterns and categories added

## Migration Path

1. **v2.0.0:** Add new L1 patterns to `shared/checks/engine.sh`. Register 16 new categories in `category-registry.json`.
2. **v2.0.0:** Add `security.mcp_governance`, `security.cache_integrity`, `security.secret_detection`, `security.supply_chain`, `security.audit_trail` to `forge-config-template.md` for all frameworks. Default: all enabled.
3. **v2.0.0:** Add `.forge/integrity.json` and `.forge/security-audit.jsonl` to state-schema.md directory structure.
4. **v2.0.0:** Update `shared/security-posture.md` ASI04 and ASI06 mitigation columns.
5. **v2.0.0:** Update `shared/data-classification.md` with enhanced detection patterns and context-aware classification.
6. **v2.0.0:** Update `shared/mcp-detection.md` to reference MCP governance.
7. **No breaking changes:** All new features are additive. Existing SEC-SECRET and SEC-PII patterns are unchanged. New patterns supplement them. Default allowlist includes all 7 currently detected MCPs — no existing MCP integrations are blocked.

## Dependencies

**Depends on:**
- F01 (Tree-sitter Code Graph): for AST-context-aware secret detection. Graceful degradation when unavailable.
- Existing: `shared/data-classification.md` (SEC-SECRET, SEC-PII patterns), `shared/security-posture.md` (OWASP framework), `shared/mcp-detection.md` (MCP detection table), `shared/checks/engine.sh` (L1 check engine), `shared/checks/category-registry.json` (finding categories).

**Depended on by:**
- F09 (Active Knowledge Base): learned SEC-* rules (from knowledge base) extend the detection patterns. Cache integrity also protects `.forge/knowledge/` files.
