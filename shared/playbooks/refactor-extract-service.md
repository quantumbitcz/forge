---
name: refactor-extract-service
description: Extract a service from existing code to improve modularity and separation of concerns
version: "1.0"
mode: refactor
parameters:
  - name: source_class
    description: The class or module to extract from (fully qualified name or file path)
    type: string
    required: true
  - name: target_service
    description: Name for the new extracted service (PascalCase)
    type: string
    required: true
    validation: "^[A-Z][a-zA-Z]+$"
  - name: extraction_type
    description: Type of extraction to perform
    type: enum
    default: interface
    allowed_values: [interface, module, microservice]
  - name: methods
    description: Specific methods to extract (comma-separated). Leave empty to auto-detect based on cohesion analysis
    type: string
    required: false
stages:
  skip: []
  focus:
    REVIEWING:
      review_agents: [fg-410-code-reviewer, fg-412-architecture-reviewer]
review:
  focus_categories: ["ARCH-*", "QUAL-*", "TEST-*", "CONV-*"]
  min_score: 90
scoring:
  critical_weight: 20
  warning_weight: 5
acceptance_criteria:
  - "GIVEN the extracted {{target_service}} WHEN all tests run THEN all existing tests pass without modification (or with minimal import changes)"
  - "GIVEN the extraction WHEN complete THEN {{source_class}} no longer contains the extracted responsibilities"
  - "GIVEN the new {{target_service}} WHEN inspected THEN it has a clear single responsibility and clean interface"
  - "GIVEN the extraction WHEN complete THEN no circular dependencies exist between {{source_class}} and {{target_service}}"
  - "GIVEN the new {{target_service}} WHEN tested THEN it has unit tests covering its public interface"
  - "GIVEN callers of the extracted methods WHEN inspected THEN they use {{target_service}} through its interface (not concrete implementation)"
tags: [refactor, architecture, service, extraction, modularity]
---

## Requirement Template

Extract **{{target_service}}** from `{{source_class}}` as {{#if (eq extraction_type "interface")}}an interface-backed service{{else if (eq extraction_type "module")}}a separate module{{else if (eq extraction_type "microservice")}}a separate microservice{{/if}}.

### Extraction Details
- **Source:** `{{source_class}}`
- **Target:** {{target_service}}
- **Type:** {{extraction_type}}
{{#if methods}}
- **Methods to extract:** {{methods}}
{{else}}
- **Methods to extract:** Auto-detect based on cohesion analysis of `{{source_class}}`
{{/if}}

### Requirements

#### Analysis Phase
1. Read `{{source_class}}` and identify all methods and their dependencies
{{#if methods}}
2. Verify that the specified methods ({{methods}}) exist in `{{source_class}}`
3. Map the dependency graph for the specified methods
{{else}}
2. Analyze method cohesion to identify the best candidates for extraction
3. Group methods that share data dependencies and form a logical service boundary
{{/if}}
4. Identify all callers of the methods being extracted
5. Identify shared state and cross-cutting concerns (logging, transactions, error handling)

#### Extraction
{{#if (eq extraction_type "interface")}}
- Define a **{{target_service}}** interface with the extracted method signatures
- Create a concrete implementation class (e.g., `Default{{target_service}}` or `{{target_service}}Impl`)
- Register the service in the dependency injection container
- Update `{{source_class}}` to depend on the {{target_service}} interface (constructor injection)
- Update all other callers to use the {{target_service}} interface
{{else if (eq extraction_type "module")}}
- Create a new module/package for **{{target_service}}**
- Move the extracted methods and their direct dependencies to the new module
- Define a public API surface for the module (export only what callers need)
- Update `{{source_class}}` to import from the new module
- Update the build configuration to include the new module
{{else if (eq extraction_type "microservice")}}
- Create a new service project for **{{target_service}}** following the project's service template
- Define an API contract (REST/gRPC/messaging) for communication
- Implement the extracted logic in the new service
- Replace direct method calls in `{{source_class}}` with API calls to the new service
- Add circuit breaker and timeout handling for the inter-service calls
- Add integration tests for the service boundary
{{/if}}

#### Safety
- All existing tests must pass after extraction (modify imports as needed, not test logic)
- No circular dependencies between the source and target
- No change in external behavior (callers see the same API contract)
- Add unit tests for the new {{target_service}} covering its public interface
- If the extraction changes any public API, document the change in a migration note
