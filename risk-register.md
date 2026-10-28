# Risk register

Scope: this branch (`native-c-sokol`) — standalone C runtime, Sokol GFX,
JavaScriptCore, dev server/hot reload. Likelihood/impact: H/M/L. Status values
are facts observed in this environment, not predictions.

| # | Risk | L | I | Evidence / impact detail | Mitigation | Status |
|---|---|---|---|---|---|---|
| R1 | Only Linux/X11 is validated; Windows/Android/iOS builds unproven | H | H | CMake requires `javascriptcoregtk-4.1`, X11 and GL; sokol has other backends but they are not exercised | Keep platform code behind sokol + `devserver`/`hotreload` POSIX paths; document requirements in `docs/platforms.md`; gate claims on a real build per platform | Open |
| R2 | JavaScriptCore availability/licensing per platform | M | H | LGPL-2.1 system library on Linux; Android/iOS need a bundled or system JSC; Windows needs WebKit-for-Windows JSC | `js_engine.h` is the only engine boundary; swap implementations without touching DOM/app code | Open |
| R3 | 100 MB RSS target depends on the graphics stack | H | M | Windowed example app peaks at **100.4 MB** under Xvfb + llvmpipe; a trivial page peaks at 98.0-100.1 MB, so ~56 MB separates the headless and windowed runs (software GL/X11), not app content | Optimized style arrays (120.8 → 100.4 MB); measure on real GPU drivers before claiming margin; report fixed vs app cost separately | Open (at target, no margin) |
| R4 | GPU memory is not measured | H | M | Only process RSS is probed (`meminfo.c`); texture/buffer bytes are not attributed | Add registry counters (glyph pages, image textures, vertex/index buffers) to `--mem` | Open |
| R5 | Hot reload semantics lose JS heap state | H | L | `js` reload creates a fresh context by design; closures/timers are dropped | Documented contract in `architecture.md` §6; HTML/CSS reloads keep DOM and (for CSS) JS state | Accepted |
| R6 | Native code hot swap is unsafe | H | H | No ABI/state-migration guarantee; patching C into a live process can leave dangling callbacks and stale GPU handles | CLI does controlled incremental rebuild + relaunch; never patches object code into the running process | Accepted |
| R7 | Layout subset (no flex/grid/float/absolute) breaks real-world pages | H | H | `layout.c` implements normal flow + inline text only; inline element boxes are flattened | Documented gaps; prioritise flexbox subset for existing sample apps; tests assert current geometry so regressions surface | Open |
| R8 | Dev server exposed beyond loopback | L | H | Binds `127.0.0.1` only; no auth token | Keep loopback-only; reject `..` traversal; no directory listing; document that it is a development tool | Mitigated |
| R9 | Hot-reload message storms / duplicate reloads | M | L | Editors emit multiple write events per save | 40 ms debounce + duplicate suppression in `drain_watcher`; reloads are idempotent | Mitigated |
| R10 | Script errors or infinite loops stall the frame | M | M | JSC time budget is soft (WebKitGTK exposes no hard interrupt); a runaway loop still blocks the frame | 500 ms soft budget logs offenders; hard termination needs an engine interrupt handler (available on Apple platforms) | Open |
| R11 | DOM/style arrays outgrow cached capacity | L | M | Restyle requires `nx_node_slot_bound(doc) <= lay->styles_cap`; nodes created by script can exceed it | `nx_layout_restyle` returns false and the app rebuilds the layout; covered by app tests that create/remove nodes | Mitigated |
| R12 | Event model is incomplete (no capture phase from script, no `dispatchEvent`, no pointermove) | H | L | `nx_dom_dispatch_js` bubbles target→ancestors; pointer input is click only | Documented; extend listener spec with capture flag and add pointer events before building interactive UI samples | Open |
| R13 | No conformance harness wired to the C parser | H | M | html5lib/WPT files exist in `debug/upstream`; adapters still target the old runtime | Wire adapters to `nx_html_parse`/`cs_sheet_parse`; publish pass rates only when measured | Open |
| R14 | Memory safety of new modules unverified under sanitizers | M | H | `build-asan` exists for the older suite; the new `app`/`devserver`/`hotreload` code has not run under ASan/UBSan yet | Run the 13 suites in an ASan build; fix findings before shipping | Open |
| R15 | Asset caching/invalidation correctness | L | M | Dev server serves `Cache-Control: no-store` + ETag; runtime re-reads files on reload | No stale-state path in dev; release mode asset bundling is not implemented yet | Partial |
| R16 | Single-threaded frame path couples script and presentation | M | M | Long parse/layout blocks presentation | Reloads only run between frames; long tasks budgeted (`nx_js_set_time_budget_ms`); worker/off-thread parse not implemented | Accepted for v1 |
| R17 | Font/atlas growth unbounded across many sizes/scripts | L | M | Glyph pages are added on demand and only freed at teardown | Documented; add LRU eviction before shipping long-running multi-script apps | Open |
