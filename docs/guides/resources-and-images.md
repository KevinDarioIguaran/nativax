# Resources, images, fonts, and networking

This guide is the practical contract for making a page's assets work without
opening a browser hole. The short rule: **the host decides what exists.** NativaX
does not fetch images, styles, fonts, scripts, modules, or network data on its
own.

## Three separate policies

| Policy | Type | Covers | Default |
|---|---|---|---|
| Own-document files | `NativaXResourceLoader` | scripts, linked CSS, modules, fonts, worker scripts, same-origin fetch/wasm | deny all |
| External network | `NativaXNetwork` | cross-origin fetch/XHR/WebSocket | deny all |
| Images | `NativaXImageResolver` | `img`/image painting | no image |

Do not collapse them into one filesystem callback unless your app genuinely
wants that policy. Keeping them separate is why same-origin wasm can work while
internet access is denied.

## Resource loader

```dart
final resources = NativaXAssetLoader(root: 'assets/www/');
```

Use it for a page bundled in Flutter assets. The loader:

- strips query/fragment for the asset key;
- rejects `://` and `//` (cross-origin) URLs;
- rejects `..` path segments;
- maps `/app.js` to `assets/www/app.js` (or the configured root).

`NativaXDirectoryLoader('path/to/site')` serves desktop/dev files. It applies the
same `..` and cross-origin checks. The directory root itself must be narrow; a
loader is not a sandbox.

For a custom source (database, encrypted bundle, generated content):

```dart
class MyLoader extends NativaXResourceLoader {
  @override
  Future<String?> load(String url) async {
    final bytes = await loadBytes(url);
    return bytes == null ? null : utf8.decode(bytes);
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    // Resolve only your app's known resources. Return null for everything else.
    return myStore.read(url);
  }
}
```

The default `loadBytes` UTF-8-encodes `load`, which corrupts binary wasm/fonts.
Override `loadBytes` for binary assets.

## Images

Images never go through the resource loader implicitly. Supply a resolver:

```dart
ImageProvider? resolveImage(nativa_dom.Element element, String src) {
  if (src.startsWith('asset:')) {
    return AssetImage(src.substring(6));
  }
  if (src.startsWith('memory:')) {
    return MemoryImage(myBytes[src]!);
  }
  return null;
}

NativaXView(
  source: html,
  imageResolver: resolveImage,
  config: NativaXRuntimeConfig(
    resources: NativaXAssetLoader(root: 'assets/www/'),
  ),
)
```

The renderer applies `object-fit`, `alt`, borders, and clipping. A null result
shows a broken-image placeholder and emits a renderer diagnostic. `Image.network`
inside the resolver is a host decision; NativaX itself does not perform it.

## Fonts

`@font-face` is supported:

```css
@font-face {
  font-family: "App Sans";
  src: url("fonts/app-sans.woff2") format("woff2"),
       url("fonts/app-sans.ttf") format("truetype");
  font-weight: 400;
  font-style: normal;
}
body { font-family: "App Sans", sans-serif; }
```

The runtime:

- parses `@font-face` descriptors (`font-family`, `src`, `font-weight`,
  `font-style`, `font-display`);
- resolves URLs against the stylesheet's base URL;
- loads bytes through `NativaXResourceLoader.loadBytes`;
- registers SFNT (TTF/OTF) fonts with Flutter;
- probes for a sibling `.ttf`/`.otf` when a stylesheet only lists `.woff`/`.woff2`,
  because Flutter's `FontLoader` does not accept WOFF containers directly;
- falls back to another font if nothing usable loads.

A missing/denied font is not fatal. If you need exact font rendering, ship SFNT
files and test them on the target platform.

## Network

The default `DeniedNetwork` makes `fetch`, XHR, and WebSocket fail. To allow a
specific API:

```dart
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';

final network = IoNetwork(
  allow: (uri) =>
      uri.scheme == 'https' &&
      uri.host == 'api.example.com' &&
      uri.path.startsWith('/v1/'),
  maxResponseBytes: 8 * 1024 * 1024,
);

NativaXView(
  source: html,
  config: NativaXRuntimeConfig(
    resources: const NativaXAssetLoader(root: 'assets/www/'),
    network: network,
  ),
)
```

`IoNetwork` uses `HttpClient` and follows redirects. It does not implement CORS,
cookies, certificate pinning, proxy auth, or a redirect re-check. For those,
implement `NativaXNetwork` and enforce policy before/after redirects. A denied
request is a script-visible failure, not a silent empty response.

`LocalResourceNetwork` serves a same-origin GET/HEAD from the resource loader
when the loader returns bytes. If the loader returns null, it falls back to the
configured network; if that network also fails, the page sees a synthetic 404.
`/api/` paths and non-GET/HEAD requests always go to the network policy. This is
how a page can load its wasm model with `fetch('model.wasm')` while external
networking is denied. It is host routing, not the browser same-origin policy,
and the configured `NativaXNetwork` still decides whether the fallback is
allowed.

## Workers and modules

- Worker scripts/modules use the resource loader; worker fetch uses the shared
  network policy.
- Module imports resolve relative to the document/importing module.
- Bare npm specifiers are not resolved; bundle or use a custom module host.
- Workers are QuickJS, including when the page is V8.
- `threadedWorkers: false` runs workers in the page isolate for debugging.

See [`../architecture/workers-and-resources.md`](../architecture/workers-and-resources.md).

## Security checklist

1. Start with deny-all; add one resource/network rule at a time.
2. Keep the loader root narrow; never serve arbitrary absolute paths.
3. Validate image URLs in the resolver; do not blindly call `Image.network`.
4. Treat `documentUrl` and `location` as untrusted when a page controls them.
5. Never add a filesystem/process host handler for convenience.
6. Do not use `IoNetwork` as the only sandbox for hostile content.
7. Test denied cases, not only happy paths.
8. For adversarial pages, run in a separate OS process/sandbox and prefer
   QuickJS until V8 enforces time/job limits.

## Tests

- `packages/nativax/test/runtime_test.dart` (resource loading)
- `packages/nativa_dom_bindings/test/web_platform_test.dart` (fetch/storage)
- `packages/nativa_render/test/background_image_test.dart`
- `packages/nativa_render/test/font_mapping_test.dart`
- `packages/nativa_render/test/broken_image_size_test.dart`
- security suite (`debug/engines/security`) for network/resource policy

## Related

- [`embedding.md`](embedding.md)
- [`../architecture/workers-and-resources.md`](../architecture/workers-and-resources.md)
- [`../security/threat-model.md`](../security/threat-model.md)
- [`../reference/configuration.md`](../reference/configuration.md)
