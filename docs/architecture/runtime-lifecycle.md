# Runtime lifecycle

A NativaX document is a short-lived session with one document, one style engine,
one JavaScript engine, and one set of bindings. This page follows that session
from creation to disposal. It describes the current implementation, not an
idealized browser lifecycle.

Public entry points:

- `NativaXView` for Flutter apps.
- `NativaXRuntime.create` for direct embedding and tests.
- `NativaXRuntime` itself for post-creation access.

## Creation

```dart
final runtime = await NativaXRuntime.create(
  source: html,
  config: const NativaXRuntimeConfig(),
  documentUrl: 'app://example/index.html',
  forceQuickJs: false,
);
```

`NativaXRuntime.create` wraps `_create`. If creation selected V8 and the V8
startup memory limit was reached, the runtime is disposed and `_create` runs
again with `forceQuickJs: true`. The configured `onDiagnostic` receives a
message. This is a startup-only fallback. After startup, `NativaXView` listens
to `NativaXRuntime.onEngineOverBudget`, marks its local `_forceQuickJs` flag, and
reloads the document on QuickJS.

`forceQuickJs` is a request, not a guarantee that the host supplied a working
QuickJS native build. A build failure is an error.

## Ordered startup

`NativaXRuntime._create` performs the following steps in order. The order
matters for page semantics.

### 1. URL and environment

The runtime resolves the document URL (default `app://local/index.html`), builds
a `FlutterHostEnvironment` when used through `NativaXView`, and attaches storage,
device pixel ratio, theme, and platform services.

### 2. Parse the document

`HtmlParser.parseDocument` returns a `nativa_dom.Document` plus recoverable
parse errors. The default path delegates tree construction to `package:html`;
the in-house simplified parser is used only when a non-default `maxDepth` is
requested. Parse errors are exposed as `runtime.parseErrors` and reported to
`onDiagnostic` where appropriate.

Hard parser limits throw `HtmlLimitException` (for example input over 4 MiB or
more than 100,000 nodes). Recoverable tree errors are collected and do not abort
the page.

### 3. Build the style engine

A `nativa_css.StyleEngine` is created from the document. The runtime parses:

- `<style>` elements, in document order;
- `<link rel="stylesheet">` elements whose resource is returned by
  `NativaXRuntimeConfig.resources`.

Disabled style elements/links are skipped. A denied or failed stylesheet is a
diagnostic, not a fatal error. The parsed sheets become `styleEngine.authorSheets`.

### 4. Load fonts

`@font-face` declarations are registered before scripts run. The runtime scans
the parsed author sheets for used font families and asks the host resource
loader for the font bytes. Font decoding/registration is implemented by
`nativa_render`'s font runtime. A missing font is a diagnostic; text falls back
to another font.

### 5. Select the JavaScript engine

If `config.engineFactory` is supplied, it creates the engine. Otherwise:

- a page with `<script type="module">` uses `QuickJsEngine`, because the V8
  backend has no ES-module support;
- `forceQuickJs: true` uses `QuickJsEngine`;
- otherwise `createDefaultJavaScriptEngine(config.engine)` applies the desktop
  V8 rules, mobile QuickJS rule, and `NATIVAX_ENGINE` override.

The exact matrix is in [`javascript-engines.md`](javascript-engines.md).

### 6. Install host services and bindings

The runtime creates:

- a `TimerHost` with the configured timer limits;
- `console` (a no-op sink when no `onConsole` is configured);
- the document listener-error hook;
- navigation and submit hooks;
- a `LocalResourceNetwork` that maps same-origin URLs to the host resource
  loader and applies the configured network policy to external requests;
- a worker launcher (isolate-backed by default, in-process when
  `threadedWorkers: false`);
- a `DomBindings` instance, which installs the window/document/DOM/web APIs;
- the module host (`DocumentModules`).

`bindings.install()` runs before any page script. `bindings.harden()` removes
the raw host bridge from script globals before user code executes. Preludes that
need the raw bridge must run earlier; this ordering is deliberate.

### 7. Run classic scripts

Classic `<script>` elements are visited in document order:

