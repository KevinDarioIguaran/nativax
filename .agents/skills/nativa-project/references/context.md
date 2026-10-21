# Project context

## What NativaX is

NativaX is an experimental UI runtime written in Dart. It interprets a
documented subset of HTML, CSS, and JavaScript and renders it with native
Flutter widgets. The goal is to share one UI codebase across Android, iOS,
Linux, Windows, and macOS without embedding a browser.

**NativaX renders its interface through its own runtime.** `nativa_html` parses
the markup, `nativa_dom` owns the tree, `nativa_css` resolves styles,
`nativa_render` performs layout and painting, and QuickJS-ng runs JavaScript
through `nativa_js`. Flutter supplies painting, input, focus, accessibility, and
platform integration; it is not a browser. Rendering is never delegated to a
WebView, Chromium, CEF, or an external browser.

Nativa is the family name. NativaX is the platform; NativaJS, NativaWeb,
NativaRender, NativaFlow, NativaForge, NativaShield, and NativaBench identify
the other responsibilities. See `docs/nativa-family.md` for the current package
map and extraction criteria.

## What it is not

- It is not a browser.
- It is not a 100 % WHATWG/W3C-compatible web engine.
- It does not use `WebView`, `webview_flutter`, `flutter_inappwebview`,
  Chromium, CEF, Electron, or a local HTTP server to paint the interface.
- It does not execute JavaScript with a toy text-search interpreter; it uses a
  real QuickJS-ng build compiled from C.
- It does not promise compatibility that has not been measured by tests.

## Non-negotiable constraints

1. Rendering uses Flutter widgets and primitives (`RenderObject`, `Text`,
   `Stack`, `Flex`, and similar), not a browser surface.
2. HTML and CSS use in-house parsers; regex over markup is not a general
   solution.
3. JavaScript is real JavaScript. A JIT is not required because iOS does not
   allow one.
4. Explicit limits cover memory, stack, time, nodes, and storage.
5. Public APIs are small and documented. Host errors do not leak internal
   details to scripts.
6. Everything crossing the JS ↔ Dart bridge is scalar or JSON; never a
   `JSValue`.
7. Documentation of limitations is part of the product, not an optional extra.

## Performance expectation

QuickJS is compiled with `-O3 -DNDEBUG`. The dominant bridge cost is JSON per
call (about 3 µs for a trivial call on Linux). "As fast as C" describes the
engine, not the complete system: perceived performance also depends on the
renderer and on how often the bridge is crossed.

## Platforms

| Platform | Status |
|---|---|
| Linux desktop | verified (build + tests) |
| Android | not verified |
| iOS | not verified (no JIT; the design assumes this) |
| Windows | not verified (MSVC needs `/experimental:c11atomics`) |
| macOS | not verified |
