# Repository map

This map explains where code, tests, evidence, and documentation live. It is
not an exhaustive file listing; use `rg --files` or the context index for that.

## Top level

| Path | Role |
|---|---|
| `packages/` | Seven Dart/Flutter packages: runtime, JS, HTML, DOM, CSS, bindings, render |
| `examples/` | Web challenge, game player, render benchmark, test pages, reference app |
| `debug/` | Diagnostic engines, benchmark runs, generated artifacts, context tooling |
| `progress/` | Live status, conformance baseline, latest reports, history/log |
| `docs/` | Canonical English documentation (this tree) |
| `.agents/` | Shared agent skills and references |
| `.claude/` | Symlinked skill copies for Claude Code |
| `tools/` | Test entry point, analytics, architecture/purity checks, docs checker, V8 spike |
| `AGENTS.md` | Binding agent instructions for this repository |

Generated/build state (`.dart_tool/`, `build/`, `debug/artifacts/`, `.freebuff/`)
is not source.

## Packages

### `packages/nativax`

The composition root and public platform package.

| Path | Role |
|---|---|
| `lib/nativax.dart` | Public barrel |
| `lib/src/view.dart` | `NativaXView` lifecycle |
| `lib/src/runtime.dart` | Parse/style/font/engine/bindings/scripts/session |
| `lib/src/resources.dart` | `NativaXResourceLoader`, asset/directory/deny loaders |
| `lib/src/modules.dart` | Module graph, same-origin routing, local network |
| `lib/src/workers.dart` | Isolate worker launcher |
| `lib/src/hot_reload.dart` | Development document reload |
| `lib/src/template_engine.dart` | Jinja-like template engine |
| `lib/src/flutter_environment.dart` | Flutter-backed media/theme/locale environment |
| `test/` | Runtime, web platform, modules, hot reload, workers, game, V8/WASM smoke |

### `packages/nativa_js`

JavaScript engines, event loop, native bridge, WASM/GL/JIT primitives.

| Path | Role |
|---|---|
| `lib/src/javascript_engine.dart` | Engine contract and config |
| `lib/src/quickjs_engine.dart` | QuickJS-ng FFI, module support, host prelude |
| `lib/src/v8_engine.dart` | V8 cdylib FFI |
| `lib/src/default_engine.dart` | Default desktop/mobile selection |
| `lib/src/event_loop.dart` | Timers, microtasks, timer limits |
| `lib/src/wasm_prelude.dart` | WebAssembly bridge/prelude |
| `lib/src/jit.dart` | QuickJS JIT prototype status |
| `src/nativax_bridge.c` | C host bridge |
| `src/nativax_wasm.c` | wasm3 integration |
| `src/nativax_gl.c` | GL bridge (Linux/Android) |
| `hook/build.dart` | Native-asset build hook |
| `third_party/` | Vendored QuickJS, wasm3, stb, MIR/Khronos headers |
| `test/` | QuickJS/V8/modules/WASM/GL/JIT tests |

### `packages/nativa_html`

- `lib/src/tokenizer.dart`, `token.dart`: HTML tokenizer.
- `lib/src/parser.dart`: `HtmlParser`, default `package:html` tree path and
  simplified custom-depth path.
- `lib/src/parser_error.dart`: `HtmlParseError`, `HtmlLimitException`,
  `HtmlParserLimits`.
- `test/`: tokenizer, parser, fuzz.

### `packages/nativa_dom`

- `lib/src/document.dart`: `Document`, `DocumentLimits`.
- `lib/src/node.dart`, `element.dart`: tree, attributes, classes, forms.
- `lib/src/events.dart`: event targets/dispatch/trusted flags.
- `lib/src/selectors.dart`: selector engine.
- `lib/src/mutation.dart`: mutation records/observers.
- `lib/src/layout_host.dart`: geometry/scroll/focus contract implemented by the
  renderer.
- `lib/src/serializer.dart`, `exceptions.dart`.
- `test/`: DOM and fuzz tests.

### `packages/nativa_css`

- `tokenizer.dart`, `parser.dart`, `media_queries.dart`, `supports.dart`.
- `cascade.dart` (`StyleEngine`).
- `computed_style.dart`, `properties.dart`, `values.dart`, `named_colors.dart`.
- `user_agent.dart` (UA stylesheet).
- `test/`: CSS, flex, media matrix, style cache, fuzz.

### `packages/nativa_dom_bindings`

Browser-facing API layer.

| Path | Role |
|---|---|
| `dom_bindings.dart` | `DomBindings`, ids, events, install/harden |
| `web_ops.dart` | Host operations (CSS, layout, storage, network, etc.) |
| `prelude.dart`, `web_prelude*.dart` | JavaScript wrappers and web APIs |
| `network.dart` | `NativaXNetwork`, `DeniedNetwork`, `IoNetwork` |
| `environment.dart` | `HostEnvironment`, storage, theme |
| `messaging.dart` | Ports/router/messaging |
| `module_graph.dart` | ES-module graph |
| `worker_runtime.dart` | Worker launcher/scope |
| `inline_style.dart` | CSSOM inline style |
| `test/` | bindings, web platform, messaging, WebGL |

