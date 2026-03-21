---
name: fe-design-review
description: Comprehensive UI/UX design review of WellPlanned components against project design system and conventions
disable-model-invocation: true
---

# Design Review

Perform a comprehensive UI/UX design review of specified components or pages against WellPlanned's design system.

## Arguments

The user provides a component, page, or feature area to review.

## Review Checklist

### 1. Visual Design System Compliance

**Typography** — Must use inline `style={{ fontSize }}`:

- [ ] No Tailwind text-size classes (`text-sm`, `text-lg`, etc.) — use inline fontSize
- [ ] Sizes follow the scale: 1.1rem (page heading) → 0.55rem (tiny annotation)
- [ ] Weights match purpose (600 headings, 400-500 body, 500-600 labels)

**Colors** — Must use CSS custom properties:

- [ ] No hardcoded colors (`bg-white`, `#fff`, `bg-gray-100`)
- [ ] Using `bg-background`, `bg-card`, `text-foreground`, `border-border`
- [ ] Surface hierarchy correct: `bg-card` → `bg-muted/30` → `bg-muted/20`
- [ ] Status colors semantic: emerald (success), amber (warning), red/destructive (danger)

**Spacing & Layout**:

- [ ] Gap scale: `gap-2` tight, `gap-3` related, `gap-5` distinct, `gap-6` top-level
- [ ] Border subtlety: `border-border/50` sections, `border-border/30` dividers
- [ ] Corners: `rounded-lg` cards, `rounded-xl` containers, `rounded-full` pills
- [ ] Shadows subtle: `shadow-sm`/`shadow-md` only

### 2. Dark Mode Verification

- [ ] All custom properties resolve in both `:root` and `.dark`
- [ ] Prefer borders over shadows in dark mode
- [ ] No pure white/black that would look jarring

### 3. Responsive & Progressive Disclosure

- [ ] Show 20% of controls for 80% of use cases
- [ ] Advanced options behind expandable sections or `...` menus
- [ ] Layout works at common viewport sizes

### 4. Empty States

- [ ] Every data-dependent section handles zero-state
- [ ] Uses `EmptyChartState` for chart areas
- [ ] No broken charts, NaN values, or blank space

### 5. Accessibility

- [ ] All interactive elements keyboard-accessible
- [ ] Icon-only buttons have `title` or `aria-label`
- [ ] Color paired with icons for status indication
- [ ] Focus rings visible on keyboard navigation

### 6. Charts (recharts)

- [ ] Tooltip uses `CHART_TOOLTIP_STYLE`
- [ ] Wrapped in `<ResponsiveContainer>` inside fixed-height parent
- [ ] Heights: `h-52` standard, `h-56` complex, `h-36` compact
- [ ] Grid: `strokeDasharray="3 3" stroke="var(--border)"`
- [ ] Axis ticks: `fontSize: 11, fill: "var(--muted-foreground)"`

### 7. Interaction & Feedback

- [ ] Every action produces visible feedback within 100ms
- [ ] Toast notifications via `sonner` for mutations
- [ ] Drag targets show visual feedback (border on canDrop, background on isOver)

### 8. Design Philosophy

- [ ] "Does this make the coach's or client's life simpler?"
- [ ] Reduce, don't add — can this be automated, inferred, or removed?
- [ ] One way to do each thing
- [ ] Intentionality, not intensity — avoid generic "AI slop" aesthetics

## Output Format

For each finding:

```
[SEVERITY] file:line — Description
  Fix: Suggested change
```

Severities: CRITICAL (breaks design system), WARNING (convention violation), INFO (improvement opportunity)

## After Review

Offer to fix the issues found, starting with CRITICAL items.
