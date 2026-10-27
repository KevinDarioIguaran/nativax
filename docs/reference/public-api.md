# Public API reference

This is a curated reference for the exported API. The source and generated
`dart doc` output are authoritative for every member. All packages are
`0.1.0` pre-release; no semver stability is promised.

```dart
import 'package:nativax/nativax.dart';
```

The `nativax` barrel is the normal entry point. Lower-level packages are also
public for tooling and advanced embedding, but changing their internals is not
covered by the `nativax` facade.

## `NativaXView`

`Widget` that loads, owns, renders, and disposes one runtime.

```dart
const NativaXView({
  Key? key,
  required String source,
  NativaXRuntimeConfig config = const NativaXRuntimeConfig(),
  NativaXImageResolver? imageResolver,
  EdgeInsets padding = EdgeInsets.zero,
  void Function(NativaXRuntime runtime)? onRuntimeReady,
});
```

- `source` identity change triggers reload.
- `config` change alone does **not** reload.
- The view supplies Flutter-backed platform services and an in-memory storage
  when the config omits them.
- It displays a spinner/error widget; it does not add Material/Scaffold.

## `NativaXRuntimeConfig`

`const` configuration passed to `NativaXView` or `NativaXRuntime.create`.

```dart
const NativaXRuntimeConfig({
  JavaScriptEngineConfig engine = defaultEngineConfig,
  TimerLimits timers = const TimerLimits(),
  NativaXResourceLoader resources = const NativaXDenyAllResources(),
  KeyValueStorage? storage,
  Map<String, AppHandler> appHandlers = const {},
  void Function(Object error)? onScriptError,
  void Function(ConsoleMessage message)? onConsole,
  void Function(String message)? onDiagnostic,
  void Function(String href, dom.Element anchor)? onNavigate,
  void Function(dom.Element form)? onSubmit,
  bool Function(ThemeModeRequest mode)? onThemeMode,
  String documentUrl = 'app://local/index.html',
  double? devicePixelRatio,
  NativaXNetwork network = const DeniedNetwork(),
  PlatformServices? services,
  bool threadedWorkers = true,
  JavaScriptEngine Function(JavaScriptEngineConfig config)? engineFactory,
});
```

`defaultEngineConfig` is `executionBudget: 10 s`, `maxJobsPerDrain: 1,000,000`,
memory 64 MiB, stack 256 KiB.

## `NativaXRuntime`

```dart
static Future<NativaXRuntime> create({
  required String source,
  NativaXRuntimeConfig config = const NativaXRuntimeConfig(),
  HostEnvironment? environment,
  String? documentUrl,
  PlatformServices? platformServices,
  bool forceQuickJs = false,
});
```

Fields/getters:

| Member | Type | Notes |
|---|---|---|
| `document` | `nativa_dom.Document` | Owned session document |
| `styleEngine` | `nativa_css.StyleEngine` | Computed styles |
| `engine` | `JavaScriptEngine` | Selected engine |
| `bindings` | `DomBindings` | Web API installation |
| `timers` | `TimerHost` | Timer scheduler |
| `config` | `NativaXRuntimeConfig` | Effective config |
| `parseErrors` | `List<HtmlParseError>` | Recoverable parse errors |
| `scriptErrors` | `List<Object>` | Script errors observed |
| `engineName` | `String` | `v8`, `quickjs`, custom type name |
| `isDisposed` | `bool` | Lifecycle guard |
| `onEngineOverBudget` | `void Function()?` | V8 post-startup heap stop |
| `environmentChanged()` | `void` | Notify resize/theme/locale |
| `dispose()` | `void` | Release session |

The runtime is single-isolate/session. Do not share it across isolates.

## Resources and networking

From `package:nativax/nativax.dart`:

- `abstract class NativaXResourceLoader` with `load`/`loadBytes`;
- `NativaXDenyAllResources`, `NativaXAssetLoader`, `NativaXDirectoryLoader`;
- `DocumentModules`;
- `LocalResourceNetwork`.

From `package:nativa_dom_bindings/nativa_dom_bindings.dart`:

- `NativaXNetwork`, `NetworkRequest`, `NetworkResponse`, `NetworkSocket`;
- `DeniedNetwork`, `IoNetwork`, `NetworkDenied`;
- `PlatformServices`.

`LocalResourceNetwork` is exported by `nativax`, not by the bindings package.

The `nativax` barrel does **not** re-export `NativaXNetwork`,
`DeniedNetwork`, `IoNetwork`, or `PlatformServices`; import
`nativa_dom_bindings` when using them. This is a public-surface wart to fix in a
future API change, not a reason to invent a local HTTP server.

## Images, renderer, and fonts

From `nativax`:

```dart
typedef NativaXImageResolver = ImageProvider? Function(Element element, String src);

class NativaXDocumentView extends StatefulWidget {
  const NativaXDocumentView({
    Key? key,
    required Document document,
    required StyleEngine styleEngine,
    NativaXImageResolver? imageResolver,
    void Function(String message)? onDiagnostic,
    void Function(String href, Element anchor)? onNavigate,
    void Function(Element form)? onSubmit,
    EdgeInsets padding = EdgeInsets.zero,
  });
}
```

Also exported: `NativaXDrawTrace`, `NativaXSvgImageProvider`,
`nativaxDefaultFontFamily`, `nativaxFontAvailable`, `nativaxFontFallback`,
`Event` (the DOM event type), and `MediaContext` (the CSS media evaluation
context).

The renderer package exports layout primitives (`CssBox`, `CssBlockFlow`,
`CssFlexLayout`, `CssGridLayout`, `CssTransform`, virtualization, layout
profile). These are for advanced embedding/tests, not a stable layout API.