### `packages/nativa_render`

Flutter rendering and CSS layout.

| Path | Role |
|---|---|
| `lib/src/layout/css_box.dart` | Box model and containing block |
| `css_block.dart`, `css_flex.dart`, `css_grid.dart` | Flow/flex/grid |
| `css_item.dart`, `css_sticky.dart`, `css_transform.dart` | Items, sticky, transforms |
| `virtualization.dart` | Virtual scroll/block and viewport scope |
| `preferred_width.dart`, `layout_timed.dart`, `layout_profile.dart` | Intrinsic sizing/timing |
| `lib/src/render/document_view.dart` | Document view and invalidation |
| `node_view.dart` | Widget tree builder and virtual decisions |
| `canvas2d.dart`, `gl_surface.dart` | Canvas/GL surfaces |
| `svg.dart`, `svg_image.dart` | Inline SVG and SVG image provider |
| `animation.dart`, `widget_cache.dart`, `control_glyphs.dart` | Animation, cache, controls |
| `style_mapping.dart` | ComputedStyle → Flutter styles |
| `test/` | 23 renderer/layout/widget tests |

## Examples

| Path | Role |
|---|---|
| `examples/web-challenge` | Flutter host + real HTML/CSS/JS challenge |
| `examples/game-player` | Three.js/Rapier game bundle + desktop shell; separate native V8 lib when present |
| `examples/render-benchmark` | Large-document/render scenario harness |
| `examples/test-pages` | Small analyzer pages |
| `examples/threejs-multiplayer-starter` | Standalone browser TypeScript reference app |

## Debug tooling

| Path | Role |
|---|---|
| `debug/engines/compatibility` | Test262/html5lib/WPT/URL/tree runners and summary schemas |
| `debug/engines/visual_comparison` | Chromium-vs-NativaX visual judge |
| `debug/engines/performance` | Headless workload suite, metrics, GUI panel |
| `debug/engines/memory` | Leak/lifecycle suite |
| `debug/engines/security` | Security case runner |
| `debug/engines/microbenchmarks` | Microbenchmark runner |
| `debug/engines/bug_detection` | `nxaudit` and audit batches |
| `debug/engines/quality_gate` | Combined visual/perf/compatibility gate |
| `debug/engines/recommendations` | Recommendation engine |
| `debug/harness` | Widget/perf/screenshot harness |
| `debug/benchmarks/<area>/<run_id>/` | Tracked run results + `manifest.json` |
| `debug/artifacts/` | Generated gitignored runs, suites, indexes, reports |
| `debug/logic/` | Schemas, storage, context, IA audit, tests |
| `debug/manifest/` | Shared run-id/manifest Dart package |
| `debug/architecture/` | Storage/engine contracts |
| `debug/archive/` | Superseded debug-system and engine-inventory snapshots |
| `debug/scripts/` | Report/quality scripts |

## Progress and evidence

| Path | Role |
|---|---|
| `progress/status.md` | Live compact state and blockers |
| `progress/conformance.md` | Last conformance baselines |
| `progress/log.md` | English chronological log |
| `progress/phases.md` | Current phase checklist |
| `progress/reports/*-latest.md` | Convenience latest reports (can lag canonical data) |
| `progress/reports/*.json` | IA/audit reports |
| `progress/history/` | Archived status/log/phases and phase-0 evidence (including Spanish originals) |
| `progress/tasks/` | Explicit pending test/video/game work |

## Tools

| Path | Role |
|---|---|
| `tools/test_all.sh` | Full test entry point; flaky at `game_play_test.dart`, no CI |
| `tools/analyze_app.py` | Static web API usage analyzer |
| `tools/check_docs.py` | Documentation link/language/reference/API checker; `--write` publishes the audit |
| `tools/test_architecture.py` | Package-boundary checks |
| `tools/check_purity.py` | Purity checks |
| `tools/test_video_manifest.py`, `tools/run_video_contract.py` | Video contract checks |
| `tools/v8-spike/` | Rust `rusty_v8` cdylib source |

## Documentation

| Path | Role |
|---|---|
| `docs/README.md` | Canonical documentation hub |
| `docs/architecture/` | System/lifecycle/rendering/JS/workers/platform |
| `docs/internals/` | Parser/DOM/CSS, renderer, bridge, limits, diagnostics |
| `docs/guides/` | Embedding/resources/forms/templates/examples |
| `docs/reference/` | Public API/config/env/repository map |
| `docs/security/` | Threat model, audit, test plan, platform matrix |
| `docs/archive/legacy-es/` | Historical Spanish docs (not maintained) |
| `progress/reports/docs-audit-latest.md` | Latest mechanical documentation audit |

## Naming and boundaries

NativaX, NativaJS, NativaWeb, NativaRender, NativaFlow, NativaForge,
NativaShield, and NativaBench are responsibility names; not all are packages.
See [`nativa-family.md`](../nativa-family.md). Do not create a new package unless
it has a public API, tests, and a development cycle.

## Related

- [`../architecture/README.md`](../architecture/README.md)
- [`public-api.md`](public-api.md)
- [`../testing.md`](../testing.md)
- [`../information-architecture.md`](../information-architecture.md)
