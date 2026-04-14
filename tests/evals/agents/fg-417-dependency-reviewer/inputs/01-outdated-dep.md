# Eval: Outdated minor dependency versions

## Language: json

## Context
Package.json with dependencies pinned to old minor versions when major upgrades are available.

## Code Under Review

```json
// file: package.json
{
  "name": "my-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "4.17.1",
    "lodash": "4.17.15",
    "axios": "0.21.1",
    "moment": "2.29.1"
  }
}
```

## Expected Behavior
Reviewer should flag outdated dependencies that are several minor versions behind current releases.
