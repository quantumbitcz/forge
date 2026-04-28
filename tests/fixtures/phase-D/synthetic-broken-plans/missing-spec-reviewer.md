# Broken plan: test task missing spec-reviewer prompt (W3 violation)

## Phase 1: Add greeting

### Task 1.1: Write test for greet()

**Type:** test
**File:** tests/unit/greet_test.py
**Risk:** low
**ACs covered:** AC-1

**Implementer prompt:**
You are implementing one task from a plan. Build exactly what the task says.
Task: write a failing test asserting greet("World") == "Hello, World!".

- [ ] Step 1: Write the failing test.
- [ ] Step 2: Run pytest, confirm FAIL.
- [ ] Step 3: Commit.

### Task 1.2: Implement greet()

**Type:** implementation
**File:** src/greet.py
**Risk:** low
**Depends on:** Task 1.1
**ACs covered:** AC-1

**Implementer prompt:**
Implement greet() returning "Hello, <name>!". Make Task 1.1's test pass.

- [ ] Step 1: Write minimal implementation.
- [ ] Step 2: Run pytest, confirm PASS.
- [ ] Step 3: Commit.
