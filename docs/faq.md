# FAQ

Answers are scoped to the current implementation. If an answer would require an
unmeasured claim, it says so.

## Is NativaX a browser?

No. It is a Flutter UI runtime that interprets a documented subset of
HTML/CSS/JavaScript and paints with Flutter render objects. It does not embed
Chromium/WebKit, use a WebView, or serve the page over HTTP.

## Can I load any website?

No. Loading a site requires HTML/CSS/JS support that site uses, correct
resources, network policy, and often APIs/protocols NativaX does not implement.
There is no compatibility guarantee per site. Use the support pages and run the
page through the visual/audit suites before claiming it works.

## Can I use React, Vue, or another framework?

Some framework output may run, but there is no framework integration or
guarantee. A framework needs its runtime, module/bundling strategy, DOM APIs,
and often events/timers to match. Test the built bundle on the engine and
platform you ship; do not assume a browser tutorial applies.

## Why is visual fidelity only ~53 %?

The 51-page baseline compares NativaX to Chromium with a strict weighted judge:
position, layout, color, design, and pixel differences. The low mean is dominated
by layout/position errors; it is not a percentage of CSS features supported.
Many pages are marked FAIL for strict thresholds even when they render. Use the
per-page element/position data to find a specific cause.

## Why does a page use QuickJS instead of V8?

By design: modules force QuickJS; mobile targets use QuickJS; workers are
QuickJS; `NATIVAX_ENGINE=quickjs`/`forceQuickJs` force it; V8 may be missing or
already live; and a prior V8 heap stop makes the view sticky on QuickJS. See
[`architecture/javascript-engines.md`](architecture/javascript-engines.md).

## Why does V8 not support modules/WebGL/WebAssembly/SharedArrayBuffer?

The current V8 Rust bridge implements classic script evaluation and the host
call/buffer path, not those integrations. It does not have `evaluateModule`, and
its prelude sets `__nx_gl_native`/`__nx_sab_*` to null. Use QuickJS when you need
those features. Do not document a V8 feature that has no source/test.

## Why is my V8 test skipped?

`packages/nativa_js/test/v8_engine_test.dart` and `v8_smoke_test.dart` skip
without `NATIVAX_V8_LIB` (and the V8 symbols). A skip is not coverage. Build the
cdylib, set the variable, and rerun; report the actual output.

## Why is `./tools/test_all.sh` unreliable?

`packages/nativax/test/game_play_test.dart` is flaky. Repeated runs on
2026-10-26 produced both `exit 0` and
`TestDeviceException(Shell subprocess crashed with SIGABRT (-6))`; the final
validation run failed. The failure is pre-existing and not caused by the
documentation changes. Do not report the suite as green. Save the full output and
environment when it fails; root cause is not established. See
[`testing.md`](testing.md).

## Can I use `fetch`, XHR, or WebSocket?

Only through a host `NativaXNetwork`. The default `DeniedNetwork` fails them.
`IoNetwork` is a convenience with an allow callback and a body limit; it is not
CORS/cookie/certificate-pinning infrastructure. Same-origin paths may route to
the resource loader first.

## Why is my image broken?

`img` is not fetched automatically. Provide `NativaXImageResolver`; return a
Flutter `ImageProvider` or null. `NativaXResourceLoader` is a separate contract
for scripts/CSS/fonts/workers. See
[`guides/resources-and-images.md`](guides/resources-and-images.md).

## Why does `confirm()` always return false?

Because a blocking browser confirm cannot be implemented synchronously on the
Flutter UI isolate with the current host contract. `alert()` is a non-blocking
host callback; `confirm`/`prompt` show the alert-style path and return false/null.
Add an async app handler if you need a real dialog, or use a DOM `<dialog>` with
an explicit UI flow. Faking success would be worse.

## Why does a form not submit to `action`?

NativaX does not own HTTP form submission or navigation. `onSubmit` gives the
host the form; the host validates, serializes, and sends it. `form.submit()` is
the DOM method (no submit event); `requestSubmit()` validates and fires `submit`.

## Can I use file inputs?

No usable file picker exists in the default UI. `<input type=file>` renders a
control but does not expose the user's filesystem. Do not claim file upload
support.

## Can I use `<video>`, `<audio>`, or `<iframe>`?

They are space placeholders. There is no media decoder/playback or nested
document. Use a Flutter media widget outside NativaX if that is what you need.

## Does CSS `@font-face` work?

Yes for SFNT TTF/OTF loaded through the resource loader's `loadBytes`, with
fallback. WOFF/WOFF2 containers are not directly accepted by Flutter's loader;
the runtime probes for a sibling `.ttf`/`.otf` when listed. Test the actual fonts
on the target platform.

## Why do DOM geometry queries look stale or approximate?

The renderer computes layout on frames. A query immediately after a mutation may
see the previous layout, and virtualized offscreen elements report estimated
geometry until materialized. `scrollIntoView` may force a frame. This is not a
synchronous browser layout engine.

## What is virtualized, and can I turn it off?

Large block/flex/grid containers (at least 24 child slots) may build only the
viewport plus overscan. `data-nativa-virtual="false"` or
`data-nv-virtual="false"` opts out for pages that need exact geometry everywhere.
Virtualization is why some offscreen DOM elements have no render object.

## Is NativaX secure enough for hostile content?

Not as an OS sandbox. It has in-process limits and a security suite, but native
bugs, host callbacks, and V8's missing time/job enforcement mean a determined
attacker may compromise the process. Run hostile content in a separate
OS-sandboxed process and keep network/resource policy narrow. See
[`security/threat-model.md`](security/threat-model.md).

## Can I add a WebView for one unsupported feature?

No. That violates the product boundary and is not an acceptable compatibility
fix. Implement the feature in the owned chain or document it as unsupported.

## How do I improve compatibility?

Pick a measured gap, write a focused test/regression, implement the smallest
correct behavior, run the relevant conformance suite, and record the delta. Do
not mix incremental compatibility gains with architecture refactors. A harness
adapter correction is not a product gain.

## How do I report progress without fabricating numbers?

Use a run id/manifest, command, date, commit, platform, engine, and actual result.
State skips and unmeasured areas. `progress/reports/*-latest.md` can lag; link the
canonical JSON/JSONL and manifest. Never round a FAIL/SKIP into a pass or quote a
visual score as standards compatibility.

## Where do I start as a contributor?

[`getting-started.md`](getting-started.md), then [`testing.md`](testing.md) and
[`contributing.md`](contributing.md). For architecture changes, load the
`nativa-architecture` skill or read
[`architecture/README.md`](architecture/README.md).

## Why English?

English is the maintained documentation language. Older Spanish pages are
archived under [`archive/legacy-es/`](archive/legacy-es/README.md) with a
replacement map; they are historical evidence, not current guidance.
