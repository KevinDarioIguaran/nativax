# Configuration

`NativaXRuntimeConfig` is the policy object for one document session. It covers
resources, network, storage, JavaScript limits, timers, workers, callbacks, and
engine choice. This page explains the effects and the current defaults.

```dart
const NativaXRuntimeConfig(
  documentUrl: 'app://example/index.html',
  resources: NativaXAssetLoader(root: 'assets/www/'),
  network: DeniedNetwork(),
  engine: JavaScriptEngineConfig(
    memoryLimitBytes: 64 << 20,
    maxStackBytes: 256 << 10,
    executionBudget: Duration(seconds: 10),
    maxJobsPerDrain: 1000000,
  ),
  timers: TimerLimits(maxActiveTimers: 1000, minIntervalMs: 4),
  threadedWorkers: true,
)
```

`DeniedNetwork` and `NativaXNetwork` require `package:nativa_dom_bindings`.
`NativaXAssetLoader` is in `nativax`.

## Fields

| Field | Default | Effect | Risk / note |
|---|---|---|---|
| `documentUrl` | `app://local/index.html` | `location.href`, URL base, same-origin routing | A page can read it; do not put secrets in it |
| `resources` | `NativaXDenyAllResources()` | Own-document files | Deny-all is safe but pages cannot load scripts/CSS |
| `network` | `DeniedNetwork()` | External fetch/XHR/WebSocket | IoNetwork is not a full web policy |
| `storage` | null | `localStorage` backing; `NativaXView` supplies `MemoryStorage` | Direct runtime without storage may have no localStorage |
| `engine` | 64 MiB / 256 KiB / 10 s / 1M jobs | JS limits | V8 ignores time/jobs/stack currently |
| `engineFactory` | null | Custom engine | Must preserve bridge contract/limits |
| `timers` | 1,000 active / 4 ms | Timer limits | `RangeError` / clamp |
| `threadedWorkers` | true | Isolate per worker | false shares UI isolate |
| `devicePixelRatio` | null | `window.devicePixelRatio`; null uses MediaQuery | Cap for heavy canvas on HiDPI |
| `appHandlers` | empty | `nativax.invoke` callbacks | Validate input; not sandboxed |
| `services` | null | Clipboard/vibration/alert/open/theme | View supplies Flutter defaults; direct runtime has none |
| `onConsole` | no-op | `console.*` | Avoid logging secrets |
| `onScriptError` | null | Script errors | A page can continue after an error |
| `onDiagnostic` | null | Resource/font/render warnings | Not a fatal error channel |
| `onNavigate` | null | Link activation | Validate schemes/origins |
| `onSubmit` | null | Form submission | NativaX does not submit over HTTP |
| `onThemeMode` | null | Script theme request | View default reports a diagnostic |

## Engine selection

`engineFactory` wins if provided. Otherwise:

- module script → QuickJS;
- `forceQuickJs: true` (create argument) → QuickJS;
- desktop + V8 available + no live V8 → V8;
- everything else → QuickJS.

`NATIVAX_ENGINE=quickjs` forces QuickJS in the default selector.
`NATIVAX_ENGINE` with any other value does not force V8; it only leaves V8
eligible. Use `forceQuickJs` or `NATIVAX_ENGINE=quickjs` for explicit QuickJS.

For a page that must use WebGL, WebAssembly, SharedArrayBuffer, or modules, do
not rely on the desktop default; force QuickJS or supply a compatible engine.
For a page that must not be interruptible by the QuickJS timeout, V8 is not a
safe substitute because it has no time budget; use a process boundary.

## JavaScript limits

`JavaScriptEngineConfig` defaults when constructed directly are **1 s** and
**10,000 jobs**; `NativaXRuntimeConfig.defaultEngineConfig` overrides them to
**10 s** and **1,000,000 jobs** for the runtime. Keep this distinction when
copying a config into a standalone engine.

