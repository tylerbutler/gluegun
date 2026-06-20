---
target: website/src/content/docs/index.mdx
total_score: 29
p0_count: 0
p1_count: 2
timestamp: 2026-06-20T21-25-49Z
slug: website-src-content-docs-index-mdx
---
#### Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Static docs page has clear navigation affordances, but no page-level cue that this splash is the docs entry point beyond Starlight chrome. |
| 2 | Match System / Real World | 3 | Speaks BEAM/Gleam developer language well; a first-time evaluator still has to decode Gun, stream messages, and collection tradeoffs quickly. |
| 3 | User Control and Freedom | 3 | Multiple exits into quick start, introduction, guides, API reference, and module docs; no traps. |
| 4 | Consistency and Standards | 3 | Uses Starlight and the committed magenta/purple system consistently; custom sections mostly match the site system. |
| 5 | Error Prevention | 2 | The landing sample and module map do not foreground connection lifecycle, protocol limits, or when not to use the high-level client. |
| 6 | Recognition Rather Than Recall | 3 | Reading path and module map reduce recall, but the foundational connection layer is missing from the module map despite appearing in the snippet. |
| 7 | Flexibility and Efficiency | 3 | Serves quick-start and reference users, though the first fold has too many competing paths for a fast evaluator. |
| 8 | Aesthetic and Minimalist Design | 3 | Focused, high-contrast, and on-brand; not yet distinctive enough for the Charged Lab Manual concept. |
| 9 | Error Recovery | 2 | Troubleshooting/error-handling paths exist in site navigation but are not surfaced from this entry page where production evaluators need reassurance. |
| 10 | Help and Documentation | 4 | Strong docs-oriented structure with direct links to guides, reference, and concrete code. |
| **Total** | | **29/40** | **Good foundation; needs sharper entry-flow hierarchy and production reassurance.** |

#### Anti-Patterns Verdict

**LLM assessment**: This does not look like obvious AI slop. It avoids gradient text, side-stripe accents, ghost-card shadows, over-rounded cards, tiny repeated section eyebrows, and identical icon-card grids. The magenta/purple identity is coherent and already grounded in the documented design system.

The weaker tell is structural, not visual: a polished docs splash with a hero, a code panel, a pill-link path, and a module list is safe. It is clean and useful, but it does not yet fully deliver the brand promise of a charged, memorable developer manual.

**Deterministic scan**: `detect.mjs --json website/src/content/docs/index.mdx` returned `[]`. No detector findings, no ignored findings, and no false positives.

**Visual overlays**: No reliable user-visible overlay is available in this session. Browser automation/mutable page injection tools are not exposed here, and the probed local ports did not serve this Gluegun page, so the fallback signal is source inspection plus the clean deterministic scan.

#### Overall Impression

The page is useful and credible. The biggest opportunity is to make the first screen choose harder: one dominant adoption path, one code proof, and one explicit production-confidence cue. Right now it asks evaluators to parse several good paths at once instead of staging the decision.

#### What's Working

1. **The code-led lab panel is the right move.** It proves the wrapper through real Gleam instead of abstract marketing claims, and it avoids generic feature-card scaffolding.
2. **The palette is committed without getting toy-like.** Dark purple surfaces, charged magenta, and pale pink text preserve the Gluegun identity while keeping technical trust.
3. **The module map explains the abstraction boundary.** It tells users when to stay high-level and when to drop into request/message/websocket, which is the package's core adoption risk.

#### Priority Issues

**[P1] The first fold has too many competing next steps**

**Why it matters**: A package evaluator lands here with one question: "Can I get a request working, and do I trust this abstraction?" The hero already offers four actions, then the custom section adds three more reading-path links, then the next section adds module links. All are reasonable, but together they flatten priority.

**Fix**: Make the first fold commit to one primary journey: quick start as the dominant action, introduction as the confidence-builder, and the advanced paths staged after the code proof. Keep the three-step path only if it visually reads as a sequence, not as another equal set of navigation pills.

