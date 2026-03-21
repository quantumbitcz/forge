---
name: fe-react-doctor
description: Run react-doctor to analyze the React codebase for common issues, anti-patterns, and improvement opportunities
disable-model-invocation: true
---

# React Doctor

Run `react-doctor` to analyze the WellPlanned React codebase for common issues and anti-patterns.

## Usage

Run the analysis:

```bash
cd /Users/denissajnar/WebstormProjects/wellplanned-fe && npx -y react-doctor@latest .
```

## After Analysis

1. **Read the output** carefully — react-doctor reports issues across categories:
   - Component complexity and size
   - Hook usage patterns
   - Performance anti-patterns
   - Import/dependency issues
   - React best practices violations

2. **Prioritize fixes** by severity:
   - **Critical**: Issues that cause bugs or crashes (missing keys, state mutations)
   - **Warning**: Performance issues (unnecessary re-renders, missing memoization)
   - **Info**: Style/convention suggestions

3. **Apply fixes** following WellPlanned conventions:
   - Files over ~400 lines → extract sub-components
   - Missing `useMemo`/`useCallback` → add for derived data and prop-passed functions
   - Direct state mutations → spread/clone (use `cloneSession`, `cloneBlock`, `cloneWeekPlans`)
   - Array index keys → replace with entity ID keys

4. **Run tests** after fixing: `bun run test`

5. **Run react-doctor again** to verify fixes resolved the issues.

## When to Use

- After completing a feature or significant code changes
- Before creating a pull request
- As a periodic codebase health check
- After refactoring components