`memoryLimitBytes`:

- QuickJS: allocator ceiling; exceeding raises a script error.
- V8: near-heap-limit callback terminates the running script; startup overage
  triggers a QuickJS reload, post-startup reports `onEngineOverBudget`.
- `0`: disables the limit (not recommended).

`maxStackBytes`:

- QuickJS: native stack guard, default 256 KiB.
- V8: passed to `nv8_create` but ignored in the current Rust bridge.

`executionBudget`:

- QuickJS: wall-clock per engine entry including microtask drain.
- V8: not enforced in the current native bridge.

`maxJobsPerDrain` / `microtaskSlice`:

- QuickJS: job cap and optional yield.
- V8: not enforced.

`TimerHost` limits are separate: `maxActiveTimers` (1,000) and
`minIntervalMs` (4 ms).

## Workers

`threadedWorkers: true` uses `IsolateWorkerLauncher`:

- each worker has its own isolate and QuickJS runtime;
- default worker config: 1 GiB memory, 1 MiB stack, 30 s budget, 1M jobs;
- `maxWorkers` defaults to 16 per launcher;
- scripts/modules/fetch use the page's loader/network policy.

`threadedWorkers: false` uses `InProcessWorkerLauncher`, which shares the UI
isolate. It is easier to debug but has no parallelism.

## Storage and services

`NativaXView` creates `MemoryStorage()` when `config.storage` is null. The default
quota is 5 MB of keys + values. To persist, implement `KeyValueStorage` (for
example with `shared_preferences`) and pass it.

`PlatformServices` is optional. If omitted in a direct runtime, clipboard,
vibration, external URL open, and alert are unavailable/no-op. `NativaXView`
supplies Flutter-backed defaults for clipboard/haptics/alert.

## Recommended profiles

### Asset page, no network

```dart
NativaXRuntimeConfig(
  documentUrl: 'app://app/index.html',
  resources: NativaXAssetLoader(root: 'assets/www/'),
  // network: DeniedNetwork() is the default
)
```

### API page with a narrow allowlist

```dart
NativaXRuntimeConfig(
  documentUrl: 'https://app.example/',
  resources: NativaXAssetLoader(root: 'assets/www/'),
  network: IoNetwork(
    allow: (uri) => uri.host == 'api.example.com',
    maxResponseBytes: 8 << 20,
  ),
)
```

`LocalResourceNetwork` still routes same-origin paths to the loader. A missing
same-origin asset can fall back to the network policy; keep the network
allowlist narrow.

### QuickJS-only (WebGL/WASM/modules or adversarial input)

```dart
final runtime = await NativaXRuntime.create(
  source: html,
  forceQuickJs: true,
  config: const NativaXRuntimeConfig(),
);
```

or set `NATIVAX_ENGINE=quickjs` for the process.

### Deterministic tests

```dart
final runtime = await NativaXRuntime.create(
  source: html,
  environment: StaticEnvironment(
    media: const MediaContext(width: 800, height: 600),
    languages: const ['en-US'],
    platform: 'linux',
    localStorage: MemoryStorage(quota: 1024 * 1024),
  ),
  config: const NativaXRuntimeConfig(),
);
```

Use `StaticEnvironment` and no network for reproducible widget/unit tests.

## What config cannot do

- It cannot add a browser engine or fallback.
- It cannot make V8 support modules/WebGL/WASM/SAB.
- It cannot turn a denied image into a loaded image; supply an image resolver.
- It cannot make `window.open`, `confirm`, or file inputs real.
- It cannot enforce a custom engine's limits for you.
- It cannot sandbox the process; use OS isolation for hostile content.

## Related

- [`public-api.md`](public-api.md)
- [`environment-variables.md`](environment-variables.md)
- [`../architecture/javascript-engines.md`](../architecture/javascript-engines.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)
- [`../guides/resources-and-images.md`](../guides/resources-and-images.md)
