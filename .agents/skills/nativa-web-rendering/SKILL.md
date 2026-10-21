---
name: nativa-web-rendering
description: Use when changing HTML, DOM, CSS, layout, or painting, or when reviewing a change for WebView, Chromium, or browser-engine shortcuts.
---

# Nativa web rendering

Read `references/rendering.md` before touching the render path. It contains the
real HTML → DOM → CSS → Flutter chain, absolute prohibitions, invariants, and
verification commands.

## Required checks

1. Confirm the implementation belongs to the owned runtime chain:
   `nativa_html` → `nativa_dom` → `nativa_css` → `nativa_render`.
2. Confirm there is no `WebView`, `webview_flutter`, `flutter_inappwebview`,
   `HtmlElementView`, Chromium, CEF, Electron, or local UI server.
3. Confirm scripts see only ids, scalars, and JSON; never Dart objects.
4. Confirm `innerHTML` and `insertAdjacentHTML` do not execute scripts.
5. Confirm external resources are authorized by the host loader and denied by
   default.
6. If a feature is missing, declare it. Do not activate a browser fallback.

## Verification

```bash
grep -R "webview\|InAppWebView\|HtmlElementView\|CEF\|Chromium" \
  packages tools examples/web-challenge examples/game-player pubspec.yaml
(cd packages/nativa_render && flutter test)
(cd packages/nativax && flutter test)
./tools/test_all.sh
```

Add an end-to-end HTML → DOM → CSS → Flutter test when behavior changes. Report
what is still outside the documented subset.
