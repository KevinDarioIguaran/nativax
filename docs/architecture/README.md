# Architecture

NativaX is a Dart/Flutter runtime that owns the path from a document to pixels.
It is deliberately not a browser shell: no WebView, Chromium, CEF, Electron, or
local HTTP server is used for presentation. JavaScript is executed by a real
engine behind a narrow contract.

This page is the system map. Detailed behavior lives in:

- [`runtime-lifecycle.md`](runtime-lifecycle.md)
- [`rendering.md`](rendering.md)
- [`javascript-engines.md`](javascript-engines.md)
- [`workers-and-resources.md`](workers-and-resources.md)
- [`platform-support.md`](platform-support.md)
- [`../internals/README.md`](../internals/README.md)

## One document, five owned stages

```text
source string / loaded HTML
        |
        v
+------------------+     +------------------+     +------------------+
| nativa_html      | --> | nativa_dom       | <-> | nativa_css       |
| tokenize + parse |     | tree + events +  |     | cascade +        |
| errors + limits  |     | selectors        |     | computed styles  |
+------------------+     +------------------+     +------------------+
                                  |
                                  v
                         +------------------+
                         | nativa_render    |
                         | layout + paint   |
                         | Flutter objects  |
                         +------------------+
                                  |
                                  v
                          Flutter widgets

+------------------+     +--------------------------+
| nativa_js        | <-> | nativa_dom_bindings      |
| QuickJS-ng / V8  |     | window, DOM, timers,     |
| FFI + limits     |     | storage, fetch, workers  |
+------------------+     +--------------------------+
```

The `nativax` package is the composition root: it parses, creates the style
engine, selects an engine, installs bindings, runs scripts, loads fonts and
modules, and exposes the Flutter view.

## Package responsibilities

| Package | Owns | Must not own |
|---|---|---|
| `nativa_dom` | DOM nodes, attributes, events, selectors, mutation records, serialization, document limits | Flutter, JavaScript, CSS parsing |
| `nativa_html` | HTML tokenizer, parse errors, parser limits, tree construction | JavaScript execution, layout |
| `nativa_css` | CSS tokenizer/parser, selectors, cascade, media/supports, computed styles, font-face metadata | Flutter widgets, JavaScript |
| `nativa_js` | Engine contract, QuickJS-ng FFI, V8 FFI, event loop primitives, timers, native buffers, WebAssembly/WebGL native bridge primitives | DOM policy, Flutter rendering |
| `nativa_dom_bindings` | Browser-facing surface: window, document wrappers, events, storage, network, modules, workers, canvas/CSSOM/IDB/Intl preludes | Layout, styling decisions |
| `nativa_render` | CSS layout, Flutter RenderObjects, text, paint, SVG, canvas surfaces, virtualization | HTML parsing, JS engine policy |
| `nativax` | Public view/runtime, configuration, resources, fonts, hot reload, templates, worker launcher | Duplicating lower-layer logic |

Dependency direction is one-way:

```text
nativax
  ├── nativa_dom_bindings
  │     ├── nativa_css
  │     ├── nativa_html
  │     ├── nativa_dom
  │     └── nativa_js
  ├── nativa_render
  │     ├── nativa_css
  │     ├── nativa_dom
  │     └── nativa_js
  ├── nativa_html
  ├── nativa_css
  ├── nativa_dom
  └── nativa_js
```

`nativa_dom` and `nativa_js` are pure-Dart packages. `nativa_css` and
`nativa_html` are pure Dart as well. `nativa_render` and `nativax` require
Flutter. Native code is reached through `dart:ffi` and Dart native assets; it is
not a hidden browser process.

## Runtime ownership

A `NativaXRuntime` owns exactly one document session:

- one `nativa_dom.Document`;
- one `nativa_css.StyleEngine`;
- one JavaScript engine instance;
- one `DomBindings` installation;
- one timer host;
- its parsed style sheets and font registrations;
- the runtime configuration and callbacks.

It is created asynchronously because stylesheets, scripts, modules, and fonts
may need host resources. It must be used from the isolate that created it and
disposed when the view unmounts. `NativaXView` does this automatically.

Workers are separate executions:

- threaded workers run in their own isolate and QuickJS runtime;
- in-process workers share the UI isolate when `threadedWorkers: false`;
- the page engine can be V8, but workers are QuickJS in the current
  implementation.

