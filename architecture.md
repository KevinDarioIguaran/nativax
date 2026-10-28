# NativaX native runtime — architecture

Branch `native-c-sokol`. Standalone C11 runtime for HTML/CSS/JavaScript
applications. **No Flutter, Dart, WebView, Chromium, Electron or platform
channels are part of this runtime, its build or its dependency graph.**

## 1. Goals and non-goals

Goals:

- One native executable that loads an HTML entry document, resolves CSS,
  lays out the DOM, paints a display list and presents it with Sokol GFX.
- JavaScript runs on an independent engine (JavaScriptCore) exposed through a
  C API; script manipulates the native DOM and produces visible updates.
- Native development workflow: dev server, file watcher, WebSocket hot reload,
  incremental C rebuild and relaunch — no Flutter tooling anywhere.
- Measured memory/performance, with the 100 MB RSS target tracked against
  documented workloads (`benchmarks/baseline.json`).

Non-goals (v1, documented gaps):

- Full HTML5/CSS3 conformance. The parser, cascade and layout implement a
  deliberate subset (see §7).
- Flexbox/grid layout, floats, absolute positioning, tables as layout boxes.
- Browser security model (origin isolation, CSP, sandboxing). The runtime
  executes the project's own scripts only.

## 2. Module map

```
include/nativax/*.h            public interfaces (no engine internals leak)
src/log.c        logging               src/dl.c        display-list builder
src/meminfo.c    RSS/peak probes       src/text.c      glyph atlas + shaping
src/image.c      image decode          src/raster.c    CPU rasterizer (tests)
src/dom.c        DOM pool + events     src/html.c      HTML tokenizer/tree
src/css.c        CSS tokenizer/parser  src/style.c     cascade + computed style
src/layout.c     block/inline layout   src/paint.c     boxes → display list
src/debug_dump.c headless artifacts     src/gfx_sokol.c Sokol GFX renderer
src/js_engine.c  JavaScriptCore layer   src/js_loop.c   timers + rAF
src/js_dom.c     DOM ↔ JS bindings      src/app.c       application host
src/devserver.c  HTTP/WS/watcher        src/hotreload.c runtime WS client
src/cli_main.c   `nativax` CLI          src/main_sokol.c window + lifecycle
```

Libraries (CMake targets):

| target | contents | links |
|---|---|---|
| `nativax_core` | log, meminfo, dl, text, image, raster, dom, html, css, style, layout, paint, debug_dump | stb, m |
| `nativax_js` | js_engine, js_loop | `nativax_core`, JavaScriptCoreGTK |
| `nativax_app` | js_dom, app | `nativax_js` |
| `nativax_dev` | devserver, hotreload | `nativax_core` |
| `nativax_gfx` | gfx_sokol | `nativax_core`, `nativax_sokol` (sokol) |
| `nativax` | CLI | `nativax_dev`, `nativax_core` |
| `nativax-runtime` | main_sokol | core, app, dev, gfx |

## 3. Data flow

```
 index.html ──► html.c ──► DOM (dom.c, handle pool)
                            │      ▲
 <style>/<link> ──► css.c ──► style.c (cascade, inline style="" last)
                            │
                            ▼
                        layout.c (box tree, text runs)
                            │
                            ▼
                        paint.c ──► display list (verts/indices/groups)
                                        │                 │
                              gfx_sokol.c (GPU)     raster.c (CPU, tests)
                                        │
                                  Sokol GFX + sokol_app window
```

Script path:

```
app.c ──► js_engine.c (JavaScriptCore) ──► js_dom.c primitives ──► dom.c
     ◄── mutation callback ◄──────────────────────────────┘
                       (style_dirty → restyle → relayout → repaint)
```

## 4. Ownership and memory model

- DOM nodes live in a document pool; handles (`int32_t`, generation-tagged)
  are the only node currency crossing module boundaries. Slot index is
  available via `nx_node_index()` for dense arrays.
