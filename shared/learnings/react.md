# Cross-Project Learnings: react

## PREEMPT items

### RV-PREEMPT-001: Always check TypeScript compiles after component changes
- **Domain:** build
- **Pattern:** Run tsc --noEmit before writing tests to catch type errors early
- **Confidence:** HIGH
- **Hit count:** 0

### RV-PREEMPT-002: Typography uses inline style, not Tailwind text-* classes
- **Domain:** styling
- **Pattern:** Use style={{ fontSize: '...' }} instead of text-sm/text-lg classes
- **Confidence:** HIGH
- **Hit count:** 0

### RV-PREEMPT-003: Colors must use theme tokens, never hardcoded hex
- **Domain:** styling
- **Pattern:** Use bg-background, text-foreground, etc. from theme.css custom properties
- **Confidence:** HIGH
- **Hit count:** 0

## TypeScript Variant Learnings

### Common Pitfalls
<!-- Populated by retrospective agent -->

### Effective Patterns
<!-- Populated by retrospective agent -->
