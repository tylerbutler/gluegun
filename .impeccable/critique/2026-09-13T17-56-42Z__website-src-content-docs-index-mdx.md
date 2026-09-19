---
target: website
total_score: 31
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 1
timestamp: 2026-09-13T17-56-42Z
slug: website-src-content-docs-index-mdx
---
Method: dual-agent (A: de5ead39-bb49-459e-bd21-236347af3ea1 · B: 40eae47d-81e3-4a3c-8631-69467e116653)

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|-----------|------:|-----------|
| 1 | Visibility of System Status | 3/4 | Desktop navigation shows location well; mobile collapses most context into a small page menu. |
| 2 | Match System / Real World | 4/4 | Task labels match how Gleam developers think about requests, streams, TLS, and production use. |
| 3 | User Control and Freedom | 3/4 | Search, anchors, sidebar links, and next-page links provide exits, but the splash homepage removes normal docs navigation. |
| 4 | Consistency and Standards | 3/4 | Components are consistent, but the authored homepage and conventional Starlight interior pages feel like adjacent systems. |
| 5 | Error Prevention | 3/4 | Strong compatibility and production guidance exists, but it appears after the first-run path needs it. |
| 6 | Recognition Rather Than Recall | 3/4 | Search and visible module names help; mobile hides navigation and large reference groups require scanning. |
| 7 | Flexibility and Efficiency | 3/4 | Ctrl-K search, copy controls, anchors, and direct references help experts; generated API pages lack focused filtering. |
| 8 | Aesthetic and Minimalist Design | 3/4 | The reading system is clean, but the hero spends too much of the first viewport on space and secondary pink emphasis. |
| 9 | Error Recovery | 2/4 | Troubleshooting is strong, but Quick Start gives no install check, expected output, or immediate recovery path. |
| 10 | Help and Documentation | 4/4 | Searchable, task-oriented guides, advanced topics, and generated reference material form a strong system. |
| **Total** | | **31/40** | **Good** |

## Design Specificity Verdict

**LLM assessment:** The site feels distinctly Gluegun at entry, then becomes mostly standard Starlight. The glue-gun mark, gunmetal and magenta palette, Chivo headings, "HTTP without footguns," lifecycle map, and connection-first example are relevant to the product. The strongest product concept, the Gun connection lifecycle, disappears from guide and reference pages.

**Deterministic scan:** The source scan returned zero findings. Browser injection produced 25 warnings across four pages: `ai-color-palette` (8), `radial-spotlight-glow` (5), `layout-transition` (4), `low-contrast` (4), `first-viewport-column-overflow` (2), `radial-halo` (1), and `side-tab` (1). Most are false positives:

- Palette and halo warnings describe the intentional Gluegun theme.
- Code-block "spotlights" are functional horizontal-scroll shadows in `website/src/styles/custom.css`.
- Reported 1.1:1 and 1.6:1 contrast values are inconsistent with the rendered colors; measured combinations are approximately 8.50:1 and 5.83:1.
- The layout transition comes from Starlight/Pagefind search UI.
- Column overflow is the normal content/TOC layout; no page exceeded its viewport width.
- The side tab is Starlight's semantic note callout.

The detector missed the material problems found in the design review: a broken first-run sequence, excessive reference choices, small mobile controls, and a loss of product-specific orientation inside the docs.

**Visual overlays:** Mutable script injection succeeded on the homepage, Quick Start, Basic Requests, and Reference pages in fresh browser contexts. The browser showed detector overlays during the assessment. The assessment closed its browser and detector server after collecting evidence, so no overlay remains open.

## Overall Impression

Gluegun has a confident, readable documentation site with a real point of view. Its type system, color system, and technical guidance are stronger than the average package site. The largest opportunity is not visual decoration: it is to turn the strong homepage concept into a complete first-success journey and use that concept to orient readers throughout the documentation.

## What's Working

1. **Product-grounded identity.** The visual language and homepage copy connect to Gluegun's connection and stream model instead of applying generic developer-tool styling.
2. **Strong reading system.** Atkinson Hyperlegible, Chivo, JetBrains Mono, the `58ch` prose cap, clear heading scale, and careful code presentation support long technical reading.
3. **Responsible guidance.** Installation constraints, API boundaries, TLS warnings, typed errors, limitations, and the production checklist build trust instead of showing only a happy path.

## Cognitive Load

**Moderate: 3 of 8 checks fail.**

