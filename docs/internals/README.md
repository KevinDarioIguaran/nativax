# Internals

These pages explain how the implementation works and where it is approximate.
They are for contributors and debuggers who need more than the public guide.

| Page | Subject |
|---|---|
| [`html-dom-css.md`](html-dom-css.md) | Tokenizer, tree construction, DOM, cascade, computed styles |
| [`renderer.md`](renderer.md) | Render objects, invalidation, geometry, virtualization |
| [`javascript-bridge.md`](javascript-bridge.md) | Host calls, serialization, preludes, hardening |
| [`limits-and-memory.md`](limits-and-memory.md) | Every runtime limit and memory boundary |
| [`diagnostics.md`](diagnostics.md) | Tracing, profiling, diagnostics, artifacts |

Before changing these internals, read [`../architecture/README.md`](../architecture/README.md)
and the product boundary rules in [`../../AGENTS.md`](../../AGENTS.md). The
short version: own the chain, never add a browser fallback, keep scripts on a
real JS engine, and send only ids/scalars/JSON across the bridge.

## Source orientation

| Layer | Main source |
|---|---|
| HTML tokenizer/parser | `packages/nativa_html/lib/src/tokenizer.dart`, `parser.dart`, `parser_error.dart` |
| DOM | `packages/nativa_dom/lib/src/document.dart`, `element.dart`, `node.dart`, `selectors.dart`, `events.dart` |
| CSS | `packages/nativa_css/lib/src/tokenizer.dart`, `parser.dart`, `cascade.dart`, `computed_style.dart`, `properties.dart` |
| Rendering | `packages/nativa_render/lib/src/layout/`, `render/` |
| JS engines | `packages/nativa_js/lib/src/quickjs_engine.dart`, `v8_engine.dart`, `event_loop.dart` |
| Web bindings | `packages/nativa_dom_bindings/lib/src/dom_bindings.dart`, `web_prelude*.dart`, `web_ops.dart` |
| Runtime composition | `packages/nativax/lib/src/runtime.dart`, `view.dart`, `resources.dart`, `workers.dart` |
