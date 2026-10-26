# JavaScript support

NativaX executes JavaScript on a real engine. It is not a toy interpreter, a
regex rewriter, or a browser text-mode shim. This page covers the engine
contract, the JavaScript-visible web APIs, the event loop, and the deliberate
gaps.

## Engines

| Backend | Where | Modules | WebAssembly | SharedArrayBuffer | WebGL | Time budget |
|---|---|---|---|---|---|---|
| QuickJS-ng | Default on mobile/workers; modules; explicit force | Yes | Yes (wasm3) | Yes | Host bridge (Linux/Android) | Yes |
| V8 | Optional desktop cdylib | **No** | Host bridge absent | **No** | **No** | **Not enforced** |

The default page engine on Linux/macOS/Windows is V8 when `libnx_v8.so` loads,
there is no module script, and no V8 instance is already live. Everything else
uses QuickJS. The full matrix and fallback rules are in
[`architecture/javascript-engines.md`](architecture/javascript-engines.md).

The conformance numbers below are **QuickJS numbers**. V8 has no Test262/WPT
run in this repository. Do not present them as V8 results.

## Language conformance

QuickJS-ng implements modern ECMAScript: variables, functions, classes,
promises/`async`/`await`, generators, `Proxy`, `Reflect`, `BigInt`, `Symbol`,
regular expressions, `Map`/`Set`, modules, and so on.

Recorded Test262 subset (`language/{expressions,statements,types,literals}`):

| PASS | FAIL | SKIP | ERROR | Rate |
|---:|---:|---:|---:|---:|
| 19,577 | 413 | 1,108 | 0 | **97.93 %** |

`SKIP` is excluded. The suite does not run modules or host APIs, and it does not
measure the DOM or rendering. See
[`../progress/conformance.md`](../progress/conformance.md).

Known language caveats:

- Recent proposals and decorators are not guaranteed; check Test262 and the
  vendored engine version before relying on one.
- Tail-call optimization is not implemented; relevant tests are skipped to
  avoid native stack exhaustion.
- Strict-mode edge cases can differ from V8. This is engine-specific; do not
  generalize from one backend.

## Console and timers

```js
console.log('value', {a: 1});
console.warn('warning');
console.error('error');

const id = setTimeout(() => {}, 100);
clearTimeout(id);
setInterval(() => {}, 250);
queueMicrotask(() => {});
```

`ConsoleMessage` is delivered to `NativaXRuntimeConfig.onConsole`; without a
handler, console output is discarded. Timers use Dart timers and do not block
the isolate.

- `setInterval` is clamped to a 4 ms minimum.
- At most 1,000 active timers per runtime; more raises a range error.
- `queueMicrotask` uses the engine's promise-job queue.
- There is no `setImmediate` or `process.nextTick`.

## DOM and web APIs

The bindings expose a substantial browser-like surface. It is a subset, not a
standards-complete DOM.

### Nodes and queries

- `Node`/`Element`/`Document`/`DocumentFragment`, text/comment/doctype nodes.
- `querySelector*`, `getElementsBy*`, `closest`, `matches`.
- `createElement`, `createElementNS`, `createTextNode`, `createDocumentFragment`,
  `cloneNode`, `importNode`, `adoptNode`.
- append/prepend/before/after/replaceWith/remove/replaceChildren and
  `insertAdjacent*`.
- `innerHTML`/`outerHTML` (read/write), `textContent`, `innerText`,
  `attributes`, `classList`, `dataset`, `style`, `compareDocumentPosition`.
- `TreeWalker`, `NodeIterator`, `Range`, basic `Selection`.
- Live wrappers preserve script properties while a node is connected;
  disconnected wrappers are weakly retained and released by a
  `FinalizationRegistry`.
- Common HTML interface classes (`HTMLInputElement`, `HTMLDialogElement`,
  `HTMLCanvasElement`, SVG classes, etc.) exist for `instanceof`.
- `DOMParser` and `XMLSerializer` (subset).
- `customElements`: autonomous elements, `observedAttributes`, and lifecycle
  callbacks.
- Shadow DOM is a **facade** over light DOM: `attachShadow()` and a
  `ShadowRoot` wrapper exist, but there is no CSS scoping, slot distribution, or
  real composed tree.

### Events

Capture/bubble phases, `once`, `signal`, `composedPath`, `preventDefault`,
`stopPropagation`, trusted flags, and `on*` properties/attributes. Event
classes include mouse/pointer/keyboard/focus/input/submit/drag/error/message/
progress/close/hashchange/popstate/transition/animation events.

A listener exception is reported (window `error` path and host
`onScriptError`) and does not stop the page. Synthetic events are untrusted
unless Dart marks them trusted.

### Forms

`form.elements` (including named access and `RadioNodeList`), `FormData`,
`validity`, `checkValidity`, `reportValidity`, `setCustomValidity`,
`validationMessage`, `willValidate`, `requestSubmit`, `reset`,
`valueAsNumber`, `valueAsDate`, selected options, and `labels` are implemented.
File inputs have no picker. See
[`guides/forms-and-navigation.md`](guides/forms-and-navigation.md).

