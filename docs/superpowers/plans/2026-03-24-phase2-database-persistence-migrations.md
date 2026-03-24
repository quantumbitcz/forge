# Phase 2: Database + Persistence + Migrations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate the database, persistence, and migrations module layers with best-practice convention files, plus framework bindings for all applicable frameworks.

**Architecture:** Each generic module file follows the standard structure (Overview, Architecture Patterns, Configuration, Performance, Security, Testing, Dos, Don'ts). Framework bindings follow a shorter structure (Integration Setup, Framework-Specific Patterns, Scaffolder Patterns, Additional Dos/Don'ts). Bindings EXTEND the generic module.

**Tech Stack:** Markdown only — convention documentation files.

**Spec:** `docs/superpowers/specs/2026-03-24-crosscutting-modules-design.md` (Sections 6.1-6.3, 10.1)

---

### Task 1: Database Modules — SQL Engines

**Files:**
- Create: `modules/databases/postgresql.md`
- Create: `modules/databases/mysql.md`
- Create: `modules/databases/sqlite.md`

Each file follows the generic module structure with engine-specific best practices per the spec's Section 6.1.

---

### Task 2: Database Modules — NoSQL & Analytics

**Files:**
- Create: `modules/databases/mongodb.md`
- Create: `modules/databases/redis.md`
- Create: `modules/databases/clickhouse.md`
- Create: `modules/databases/dynamodb.md`
- Create: `modules/databases/cassandra.md`

---

### Task 3: Persistence Modules — JVM

**Files:**
- Create: `modules/persistence/hibernate.md`
- Create: `modules/persistence/exposed.md`
- Create: `modules/persistence/jooq.md`
- Create: `modules/persistence/koog.md`
- Create: `modules/persistence/r2dbc.md`

---

### Task 4: Persistence Modules — Python + JS/TS + Mobile

**Files:**
- Create: `modules/persistence/sqlalchemy.md`
- Create: `modules/persistence/django-orm.md`
- Create: `modules/persistence/prisma.md`
- Create: `modules/persistence/typeorm.md`
- Create: `modules/persistence/drizzle.md`
- Create: `modules/persistence/mongoose.md`
- Create: `modules/persistence/room.md`
- Create: `modules/persistence/sqldelight.md`

---

### Task 5: Migration Modules — All 8

**Files:**
- Create: `modules/migrations/flyway.md`
- Create: `modules/migrations/liquibase.md`
- Create: `modules/migrations/alembic.md`
- Create: `modules/migrations/prisma-migrate.md`
- Create: `modules/migrations/django-migrations.md`
- Create: `modules/migrations/knex.md`
- Create: `modules/migrations/diesel.md`
- Create: `modules/migrations/sqlx.md`

---

### Task 6: Framework Bindings — Spring

**Files:**
- Create: `modules/frameworks/spring/databases/postgresql.md`
- Create: `modules/frameworks/spring/persistence/hibernate.md`
- Create: `modules/frameworks/spring/persistence/exposed.md`
- Create: `modules/frameworks/spring/persistence/jooq.md`
- Create: `modules/frameworks/spring/persistence/r2dbc.md`
- Create: `modules/frameworks/spring/migrations/flyway.md`
- Create: `modules/frameworks/spring/migrations/liquibase.md`

---

### Task 7: Framework Bindings — FastAPI + Django

**Files:**
- Create: `modules/frameworks/fastapi/persistence/sqlalchemy.md`
- Create: `modules/frameworks/fastapi/migrations/alembic.md`
- Create: `modules/frameworks/fastapi/databases/postgresql.md`
- Create: `modules/frameworks/django/persistence/django-orm.md`
- Create: `modules/frameworks/django/migrations/django-migrations.md`
- Create: `modules/frameworks/django/databases/postgresql.md`

---

### Task 8: Framework Bindings — Express + Axum

**Files:**
- Create: `modules/frameworks/express/persistence/prisma.md`
- Create: `modules/frameworks/express/persistence/typeorm.md`
- Create: `modules/frameworks/express/persistence/drizzle.md`
- Create: `modules/frameworks/express/persistence/mongoose.md`
- Create: `modules/frameworks/express/migrations/knex.md`
- Create: `modules/frameworks/express/migrations/prisma-migrate.md`
- Create: `modules/frameworks/axum/persistence/diesel.md`
- Create: `modules/frameworks/axum/persistence/sqlx.md`
- Create: `modules/frameworks/axum/migrations/diesel.md`
- Create: `modules/frameworks/axum/migrations/sqlx.md`

---

### Task 9: Framework Bindings — Remaining

**Files:**
- Create: `modules/frameworks/gin/persistence/gorm.md` (adding GORM — Go's primary ORM)
- Create: `modules/frameworks/aspnet/persistence/efcore.md` (Entity Framework Core)
- Create: `modules/frameworks/aspnet/migrations/efcore-migrations.md`
- Create: `modules/frameworks/jetpack-compose/persistence/room.md`
- Create: `modules/frameworks/kotlin-multiplatform/persistence/sqldelight.md`

---

### Task 10: Learnings Files + Validation

**Files:**
- Create: learnings files for key technologies
- Remove: `.gitkeep` from populated directories
- Run: validation

---

## Summary

| Task | Layer | Count |
|------|-------|-------|
| 1 | Databases (SQL) | 3 files |
| 2 | Databases (NoSQL) | 5 files |
| 3 | Persistence (JVM) | 5 files |
| 4 | Persistence (Python/JS/Mobile) | 8 files |
| 5 | Migrations (all) | 8 files |
| 6 | Bindings: Spring | 7 files |
| 7 | Bindings: FastAPI + Django | 6 files |
| 8 | Bindings: Express + Axum | 10 files |
| 9 | Bindings: Remaining | 5 files |
| 10 | Learnings + Validation | cleanup |
| **Total** | | **~57 files** |
