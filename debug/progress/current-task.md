# Current task

Debug laboratory audit completed (see debug/reports/debug-audit.md).
Branch: `native-c-sokol`. Next: conformance harness (html5lib adapter) and
visual pixel-diff gate.

## Verified (2026-10-28)

- Debug CLI generates DOM/CSS/layout/displaylist/summary/render artifacts.
- Crash reporter installed (backtrace).
- Benchmarks and history present.
- Dependency inventory exists.

## Debug workflow update (2026-10-28)

- Added `.agents/AGENTS.md` and `.agents/skills/debug-lab-workflow/SKILL.md`
  describing the step-by-step visual debugging protocol.
- Fixed `innerHTML` getter in `src/js_dom.c` via `nx_node_serialize_inner`.
- Added `hsl()`/`hsla()` colour parsing in `src/style.c`.
- Section 2: 99/100 pass (1 blocked: var()).
- Section 17: 1/30 pass (hsl unblocked), 29 blocked (documented gaps).
- Quality gate: PASS.