**Suggested command**: `$impeccable layout website/src/content/docs/index.mdx`

**[P1] The foundational connection layer is missing from the module map**

**Why it matters**: The snippet starts with `connection.options()` and `connection.await_up`, but the module map jumps to `client`, `request`, `message`, and `websocket`. That makes users infer where connection setup lives, exactly where Gluegun most needs to be explicit.

**Fix**: Add `connection` to the module map or restructure the map around the actual lifecycle: connect -> send/stream -> decode messages -> upgrade to WebSocket. Include `tls` or `error` only if the map expands into a production-readiness row; otherwise keep it focused.

**Suggested command**: `$impeccable clarify website/src/content/docs/index.mdx`

**[P2] The code proof demonstrates API shape, but not a complete success moment**

**Why it matters**: The snippet ends at `client.send(connection: conn)` without binding the response, showing what comes back, or closing/shutting down. For experienced developers this is enough; for evaluators, the page misses the emotional payoff of "I can see the result."

**Fix**: Either make the snippet one step more complete (`let assert Ok(response) = ...`) or add a short caption that names what `client.send` collects and where to go for streaming/cleanup. Avoid turning it into a full tutorial; this page needs a clean proof, not a wall of setup.

**Suggested command**: `$impeccable clarify website/src/content/docs/index.mdx`

**[P2] Production reassurance is present in the site IA but not in the splash narrative**

**Why it matters**: PRODUCT.md says the site should help developers trust security and error-handling choices. This page mentions visible errors in the module map, but TLS, error handling, limitations, and troubleshooting are not part of the page's main confidence arc.

**Fix**: Add one compact production-confidence bridge near the module map: a sentence or short link cluster for TLS, errors, limitations, and troubleshooting. Keep it tonal, not another card grid.

**Suggested command**: `$impeccable harden website/src/content/docs/index.mdx`

**[P3] The visual system is strong but still conservative for the brand register**

**Why it matters**: The page is tasteful and coherent, but "Charged Lab Manual" could be more memorable. The current custom design is still close to a standard docs landing composition: panel, code block, pills, module list.

**Fix**: Push one distinctive brand move: asymmetric lab-panel composition, stronger active path treatment, instrument-label styling used once, or a more dramatic relationship between code and reading path. Do not add decoration; make the interaction model feel charged.

**Suggested command**: `$impeccable bolder website/src/content/docs/index.mdx`

#### Persona Red Flags

**Mira, Gleam developer evaluating a new dependency**: The page gives her real code and fast routes, but she must choose among seven visible entry links before the module map. She may click API reference too early instead of reaching the quick-start success path.

**Noah, BEAM engineer worried about Gun semantics being hidden**: The headline reassures him, and the copy explicitly says Gluegun keeps Gun visible. The red flag is that `connection` is shown in code but omitted from the module map, creating a small trust gap in the mental model.

**Rae, production maintainer checking risk before adoption**: She can find guides and reference through the site chrome, but the splash does not surface TLS, errors, limitations, or troubleshooting as a confidence cluster. She may assume those details are buried or incomplete.

#### Minor Observations

- The numbered reading path is justified because it is an actual sequence, but the pill styling makes the steps feel like peer navigation rather than progression.
- `protocol` is assigned in the snippet but not used, which can read like a dangling detail on a landing page.
- The module map heading is another `h2` inside a nav; semantically acceptable, but visually it may compete with the section heading rather than acting as a compact label.
- Hover lift on path pills has a reduced-motion fallback; good.
- Light/dark color choices appear aligned with the existing same-hue neutral rule; no obvious contrast failure from source inspection.

#### Questions to Consider

- What should the first fold optimize for: fastest successful GET, trust in the streaming model, or proof that this is production-safe?
- Could the module map be a lifecycle map instead of a package index?
- What would make this feel unmistakably Gluegun rather than a well-skinned Starlight splash?
