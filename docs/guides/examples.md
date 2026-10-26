# Examples

The examples are integration evidence, not platform-support claims. Each has a
different purpose; none is a complete browser demo.

## `examples/web-challenge`

**Purpose:** a realistic HTML/CSS/JS page loaded from Flutter assets.

**Contents:**

- `assets/index.html`, `assets/styles.css`, `assets/app.js`;
- `lib/main.dart`: Flutter host and asset loader;
- `test/`: boot and interaction widget tests.

Run:

```bash
cd examples/web-challenge
flutter run -d linux
flutter test
```

The page exercises layout, text, forms, events, lists, tabs, counters, theme and
language switching, storage, media queries, timers, URLs, and the runtime's
unsupported-API diagnostics. Its host supplies an asset loader and an explicit
network policy; it does not use a WebView or local server.

The example's own `README.md` is current as of the documentation overhaul. Do
not trust older copies that claim Canvas 2D, `fetch`, `WebSocket`, `FormData`,
`MutationObserver`, or `<dialog>` are unsupported; those APIs now exist in part.
The example still flags the exact APIs it does not use.

## `examples/game-player`

**Purpose:** a large Three.js/Rapier game bundle inside NativaX, with WebGL,
WebAssembly, workers, `SharedArrayBuffer`, canvas, assets, and audio files.

Assets live under `assets/game/` and are a built Vite bundle. The game sources
are not part of this repository's documentation scope, and game code/assets are
not modified by documentation work. The app shell is `lib/main.dart`; metrics
overlay is `lib/metrics_overlay.dart`.

Run (Linux desktop):

```bash
cd examples/game-player
flutter run -d linux
```

Optional V8 path (requires the untracked native library):

```bash
examples/game-player/run_v8.sh
```

The game uses the QuickJS WebGL/WebAssembly bridge. V8 does not expose WebGL,
WebAssembly, or SharedArrayBuffer in this implementation; do not switch a game
run to V8 and expect parity. `game_play_test.dart` is flaky: repeated
2026-10-26 runs produced both a pass and a SIGABRT. A pass is Linux integration
evidence, not proof that the game is playable on every platform or GPU.

## `examples/render-benchmark`

**Purpose:** profile/AOT renderer workloads for large documents.

Scenarios: `load` (default), `mutate`, `updateall`, `scroll`, `resize`. The
harness is documented by its source comments:

```bash
cd examples/render-benchmark
flutter build linux --profile
NATIVAX_BENCH_FILE=/tmp/list_10k.html \
  build/linux/x64/profile/bundle/render_benchmark
```

Controls include `NATIVAX_BENCH_HTML`, `NATIVAX_SCENARIO`, `NATIVAX_TARGET`,
`NATIVAX_BENCH_ROOT`, `NATIVAX_SCROLL_STEPS`, `NATIVAX_FRAMES_MS`,
`NATIVAX_NO_STYLE_CACHE`, and `NATIVAX_METRICS`/`NATIVAX_LAYOUT_PROFILE`. These
are harness controls, not public runtime API. The renderer benchmark output is
not a GPU FPS result.

## `examples/test-pages`

Small pages used by engine changes and `tools/analyze_app.py`:

- `list.html`: 500 rows, scrolling, delegated click mutations;
- `form.html`: input/change/submit events;
- `animations.html`: infinite CSS animation and class toggle.

```bash
python3 tools/analyze_app.py examples/test-pages
```

These are not a conformance suite.

## `examples/threejs-multiplayer-starter`

A TypeScript/Three.js/Rapier reference app with its own browser/Vite/bun build.
It is not a NativaX Flutter example and is not run by `tools/test_all.sh`. Treat
its README and build instructions as its own project, not as NativaX support.

## Example rules

- Do not add a browser fallback to make an example work.
- Do not copy a screenshot or a boot as a conformance result.
- If an example needs an asset, add it through a resource loader and list it in
  `pubspec.yaml`.
- If an example needs network, use a narrow `NativaXNetwork`; do not expose a
  general fetch proxy.
- If an example crashes natively, record the command and platform; a Dart error
  handler cannot catch SIGABRT.

## Related

- [`embedding.md`](embedding.md)
- [`resources-and-images.md`](resources-and-images.md)
- [`../testing.md`](../testing.md)
- [`../architecture/platform-support.md`](../architecture/platform-support.md)
