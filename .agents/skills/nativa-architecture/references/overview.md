# Architecture

## Layers

```text
HTML source ──► nativa_html ──► nativa_dom ──► nativa_css
                                      │              │
                                      ▼              ▼
                                  nativa_render (layout + paint)
                                      │
                                      ▼
                                  Flutter widgets/RenderObjects

JavaScript (QuickJS-ng) ──► C bridge (JSON) ──► nativa_dom_bindings ──► DOM
```

Flutter provides the canvas, gestures, focus, accessibility, and platform
integration. It does not provide an HTML/CSS/JS engine or a WebView.

## Packages

| Package | Responsibility | Must not do |
|---|---|---|
| `nativa_js` | QuickJS-ng, FFI, timers, WebAssembly bridge, limits, WebGL bridge | Know the DOM or Flutter |
| `nativa_dom` | Tree, events, selectors, mutations, forms | Parse HTML/CSS or paint |
| `nativa_html` | Tokenizer and HTML tree builder | Execute scripts |
| `nativa_css` | Tokenizer/parser, cascade, media queries, computed styles | Layout |
| `nativa_dom_bindings` | JavaScript prelude, host functions, browser APIs | Depend on Flutter |
| `nativa_render` | CSS layout and Flutter rendering | Execute JavaScript |
| `nativax` | Public runtime, `NativaXView`, Flutter environment | Duplicate layer logic |

**NativaWeb** is the family formed by `nativa_html`, `nativa_dom`, `nativa_css`,
and `nativa_dom_bindings`. It is intentionally not a single umbrella package:
each module has its own API, tests, and dependency boundary.

## JS ↔ Dart bridge

- `src/nativax_bridge.c` exposes only pointers, scalars, and UTF-8 JSON buffers.
- `QuickJsEngine` registers a `NativeCallable.isolateLocal`; scripts call
  `__nx.host(name, ...args)` and receive JSON.
- Host errors travel as `{error:{type,message}}` and become real JavaScript
  exceptions.
- The engine lives in the isolate that created it. JavaScript runs on the UI
  thread with a time budget, not in parallel.

## Layout

- `CssBoxSpec` + `RenderCssBox`: box, padding, border, background, radii, clip.
- `CssItemParentData`: margins, auto sizing, flex, and the containing block that
  the parent reports to the child for percentage resolution.
- `RenderCssBlock`: normal vertical flow and margin collapsing between siblings.
- `RenderCssFlex`: flex algorithm with `grow/shrink`, `wrap`, `gap`, `justify`,
  `align`, auto margins, and min-size freezing.
- `style_mapping.dart`: `ComputedStyle` → `TextStyle`, `CssBoxSpec`, font
  families, `white-space`, and `text-transform`.
- Positioning: `absolute` children in a parent `Stack`; `relative` with
  `Transform.translate`; lists with a marker in a 24 px column; `auto/scroll`
  overflow with `SingleChildScrollView`.

## Renderer

`NativaXDocumentView` listens for mutations, batches them in a microtask,
recomputes styles, and rebuilds the tree. The initial version performs a global
revision; per-owner optimization (one `ValueNotifier` per subtree) is the next
step.

## Recorded decisions

- Vendor QuickJS-ng instead of `flutter_js`/`flutter_qjs` (abandoned, different
  engines per platform).
- Use Pub workspaces instead of melos.
- No pure layout package: geometry lives in `RenderObject`s.
- In-house parsers, not regex.
