# Workers, modules, resources, and networking

NativaX never fetches a resource by itself. The embedder supplies a resource
loader and a network policy, and the runtime applies them consistently to page
scripts, modules, workers, fetch/XHR, fonts, and same-origin wasm/data files.
This page describes those boundaries and the worker model.

## Resource loader

`NativaXResourceLoader` is the host contract for the document's own files:

```dart
abstract class NativaXResourceLoader {
  Future<String?> load(String url);
  Future<Uint8List?> loadBytes(String url); // default: UTF-8 encode(load)
}
```

It is used for:

- `<script src>`;
- `<link rel="stylesheet">`;
- ES-module sources and imports;
- same-origin `fetch()`/XHR (wasm, audio, models, JSON);
- `@font-face` bytes;
- worker scripts and worker module imports;
- worker `fetch()` through the shared network policy.

`url` is the same-origin request key for page resources, or an absolute URL for
another origin. The runtime does not normalize a cross-origin URL into a local
path; the loader should return `null` for anything it does not serve.

Built-ins:

| Loader | Behavior | Safety boundary |
|---|---|---|
| `NativaXDenyAllResources` | Returns `null` for everything | Default; no external files |
| `NativaXAssetLoader` | Reads from a Flutter asset root (`assets/www/` by default) | Rejects cross-origin URLs and `..` path segments |
| `NativaXDirectoryLoader` | Reads from a directory on disk | Rejects cross-origin URLs and `..` path segments |
| Custom | Host-defined | Host must enforce origin/root policy |

`NativaXAssetLoader` needs every asset subdirectory listed in `pubspec.yaml`
under `flutter: assets:`. `NativaXDirectoryLoader` is appropriate for desktop
development or app-controlled content; do not point it at a broad filesystem
root for untrusted pages.

## Network policy

`NativaXNetwork` is the contract for external requests:

```dart
abstract interface class NativaXNetwork {
  Future<NetworkResponse> fetch(NetworkRequest request);
  Future<NetworkSocket> connect(Uri url, List<String> protocols);
}
```

Defaults:

- `DeniedNetwork` fails all fetch/XHR/WebSocket requests as offline.
- `IoNetwork(allow: ...)` permits only `http`/`https` or `ws`/`wss` URLs accepted
  by the host callback and limits response bodies to 32 MiB by default.
- The allow callback sees the final request URI; redirects are followed by
  `dart:io` and the response records the final URL.

`LocalResourceNetwork` sits in front of the configured network: a same-origin
GET/HEAD URL is tried against the `NativaXResourceLoader` first. If the loader
returns bytes, they are served without network access. If it returns null, the
request falls back to the configured network policy; if that fails, the result
is a synthetic 404. `/api/` paths, non-GET/HEAD methods, and cross-origin URLs
go directly to the network policy. This is why a page's own wasm/model files can
work with networking denied, while a missing local asset can still reach a
backend. It is not a same-origin browser security model; it is a host routing
rule. The network policy remains the authority for what is actually allowed.

`IoNetwork` is a convenience, not a complete HTTP security policy. It does not
implement CORS, cookie jars, certificate pinning, proxy policy, or a full
redirect re-check. If you need those, implement `NativaXNetwork` yourself and
enforce them in the app, OS sandbox, or a dedicated process.

## Modules

`DocumentModules` resolves and loads ES modules:

- base URL: the document URL;
- relative imports: resolved against the importing module;
- source: the host resource loader;
- cycles and duplicate URLs: cached in the module graph;
- errors: reported through `onScriptError` / `onDiagnostic`;
- top-level `await`: supported by QuickJS;
- inline modules: use the document URL as `import.meta.url`.

Module scripts are deferred until after classic scripts. V8 does not implement
`evaluateModule`, so a page with a module script is automatically kept on
QuickJS by the default selector. A custom `engineFactory` that returns V8 on a
module page will fail at module execution.

Bare specifiers (for example `import x from 'pkg'`) are not resolved by an npm
resolver. Use relative/absolute URLs or a custom module host if you need a
bundler-style policy.