- Per-node style arrays are sized to `nx_node_slot_bound(doc)`, not the 100k
  hard limit. Hot reload re-resolves styles **into the layout's own array**
  (`nx_layout_restyle`), so restyling allocates nothing and layout boxes keep
  valid `NxComputedStyle*` pointers.
- Display-list arrays grow geometrically and are reused across frames
  (`nx_dl_reset` keeps capacity).
- `NxJs`/`JSValueRef` never leaves `js_engine.c`/`js_dom.c`; script receives
  handles, numbers and strings only.
- Fonts/atlases are process-global registries (`text.c`), freed on teardown.

## 5. Threading

Single-threaded: window events, script execution, style/layout/paint and
presentation all run on the main thread in `frame_cb`. The dev server is
poll-driven (`nx_dev_server_poll`), driven by the CLI loop; the runtime's
WebSocket client is non-blocking and polled once per frame. No locks are
needed on the runtime path.

## 6. Hot reload contract

Messages on `/__nativax_ws`:

```json
{"type":"change","kind":"css|js|html|asset","path":"/style.css"}
```

| kind | action | state kept | state dropped |
|---|---|---|---|
| `css` | re-read stylesheets, restyle in place, relayout, repaint | DOM, script heap, listeners, scroll-independent layout inputs | — |
| `js` | fresh JS context, bindings reinstalled, scripts re-executed | DOM tree and attributes | JS heap/closure state, timers |
| `html`, `asset` | full document reload (parse, style, layout, runtime reset) | nothing | everything |
| native C | incremental rebuild (`cmake --build`), process relaunch | nothing | everything |

Native code is deliberately **not** patched into a live process: no ABI
stability or state-migration guarantee exists, so the CLI performs a
controlled rebuild + relaunch. Dangling callbacks/GPU resources are avoided by
tearing the app down in `cleanup_cb` before `sg_shutdown()`.

## 7. Implemented subsets and known gaps

- HTML: tokenizer/tree builder subset; implied end tags; raw text; no foster
  parenting, no fragment parsing (innerHTML reparses via a scratch document).
- CSS: selectors incl. attribute combinators and `:not()`, `@media`
  width/height/orientation; no `@import`, `@supports`, `@keyframes`, nesting.
- Style: display block/inline/none, box edges, colors, font-size/weight,
  text-align, line-height. Inline `style=""` participates after author rules.
- Layout: normal-flow blocks, inline text with word wrapping, percentages,
  auto margins. No flex/grid/float/absolute/inline-block boxes.
- Paint: backgrounds, borders, text, images, opacity-free compositing,
  scissor clipping. Inline elements do not paint their own box (documented).
- JS: JavaScriptCore VM, timers/rAF via `js_loop`, DOM API from `js_dom`
  prelude. No modules, no fetch/XHR, no layout-box APIs (offsetWidth).

## 8. Platform layer

- Windowing/presentation: sokol_app + Sokol GFX (GL core on Linux).
- Platform services are consumed through sokol (`sapp_*`) and small C
  interfaces; the dev server/CLI use POSIX sockets and inotify on Linux.
- Supported/validated today: Linux/X11 (tests run under Xvfb + llvmpipe).
  See `docs/platforms.md` for the status and requirements of Windows, Android
  and iOS.

## 9. Verification surfaces

- `ctest`: 13 suites — parser/DOM/CSS/layout/paint units, JS unit, binding
  unit, debug artifacts, app pipeline (script mutation + all three reload paths), dev
  server (HTTP 200/304/404, RFC 6455 handshake, broadcast, inotify), render
  bench smoke, GPU window screenshot.
- `nativax-runtime --headless --stats --mem` prints pipeline counts and
  RSS/peak JSON for measurement runs.
- `debug/` holds the audit lab: cases, artifacts, visual judge and progress
  evidence (no fabricated results; failures are recorded).
