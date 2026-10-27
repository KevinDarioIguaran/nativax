# Nativa

**Nativa** is the technology family. **NativaX** is the main platform: an
experimental UI runtime written in Dart that interprets a documented subset of
HTML, CSS, and JavaScript and renders it with native Flutter widgets.

NativaX does **not** use WebView, Chromium, CEF, Electron, an embedded browser,
or a local HTTP server for presentation. The rendering path is owned end to end:

```text
HTML bytes
  → nativa_html parser
  → nativa_dom tree
  → nativa_css cascade and computed styles
  → nativa_render layout and Flutter RenderObjects
  → Flutter widgets / canvas
```

JavaScript runs on a real engine behind the `JavaScriptEngine` contract:
JavaScriptCore (JSC) on every platform, loaded from the host system library.
Scripts receive ids, scalars, and JSON; they never receive Dart objects.

> **Maturity:** experimental, pre-1.0. Linux x86_64 is the only platform with
> build and measurement evidence in this repository. Do not treat the feature
> lists as browser parity. See [`docs/status.md`](docs/status.md) and
> [`progress/status.md`](progress/status.md).

## Why it exists

NativaX explores a different trade-off from embedding a browser: keep the
document model and the authoring model, but render with native Flutter layout
and painting. That gives the host control over resources, network, storage,
theme, and performance, and avoids shipping a browser engine for UI.

It is not a browser replacement yet. CSS, DOM, HTML parsing, JavaScript host
APIs, accessibility, and platform coverage are incomplete and measured
incrementally.

## Quick start

Requirements: Flutter 3.35+ with Dart 3.10+ (the current workspace was measured
with Dart 3.13.0 and Flutter 3.47.0 on Linux x86_64), plus the native toolchain
needed by Flutter desktop and the QuickJS build hook.

```bash
flutter pub get

# The most representative runnable example (Linux desktop)
cd examples/web-challenge
flutter run -d linux
```

The smallest embedding API:

```dart
import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

void main() => runApp(
  const MaterialApp(
    home: Scaffold(
      body: NativaXView(
        source: '''
          <style>
            body { font-family: sans-serif; padding: 24px }
            h1 { color: #2563eb }
            button { padding: 8px 16px }
          </style>
          <h1>Hello from NativaX</h1>
          <button id="counter">0</button>
          <script>
            let n = 0;
            const button = document.getElementById('counter');
            button.addEventListener('click', () => {
              n += 1;
              button.textContent = String(n);
            });
          </script>
        ''',
      ),
    ),
  ),
);
```

`NativaXView` loads a document and creates a `NativaXRuntime` asynchronously.
External stylesheets, scripts, images, fonts, and network requests are denied
until the host supplies a resource loader or network policy. Read
[`docs/guides/embedding.md`](docs/guides/embedding.md) before using real assets.

## Documentation

Start at [`docs/README.md`](docs/README.md). High-value entry points:

| Topic | Page |
|---|---|
| Project overview and mental model | [`docs/getting-started.md`](docs/getting-started.md) |
| Public Dart API | [`docs/reference/public-api.md`](docs/reference/public-api.md) |
| Runtime configuration and limits | [`docs/reference/configuration.md`](docs/reference/configuration.md) |
| Architecture and lifecycle | [`docs/architecture/README.md`](docs/architecture/README.md) |
| Internals | [`docs/internals/README.md`](docs/internals/README.md) |
| Supported HTML / CSS / JavaScript | [`docs/html-supported.md`](docs/html-supported.md), [`docs/css-supported.md`](docs/css-supported.md), [`docs/javascript-supported.md`](docs/javascript-supported.md) |
| Testing and evidence rules | [`docs/testing.md`](docs/testing.md) |
| Benchmarks and conformance tooling | [`docs/debugging.md`](docs/debugging.md) |
| Security model | [`docs/security/threat-model.md`](docs/security/threat-model.md) |
| Honest maturity and gaps | [`docs/status.md`](docs/status.md) |
| Contributing and evidence rules | [`docs/contributing.md`](docs/contributing.md) |

## The Nativa family

| Project | Current location | Responsibility |
|---|---|---|
| **NativaX** | `packages/nativax` | Public runtime, view, lifecycle, workers, templates |
| **NativaJS** | `packages/nativa_js` | JavaScriptCore (JSC), timers, WebAssembly, limits, WebGL bridge |
| **NativaWeb** | `packages/nativa_html`, `nativa_dom`, `nativa_css`, `nativa_dom_bindings` | HTML, DOM, CSS, and browser-style APIs |
| **NativaRender** | `packages/nativa_render` | CSS layout, Flutter RenderObjects, painting, SVG/canvas integration |
| **NativaFlow** | `packages/nativax/lib/src/workers.dart`, `packages/nativa_dom_bindings/lib/src/worker_runtime.dart` | Workers, isolates, messaging |
| **NativaForge** | `tools/` | Tests, conformance, packaging, developer tooling |
| **NativaShield** | `debug/engines/security`, runtime limits | Isolation, permissions, resource limits, audit |
| **NativaBench** | `debug/benchmarks/`, `debug/engines/*` | Reproducible benchmarks, visual diffs, leaks, conformance |

NativaWeb is deliberately four packages, not one façade. Not every family name
is a separate package yet; a name becomes a package only when it has a public
API, its own tests, and a development cycle. See
[`docs/nativa-family.md`](docs/nativa-family.md).

## Verification snapshot