## Workers

A dedicated worker gets its own JavaScript execution and messaging context.

| Mode | Runtime | Parallel? | Use |
|---|---|---|---|
| `threadedWorkers: true` (default) | `IsolateWorkerLauncher`; each worker is an isolate + QuickJS runtime | Yes, separate OS thread/isolate | Normal page workers |
| `threadedWorkers: false` | `InProcessWorkerLauncher`; worker runs in the page isolate | No | Debugging, constrained hosts |

Worker facts from the current implementation:

- Workers always use QuickJS-ng, even when the page engine is V8.
- Default worker engine config: 1 GiB memory limit, 1 MiB native stack,
  30 s execution budget, 1,000,000 jobs per drain.
- `maxWorkers` defaults to 16 per page launcher. More workers fail with a
  `QuotaExceededError`-style event.
- Worker scripts can be `blob:`/`data:` inline or a resource URL served by the
  loader. Imports and worker fetch use the shared module/network policy.
- Messaging uses the runtime's `RouterMessaging` and ports; `SharedArrayBuffer`
  and `Transferable` byte buffers use native shared memory where supported.
- `postMessage` data is serialized; the bridge does not expose Dart objects.
- Worker errors are reported to the page as error events/messages; a worker does
  not crash the app process by itself, but a native failure can still abort it.

A worker is not a security sandbox. It is an execution/parallelism boundary in
one process. Hostile content still needs OS-level isolation and network policy.

## Storage and services

`NativaXView` supplies an in-memory `MemoryStorage` when no storage is configured.
The default quota is 5 MB of keys plus values. Scripts see `localStorage` and
`sessionStorage` through the bindings; they do not touch Flutter preferences or
files directly.

`PlatformServices` exposes optional host actions:

- clipboard read/write;
- vibration/haptics;
- `alert` (non-blocking; the default view uses a snack bar);
- external URL open;
- theme mode requests.

If a service is omitted, the API reports unavailable or no-ops. It never invents
platform behavior. The host should validate/clipboard-gate input and treat all
script-provided URLs as untrusted.

## Images, fonts, and media

- Images are resolved exclusively through `NativaXImageResolver`. This is a
  separate contract from the resource loader so an embedding app can use cached
  `ImageProvider`s, asset images, or code-generated images.
- `@font-face` source bytes go through the resource loader; decoded fonts are
  registered in the font runtime. A denied font falls back.
- `<video>`, `<audio>`, and `<iframe>` are space placeholders. There is no media
  decoder, playback engine, or nested document.
- Canvas/WebGL are separate native surfaces, not network resources.

## Common mistakes

1. **Adding `webview_flutter` or `HtmlElementView` to make a page render.** This
   violates the product boundary and hides unsupported HTML/CSS.
2. **Passing a broad directory to `NativaXDirectoryLoader` for untrusted
   content.** The `..` check prevents root escape from the request path, but the
   root itself must be narrow.
3. **Using `IoNetwork` as the only sandbox.** It is a host callback plus HTTP
   client, not an OS sandbox or CORS implementation.
4. **Expecting V8 worker parity.** Workers are QuickJS.
5. **Expecting `fetch` to load a same-origin asset when no resource loader is
   configured.** It is denied.
6. **Expecting `img src` to fetch automatically.** It does not; provide an image
   resolver.

## Tests

- `packages/nativax/test/modules_test.dart`
- `packages/nativa_dom_bindings/test/messaging_test.dart`
- `packages/nativax/test/phase2_test.dart` (workers and web APIs; inspect the
  current test names before relying on one)
- `packages/nativa_dom_bindings/test/web_platform_test.dart`
- `packages/nativa_dom_bindings/test/bindings_test.dart`

## Related

- [`runtime-lifecycle.md`](runtime-lifecycle.md)
- [`../guides/resources-and-images.md`](../guides/resources-and-images.md)
- [`../internals/javascript-bridge.md`](../internals/javascript-bridge.md)
- [`../security/threat-model.md`](../security/threat-model.md)
