---
name: Gluegun
description: Bold, high-energy developer documentation for a typed Gleam wrapper around Erlang Gun.
colors:
  gunmetal-ink: "#100b1d"
  midnight-purple: "#241024"
  deep-violet: "#501060"
  plum-rail: "#7d2a70"
  soft-plum: "#b060a0"
  charged-magenta: "#ff1070"
  command-magenta: "#c00050"
  blush-panel: "#ffe1ec"
  pale-signal: "#ffe8f0"
  light-pink: "#ffc0d8"
  frost-white: "#ffffff"
  shell-white: "#fff7fa"
typography:
  display:
    fontFamily: "Bricolage Grotesque Variable, var(--sl-font-system)"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Bricolage Grotesque Variable, var(--sl-font-system)"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Hanken Grotesk Variable, var(--sl-font-system)"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: "Hanken Grotesk Variable, var(--sl-font-system)"
    fontWeight: 600
    lineHeight: 1.2
  code:
    fontFamily: "JetBrains Mono Variable, var(--sl-font-system-mono)"
    fontWeight: 400
components:
  button-primary:
    backgroundColor: "{colors.charged-magenta}"
    textColor: "{colors.frost-white}"
    typography: "{typography.label}"
  button-secondary:
    backgroundColor: "{colors.blush-panel}"
    textColor: "{colors.deep-violet}"
    typography: "{typography.label}"
  docs-card:
    backgroundColor: "{colors.midnight-purple}"
    textColor: "{colors.pale-signal}"
    typography: "{typography.body}"
---

# Design System: Gluegun

## 1. Overview

**Creative North Star: "The Charged Lab Manual"**

Gluegun's visual system should feel like technical documentation with live current running through it: precise enough for production developers, vivid enough to be remembered after a quick package evaluation. The Astro/Starlight site commits to a magenta-and-purple identity with a two-voice type system — Bricolage Grotesque headings over Hanken Grotesk body, JetBrains Mono for code; future work should deepen that identity rather than replacing it with generic developer-docs gray.

The system rejects toy-like candy branding that undercuts technical trust. Energy should come from saturated accent, confident contrast, direct copy, and strong examples, not novelty shapes or decorative gimmicks.

**Key Characteristics:**
- Saturated magenta and violet are identity colors, not occasional decoration.
- Bricolage Grotesque headings over a Hanken Grotesk body keep the voice direct and technical while giving the brand real typographic character.- Documentation density should stay scannable: short sections, explicit examples, and clear module mapping.
- Framework defaults are acceptable only when they preserve the bold Gluegun palette.

## 2. Colors

The palette is a charged magenta/purple system: dark mode feels like a compact instrument panel, while light mode keeps the same hue family instead of falling back to neutral grays.

