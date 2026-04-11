# Context7 Query Templates

Standardized prompts for `query-docs` calls. Agents SHOULD use these templates instead of ad-hoc queries for consistent, high-quality documentation retrieval.

## Templates

### VERSION_RESOLUTION
```
What is the latest stable version of {library}? Include release date.
```

### SETUP_GUIDE
```
Show the recommended setup for {library} in a {framework} project. Include imports, configuration, and minimal working example.
```

### API_REFERENCE
```
Show the API for {class_or_function} in {library}. Include parameters, return types, and usage example.
```

### MIGRATION_GUIDE
```
How to migrate {library} from {old_version} to {new_version}? List breaking changes and required code modifications.
```

### DEPRECATION_CHECK
```
What APIs are deprecated in {library} {version}? Include replacement APIs and removal timeline.
```

### TESTING_PATTERNS
```
Show testing patterns for {library} using {test_framework}. Include setup, mocking, and common pitfalls.
```

## Usage

Agents should reference templates by name and fill in placeholders:
```
query-docs(libraryId, topic=SETUP_GUIDE.format(library="Spring Boot", framework="Kotlin"))
```

If a query doesn't fit any template, use a free-form question but keep it concise (< 50 words).