### Geometry, styles, observers

- `getBoundingClientRect`, `offset*`, `client*`, `scroll*`, `scrollIntoView`,
  `elementFromPoint` through the renderer's layout host.
- `getComputedStyle` including pseudo-elements; `CSS.supports`, `CSS.escape`.
- `MutationObserver` (microtask-based), `ResizeObserver`, and
  `IntersectionObserver` (frame polling).
- CSSOM subset: `document.styleSheets`, `CSSStyleSheet`, `CSSStyleRule`,
  `insertRule`/`deleteRule`, `CSSStyleDeclaration`. It is not a full CSSOM.
- Geometry immediately after a mutation can be one frame stale; virtualized
  offscreen elements report estimated geometry.

### Window, navigation, storage

- `location`, fragment navigation/`hashchange`/`:target`, `history`
  (`pushState`, `replaceState`, `back`, `popstate`). History is in-memory; it is
  not the app router and does not span documents.
- `performance.now/mark/measure`, `requestAnimationFrame`,
  `requestIdleCallback`.
- `crypto.getRandomValues` (65,536-byte request cap), `crypto.randomUUID`,
  `TextEncoder`, `TextDecoder`, `atob`, `btoa`, `structuredClone`.
- `localStorage`/`sessionStorage` backed by the host `KeyValueStorage` (memory,
  5 MB default), and an in-memory `indexedDB` with stores, indexes, ranges,
  cursors, and transactions.
- `BroadcastChannel`, `MessageChannel`, `window.postMessage`.
- `screen`, `visualViewport`, `scrollX/Y`, `scrollTo`, `alert` (non-blocking
  snackbar), `confirm`/`prompt` (return `false`/`null`; not blocking dialogs).
- `navigator`: user agent, platform, languages, online, hardware concurrency,
  permissions query, storage estimate, clipboard/vibrate when host services are
  supplied.
- `AudioContext` is a silent graph; `decodeAudioData` rejects with
  `NotSupportedError`. It is not media playback.

### Canvas 2D

Implemented: rectangles, paths (`arc`, `ellipse`, curves, `roundRect`,
`Path2D`), fill/stroke/clip, gradients, shadows, `globalAlpha`, compositing,
transforms, save/restore, line dash, text (`fillText`, `strokeText`,
`measureText`).

Limitations:

- `drawImage` only draws another `<canvas>` element; `<img>`/`ImageBitmap` sources
  are not supported.
- `getImageData` returns an empty `ImageData`; it does not read pixels.
- `putImageData` is implemented.
- `toDataURL` returns `'data:,'` and `toBlob` is not supported.
- `isPointInPath`/`isPointInStroke` always return false.
- Canvas 2D is not WebGL, and WebGL is not 2D canvas.

### WebGL

`canvas.getContext('webgl'|'webgl2'|'experimental-webgl')`,
`OffscreenCanvas`, `ImageBitmap`, `createImageBitmap`, and WebGL 1/2 wrapper
classes exist. The GL bridge is native and only available where the host
provides it (the build includes it on Linux/Android, with a stub elsewhere).
V8 pages have `__nx_gl_native = null`, so WebGL is not available there.

This surface has **no WebGL conformance run** in the repository. It is used by
the game example and covered by targeted tests, not by a browser WebGL suite.
Do not claim browser WebGL compatibility.

### Workers and messaging

Dedicated workers run in their own isolate/thread by default
(`threadedWorkers: true`) with their own QuickJS runtime. `false` runs them in
the UI isolate for debugging. Workers support `postMessage`, `MessagePort`,
`SharedArrayBuffer`/`Atomics`, module workers, `importScripts` in classic
workers, and transferring an `OffscreenCanvas`. At most 16 workers per launcher.
Workers are always QuickJS, even on a V8 page.

### WebAssembly

QuickJS pages install a `WebAssembly` surface over wasm3:

- `Module`, `Instance`, exported `Memory`, `compile`, `instantiate`,
  `instantiateStreaming`, `validate`.
- reusable modules, `(module, name)` imports, `i64` with `BigInt`, live linear
  memory, and a gas budget per call (1,000,000,000 units).
- `Table`/`Global` constructors exist, but imported/exported table/global
  support is incomplete and rejected where unsupported.
- no SIMD (`v128`), wasm threads/atomics, or imported memory in the current
  bridge. Self-contained modules (for example Rapier-style builds without memory
  imports) are the supported path.
- V8 pages do not have this host WebAssembly bridge.

The game example's physics worker is evidence that a real wasm module can run;
it is not a general wasm conformance claim.

## Network

`fetch` (`Request`, `Response`, `Headers`, `AbortController`, text/JSON/Blob/
FormData bodies, `URLSearchParams`), asynchronous `XMLHttpRequest`, and
`WebSocket` all go through `NativaXNetwork`.

- The default `DeniedNetwork` fails them as offline.
- `IoNetwork(allow: ...)` permits real HTTP(S)/WS(S) requests selected by the
  host callback and caps bodies (32 MiB default).
