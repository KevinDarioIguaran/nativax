---
name: nativa-architecture
description: Use before changing package boundaries, adding a module or public API, reviewing a cross-layer refactor, or deciding where Nativa code belongs.
---

# Nativa architecture

Read `references/overview.md` first. It contains the layer diagram, package
responsibilities, JS-Dart bridge, layout components, and recorded decisions.

## Workflow

1. Identify the layer that owns the behavior:
   - `nativa_html`: tokenizer and HTML tree builder.
   - `nativa_dom`: tree, events, selectors, mutations, forms.
   - `nativa_css`: tokenizer, cascade, media queries, computed styles.
   - `nativa_dom_bindings`: JavaScript prelude, host functions, browser APIs.
   - `nativa_js`: QuickJS-ng, FFI, timers, WebAssembly, limits, WebGL bridge.
   - `nativa_render`: CSS layout and Flutter rendering.
   - `nativax`: public runtime, `NativaXView`, Flutter environment.
2. Check dependency direction. A lower layer must not import a higher layer.
3. Search for an existing contract before adding a new API.
4. Keep NativaWeb modular: `nativa_html`, `nativa_dom`, `nativa_css`, and
   `nativa_dom_bindings` are separate packages. Do not add an umbrella package
   unless it has its own API, tests, and versioning value.
5. State the boundary decision and the tests that protect it.

## Rules

- Never duplicate parser, DOM, style, bridge, or renderer logic.
- Never make `nativa_dom_bindings` depend on Flutter.
- Never expose `JSValue` or Dart objects across the bridge.
- Keep web-platform code out of the runtime package when it belongs to a module.
- If a new package is justified, explain what would break without it.

## Output

Return a short architecture note with owner, dependencies, public surface, and
verification command. Do not edit files unless the user asked for an
implementation.
