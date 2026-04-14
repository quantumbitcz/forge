# Eval: Dependency on unmaintained package

## Language: json

## Context
Project depends on packages known to be unmaintained or deprecated.

## Code Under Review

```json
// file: package.json
{
  "name": "my-app",
  "version": "1.0.0",
  "dependencies": {
    "moment": "2.29.4",
    "request": "2.88.2",
    "tslint": "6.1.3"
  }
}
```

## Expected Behavior
Reviewer should flag unmaintained/deprecated packages (moment is in maintenance mode, request is deprecated, tslint is deprecated in favor of eslint).
