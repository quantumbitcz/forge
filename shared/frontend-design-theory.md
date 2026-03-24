# Frontend Design Theory Guardrails

Shared reference for all frontend agents (`pl-320-frontend-polisher`, `frontend-design-reviewer`, `frontend-a11y-reviewer`, `frontend-reviewer`). These are actionable design rules distilled from established theory — not textbook abstractions. Agents that CREATE (polisher) use these to guide implementation. Agents that EVALUATE (reviewers) use these as scoring criteria.

---

## 1. Gestalt Principles (as Code Rules)

These perceptual laws determine how users group and interpret visual elements. Violations cause confusion; adherence creates intuitive layouts.

### Proximity — Space Defines Relationship

- **Rule:** Related elements must be closer together than unrelated elements. No exceptions.
- **Measurement:** Intra-group spacing < inter-group spacing by at least 2x.
- **Check:** If two elements are equidistant from their group AND from an unrelated element, the grouping is ambiguous — fix the spacing.
- **Common violation:** Form labels equidistant from the field above and below. Fix: label must be significantly closer to its own field.

### Similarity — Visual Sameness Implies Same Function

- **Rule:** Elements that do the same thing must look the same. Elements that do different things must look different.
- **Check:** Same-function items (nav links, action buttons, data cards) must share: font size, weight, color, padding, border radius.
- **Common violation:** Two buttons with different padding that serve the same role. Fix: extract to a shared component/class.

### Continuity — Eyes Follow Lines and Curves

- **Rule:** Align elements along clear visual lines (horizontal, vertical, or diagonal). Misalignment breaks flow.
- **Check:** Grid alignment must be consistent. If 4 of 5 elements align to a left edge and 1 doesn't, that's a violation.
- **Common violation:** Mixed alignment in a card — icon left-aligned, title center-aligned, description justified. Fix: pick one alignment and commit.

### Closure — Implied Shapes Reduce Clutter

- **Rule:** Use borders, backgrounds, or whitespace to define regions — you don't need all four sides of a box to imply one.
- **Check:** Over-bordered UIs (every section has explicit 1px borders on all sides) are visually heavy. Prefer implied boundaries via spacing and backgrounds.
- **Common violation:** Nested bordered boxes creating a "cage" effect. Fix: remove inner borders, use background color difference.

### Figure-Ground — Content Must Stand Out from Background

- **Rule:** Primary content (text, actions, data) must clearly separate from background. Achieve via contrast, elevation, or color.
- **Check:** If you squint at the UI, can you immediately distinguish interactive elements from decorative/background elements? If not, figure-ground is weak.
- **Common violation:** Ghost buttons on a busy background. Fix: add background or increase border contrast.

---

## 2. Visual Hierarchy (Scoring Framework)

Every screen must have ONE primary focal point, a clear secondary level, and everything else recedes. If everything screams for attention, nothing gets it.

### Hierarchy Tools (strongest to weakest)

1. **Size** — largest element gets attention first
2. **Color contrast** — high contrast elements draw the eye before low contrast
3. **Weight** — bold/heavy type reads before light/regular
4. **Position** — top-left (LTR languages) reads before bottom-right
5. **Space** — isolated elements with generous whitespace command more attention than crowded ones
6. **Depth** — elevated elements (shadows, overlays) appear "closer" and draw focus

### The Squint Test

Blur or squint at the interface. You should be able to identify:
1. The primary action or content (in <1 second)
2. The secondary information layer
3. The navigation/chrome

If the hierarchy is unclear when squinted, it needs work.

### Heading Scale

- H1: Page title — one per page, largest text element
- H2: Section headers — clear visual break, significant size reduction from H1
- H3: Subsection — smaller than H2 but still distinct from body
- Body: Default reading text — most content lives here
- Caption/label: Smallest — metadata, timestamps, helper text

**Minimum ratio:** Each level should be at least 1.2x the size of the next level down. Recommended: 1.25x (major third) or 1.333x (perfect fourth) scale.

---

## 3. Color Theory (Actionable Rules)

### The 60/30/10 Rule

- **60%** — Dominant color (background, large surfaces). Should be neutral or very muted.
- **30%** — Secondary color (cards, sections, secondary UI). Complementary to dominant.
- **10%** — Accent color (CTAs, active states, highlights). This is where brand personality lives.

Violation: evenly distributed colors (33/33/33) create visual noise with no hierarchy.

### Semantic Color Meaning

- **Green/Emerald:** Success, positive, growth, confirmation
- **Red/Rose:** Error, danger, destructive action, critical alert
- **Amber/Yellow:** Warning, caution, pending, needs attention
- **Blue:** Information, neutral action, link, trusted
- **Gray:** Disabled, secondary, muted, placeholder

**Rule:** Never use semantic colors for decorative purposes. A green button that doesn't mean "success" confuses users.

### Contrast Requirements (WCAG)