## Hot reload

```dart
class NativaXHotReloadController extends ChangeNotifier {
  int get revision;
  bool get isReloading;
  Object? get lastError;
  Future<void> reload();
  void reportDone();
  void reportError(Object error);
}

class NativaXHotReloadView extends StatefulWidget {
  const NativaXHotReloadView({
    Key? key,
    required String sourcePath,
    NativaXRuntimeConfig config = const NativaXRuntimeConfig(),
    NativaXImageResolver? imageResolver,
    EdgeInsets padding = EdgeInsets.zero,
    NativaXHotReloadController? controller,
    Duration debounce = const Duration(milliseconds: 80),
    void Function(String source)? onBeforeReload,
    void Function(NativaXRuntime runtime)? onAfterReload,
    void Function(Object error)? onError,
  });
}
```

Hot reload recreates the runtime; script state is lost. It is development-only
and uses `dart:io` file watching.

## Workers

`IsolateWorkerLauncher` is exported from `nativax`:

```dart
IsolateWorkerLauncher({
  required Future<String?> Function(String url) loadScript,
  required NativaXNetwork network,
  JavaScriptEngineConfig engineConfig = const JavaScriptEngineConfig(
    memoryLimitBytes: 1024 * 1024 * 1024,
    maxStackBytes: 1024 * 1024,
    executionBudget: Duration(seconds: 30),
    maxJobsPerDrain: 1000000,
  ),
  int maxWorkers = 16,
});
```

`WorkerLauncher`, `WorkerRequest`, `WorkerScopeInfo`, and messaging primitives
are in `nativa_dom_bindings`.

## Templates

```dart
typedef NativaXTemplateLoader = Future<String?> Function(String name);

class NativaXTemplateEngine {
  NativaXTemplateEngine({
    required NativaXTemplateLoader loader,
    Map<String, dynamic>? globals,
  });

  final NativaXTemplateLoader loader;
  final Map<String, dynamic> globals;

  Future<String> render(String name, [Map<String, dynamic>? context]);
  Future<String> renderString(
    String source, [
    Map<String, dynamic>? context,
    String? name,
  ]);
}
```

## JavaScript engine contract

From `nativa_js` (partly re-exported by `nativax`):

- `abstract interface class JavaScriptEngine`: `evaluate`, `evaluateModule`,
  `callGlobal`, `registerHostFunction`, `drainMicrotasks`,
  `hasPendingMicrotasks`, `memoryUsed`, `collectGarbage`, `dispose`.
- `JavaScriptEngineConfig`: memory, stack, budget, jobs, microtask slice.
- `QuickJsEngine`, `V8Engine`, `JscEngine` (opt-in JavaScriptCore;
  `JscEngine.isAvailable([path])`, `memoryExhausted`, `enforceMemoryLimit()`).
- `createDefaultJavaScriptEngine(config, {environment})`,
  `createJavaScriptEngineNamed(name, [config])` (`quickjs`, `v8`, `jsc`).
- `TimerHost`, `TimerLimits`.
- `ConsoleMessage`, `ConsoleLevel`, `installConsole`.
- exceptions: `JavaScriptException`, `JavaScriptMemoryLimitException`,
  `JavaScriptTimeoutException`, `JavaScriptEngineStateException`,
  `JavaScriptHostError`.
- module host: `ModuleHost`, `ModuleGraph`.
- JIT/WASM helpers (`Jit`, wasm prelude) are lower-level and experimental.

A custom engine must preserve the JSON-only host contract and synchronous DOM
calls. It is responsible for its own limits; the runtime cannot enforce a custom
backend's time/memory behavior.

## DOM/CSS/HTML packages

These are public packages, not required for normal embedding:

- `nativa_dom`: `Document`, `Element`, `Node`, events, selectors, mutation
  records, `LayoutHost`, limits.
- `nativa_html`: `HtmlParser`, `HtmlParseResult`, tokenizer, parse errors.
- `nativa_css`: `StyleEngine`, `ComputedStyle`, `StyleSheet`, selectors,
  media/supports, values, `longhands`, `isSupportedProperty`.
- `nativa_dom_bindings`: `DomBindings`, `WindowTarget`, `AppHandler`, storage,
  network, messaging, modules, worker runtime, CSSOM/canvas/IDB/Intl preludes.
- `nativa_render`: render widgets/objects, style mapping, SVG, draw trace,
  fonts, virtualization.

## Host environment and storage

- `HostEnvironment` (interface): media, languages, theme, platform, localStorage,
  theme request.
- `FlutterHostEnvironment`: Flutter-backed implementation used by `NativaXView`.
- `StaticEnvironment`: deterministic tests/headless hosts.
- `KeyValueStorage`, `MemoryStorage` (5 MB default), `ThemeSnapshot`,
  `ThemeModeRequest`.

`PlatformServices` is in `nativa_dom_bindings`, not the `nativax` barrel.

## Versioning and stability

- Package versions are `0.1.0`; no stable API promise.
- The `nativax` facade is more stable than package internals.
- Source files under `lib/src/` are implementation, even when exported through a
  barrel. Treat them as public only if the package's barrel exports them and a
  test/Linked documentation covers them.
- Breaking public API changes need a migration note and a test update.

## Generate full API docs

```bash
dart doc packages/nativax
dart doc packages/nativa_render
```

Generated output is not checked into the repository. It reflects doc comments,
some of which lag the implementation; prefer source plus this page when they
disagree.

## Related

- [`configuration.md`](configuration.md)
- [`environment-variables.md`](environment-variables.md)
- [`../guides/embedding.md`](../guides/embedding.md)
- [`../architecture/README.md`](../architecture/README.md)
