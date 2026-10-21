# Own rendering: a non-negotiable rule

**NativaX renders its interface through its own runtime.** It is not a browser,
does not embed one, and does not delegate rendering to the web.

## Real chain

```text
HTML ──► nativa_html ──► nativa_dom ──► nativa_css (StyleEngine)
                                             │
                                             ▼
                                  nativa_render (RenderCssBox,
                                  RenderCssBlock, RenderCssFlex)
                                             │
                                             ▼
                                  Flutter widgets / RenderObjects
                                             ▲
JS (QuickJS-ng) ──► nativa_dom_bindings ─────┘
        mutates the DOM; the renderer observes and rebuilds
```

- `nativa_html` parses markup. It does not use the browser parser.
- `nativa_dom` is the real tree; there is no browser DOM behind it.
- `nativa_css` resolves selectors, cascade, and computed styles.
- `nativa_render` measures and paints boxes, blocks, flex, text, and controls.
- `nativa_js` runs QuickJS-ng; `nativa_dom_bindings` exposes the DOM.
- Flutter provides canvas, gestures, focus, accessibility, and platform
  integration. It does **not** provide an HTML/CSS/JS engine or a WebView.

## Absolute prohibitions

1. `webview_flutter`, `flutter_inappwebview`, native WebView, WKWebView,
   Android WebView, CEF, Chromium, Electron, or similar.
2. Loading a URL in an external browser to display the interface.
3. A local HTTP server to serve the UI.
4. Screenshotting HTML as a substitute for an interactive interface.
5. Using Flutter's HTML/CSS engine (`HtmlElementView`, web plugins) as a
   shortcut.
6. Running JavaScript with a toy interpreter or text substitution.
7. Presenting an approximation as native standard rendering.

## Invariants

- Every visible node has an `Element` in `nativa_dom` and a style from
  `nativa_css`.
- Layout is computed in `RenderCss*`; it is not delegated to a browser.
- Scripts see only ids, scalars, and JSON; never Dart objects.
- `innerHTML`/`insertAdjacentHTML` do not execute scripts.
- An external resource loads only if the host authorizes it through
  `NativaXResourceLoader`; the default is deny.
- If a feature is not implemented, it is declared. A WebView is **not**
  activated as a fallback.

## Verification

A contribution that touches rendering must demonstrate:

1. `flutter test` for the renderer and runtime.
2. An end-to-end test HTML → DOM → CSS → Flutter.
3. That no browser/WebView dependency was added.
4. That the behavior is explained by the documented HTML/CSS subset.
5. That no shortcut bypasses the NativaX runtime.

Useful commands:

```bash
grep -R "webview\|InAppWebView\|HtmlElementView\|CEF\|Chromium" \
  packages tools examples/web-challenge examples/game-player pubspec.yaml
(cd packages/nativa_render && flutter test)
(cd packages/nativax && flutter test)
./tools/test_all.sh
```

## Where it is implemented

| Piece | File/package |
|---|---|
| HTML parser | `packages/nativa_html` |
| DOM and events | `packages/nativa_dom` |
| CSS and cascade | `packages/nativa_css` |
| Layout and paint | `packages/nativa_render/lib/src/layout`, `render` |
| Runtime/View | `packages/nativax/lib/src/runtime.dart`, `view.dart` |
| JS and bridge | `packages/nativa_js`, `nativa_dom_bindings` |

This rule overrides any compatibility or performance shortcut.
