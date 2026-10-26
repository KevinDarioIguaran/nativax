# Nativa family

Nativa is the technology family; NativaX is the platform. The other names
identify components or responsibilities. A name becomes a real package only
when it has a public API, tests, and its own development cycle. Empty facade
packages are not created.

## Project map

```text
NATIVA
├── NativaX       Cross-platform UI runtime
├── NativaJS      JavaScript engine and native bridge
├── NativaWeb     HTML, DOM, CSS, and web APIs
├── NativaRender  CSS layout and Flutter rendering
├── NativaFlow    Workers, concurrency, and messaging
├── NativaForge   Tooling, tests, and conformance
├── NativaShield  Security, permissions, and limits
└── NativaBench   Benchmarks and performance evidence
```

| Project | Status | Current location | Responsibility |
|---|---|---|---|
| **NativaX** | Active | `packages/nativax` | Public runtime, `NativaXView`, document loading, lifecycle, workers |
| **NativaJS** | Active | `packages/nativa_js` | QuickJS-ng, optional V8, C/FFI bridge, timers, WebAssembly, limits, WebGL bridge |
| **NativaWeb** | Active, modular | `packages/nativa_html`, `nativa_dom`, `nativa_css`, `nativa_dom_bindings` | HTML, DOM, CSS, and browser APIs exposed to JavaScript |
| **NativaRender** | Active | `packages/nativa_render` | CSS layout, composition, Flutter widgets/render objects |
| **NativaFlow** | Embedded | `packages/nativax/lib/src/workers.dart`, `packages/nativa_dom_bindings/lib/src/worker_runtime.dart` | Workers, messaging, work scheduling |
| **NativaForge** | Active area | `tools/`, `debug/engines/compatibility` | Tests, conformance runners, packaging, developer tooling |
| **NativaShield** | Active area | `debug/engines/security`, security tests/docs | Isolation, permissions, resource limits, audit |
| **NativaBench** | Active area | `debug/engines/{performance,visual_comparison,microbenchmarks,memory}`, `debug/benchmarks` | Reproducible performance, visual, leak, and conformance evidence |

NativaFlow, NativaForge, NativaShield, and NativaBench are **not** separate Dart
packages yet. Their names describe ownership areas. Turning one into a package
requires the extraction criteria below; until then, a package with that name
would be a facade without an independent API.

## NativaWeb is not one monolithic package

| Package | Responsibility |
|---|---|
| `nativa_html` | HTML tokenizer, parser paths, limits |
| `nativa_dom` | DOM tree, selectors, events, mutations, serialization |
| `nativa_css` | Tokenizer, parser, cascade, media queries, computed style |
| `nativa_dom_bindings` | DOM/browser APIs exposed to the JavaScript engine |

There is no `nativa_web` facade package. Applications that need the full
platform can depend on `nativax`; lower-level consumers can depend only on the
modules they use.

## Naming and conventions

- Family: **Nativa**.
- Platform and Dart package: **NativaX** / `nativax` (the package name is part
  of the public API).
- Internal packages: `snake_case` with `nativa_` prefix (`nativa_js`,
  `nativa_html`, `nativa_dom`, `nativa_css`, `nativa_dom_bindings`,
  `nativa_render`).
- Product/component names: `CamelCase` (NativaJS, NativaWeb, NativaRender,
  NativaFlow, NativaForge, NativaShield, NativaBench).
- Inherited native symbols (`nativax_bridge`, `nativax_gl`, etc.) keep their
  names for ABI compatibility; they are not product names.

## Applied package migration

| Before | Now |
|---|---|
| `nativax_js` | `nativa_js` |
| `nativax_html` | `nativa_html` |
| `nativax_dom` | `nativa_dom` |
| `nativax_css` | `nativa_css` |
| `nativax_dom_bindings` | `nativa_dom_bindings` |
| `nativax_flutter` | `nativa_render` |
| `nativax` | `nativax` (unchanged) |

## Extraction criteria

A responsibility area becomes an independent package when at least three of
these hold:

1. It has a stable, documented public API.
2. It has tests that do not require the full runtime.
3. It can be versioned and published independently.
4. Extraction reduces dependencies instead of multiplying them.
5. There is a clear consumer outside NativaX.

Until then, keep the code in the existing boundary and avoid adding a package
just to match the family diagram.

## Related

- [`architecture/README.md`](architecture/README.md)
- [`reference/repository-map.md`](reference/repository-map.md)
- [`contributing.md`](contributing.md)