## The rendering model

The renderer is **not** a browser layout engine:

- `nativa_css` computes a `ComputedStyle` tree from the DOM and stylesheets.
- `nativa_render` maps that tree to Flutter `RenderObject`s and widgets.
- Block flow, flex, grid, absolute/fixed/sticky positioning, text, borders,
  backgrounds, transforms, filters, inline SVG, canvas, and form controls are
  implemented to varying degrees.
- DOM mutations invalidate style and schedule a rebuild. The current document
  view batches invalidation and rebuilds the affected document tree; a granular
  per-owner invalidation model is still future work.
- Large in-flow containers with at least 24 child slots can be virtualized. Only
  viewport slots are built and styled; offscreen elements have estimated
  geometry and no render object. This is an approximation with explicit opt-out.
- Geometry APIs (`getBoundingClientRect`, `offsetWidth`, `scrollIntoView`, and
  observers) read `RenderBox` data from the renderer when materialized, or an
  estimated virtual box when not.

Visual parity is measured separately with Chromium as an external reference.
The mean score on the 51-page baseline is 52.59 %, so “renders” is not “looks
like a browser”.

## The JavaScript model

`JavaScriptEngine` is the contract between Dart and the engine. The two
production backends are:

- **QuickJS-ng**: compiled from source by the package build hook and accessed by
  FFI; default on mobile, workers, module pages, missing V8, and forced pages.
- **V8**: Rust `rusty_v8` cdylib loaded by FFI; default for desktop pages when
  available and no module script is present.

The bridge serializes host calls. Scripts receive JSON-compatible values only:
`null`, booleans, numbers, strings, lists, and maps. They never receive Dart
objects, `JSValue`s, or arbitrary native pointers. Host handles are ids checked
against the runtime's registry.

The page's event loop is the Flutter UI isolate's event loop:

1. A Dart entry (script evaluation, timer, event, host message) runs
   synchronously in the engine.
2. Microtasks are drained after the entry.
3. Timers become new entries with their own execution budget.
4. A long entry can be interrupted by the engine budget; it does not preempt
   arbitrary host Dart work.

V8 and QuickJS have different gaps. V8 has no modules, WebAssembly,
SharedArrayBuffer, or WebGL bridge. QuickJS has those integrations but is slower
on some JavaScript workloads and is an interpreter. This is a product trade-off,
not a hidden fallback.

## Trust and resource boundaries

- The default resource loader denies every external resource.
- The default network policy denies every request.
- The default storage is in-memory with a 5 MB character quota.
- Images and fonts are host-resolved.
- `DomBindings.harden()` removes the raw host bridge from script globals.
- The runtime applies document, parser, timer, memory, stack, and task limits.
- The process is **not** an OS sandbox. Untrusted content should run in a
  separate process/OS sandbox chosen by the host.

See [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md) and
[`../security/threat-model.md`](../security/threat-model.md).

## Intended architecture versus current implementation

| Intended | Current implementation |
|---|---|
| Owned HTML/CSS/JS runtime with no browser fallback | True for presentation; HTML tree construction uses `package:html` behind `nativa_html` |
| Native Flutter layout/paint | True, with approximations for tables, some flex/grid cases, media, and SVG |
| Real JS engine | QuickJS-ng and V8; V8 lacks several host integrations |
| Incremental rendering | Batched invalidation plus virtualized long containers; not a fully incremental style/render graph |
| Granular style invalidation | Whole-document recomputation on many mutations; style cache and virtual subtrees reduce cost |
| Cross-platform | Linux verified; other platforms unverified |
| Production security | In-process limits and tests; no OS sandbox, SCA, or fuzzing campaign |

## Architecture rules

1. Keep the rendering chain owned. No `webview_flutter`,
   `flutter_inappwebview`, `HtmlElementView`, Chromium, CEF, Electron, or
   browser fallback.
2. JS runs on a real engine. Never replace it with a toy interpreter or text
   search.
3. Scripts receive ids, scalars, and JSON only.
4. Do not move Flutter or browser policy into pure-Dart packages without a
   boundary reason.
5. Every new public API needs a test and a documentation update.
6. A conformance `SKIP`, a `PASS` in a narrow harness, or an example boot is not
   a general compatibility claim.

For file-level roles and test locations, see
[`../reference/repository-map.md`](../reference/repository-map.md).
