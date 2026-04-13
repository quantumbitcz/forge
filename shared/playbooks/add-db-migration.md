---
name: add-db-migration
description: Add a database schema migration with rollback
version: "1.0"
mode: standard
parameters:
  - name: entity
    description: The entity or table being modified (PascalCase)
    type: string
    required: true
    validation: "^[A-Z][a-zA-Z]+$"
  - name: change_type
    description: Type of schema change
    type: enum
    required: true
    allowed_values: [add_table, add_column, rename_column, drop_column, add_index, modify_type, add_constraint]
  - name: target_db
    description: Target database system
    type: enum
    default: auto
    allowed_values: [auto, postgresql, mysql, sqlite, mssql, mongodb]
  - name: columns
    description: Column definitions for add_table or add_column (e.g., "name:string:required, email:string:unique")
    type: string
    required: false
stages:
  skip: []
  focus:
    REVIEWING:
      review_agents: [fg-410-code-reviewer, fg-412-architecture-reviewer]
review:
  focus_categories: ["ARCH-*", "SEC-*", "TEST-*", "QUAL-*"]
  min_score: 90
scoring:
  critical_weight: 20
  warning_weight: 5
acceptance_criteria:
  - "GIVEN the migration WHEN applied to an empty database THEN the {{entity}} schema is created correctly"
  - "GIVEN the migration WHEN rolled back THEN the database returns to its previous state"
  - "GIVEN the migration WHEN applied to a database with existing data THEN no data is lost"
  - "GIVEN the {{change_type}} change WHEN the migration runs THEN it completes without errors"
  - "GIVEN the migration file WHEN inspected THEN it follows the project's migration naming and structure conventions"
  - "Integration test verifies migration up and down paths"
tags: [database, migration, schema, sql, rollback]
---

## Requirement Template

Add a database migration to **{{change_type}}** for the **{{entity}}** entity.

### Migration Details
- **Entity:** {{entity}}
- **Change type:** {{change_type}}
{{#if (eq target_db "auto")}}
- **Target database:** Auto-detect from project configuration
{{else}}
- **Target database:** {{target_db}}
{{/if}}
{{#if columns}}
- **Columns:** {{columns}}
{{/if}}

### Requirements

#### Migration File
- Follow the project's migration framework conventions (naming, directory, numbering)
- Use the project's migration tool (detect from existing migrations: Flyway, Liquibase, Alembic, Knex, Prisma, TypeORM, Active Record, etc.)
- Include both UP (apply) and DOWN (rollback) migrations

#### Schema Design
{{#if (eq change_type "add_table")}}
- Create the {{entity}} table with appropriate columns, primary key, and constraints
- Include `created_at` and `updated_at` timestamps if the project convention uses them
- Add appropriate indexes for columns that will be queried frequently
{{else if (eq change_type "add_column")}}
- Add the column(s) to the existing {{entity}} table
- Use a safe default value or make nullable to avoid breaking existing rows
- Consider if an index is needed for the new column
{{else if (eq change_type "rename_column")}}
- Rename the column on the {{entity}} table
- Update any ORM/model references to use the new column name
{{else if (eq change_type "drop_column")}}
- Remove the column from the {{entity}} table
- Ensure no application code references the dropped column
- DOWN migration must restore the column with its original type and constraints
{{else if (eq change_type "add_index")}}
- Add the index to the {{entity}} table
- Use concurrent index creation if supported by the database to avoid locking
{{else if (eq change_type "modify_type")}}
- Modify the column type on the {{entity}} table
- Ensure the type change is compatible with existing data
{{else if (eq change_type "add_constraint")}}
- Add the constraint to the {{entity}} table
- Verify existing data satisfies the constraint before applying
{{/if}}

#### Safety
- Migration must be idempotent where possible (check before apply)
- Large table migrations should use batching if the table has significant data
- DOWN migration fully reverses the UP migration
- Update the entity model/ORM mapping to reflect the schema change
- Add or update integration tests that verify the migration
