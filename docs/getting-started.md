# Getting started

This page gets a NativaX document on screen and explains the pieces you will
meet next. It is not a browser-compatibility promise. Linux x86_64 is the only
platform with current build and measurement evidence in this repository.

## 1. Requirements

- Flutter 3.35 or newer with Dart 3.10 or newer. The workspace was measured
  with Dart 3.13.0 / Flutter 3.47.0.
- A native desktop toolchain supported by Flutter (for Linux: clang, CMake,
  Ninja, GTK development packages).
- The QuickJS build hook needs a working C toolchain. V8 is optional and only
  used when `libnx_v8.so` can be loaded.

NativaX has no WebView, Chromium, CEF, or Electron dependency. Do not add one to
make a page work; the documented runtime path is the product.

## 2. Get the workspace

```bash
git clone <repository-url> /path/to/nativax
cd /path/to/nativax
flutter pub get
```

The root `pubspec.yaml` is a Dart workspace. Package commands must run from the
package directory because native assets are resolved per package.

## 3. Run the reference example

The web challenge is the most representative sample page: HTML, CSS, canvas,
forms, storage, workers, and an explicit network policy.

```bash
cd examples/web-challenge
flutter run -d linux
```

This example is a normal Flutter app. Its `lib/main.dart` creates a
`NativaXView`, loads `assets/index.html`, supplies `_AssetLoader`, and enables
network access only for the hosts it needs. The page code itself is ordinary
web code; it is not rewritten for NativaX.

Other entry points:

```bash
cd examples/render-benchmark
flutter run -d linux
```

`examples/game-player` is a larger Three.js/WebGL/WebAssembly integration. It is
not the first example to try, and its full play test is the current known test
blocker. See [`guides/examples.md`](guides/examples.md).

## 4. Embed the smallest document

```dart
import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: NativaXView(
          source: '''
            <style>
              body { font-family: sans-serif; margin: 24px }
              h1 { color: #2563eb }
              button { padding: 8px 16px }
            </style>
            <h1>Hello</h1>
            <button id="b">0</button>
            <script>
              let n = 0;
              const b = document.getElementById('b');
              b.addEventListener('click', () => {
                n += 1;
                b.textContent = String(n);
              });
            </script>
          ''',
        ),
      ),
    ),
  );
}
```

What happens:

1. `NativaXView` parses the source with `nativa_html`.
2. `NativaXRuntime` builds a `nativa_dom` document and a `nativa_css` style
   engine.
3. The runtime creates a JavaScript engine (V8 on supported desktop builds when
   the library loads; otherwise QuickJS-ng) and installs DOM, window, timer, and
   web APIs.
4. Inline and external scripts run in document order, followed by module
   scripts.
5. `NativaXDocumentView` lays out the DOM with CSS rules and paints it with
   Flutter render objects.
6. A click from Flutter becomes a real DOM event; a DOM mutation schedules a
   re-render.

No browser process is started and no local HTTP server is used for the page.

## 5. Resources are denied by default

The minimal view has **no external resources**. This is deliberate:

- `NativaXDenyAllResources` is the default resource loader.
- `DeniedNetwork` is the default `fetch`/XHR/WebSocket policy.
- `img` and CSS background images resolve only through
  `NativaXImageResolver`; NativaX does not fetch them implicitly.
- `@font-face` URLs are loaded through the host resource loader.

For assets, provide `NativaXAssetLoader` or a custom `NativaXResourceLoader`.
For images, provide an `imageResolver`. For network access, provide a
`NativaXNetwork` such as `IoNetwork(allow: ...)`. Read
[`guides/resources-and-images.md`](guides/resources-and-images.md) before
shipping untrusted content.

## 6. Choose an engine deliberately

The default page engine is selected by
`createDefaultJavaScriptEngine`:

| Condition | Engine |
|---|---|
| Linux/macOS/Windows, `libnx_v8.so` loadable, no live V8 instance, no module script, not forced | V8 |
| Mobile, V8 unavailable, V8 already live on the thread, `NATIVAX_ENGINE=quickjs`, `forceQuickJs: true`, or a page with `<script type="module">` | QuickJS-ng |
| Dedicated or in-process worker | QuickJS-ng |

V8 currently lacks ES modules, WebAssembly, SharedArrayBuffer, and the WebGL
bridge. If a page needs those, force QuickJS or provide a custom engine factory.
See [`architecture/javascript-engines.md`](architecture/javascript-engines.md).

`NativaXRuntimeConfig` controls memory, stack, execution budget, timers, storage,
callbacks, document URL, device pixel ratio, workers, and services. See
[`reference/configuration.md`](reference/configuration.md).

## 7. Run checks

```bash
# Full repository check; run with the game closed
./tools/test_all.sh

# Focused pure-Dart suites
cd packages/nativa_dom && dart test
cd packages/nativa_html && dart test
cd packages/nativa_css && dart test
cd packages/nativa_js && dart test
cd packages/nativa_dom_bindings && dart test

# Flutter suites
cd packages/nativa_render && flutter test
cd packages/nativax && flutter test

# Documentation only
python3 tools/check_docs.py
```

`./tools/test_all.sh` must be run from the repository root with the game
closed. It is flaky at `packages/nativax/test/game_play_test.dart`: repeated
runs on 2026-10-26 produced both `exit 0` and a SIGABRT, and the final run
failed. Do not assume the suite is green. See [`testing.md`](testing.md).

## 8. Read the status before extending claims

The stable maturity view is [`status.md`](status.md). The live state is
[`../progress/status.md`](../progress/status.md). The last recorded
conformance table is [`../progress/conformance.md`](../progress/conformance.md).
If you need a number that is not in those files with a date, command, and
environment, it does not exist for documentation purposes yet.

Common traps:

- `SKIP` is not compatibility.
- A visual score is not standards conformance.
- An example booting is not a platform support claim.
- A benchmark run is not an FPS guarantee.
- QuickJS and V8 do not expose the same host features.
- The HTML default parser delegates tree construction to `package:html`; the
  simplified in-house tokenizer/tree path is still present, but it is not the
  default document path. See [`internals/html-dom-css.md`](internals/html-dom-css.md).

Next: [`guides/embedding.md`](guides/embedding.md).
