# Forms and navigation

NativaX implements forms and links as DOM APIs. It does **not** own an app
navigation stack, a network form submission, or a file picker. The host receives
events and decides what happens.

## Forms in HTML

```html
<form id="login">
  <label>Email <input name="email" type="email" required></label>
  <label>Password <input name="password" type="password" required></label>
  <button type="submit">Sign in</button>
</form>

<script>
  const form = document.getElementById('login');
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const data = new FormData(form);
    nativax.invoke('login', {
      email: data.get('email'),
      password: data.get('password'),
    });
  });
</script>
```

The page can use `FormData`, `checkValidity()`, `reportValidity()`,
`requestSubmit()`, and constraint validation attributes. The exact implemented
subset is defined by `nativa_dom` and the web prelude. File inputs render a
button but do not open a file picker.

## Submission defaults

- `form.submit()` calls the runtime's form path without firing the `submit`
  event, like the DOM method.
- `requestSubmit()` validates and fires `submit`.
- If the event is not canceled, `document.onSubmit` / the host's `onSubmit`
  callback runs.
- If no host callback is configured, NativaX does not navigate anywhere or make
  an HTTP request. The form action is not a hidden web request.
- `preventDefault()` stops the host callback.

If you want a real submission, implement it in the host callback, validate and
serialize the fields yourself, and use your app's network layer. Do not assume
`action`/`method` are honored by a browser backend.

## Validation

Supported native validation state includes `required`, `pattern`, `min`, `max`,
`step`, `minlength`, `maxlength`, `type=email/url/number/...`, and custom error
messages. `checkValidity()` dispatches `invalid` when false; `reportValidity()`
also reports to the host/UI. `:valid`/`:invalid`/`:user-valid`/`:user-invalid`
are styled by the CSS engine.

The UI shows browser-like error bubbles? NativaX does not reproduce every
browser validation bubble. It reports validity and may use native Flutter
controls; treat the visual validation UI as approximate.

## Links and navigation

NativaX never navigates itself. A same-document fragment link scrolls to the
target and updates the URL/hash. For a normal link:

- `document.onNavigate` receives `(href, anchor)`.
- If the host installs `NativaXRuntimeConfig.onNavigate`, it receives the href and
  DOM anchor.
- External URLs may be offered to `PlatformServices.openUrl`; if absent, the
  default view reports a diagnostic.
- A `javascript:` URL is not automatically executed as a trusted action; validate
  it like any script-provided string.

Do not map `onNavigate` directly to `Navigator.push(Uri.parse(href))` without
validating schemes, origins, and app routes. A page can generate arbitrary hrefs.

## Dialogs and host services

| API | Behavior |
|---|---|
| `alert(message)` | Non-blocking host callback; default view shows a snack bar |
| `confirm(message)` | Shows the alert and returns `false`; it is not a blocking browser confirm |
| `prompt(message, default)` | Shows the alert and returns `null` |
| `print()` | No-op |
| `window.open(...)` | Returns null; no new window/document |
| `dialog.showModal()` | Implemented dialog layer with backdrop/Escape behavior |
| `navigator.clipboard` | Through `PlatformServices`; unavailable if not supplied |
| `navigator.vibrate` | Through `PlatformServices`; returns false if unavailable |

`confirm`/`prompt` are intentionally not silently “successful”: they cannot be
implemented synchronously without blocking the UI isolate and do not have a host
contract for a modal result. If an app needs them, add an async app handler and
change the page API; do not fake a browser dialog.

`PlatformServices` also exposes `openUrl(Uri)` for external links. The host must
validate the URI and decide whether to hand it to the OS.

## History

The bindings keep a small in-memory history:

- `pushState`/`replaceState` update the document URL and history list;
- `popstate`/`hashchange` are dispatched on history/fragment changes;
- `history.back()`/`forward()` are implemented in that in-memory list;
- `location.reload()` reloads via the host hook where available; otherwise it is
  a no-op/diagnostic;
- there is no real browser session history across app routes.

Do not rely on history for app navigation. Use the host's router.

## Dialogs and focus

`<dialog>` supports `show()`, `showModal()`, `close()`, the top layer, backdrop,
Escape, and focus movement. A modal dialog prevents interaction behind it through
the renderer's hit testing. This is a DOM-rendered dialog, not an OS window.

## File inputs and media

- `<input type=file>` is a button; there is no file picker and no `File` from the
  user's filesystem in the current default UI.
- `<video>`/`<audio>` are space placeholders; no playback.
- `<iframe>` is a placeholder; no nested document.
- `<canvas>` is real 2D canvas (bounded subset); `<canvas>` does not imply media
  or WebGL.

## Host pattern

```dart
NativaXView(
  source: html,
  config: NativaXRuntimeConfig(
    onNavigate: (href, anchor) {
      final uri = Uri.tryParse(href);
      if (uri == null) return;
      if (uri.scheme == 'app') myRouter.go(uri.path);
    },
    onSubmit: (form) {
      final data = readForm(form); // host-defined; never trust blindly
      myApi.submit(data);
    },
    services: PlatformServices(
      openUrl: (uri) {
        if (uri.scheme == 'https') launchExternal(uri);
      },
    ),
  ),
)
```

`PlatformServices` is exported from `package:nativa_dom_bindings`, not the
`nativax` barrel.

## Tests

- `packages/nativa_dom/test/dom_test.dart` (form/validation parts)
- `packages/nativa_dom_bindings/test/web_platform_test.dart`
- `packages/nativa_render/test/` for controls and dialogs
- `examples/web-challenge` for a real form flow

## Known gaps

- No file picker.
- No media playback.
- `confirm`/`prompt` are not blocking dialogs.
- No cross-document navigation.
- Validation UI is not browser-identical.
- History is in-memory and app-independent.
- A form's `action`/`method` is not a hidden network request.

## Related

- [`embedding.md`](embedding.md)
- [`../javascript-supported.md`](../javascript-supported.md)
- [`../css-supported.md`](../css-supported.md)
- [`../security/threat-model.md`](../security/threat-model.md)
