# Eval: Dependency on end-of-life major version

## Language: json

## Context
Project uses a major version of a framework that has reached end of life and is no longer maintained.

## Code Under Review

```json
// file: package.json
{
  "name": "legacy-app",
  "version": "2.0.0",
  "dependencies": {
    "react": "16.14.0",
    "react-dom": "16.14.0",
    "webpack": "4.46.0",
    "typescript": "4.2.4"
  }
}
```

## Expected Behavior
Reviewer should flag dependencies pinned to old major versions (React 16, webpack 4, TS 4.2) that are significantly behind current releases.
