# Embedding NativaX in a Flutter app

There are two levels of embedding:

- `NativaXView` for a normal widget that owns runtime lifecycle for you;
- `NativaXRuntime.create` when you need the runtime object, custom rendering,
  tests, hot reload control, or a non-widget host.

Both use the same parse/style/engine/render chain.

## The widget

```dart
import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

final class PageView extends StatelessWidget {
  const PageView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    return NativaXView(
      source: html,
      padding: const EdgeInsets.all(16),
      config: const NativaXRuntimeConfig(
        documentUrl: 'app://example/index.html',
      ),
      onRuntimeReady: (runtime) {
        debugPrint('engine: ${runtime.engineName}');
      },
    );
  }
}
```

Properties:

| Property | Type | Meaning |
|---|---|---|
| `source` | `String` | HTML document source; identity change triggers reload |
| `config` | `NativaXRuntimeConfig` | Runtime policy; **changes do not reload an existing runtime** |
| `imageResolver` | `NativaXImageResolver?` | Maps `img`/image elements to Flutter `ImageProvider`s |
| `padding` | `EdgeInsets` | Outer Flutter padding around the document |
| `onRuntimeReady` | `void Function(NativaXRuntime)?` | Called after a runtime becomes current |

The view shows a spinner while creating the runtime and an error message if
creation throws. It does not create `Scaffold`/`Material` wrappers for your app;
use them around it if you want Material theme/text direction.

## Direct runtime

```dart
final runtime = await NativaXRuntime.create(
  source: html,
  documentUrl: 'app://example/index.html',
  config: const NativaXRuntimeConfig(),
);

try {
  // Use runtime.document, runtime.styleEngine, runtime.engine, runtime.bindings.
} finally {
  runtime.dispose();
}
```

Use the same isolate that created it. The event loop uses that isolate. Call
`dispose()` exactly once when done; using the runtime afterward is invalid.

`NativaXRuntime.create` throws on hard parser limits or engine creation failure.
Script errors are reported through `onScriptError` and do not throw out of
`create` in the normal path.

## Configuration

`NativaXRuntimeConfig` fields (all optional except where noted):

| Field | Default | Purpose |
|---|---|---|
| `documentUrl` | `app://local/index.html` | `location.href`, relative URL base, same-origin routing |
| `resources` | `NativaXDenyAllResources()` | Own-document files (scripts, CSS, modules, fonts, wasm) |
| `network` | `DeniedNetwork()` | External fetch/XHR/WebSocket policy |
| `storage` | in-memory 5 MB in the view | `localStorage`/`sessionStorage` backing |
| `engine` | 10 s budget, 1M jobs, 64 MiB heap, 256 KiB stack | JS engine limits |
| `engineFactory` | null (default selector) | Custom `JavaScriptEngine` factory |
| `timers` | 1,000 timers, 4 ms min interval | Timer limits |
| `threadedWorkers` | `true` | Isolate-backed workers |
| `devicePixelRatio` | Flutter MediaQuery | `window.devicePixelRatio` and canvas scaling |
| `appHandlers` | empty | `nativax.invoke(name, ...)` app callbacks |
| `services` | view defaults | Clipboard, vibration, alert, external URL, theme |
| `onConsole` | no-op | `console.*` sink |
| `onScriptError` | null | Script errors |
| `onDiagnostic` | null | Resource/font/render diagnostics |
| `onNavigate` | null | Link activation; NativaX never navigates itself |
| `onSubmit` | null | Form submission; NativaX never navigates itself |
| `onThemeMode` | null | Script theme request |

`NativaXNetwork`, `IoNetwork`, `DeniedNetwork`, and `PlatformServices` live in
`package:nativa_dom_bindings/nativa_dom_bindings.dart`; the `nativax` barrel
does not re-export all of them. Import that package when configuring network or
services.

## Resource example

```dart
import 'package:nativax/nativax.dart';

NativaXView(
  source: html,
  config: NativaXRuntimeConfig(
    documentUrl: 'app://app/index.html',
    resources: NativaXAssetLoader(root: 'assets/www/'),
  ),
)
```

The root must contain the document's sibling CSS/JS/assets. List each asset
subdirectory in `pubspec.yaml`. For filesystem content, use
`NativaXDirectoryLoader`, but keep the root narrow. External URLs still go
through `network`, not the loader.

## Image example

```dart
ImageProvider? resolveImage(nativa_dom.Element element, String src) {
  if (src.startsWith('asset:')) {
    return AssetImage(src.substring('asset:'.length));
  }
  return null;
}

NativaXView(
  source: html,
  imageResolver: resolveImage,
)
```

`src` is not fetched for you. Returning null yields a broken-image placeholder and
a diagnostic. `NativaXImageResolver` receives the DOM element and the resolved
`src` string.

## Network example

```dart
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';

final network = IoNetwork(
  allow: (uri) => uri.host == 'api.example.com',
  maxResponseBytes: 8 * 1024 * 1024,
);

NativaXView(
  source: html,
  config: NativaXRuntimeConfig(network: network),
)
```

`IoNetwork` is a convenience. It does not implement CORS, cookies, certificate
pinning, or a complete redirect policy. Implement `NativaXNetwork` for those.

## Navigation and forms

NativaX does not own your navigation stack. `onNavigate` receives the resolved
href and anchor; `onSubmit` receives the form. Return control to the host:

```dart
onNavigate: (href, anchor) {
  // Validate/route in the Flutter app; do not silently navigate a WebView.
},
onSubmit: (form) {
  // Read form values or dispatch your own action.
},
```

`document.onNavigate`/`onSubmit` are invoked by the DOM. If a script
`preventDefault()`s the event, the host callback is not called for the default
action. A `javascript:` URL is not a special trusted path; validate it like any
other input.

## Theme, media, and lifecycle

`NativaXView` builds a `FlutterHostEnvironment` from `MediaQuery` and theme.
`nativax.theme.setMode()` calls `onThemeMode`; if absent, it reports a
diagnostic and returns false. It does not change Flutter's `ThemeMode` itself.

`didChangeDependencies` updates theme/DPR/media context. A source change
reloads; a config-only change does not. To apply a new config, recreate the view
(key it or rebuild with a new widget identity) or use a hot-reload controller.

## Hot reload

`NativaXHotReloadController` can reload the document source through a
`NativaXHotReloadView`. See [`../hot-reload.md`](../hot-reload.md). Hot reload
replaces the document/runtime; it does not preserve JS globals or DOM state.

## Error handling

- Creation errors: show them; do not silently swap to a browser.
- Script errors: report them; a page may still be partially alive.
- Denied resources: diagnostics, not fatal.
- V8 over budget: the view reloads on QuickJS and loses page state; tell the
  user if state matters.
- A fatal native crash (for example `SIGABRT` from native code) cannot be
  caught by Dart; isolate or process-bound the page if that matters.

## Tests for embedding

- `packages/nativax/test/runtime_test.dart`
- `packages/nativax/test/hot_reload_test.dart`
- `packages/nativax/test/web_platform_render_test.dart`
- `packages/nativa_render/test/js_integration_test.dart`
- `examples/web-challenge/test/boot_test.dart`

## Related

- [`resources-and-images.md`](resources-and-images.md)
- [`forms-and-navigation.md`](forms-and-navigation.md)
- [`../reference/public-api.md`](../reference/public-api.md)
- [`../reference/configuration.md`](../reference/configuration.md)
- [`../architecture/runtime-lifecycle.md`](../architecture/runtime-lifecycle.md)