- Normal text (< 18px): **4.5:1** minimum contrast ratio
- Large text (>= 18px or >= 14px bold): **3:1** minimum
- UI components and graphical objects: **3:1** minimum
- Decorative elements: no requirement
- **Dark mode:** Re-verify all contrast ratios — many pass in light but fail in dark

### Color Harmony Patterns

- **Monochromatic:** One hue, vary lightness/saturation. Safe, always works. Can feel bland.
- **Complementary:** Opposite on color wheel. High contrast, vibrant. Use accent sparingly.
- **Analogous:** Adjacent hues. Harmonious, natural. Good for backgrounds and subtle palettes.
- **Split-complementary:** One base + two adjacent to its complement. Dynamic but balanced.

**Anti-AI rule:** Never default to purple-blue gradient on white. If the design direction isn't specified, pick an unexpected but cohesive palette.

---

## 4. Typography Rules

### Font Selection

- **Display/headline:** Choose a distinctive, characterful font. Avoid Inter, Roboto, Arial for headlines.
- **Body:** Readability first. System fonts, Inter, or other clean sans-serif are fine HERE.
- **Mono:** For code, data, technical content. JetBrains Mono, Fira Code, or similar.
- **Maximum fonts:** 2 families for most projects (display + body). 3 max (display + body + mono).

### Font Pairing Rules

- Pair fonts with **contrasting** characteristics (serif + sans, geometric + humanist). Similar fonts look like a mistake.
- Share a similar **x-height** for visual harmony when used on the same line.
- The display font carries personality; the body font stays neutral.

### Type Scale

Use a mathematical ratio to define sizes. Never use arbitrary pixel values.

| Scale | Ratio | Character |
|-------|-------|-----------|
| Minor second | 1.067 | Very tight, minimal variation |
| Major second | 1.125 | Subtle, elegant |
| Minor third | 1.2 | Balanced, versatile (recommended for UI) |
| Major third | 1.25 | Clear hierarchy, good for content-heavy |
| Perfect fourth | 1.333 | Strong hierarchy, editorial feel |
| Golden ratio | 1.618 | Dramatic, best for marketing/landing |

### Line Height and Length

- **Body text line-height:** 1.5 (unitless)
- **Headings line-height:** 1.1-1.3 (tighter for large text)
- **Optimal line length:** 45-75 characters (`max-width: 65ch` is a safe default)
- **Narrow columns:** 30-40 characters (sidebars, cards)

### Weight Hierarchy

- **Bold (700):** Headings, labels, emphasis
- **Semi-bold (600):** Sub-headings, interactive element text
- **Regular (400):** Body text, descriptions
- **Light (300):** Use sparingly — only for large display text, not body

---

## 5. Spacing System (8pt Grid)

### The Rule

All spacing, padding, margin, and gap values are multiples of 8px: **4, 8, 12, 16, 24, 32, 40, 48, 64, 80, 96**.

Exception: 4px for micro-adjustments (icon padding, border offsets). 12px for tight groups.

### Spacing Semantics

- **4px:** Micro — icon-to-label gap, inline badge padding
- **8px:** Tight — related items within a group, input padding
- **16px:** Standard — default spacing between elements, card padding
- **24px:** Comfortable — section padding, between distinct groups
- **32px:** Generous — between major sections
- **48-64px:** Spacious — page-level section breaks
- **80-96px:** Dramatic — hero sections, landing page rhythm

### The Proximity Rule (Quantified)

Given three elements A, B, C where A and B are related:
- `gap(A, B)` < `gap(B, C)` — always
- Recommended: `gap(A, B)` <= 0.5 * `gap(B, C)` — group membership is unambiguous

### Consistent Rhythm

- Pick 2-3 spacing values for a component and stick with them
- Vertical rhythm: use the same base unit for all vertical spacing within a section
- Inconsistent spacing (16px here, 18px there, 20px elsewhere) looks sloppy even if each value seems reasonable in isolation

---

## 6. Motion Principles (UI-Adapted)

### Purpose Taxonomy

Every animation must serve exactly one purpose. If you can't name it, remove it.

| Purpose | Example | Timing |
|---------|---------|--------|
| **Guide** | Draw attention to a new element, indicate where to look | 200-400ms |
| **Confirm** | Button press feedback, save confirmation, toggle state | 100-200ms |
| **Clarify** | Show relationship between elements (expand/collapse, parent-child) | 200-350ms |
| **Continuity** | Route transition, page context preserved across navigation | 300-500ms |
| **Delight** | Celebration (confetti on goal completion), Easter egg | 400-800ms |

### The 12 Principles (UI-Distilled)

From Disney's animation principles, adapted for interface design:

1. **Easing** — Never linear. Ease-out for entrances (arrive fast, settle slow). Ease-in for exits (start slow, leave fast).
2. **Anticipation** — Slight pull-back before action (button scale down before up on press).
3. **Staging** — Only one thing moves at a time. If everything moves, nothing is staged.
4. **Follow-through** — Elements overshoot slightly then settle (spring physics achieves this naturally).
5. **Overlap** — Related elements start at different times (stagger: 50-80ms offset per item).
6. **Secondary action** — Supporting motion that reinforces primary (icon spins while panel opens).