- **Pass:** single focus, grouping, visual hierarchy, one thing at a time, and working-memory support.
- **Fail - chunking:** Guides has 6 items, Advanced has 5, and Reference has 12 in single navigation groups.
- **Fail - minimal choices:** the lifecycle map has 5 steps, "Before you ship" has 5 links, Basic Requests has a 6-item table of contents, and Reference exposes 10 modules.
- **Fail - progressive disclosure:** Reference shows the complete module list in both the sidebar and page content.

## Emotional Journey

- **Entry:** Confident and memorable, but the large hero delays installation and proof.
- **Learning:** Calm and credible. Momentum drops when Quick Start presents a complete program without prerequisites, a run command, or expected output.
- **Peak and end:** The lifecycle map is the conceptual peak. Interior pages lose that authored quality, and Quick Start ends with a plain reference link rather than a clear next achievement.
- **Reassurance:** Production, TLS, limitation, and error guidance is strong but separated from the moments when a new user makes those choices.

## Priority Issues

### P1 - The primary activation path skips installation and proof of success

**Why it matters:** The homepage's "Get started" action goes to Quick Start, but Quick Start assumes Gluegun is installed and does not show a run command or expected output. A first-time user can copy a complete-looking example before satisfying its prerequisites.

**Fix:** Make the path explicit: **Install -> run the first request -> understand the lifecycle**. Link "Get started" to Installation or add an installation step above the sample. Include the exact run command, expected output, and a direct troubleshooting link.

**Suggested command:** `/impeccable onboard`

### P2 - Reference navigation presents too many equivalent choices

**Why it matters:** The Reference view combines topic navigation, 12 sidebar entries, a 10-row module table, generated-content provenance, and HexDocs. Users must decide where to look before they can find an API.

**Fix:** Group modules by task: common HTTP, streaming, connection/security, and support types. Emphasize `gluegun`, `client`, `connection`, and `request`. Add module/function filtering and make one reference destination clearly primary.

**Suggested command:** `/impeccable distill`

### P2 - Mobile code and reference content require precision and horizontal scanning

**Why it matters:** Code blocks need horizontal panning, the module table compresses descriptions, and visible mobile controls measure about 32x32, 32x40, and 40x40 pixels. This adds effort for one-handed use, zoom, and motor impairments.

**Fix:** Shorten introductory code lines, split large examples into progressive snippets, stack module rows below 600px, and enforce at least 44x44-pixel touch areas for primary mobile controls.

**Suggested command:** `/impeccable adapt`

### P3 - The product-specific design language stops at the homepage

**Why it matters:** The lifecycle model is Gluegun's clearest differentiator, but guide pages return to a generic article pattern. Readers lose conceptual orientation and the experience has an emotional drop after entry.

**Fix:** Carry a restrained lifecycle cue into relevant guides, with the current stage highlighted. Add contextual next-step panels at page endings instead of more decoration.

**Suggested command:** `/impeccable layout`

## Persona Red Flags

**Alex (power user):**

- The splash homepage does not provide the shortest installation path.
- Local generated reference and "canonical" HexDocs compete without explaining which one Alex should use.
- Large generated modules have no inline function index or filter, so Alex must use global search or scan long pages.

**Jordan (first-timer):**

- The strongest CTA bypasses Installation.
- Quick Start introduces Gun, protocol negotiation, timeouts, `Result`, and connection ownership before setup confirmation or expected output.
- "What is Gluegun?" is visually secondary even though it contains the model Jordan needs.
- The Reference page starts with provenance and an external alternative before helping Jordan select a module.

**Sam (accessibility-dependent):**

- Skip links, semantic headings, navigation landmarks, descriptive anchors, logo alt text, and legible fonts are strong.
- Search, Menu, theme, and some heading permalink controls are below a comfortable 44x44-pixel mobile target.
- Long code lines require horizontal interaction under zoom.
- Strong purple and pink are used across prose, links, borders, and active states. Contrast is adequate, but broad chromatic emphasis weakens action differentiation.

## Minor Observations

- The desktop homepage spends much of the first viewport on whitespace. It feels deliberate but slows access to proof.
- The code-block scroll shadows are thoughtful and functional.
- The Reference table should remain tabular on desktop but become a stacked layout on small screens.
- "Generated content" has more visual priority than module selection warrants.
- Version `0.1.0` and "canonical HexDocs" create a freshness question that the local page does not resolve.
- No document-level horizontal overflow was found at 1440x900 or 390x844.

## Questions to Consider

1. Does "Get started" mean install Gluegun or send a request? Why does the current path start with the second?
2. Is the local generated reference primary, or is HexDocs primary? Why make users choose?
3. If the lifecycle is Gluegun's core advantage, why does it disappear after the homepage?
4. Should the homepage optimize first for memorable identity or for the fastest successful request?
