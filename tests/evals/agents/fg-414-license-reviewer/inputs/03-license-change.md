# Eval: Dependency changed license between PR base and HEAD

## Language: typescript

## Context
A transitive dependency's declared license changed between the PR's base commit (MIT) and HEAD (GPL-3.0-only). This warrants human review regardless of whether the new license is on the allow/warn/deny list.

## Code Under Review

```diff
// file: node_modules/lodash-fork/package.json
{
  "name": "lodash-fork",
  "version": "4.18.0",
- "license": "MIT"
+ "license": "GPL-3.0-only"
}
```

## Expected Behavior
Reviewer should emit `LICENSE-CHANGE` at WARNING for `lodash-fork` with the old and new license values recorded in the finding message.
