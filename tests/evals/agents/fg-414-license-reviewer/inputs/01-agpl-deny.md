# Eval: AGPL dependency on deny list

## Language: typescript

## Context
Project's `package.json` adds a dependency whose declared SPDX identifier matches the `deny` bucket of the default embedded license policy (AGPL-3.0).

## Code Under Review

```json
// file: package.json
{
  "name": "my-app",
  "dependencies": {
    "express": "^4.18.0",
    "strict-copyleft-lib": "1.2.3"
  }
}
```

```json
// file: node_modules/strict-copyleft-lib/package.json
{
  "name": "strict-copyleft-lib",
  "version": "1.2.3",
  "license": "AGPL-3.0-only"
}
```

## Expected Behavior
Reviewer should emit `LICENSE-POLICY-VIOLATION` at CRITICAL for `strict-copyleft-lib@1.2.3` because `AGPL-3.0-only` matches the default `deny` list (`AGPL-*`).
