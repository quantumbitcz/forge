---
name: add-rest-endpoint
description: Add a new REST API endpoint with tests, validation, and docs
version: "1.0"
mode: standard
parameters:
  - name: entity
    description: The domain entity name (PascalCase)
    type: string
    required: true
    validation: "^[A-Z][a-zA-Z]+$"
  - name: operations
    description: CRUD operations to support
    type: list
    default: [create, read, update, delete]
    allowed_values: [create, read, update, delete, list, search]
  - name: auth
    description: Authentication requirement
    type: enum
    default: required
    allowed_values: [required, optional, none]
  - name: pagination
    description: Enable pagination for list/search operations
    type: boolean
    default: true
stages:
  skip: []
  focus:
    REVIEWING:
      review_agents: [fg-410-code-reviewer, fg-411-security-reviewer, fg-412-architecture-reviewer]
review:
  focus_categories: ["ARCH-*", "SEC-*", "TEST-*", "CONTRACT-*"]
  min_score: 90
scoring:
  critical_weight: 20
  warning_weight: 5
acceptance_criteria:
  - "GIVEN valid {{entity}} data WHEN POST /api/{{entity | kebab-case}}s THEN returns 201 with {{entity}} ID"
  - "GIVEN invalid {{entity}} data WHEN POST /api/{{entity | kebab-case}}s THEN returns 400 with validation errors"
  - "GIVEN authenticated user WHEN GET /api/{{entity | kebab-case}}s/:id THEN returns the {{entity}} with 200"
  - "GIVEN unauthenticated user WHEN any operation on /api/{{entity | kebab-case}}s THEN returns 401"
  - "Integration tests exist for each {{operations | join:\", \"}} operation"
  - "OpenAPI spec includes the new {{entity}} endpoints"
tags: [api, backend, rest, endpoint, crud]
---

## Requirement Template

Implement a REST API endpoint for **{{entity}}** supporting **{{operations | join:", "}}** operations.

### Entity: {{entity}}
- Create the domain entity, repository, service, and controller layers
- Follow the project's existing architectural patterns (check existing controllers for reference)

### Operations
{{#each operations}}
- **{{this}}**: Implement the {{this}} operation with proper validation and error handling
{{/each}}

### Requirements
{{#if (eq auth "required")}}
- All endpoints require authentication via the project's existing auth mechanism
{{else if (eq auth "optional")}}
- Authentication is optional -- unauthenticated users get read-only access
{{else if (eq auth "none")}}
- Endpoints are publicly accessible without authentication
{{/if}}
{{#if pagination}}
- List operations support pagination (offset/limit or cursor-based, matching existing patterns)
{{/if}}
- Input validation covers: required fields, type constraints, business rules
- Error responses follow the project's standard error format
- Integration tests cover happy path and error cases for each operation
- OpenAPI/Swagger spec is updated with the new endpoints