This is a **snapshot of the last recorded evidence**, not a fresh run during
this documentation change. Percentages exclude `SKIP`, and `SKIP` never counts
as compatibility.

| Suite | PASS | FAIL | SKIP | ERROR | Rate (excl. SKIP) | Recorded |
|---|---:|---:|---:|---:|---:|---|
| Test262 `language/*` subset | 19,577 | 413 | 1,108 | 0 | 97.93 % | 2026-10-24 |
| html5lib tokenizer | 5,759 | 43 | 1,025 | 0 | 99.26 % | 2026-10-24 |
| WPT URL fixture | 665 | 231 | 0 | 0 | 74.22 % | 2026-10-25 |
| WPT `dom/nodes` | 196 | 84 | 47 | 0 | 70.00 % | 2026-10-24 |
| WPT `css/selectors` | 127 | 53 | 348 | 0 | 70.56 % | 2026-10-24 |
| WPT `dom/events` | 52 | 21 | 103 | 0 | 71.23 % | 2026-10-24 |
| WPT tree construction | 1,556 | 316 | 99 | 2 | 83.03 % | 2026-10-25 |

The latest visual baseline (51 vendored pages, Chromium headless as reference)
scored **52.59 %** mean overall, with position **36.20 %**, layout **53.04 %**,
color **45.24 %**, and design **96.72 %**. The performance suite has 270
registered scenarios; the latest measured pass covered only 17 of them. Read
the exact commands and limits in [`docs/visual-fidelity.md`](docs/visual-fidelity.md)
and [`docs/performance-suite.md`](docs/performance-suite.md).

`./tools/test_all.sh` is the full test entry point, but it is **not reliably
green**. Repeated runs on 2026-10-26 produced both `exit 0` and
`TestDeviceException(Shell subprocess crashed with SIGABRT (-6))` in
`packages/nativax/test/game_play_test.dart`; the final validation run exited 1.
The failure predates this documentation work and is not caused by it. Do not
call the suite green or use one passing run as a gate. See
[`docs/testing.md`](docs/testing.md) for the sequence and focused commands.

## Repository

```text
packages/                 runtime, web platform, JS engines, renderer
  nativax/                public platform package
  nativa_js/              JavaScript engines and FFI/native bridge
  nativa_html/            HTML tokenizer/parser
  nativa_dom/             DOM, events, selectors, mutation records
  nativa_css/             tokenizer, parser, cascade, computed styles
  nativa_dom_bindings/    DOM/window/web APIs exposed to JavaScript
  nativa_render/          CSS layout and Flutter rendering
examples/                 web challenge, game player, render benchmark
debug/                    engines, benchmark runs, generated artifacts, indexes
progress/                 live status, conformance, reports, history
docs/                     canonical documentation (English)
.agents/                  shared agent skill library
tools/                    test, analysis, and documentation entry points
```

Full map: [`docs/reference/repository-map.md`](docs/reference/repository-map.md).

## Tests

```bash
./tools/test_all.sh

# Focused package suites, run from each package directory
cd packages/nativa_dom && dart test
cd packages/nativa_render && flutter test
cd packages/nativax && flutter test
```

The full script is flaky at `game_play_test.dart` (see above); the final run
exited 1. The documentation checker is separate:

```bash
python3 tools/check_docs.py --write
```

## Conformance and quality tools

```bash
cd debug/engines/compatibility
dart run bin/fetch_suites.dart --suite test262 --suite html5lib --suite wpt
dart run bin/run_all.dart

# Visual fidelity and performance suite
dart run debug/engines/visual_comparison/bin/visual_check.dart --suite 50projects50days
dart run debug/engines/performance/bin/perf.dart run --out debug/artifacts/perf/latest

# Headless quality gate (visual + performance + compatibility)
python3 debug/engines/quality_gate/quality_gate.py --run
```

Artifacts are written under `debug/artifacts/` (gitignored); benchmark and leak
runs are kept under `debug/benchmarks/<area>/<run_id>/` with a manifest.
Evidence format and context commands: [`docs/debugging.md`](docs/debugging.md)
and [`docs/information-architecture.md`](docs/information-architecture.md).

## Examples

- [`examples/web-challenge`](examples/web-challenge): a real HTML/CSS/JS page
  using layout, canvas, forms, storage, workers, and an explicit network policy.
- [`examples/game-player`](examples/game-player): Three.js game runtime with
  WebAssembly physics and WebGL presentation. The full play test is the current
  blocker described above. Game code is not part of the documentation overhaul.
- [`examples/render-benchmark`](examples/render-benchmark): profile/AOT harness
  for large documents and renderer scenarios.

## Legal and platform boundaries

NativaX does not bundle Chromium or a browser runtime. JavaScriptCore, wasm3, and
third-party fixtures have their own licenses; see the package/vendor notices.
Only Linux x86_64 has current build and test evidence. Android, iOS, macOS, and
Windows require their own toolchain and verification before any support claim.
See [`docs/architecture/platform-support.md`](docs/architecture/platform-support.md).

## Contributing

Read [`AGENTS.md`](AGENTS.md), [`docs/agents.md`](docs/agents.md), and
[`docs/contributing.md`](docs/contributing.md). Every functional change needs a
test and evidence; conformance `SKIP`s do not count; never hide a failing suite
behind an average. Commits and pull requests are authored by the repository
owner only; no AI co-author or generated-by attribution is added.

Historical Spanish documentation is archived under
[`docs/archive/legacy-es/`](docs/archive/legacy-es/README.md). Maintained pages
are English as of 2026-10-26.