- `data:`/`blob:` URLs work without the network.
- `Blob`, `File`, `FileReader`, `URL.createObjectURL` exist in the engine.
- `IoNetwork` is not CORS/cookies/certificate pinning; implement
  `NativaXNetwork` for a real policy.
- Same-origin paths can route to the resource loader first, then fall back to
  the network policy if the loader returns null. Deny by default.

## Modules

`<script type="module">` is deferred until after classic scripts. QuickJS loads
a prefetched module graph through `DocumentModules`; `import.meta.url` is
available, top-level `await` settles through microtasks, and a literal dynamic
`import('./x.js')` works when the source was prefetched. Bare specifiers fail
with a `TypeError` (no npm resolver). Import attributes/source-phase imports and
runtime-constructed dynamic specifiers are not supported.

V8 has no module evaluator. A module page is forced to QuickJS by the default
selector; a custom V8 factory will fail at module execution.

## Event loop

1. A Dart entry (`evaluate`, timer callback, event callback, worker message)
   runs a script synchronously on the owning isolate.
2. At the end of the entry, the engine drains microtasks (promises,
   `queueMicrotask`).
3. Timers return to the Dart event loop and run as a new entry with their own
   budget.
4. On QuickJS, an entry plus its microtasks that exceeds the execution budget
   raises `JavaScriptTimeoutException`; the runtime default is 10 s. On V8 this
   budget is currently **not enforced**.
5. `requestAnimationFrame` is timer-backed at roughly 60 Hz; it is not a
   guaranteed display-vsync callback.

Consequences:

- A long synchronous loop blocks the Flutter UI.
- Same-deadline timer order follows Dart scheduling, not an exact browser order.
- Host callbacks are not preempted by the QuickJS budget.
- V8 can freeze the UI on an infinite loop until the heap limit terminates it or
  the process is killed.

## Errors and lifecycle

- Script/listener exceptions go to `NativaXRuntimeConfig.onScriptError`; a
  failing script does not cancel subsequent scripts in the normal path.
- Unexpected host exceptions become a generic script `Error`; Dart stack traces
  and paths are not exposed.
- `dispose()` cancels timers/listeners, releases workers, and disposes the
  engine. A disposed runtime must not be used.
- The engine must be used from the isolate that created it. Direct cross-isolate
  use is not supported; workers are the supported parallelism boundary.

## Limits

| Limit | Page default | Worker default | Enforced by |
|---|---:|---:|---|
| JS heap | 64 MiB | 1 GiB | QuickJS allocator / V8 heap callback |
| JS stack | 256 KiB | 1 MiB | QuickJS; V8 ignores the native value |
| Execution budget | 10 s | 30 s | QuickJS only |
| Jobs per drain | 1,000,000 | 1,000,000 | QuickJS only |
| Active timers | 1,000 | n/a | `TimerHost` |
| Timer minimum | 4 ms | n/a | `TimerHost` |
| Workers | 16 | n/a | Worker launcher |
| DOM nodes/depth | 100,000 / 256 | n/a | `nativa_dom` |
| Storage | 5 MB chars | n/a | `MemoryStorage` default |
| Wasm gas/call | 1,000 M | 1,000 M | wasm3 bridge |
| Crypto request | 65,536 bytes | 65,536 bytes | bindings |

Do not quote a single "NativaX JS limit" without the context and engine.

## Explicit gaps

- V8 modules, WebAssembly host integration, SharedArrayBuffer, WebGL, and
  time/job/stack enforcement.
- Shadow DOM CSS scoping/slots and a real composed tree.
- Full CSSOM, Web Animations, and browser layout timing.
- Canvas pixel reads, canvas `toDataURL`/`toBlob`/`drawImage(img)`, and WebGL
  conformance.
- Media decoding/playback and file picking.
- Blocking `confirm`/`prompt`, real `window.open`, cross-document navigation.
- Full `Intl`/ICU and all Unicode locales.
- Import attributes, non-literal dynamic imports, and bare specifiers.
- OS-level sandboxing; the runtime is in-process.

## Evidence and tests

- `packages/nativa_js/test/quickjs_engine_test.dart`
- `packages/nativa_js/test/module_test.dart`
- `packages/nativa_js/test/wasm_test.dart`
- `packages/nativa_js/test/v8_engine_test.dart` (skips without V8)
- `packages/nativa_dom_bindings/test/bindings_test.dart`
- `packages/nativa_dom_bindings/test/web_platform_test.dart`
- `packages/nativa_dom_bindings/test/messaging_test.dart`
- `packages/nativax/test/modules_test.dart`
- `packages/nativax/test/workers_test.dart`
- WPT DOM/events/selectors and Test262 results in
  [`../progress/conformance.md`](../progress/conformance.md)

## Related

- [`architecture/javascript-engines.md`](architecture/javascript-engines.md)
- [`internals/javascript-bridge.md`](internals/javascript-bridge.md)
- [`internals/limits-and-memory.md`](internals/limits-and-memory.md)
- [`guides/resources-and-images.md`](guides/resources-and-images.md)
- [`guides/forms-and-navigation.md`](guides/forms-and-navigation.md)