- `src` scripts are loaded through `NativaXRuntimeConfig.resources` and evaluated
  with the `src` as filename;
- inline scripts are evaluated with filename `<script>`;
- unsupported `type` values are skipped;
- a denied/missing script produces a diagnostic and is skipped;
- an evaluation error is reported through `onScriptError` and the document
  continues, matching browser behavior more closely than a fatal abort.

Scripts run synchronously during runtime creation. A script that schedules a
timer leaves that timer for the later event loop; the runtime does not pump
timers while it is still creating the page.

### 8. Run module scripts

Module scripts are deferred until after classic scripts, in document order.
The runtime prefetches the module graph through `DocumentModules`, resolves
imports relative to the document URL, and calls `engine.evaluateModule`. Inline
modules use the document URL as `import.meta.url`.

The default QuickJS path supports modules. V8 does not. A page with a module
script therefore never selects V8 through the default path; an explicit
`engineFactory: V8Engine.new` on a module page will fail at module execution.

### 9. Fire document lifecycle events

After scripts, the runtime sets ready state and dispatches, in order:

1. `readystatechange` (`interactive`);
2. `DOMContentLoaded` (bubbling, trusted);
3. `readystatechange` (`complete`);
4. `load` on the window;
5. `pageshow` on the window.

These are Dart-created DOM events dispatched through the installed bindings.
They are not browser-native events.

### 10. Return the runtime

The runtime exposes:

- `document`, `styleEngine`, `engine`, `bindings`, `timers`, `config`;
- `parseErrors` and `scriptErrors`;
- `engineName` (`v8`, `quickjs`, or a custom engine type name);
- `onEngineOverBudget` for post-startup V8 memory stops;
- `dispose()`.

## Flutter view lifecycle

`NativaXView` is a `StatefulWidget`.

| Event | Behavior |
|---|---|
| `initState` | Creates `FlutterHostEnvironment`, starts async load |
| `didChangeDependencies` | Updates theme/DPR/media information from Flutter context; notifies the runtime environment |
| `didUpdateWidget` with a new `source` identity | Disposes the old runtime and reloads |
| `didUpdateWidget` with only a new `config` | **Does not reload**; the existing runtime keeps its old config |
| `dispose` | Increments generation, disposes the runtime |
| V8 over budget | Sets sticky `_forceQuickJs`, disposes, reloads |
| Async load finishes after dispose/reload | Disposes the newly created runtime and discards it |

The `_generation` counter prevents a late async load from replacing a newer
one. `onRuntimeReady` is called only for the runtime that actually became
current.

`NativaXView` builds a loading spinner until the runtime is ready and an error
message if creation throws. It does not expose a retry button; recreating the
widget or changing the source triggers a new load.

## Mutation and event loop

After creation, the runtime is driven by:

- Flutter input converted into DOM events by the renderer;
- timers and microtasks in the JavaScript engine;
- host callbacks (storage, clipboard, alerts, theme);
- resource/module completion for asynchronous network or worker messages;
- view lifecycle changes.

Each engine entry has an execution budget (default 10 s). A timeout raises an
error through the engine and the host error callback. The runtime does not run a
separate OS thread for the page event loop; it uses the isolate that created it.

See [`javascript-engines.md`](javascript-engines.md) and
[`workers-and-resources.md`](workers-and-resources.md).

## Disposal

`dispose()` is intended to be idempotent. It disposes timers, bindings, workers,
and the JavaScript engine, and releases the document/style graph. A runtime must
not be used after disposal. Hosts that create a `NativaXRuntime` directly are
responsible for calling `dispose()`; `NativaXView` does it on unmount and reload.

Known lifecycle limits:

- The page isolate is the UI isolate unless workers are threaded.
- A custom `PlatformServices` or `NativaXNetwork` implementation can retain
  resources after runtime disposal; the runtime cannot prove it released them.
- No long-running create/destroy soak is recorded for every platform.

## Related

- [`rendering.md`](rendering.md)
- [`../guides/embedding.md`](../guides/embedding.md)
- [`../reference/configuration.md`](../reference/configuration.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)
