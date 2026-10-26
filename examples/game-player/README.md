# Game player example

A Linux Flutter shell that loads the unmodified production Vite/Three.js/Rapier
bundle from `assets/game/` through NativaX. The game is integration evidence for
WebGL, WebAssembly, workers, `SharedArrayBuffer`, canvas, assets, and audio
files; it is not a public compatibility promise.

Game sources/assets are owner-controlled. Documentation work must not modify
`examples/game-player/assets/game/**`.

## Run

```bash
cd examples/game-player
flutter run -d linux
```

The shell uses the asset loader at `assets/game/`, `documentUrl`
`app://game/index.html`, a 512 MiB JS memory limit, a 30 s execution budget,
and up to 1,000,000 jobs per drain. Metrics are opt-in:

```bash
NATIVAX_METRICS=1 flutter run -d linux
NATIVAX_METRICS_FILE=/tmp/nativax-game-metrics.json flutter run -d linux
```

Automation/performance hooks:

| Variable | Effect |
|---|---|
| `NATIVAX_GAME_DPR=0.5..2` | Internal render scale (not window size) |
| `NATIVAX_NO_BACKDROP=1` | Host-injected `backdrop-filter: none` for experiments |
| `NATIVAX_AUTOSTART=1` | Clicks the visible start button once from the host |
| `NATIVAX_ENGINE=v8` | Selects the optional V8 factory |

`NATIVAX_ENGINE=v8` is not a supported game path: this V8 implementation does
not expose host WebGL, WebAssembly, `SharedArrayBuffer`, or modules. The game
needs the QuickJS bridges. Use it only to observe the failure, not as parity.

There is also an untracked/local helper `run_v8.sh`; treat it as an experiment,
not a stable entry point.

## What it demonstrates

- a real Three.js/WebGL scene in a canvas;
- Rapier WebAssembly physics;
- dedicated workers and `SharedArrayBuffer`/`Atomics` messaging;
- `OffscreenCanvas`, module workers, and asset loading;
- CSS backdrop/filter/layout in a large page;
- a DOM start button and a game UI without a browser engine.

These are integration observations. They do not prove general Three.js, WebGL,
or Rapier compatibility.

## Known limitations

- Audio is a silent Web Audio graph; decoding/playback is not implemented.
- WebGL is a bridge with targeted coverage, not a conformance-tested browser
  implementation.
- WASM import/export support is incomplete; modules that need imported memory,
  tables, globals, SIMD, or threads are unsupported.
- V8 cannot run this game path.
- `packages/nativax/test/game_play_test.dart` is flaky: repeated 2026-10-26
  runs produced both a pass and a SIGABRT. When it passes it is integration
  evidence, not proof that every game path or platform is playable.
- Game assets are large; startup/memory behavior depends on the machine.
- Linux x86_64 is the only measured target.

## Verification

```bash
cd examples/game-player
flutter test
```

The `flutter test` result must be reported as-is; a skip/failure is not a pass.
See [`../../docs/guides/examples.md`](../../docs/guides/examples.md) and
[`../../docs/status.md`](../../docs/status.md).
