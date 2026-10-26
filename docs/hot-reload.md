# Document hot reload

`NativaXHotReloadView` is a development tool: it reads an HTML file, renders
it, and re-reads it when the file changes.

```dart
import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      body: NativaXHotReloadView(
        sourcePath: 'dev/ui.html',
      ),
    ),
  ));
}
```

The file may contain HTML, CSS, and JavaScript:

```html
<style>
  body { font-family: sans-serif }
  button { padding: 8px 16px }
</style>
<button id="b">0</button>
<script>
  let n = 0;
  document.getElementById('b').addEventListener('click', () => {
    n += 1;
    document.getElementById('b').textContent = String(n);
  });
</script>
```

## Behavior

- Watches the file's **directory** (editors often save via rename) and filters
  by file name.
- Debounces 80 ms by default so a half-written file is not loaded.
- Re-reads synchronously (development only) and creates a new
  `NativaXRuntime`.
- Keeps the previous runtime if the read fails and reports the error through
  `onError`.
- Accepts `config`, `imageResolver`, `padding`, `debounce`,
  `onBeforeReload`, and `onAfterReload`.

This is a **document hot reload**, not a patch of the JavaScript realm:

- Script variables and state are not preserved.
- Focus, scroll position, and control state are not preserved.
- There is no module HMR.

It is equivalent to a “hot restart” of the document. Store application state
outside the document (for example in the Dart host) and restore it through
`onBeforeReload`/`onAfterReload`.

## Manual control

```dart
final controller = NativaXHotReloadController();

NativaXHotReloadView(
  sourcePath: 'dev/ui.html',
  controller: controller,
);

// From a button or a test:
await controller.reload();
```

The controller exposes `revision`, `isReloading`, and `lastError`. A reload is
a request; the view performs the disk read.

## Limits

- Requires `dart:io`; it is not for Flutter web.
- The watcher depends on the platform filesystem (inotify on Linux). Manual
  reload still works if watching is unsupported.
- Do not use in production; the file is re-read on every change.
- A reload creates a new runtime; in-flight callbacks from the old runtime must
  not be reused.
- This is not Flutter hot reload, and it does not preserve a live page session.

## Related

- [`guides/embedding.md`](guides/embedding.md)
- [`architecture/runtime-lifecycle.md`](architecture/runtime-lifecycle.md)
- [`reference/public-api.md`](reference/public-api.md)
- [`debugging.md`](debugging.md)