### Primary
- **Charged Magenta** (#ff1070): The dark-theme primary accent for primary actions, active links, emphasis, and selected states.
- **Command Magenta** (#c00050): The light-theme primary accent, tuned darker so text and controls stay legible on pale surfaces.

### Secondary
- **Deep Violet** (#501060): The structural brand color used for high-contrast text, dark rails, and accent-high roles.
- **Plum Rail** (#7d2a70): Mid-ramp structure for borders, inactive navigation, dividers, and quieter affordances.
- **Soft Plum** (#b060a0): Secondary text or lower-emphasis UI in the magenta family.

### Neutral
- **Gunmetal Ink** (#100b1d): The darkest surface and primary light-theme text.
- **Midnight Purple** (#241024): Dark-mode panels and secondary structural surfaces.
- **Blush Panel** (#ffe1ec): Light-mode accent-low backgrounds and soft callout surfaces.
- **Pale Signal** (#ffe8f0): Dark-mode high-contrast text and light highlight material.
- **Light Pink** (#ffc0d8): Dark-mode secondary text and pale separators.
- **Frost White** (#ffffff): Dark-mode foreground and pure light-theme background.
- **Shell White** (#fff7fa): Light-mode page surface where a softer background is needed.

### Named Rules

**The Same-Hue Neutral Rule.** Neutral UI should remain in the purple/magenta family. Do not introduce default slate or blue-gray ramps unless a third-party component forces it and the values are overridden at the boundary.

**The No Gradient Text Rule.** Do not use gradient text, even for hero headings. The brand already has enough charge in solid magenta and violet.

## 3. Typography

**Display / Heading Font:** Bricolage Grotesque (variable, with Starlight system fallback)
**Body / UI Font:** Hanken Grotesk (variable, with Starlight system fallback)
**Code Font:** JetBrains Mono (variable; drives inline code and Expressive Code blocks via `--sl-font-mono`)

**Character:** Bricolage Grotesque gives headings a confident, slightly mechanical voice that matches the charged-lab personality; Hanken Grotesk is a calm, highly legible workhorse for long-form docs. The two pair on a contrast axis (expressive display vs. quiet body) rather than as two near-identical sans-serifs. JetBrains Mono is a deliberate code face, not faux-terminal decoration; ligatures stay on.

### Hierarchy
- **Display** (Bricolage 700, fluid Starlight hero scale, ~1.05 line-height): Splash-page headlines and one dominant idea per landing surface.
- **Headline** (Bricolage 700, section heading scale, ~1.15 line-height): Guide and reference section headings.
- **Title** (Bricolage 600, compact heading scale): Card titles, navigation group names, and module names.
- **Body** (Hanken 400, readable docs scale, ~1.65 line-height): Long-form documentation, capped around 65-75ch where layout allows.
- **Label** (Hanken 600, compact scale): Buttons, nav labels, badges, and short interface labels.

The heading scale follows a deliberate 1.25 modular ratio (`--sl-text-*` overrides) so hierarchy reads as committed, not flat.

### Named Rules

**The Two-Voice Type Rule.** Headings speak in Bricolage Grotesque; body and UI speak in Hanken Grotesk; code speaks in JetBrains Mono. Keep these three roles distinct and don't reintroduce a single-family flattening or borrow monospace as lazy shorthand for "developer" outside of code.

## 4. Elevation

The current system is primarily tonal rather than shadow-led. Starlight surfaces, cards, sidebars, and callouts should separate through hue, contrast, and borders before shadows. If shadows are introduced, they should be stateful and restrained, never paired with decorative 1px borders and wide soft blur.

### Named Rules

**The Tonal-First Rule.** Use magenta/violet surface shifts for depth before adding drop shadows.

## 5. Components

### Buttons
- **Shape:** Inherit Starlight's button shape unless a page-specific treatment is intentionally designed.
- **Primary:** Charged Magenta (#ff1070) in dark mode or Command Magenta (#c00050) in light mode with high-contrast text.
- **Hover / Focus:** Preserve visible focus states; hover can shift toward Deep Violet but must keep contrast.
- **Secondary / Ghost / Tertiary:** Use Blush Panel, Deep Violet, and transparent treatments from the same hue family.

### Chips
- **Style:** Use soft magenta/purple fills with dark plum text in light mode, or deep violet fills with pale pink text in dark mode.
- **State:** Active chips should be obvious through fill and text contrast, not only border color.

### Cards / Containers
- **Corner Style:** Let Starlight defaults stand; do not over-round cards into 24px+ "bubble" shapes.
- **Background:** Use Midnight Purple, Deep Violet, Blush Panel, or Shell White according to theme.
- **Shadow Strategy:** Follow the tonal-first elevation rule.
- **Border:** Use subtle same-hue borders when needed; never side-stripe borders as accent.
- **Internal Padding:** Keep Starlight's docs density unless a landing section needs more breathing room.

### Inputs / Fields
- **Style:** Inherit framework field structure, then tune color tokens to the magenta/violet ramp.
- **Focus:** Focus states must be highly visible and keyboard-first.
- **Error / Disabled:** Error states should remain explicit and readable; disabled states should not rely on low-contrast gray.

### Navigation
- **Style, typography, default/hover/active states, mobile treatment.** Navigation should feel like a fast reference surface: compact, clear, and strongly active-state oriented. Keep topic rails and sidebar labels legible against both dark and light themes.

### Splash Lab Panel

The splash page uses a code-led lab panel instead of a repeated feature-card grid. Keep this pattern asymmetric and task-oriented: one strong claim, one real Gleam snippet, and a short reading path that moves developers from quick start to streaming to WebSockets.

## 6. Do's and Don'ts

### Do:
- **Do** preserve the magenta/purple identity from `website/src/styles/custom.css`.
- **Do** use solid Charged Magenta or Command Magenta for emphasis instead of gradient text.
- **Do** keep examples and API claims concrete; the brand is playful, but the docs should stay precise.
- **Do** verify AA contrast whenever using Soft Plum, Light Pink, or Blush Panel for text.
- **Do** provide reduced-motion fallbacks for any future animated landing or docs interactions.

### Don't:
- **Don't** make the site feel like toy-like candy branding that undercuts technical trust.
- **Don't** use gradient text (`background-clip: text` with a gradient background).
- **Don't** introduce generic slate/blue-gray developer-docs defaults where same-hue purple neutrals can do the job.
- **Don't** use side-stripe borders, glassmorphism, or identical card grids as default decoration.
- **Don't** use monospace as lazy shorthand for technical credibility.
