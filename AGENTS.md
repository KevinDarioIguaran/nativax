# Nativa agent instructions

## Project

Nativa is the technology family. **NativaX** is the platform: an experimental
UI runtime written in Dart that interprets a documented subset of HTML, CSS, and
JavaScript and renders it with native Flutter widgets. It does not use WebView,
Chromium, CEF, Electron, or a local HTTP server for presentation.

- `nativax`: public runtime, `NativaXView`, Flutter environment.
- `nativa_js`: QuickJS-ng, FFI, timers, WebAssembly, limits, WebGL bridge.
- `nativa_html`, `nativa_dom`, `nativa_css`, `nativa_dom_bindings`: the modular
  NativaWeb family.
- `nativa_render`: CSS layout and Flutter rendering.

## Non-negotiables

- Keep rendering inside the owned runtime chain: HTML → DOM → CSS →
  `nativa_render` → Flutter widgets/RenderObjects.
- Never add `webview_flutter`, `flutter_inappwebview`, `HtmlElementView`,
  Chromium, CEF, Electron, or a browser fallback.
- JavaScript must run on a real JS engine. On desktop (Linux, macOS,
  Windows) the page engine is V8 (`createDefaultJavaScriptEngine`) when
  `libnx_v8.so` loads; QuickJS-ng is the default everywhere else (iOS, Android,
  no JIT), for pages with ES modules (V8 has no modules yet), for workers, and
  the fallback when V8 is missing or hits the memory limit. Both stay behind
  the same `JavaScriptEngine` contract; never replace the engine with a toy
  interpreter or text search.
- Scripts receive only ids, scalars, and JSON; never Dart objects or `JSValue`.
- Every new feature needs a test. A conformance `SKIP` never counts as
  compatibility.
- Do not claim compatibility, performance, maturity, platform support, or a leak
  without reproducible evidence.
- Do not modify game code or `examples/game-player/assets/game/**` unless the
  user explicitly asks. Import-path updates from a package rename are allowed
  when required to keep the build green.
- Preserve stable defaults: DPR 1.0, `backdrop-filter` enabled,
  `GlSurfaceView` + `RawImage`, metrics opt-in.
- Do not push, reset, or rewrite user work unless explicitly asked.
- Commits and pull requests are authored only by the repository owner
  (KevinDarioIguaran). Never add AI co-author trailers (`Co-Authored-By:`)
  or "Generated with" attribution lines.

## Required workflow

1. Load the relevant skills below and inspect the existing contract, tests, and
   limits.
2. Write the acceptance criterion before coding: behavior, test, command,
   metric, and out-of-scope items.
3. Prefer the smallest reversible change. Write the failing test first.
4. Run focused tests, then `./tools/test_all.sh` with the game closed. Run it
   from the repository root.
5. Run `dart analyze`/`flutter analyze` on touched packages.
6. Measure affected conformance, benchmarks, or leaks when relevant.
7. Update `progress/` and docs in the same change.
8. Report exact commands and real results; state what could not be measured.

Compatibility work is incremental: keep each real ~1 % gain as its own commit,
stop to report it, and do not mix it with structural refactors. A harness or
adapter correction is not a product compatibility gain.

## Skills

The shared skill library is `.agents/skills`. OpenCode discovers it directly.
Claude Code uses the symlinked copies under `.claude/skills`.

| Skill | Use when |
|---|---|
| `nativa-project` | Scoping, product constraints, maturity, platform status |
| `nativa-architecture` | Package boundaries, new modules, public APIs |
| `nativa-web-rendering` | HTML, DOM, CSS, layout, painting, no-WebView review |
| `nativa-conformance` | Test262, html5lib, URL, WPT DOM/CSS/tree, compatibility increments |
| `nativa-verification` | Acceptance criteria, TDD, analyze, `test_all.sh`, evidence |
| `nativa-security` | JS-Dart bridge, host APIs, limits, hostile inputs |
| `nativa-performance` | Benchmarks, memory/leaks, latency, 7x claims |
| `nativa-docs` | Progress, status, reports, public documentation |

Read `.agents/README.md` for the library map. Load only the skills needed for the
task; the references stay out of context until then.

## Useful commands

```bash
./tools/test_all.sh

# Pure Dart packages (run from each package directory)
cd packages/nativa_js && dart test
cd packages/nativa_dom && dart test
cd packages/nativa_html && dart test
cd packages/nativa_css && dart test
cd packages/nativa_dom_bindings && dart test

# Flutter packages (run from each package directory)
cd packages/nativa_render && flutter test
cd packages/nativax && flutter test

# Conformance
cd debug/engines/compatibility
dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_wpt.dart
dart run bin/run_html_tree.dart

# Bounded AI context (indexes, runs, conformance, docs, token estimates)
python3 debug/run.py context brief --budget 2000
python3 debug/run.py context index
```

## References

- `README.md`: project overview and current status.
- `docs/nativa-family.md`: family names, package map, extraction criteria.
- `progress/status.md`: live state and numbers.
- `progress/conformance.md`: suite baselines and gaps.
- `docs/information-architecture.md`: formats, schemas, indexes, and context policy.
- `docs/security/audit.md`, `docs/security/threat-model.md`: security model.