The other 6 (squash/stretch, slow-in-out, arcs, timing, exaggeration, solid drawing) are less relevant for UI but the spirit applies: **motion should feel physical and natural, not mechanical**.

### Spring Physics Configuration

Springs produce natural motion because they simulate real-world physics. Configure via:

| Preset | Stiffness | Damping | Mass | Feel |
|--------|-----------|---------|------|------|
| Snappy | 400 | 30 | 0.8 | Quick, responsive (buttons, toggles) |
| Standard | 300 | 30 | 1.0 | Balanced (panels, cards, reveals) |
| Gentle | 200 | 25 | 1.2 | Soft, luxurious (modals, page transitions) |
| Bouncy | 500 | 15 | 1.0 | Playful, energetic (celebrations, games) |

### Performance Budget

- Target: 60fps (16.66ms per frame)
- Only animate: `transform` (translate, scale, rotate) and `opacity`
- `will-change`: apply just before animation starts, remove after
- Maximum simultaneous animations: 3-5 (more causes frame drops on mobile)
- Always test on low-end devices (budget Android, older iPhone SE)

---

## 7. Anti-AI Guardrails

These patterns are statistically over-represented in AI-generated UI. Avoiding them is necessary (not sufficient) for professional output.

### Visual Signatures to Avoid

| AI Pattern | Why It Happens | Professional Alternative |
|------------|---------------|------------------------|
| Inter/system sans-serif everywhere | Most common in training data | Distinctive display font + neutral body |
| Purple-blue gradient on white | Default "modern" in training data | Committed palette with 60/30/10 split |
| Identical rounded cards in a grid | Simplest layout pattern | Varied card sizes, asymmetric grids, featured items |
| Even color distribution | No hierarchy decision made | One dominant surface color, one accent |
| Flat surfaces, no depth | Shadow/elevation not default | Layered surfaces, subtle shadows, backdrop blur |
| Generic hero with centered text | Most common landing pattern | Asymmetric layout, strong visual anchor, unexpected composition |
| Decorative animations everywhere | "Make it feel alive" | One orchestrated moment, purposeful micro-interactions |
| Stock illustration style | Default AI art direction | Photography, custom icons, or no imagery (let typography carry) |

### Distinctiveness Checklist

Before considering frontend implementation complete, verify:

- [ ] Can you identify the brand/product from the UI alone (without logo)?
- [ ] Does the typography have character beyond "clean sans-serif"?
- [ ] Is there at least one unexpected spatial or layout choice?
- [ ] Does the color palette feel intentional, not defaulted?
- [ ] Is there visual depth (shadows, layers, texture) or is it flat?
- [ ] Would a designer recognize this as "designed" vs "generated"?

### The "First Impression" Test

Cover the content and look only at the visual structure:
- Can you tell this apart from a generic template?
- Does it have a coherent visual personality?
- Is there a clear focal point?

If the answer to any is "no," the design needs more intentional direction.

---

## 8. Multi-Viewport Design Theory

### Mobile-First Is Content-First

Design for the smallest viewport first because it forces priority decisions. What survives the 375px cut is your most important content.

### Viewport Behavior Matrix

| Element | Mobile (375px) | Tablet (768px) | Desktop (1280px+) |
|---------|---------------|----------------|-------------------|
| Navigation | Bottom tabs or hamburger | Sidebar (collapsed) or top | Full sidebar or top nav |
| Layout | Single column | 2 columns where natural | Multi-column, grid layouts |
| Touch targets | 44px minimum | 44px minimum | 32px minimum (cursor precision) |
| Typography | 16px body minimum | 16px body | 16px body, larger headings |
| Images | Full-width, lazy-loaded | Adaptive sizing | Full resolution where needed |
| Whitespace | Tighter (preserve scroll) | Balanced | Generous (use the space) |
| Interactions | Tap, swipe, long-press | Tap + hover hybrid | Hover, click, keyboard |
| Data tables | Card view or horizontal scroll | Partial columns | Full columns |

### Responsive vs Adaptive

- **Responsive** (fluid): single layout that scales via `%, vw, clamp(), container queries`. Use for most content.
- **Adaptive** (breakpoint-switched): distinct layouts per breakpoint. Use for navigation patterns and complex data views that fundamentally change at different sizes.
- **Rule:** Use responsive by default, adaptive only when the mobile and desktop experiences are structurally different.

### Touch Zone Theory (Mobile)

The "thumb zone" on mobile determines where primary actions should live:

- **Easy reach** (bottom center): primary CTA, main navigation
- **Stretch** (top, corners): secondary actions, settings
- **Avoid** (top-left corner on right-handed phones): don't put frequent actions here

Navigation at the bottom of the screen (iOS tab bar, Android bottom nav) is not just a convention — it's ergonomically correct.
