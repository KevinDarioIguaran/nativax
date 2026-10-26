# Web Challenge example

A realistic HTML/CSS/JavaScript page hosted by a Flutter app and rendered by
NativaX. It does not use a WebView, embedded browser, or local HTTP server.

## Layout

- `assets/index.html`: the challenge page;
- `assets/styles.css`: page styles;
- `assets/app.js`: page logic and live API probes;
- `lib/main.dart`: Flutter host, asset loader, image resolver, and network
  policy;
- `test/`: boot and interaction widget tests.

## Run

```bash
cd examples/web-challenge
flutter run -d linux
flutter test
```

Build:

```bash
cd examples/web-challenge
flutter build linux
./build/linux/x64/release/bundle/nativax_web_challenge_example
```

The host reads from Flutter assets by default. Setting `NATIVAX_PERF_PAGE` to a
directory makes it read that directory through `dart:io`; this is a
performance-suite hook, not a public runtime mode.

## Scope

The page exercises layout, text, navigation, forms, events, lists, tabs,
counters, theme/language switching, `localStorage`, `matchMedia`, timers, URL
handling, `<dialog>`, Canvas 2D, `MutationObserver`, `FormData`, and live
probes for network, WebSocket, video, and audio behavior. The probe panel marks
an API as unsupported or blocked instead of pretending it works.

The host supplies:

- `documentUrl = app://web-challenge/index.html`;
- an asset loader that denies `http(s)` resources;
- an `IoNetwork` allow-list for `jsonplaceholder.typicode.com`,
  `ws.postman-echo.com`, `picsum.photos`, `fastly.picsum.photos`, and
  `interactive-examples.mdn.mozilla.net`;
- an HTTPS image resolver limited to the same allowed hosts.

Everything else is denied. The allow-list is a demo policy, not a general
proxy or a CORS/cookie/certificate implementation.

## Limitations

- Video/audio elements reserve space and report a media error; NativaX does not
  decode or play media.
- `<canvas>` is the implemented 2D subset, not WebGL. Pixel reads and
  `toDataURL` are limited (see
  [`../../docs/javascript-supported.md`](../../docs/javascript-supported.md)).
- `fetch`/XHR/WebSocket only work for allow-listed hosts. A blocked request is
  a script-visible failure.
- `confirm()`/`prompt()` are not blocking browser dialogs; the page uses a DOM
  `<dialog>` and non-blocking alerts.
- Remote content depends on the allow-list and network availability; the
  example is not a smoke test for arbitrary sites.
- A successful boot is not a conformance result.

## Rules

Do not add a WebView or a general fetch proxy to make the demo pass. If an API
is not implemented, report it as unsupported or extend the owned runtime with
tests.
