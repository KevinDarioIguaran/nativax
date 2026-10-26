# Web compatibility matrix

Usage-driven map for the repository's reference pages and analyzed apps. It is
**not** a standards-coverage percentage and not a promise for arbitrary sites.
Canonical support pages are [`docs/html-supported.md`](docs/html-supported.md),
[`docs/css-supported.md`](docs/css-supported.md), and
[`docs/javascript-supported.md`](docs/javascript-supported.md).

Status words: **yes** = implemented with tests for the stated scope;
**partial** = a subset works with documented gaps; **no** = absent; **no-op** =
accepted but deliberately does nothing.

| Area | Feature | Status | Evidence / limit |
|---|---|---|---|
| HTML | Tree construction | yes | Default `package:html`; in-house custom-depth builder is reduced |
| HTML | Templates, forms, tables, lists | partial | `<template>` content fragment unsupported; rows use flex approximation; forms subset |
| HTML | Custom elements / Shadow DOM | partial | `customElements`; Shadow DOM is a facade, no CSS scoping/slots |
| CSS | Block/flex/grid layout | partial | Grid subset; no subgrid/dense; no full intrinsic sizing |
| CSS | Selectors/pseudo-classes | partial | WPT selectors 70.56 %; `:focus-visible`/namespace/Shadow DOM gaps |
| CSS | `@font-face` TTF/OTF | yes | Resource bytes; WOFF containers need sibling SFNT fallback |
| CSS | Variables, transitions, keyframes | partial | CSS animations implemented; Web Animations API absent |
| CSS | `:has()` | partial | Targeted invalidation; not full browser behavior |
| CSS | Tables/floats/columns/writing modes | no | Accepted/inert or approximate; no full layout |
| DOM | Nodes, attributes, classList, events | yes | Unit + WPT subsets |
| DOM | `elementFromPoint(s)` | yes | Renderer hit-test |
| DOM | MutationObserver, Range, Selection | partial | Observers implemented; Range/Selection subset |
| DOM | Custom elements | partial | Autonomous elements; no full scoped registry |
| DOM | Fullscreen, pointer lock | no-op | Compatibility stubs |
| BOM | Timers, rAF, fetch/XHR, localStorage | yes/partial | Network requires host policy; default deny |
| BOM | Clipboard, matchMedia, history | partial | Needs host services; in-memory history |
| BOM | Service Worker, Cache API | no | Not implemented |
| BOM | `navigator.mediaDevices` | no | Camera/mic unsupported |
| JS | QuickJS-ng modern ECMAScript | yes | Test262 subset 97.93 %; not full browser |
| JS | V8 backend | experimental | Optional desktop; no modules, host WASM/WebGL/SAB, time/job/stack enforcement |
| JS | WebAssembly | partial | wasm3, self-contained modules; no SIMD/threads/full imports |
| JS | WebGL | partial | QuickJS host bridge; no conformance run; V8 unsupported |
| Media | Audio/video playback | no | Space placeholders; silent Web Audio graph |
| Build | Static app analyzer | yes | `python3 tools/analyze_app.py <dir>` |
| Build | AOT templates/bytecode | no | Planned |
| Perf | Virtualized long lists | yes | Renderer virtualization; opt-out attributes |
| Perf | Incremental subtree invalidation | partial | Scroll deferral + widget/style caches, not a complete ownership model |

## Known gaps in analyzed pages

- `navigator.serviceWorker` and `window.caches` are absent.
- `navigator.mediaDevices` is absent; camera/mic meetings cannot work.
- Custom-element `:host(...)` selectors are diagnosed as unsupported.
- Template content fragments, full table formatting, floats, and writing modes
  are not implemented.
- AOT templates/CSS and JS bytecode are not implemented.
- Host calls still serialize through JSON/scalars at the bridge.
- V8 is not a drop-in game/WebAssembly/WebGL backend.

## Reproduce

```bash
python3 tools/analyze_app.py examples/test-pages
python3 tools/analyze_app.py <app-directory>
```

Read the generated usages and compare them with the support pages. A feature
detected by the analyzer is not proof of correctness; run the page and a
focused test.

## Related

- [`docs/status.md`](docs/status.md)
- [`progress/conformance.md`](progress/conformance.md)
- [`docs/security/audit.md`](docs/security/audit.md)
