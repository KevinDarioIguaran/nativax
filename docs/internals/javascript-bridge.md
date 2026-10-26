# JavaScript bridge internals

The bridge is the security-critical seam between a real JavaScript engine and
Dart. This page describes the current implementation, not an abstract FFI
design.

## Two layers

1. **Engine host bridge** (`nativa_js`): exposes a C function
   (`__nx_host` in QuickJS) to the engine, registers Dart callbacks, converts
   JSON envelopes, and manages engine entry/exit.
2. **DOM/web prelude** (`nativa_dom_bindings`): JavaScript wrappers for nodes,
   events, window, storage, network, canvas, workers, and CSSOM. Wrappers hold
   numeric ids and call the frozen `__nx.host` function.

The prelude is installed once per runtime before page scripts. The raw bridge is
captured and then removed from globals by `nativaxHostPrelude`. The public
runtime then calls `DomBindings.harden()`, which deletes `globalThis.__nx` after
all preludes that need it have closed over `host`.

If deletion fails, `harden()` intentionally keeps the bridge rather than breaking
the page; that is a residual risk to verify in engine-specific tests.

## Call sequence

A script calls a DOM method:

```js
element.textContent = 'hello';
```

The prelude translates it into:

```js
host('node.set_text', id, ['hello'])
```

The host call:

1. JSON-encodes `[name, args]` in JavaScript;
2. enters the engine host callback with the encoded string;
3. Dart looks up the registered `HostFunction` by name;
4. validates argument count/types and resolves node ids to Dart objects;
5. performs the DOM operation;
6. returns a JSON-compatible result or an error envelope;
7. the prelude decodes it, throws a mapped DOM/JS error, or returns the value.

The same path is used for every host operation: query, mutation, event
registration, storage, timers, network, canvas, and workers. There is no direct
Dart object exposure.

## Values and handles

Allowed values:

- `null` / `undefined` (both become `null` in many return paths);
- booleans, numbers, strings;
- lists and maps with JSON-compatible values;
- typed-array bytes through the native buffer path, not JSON numbers;
- integer ids for windows, documents, nodes, events, ports, canvases, and GL
  surfaces.

Wrappers are cached by id. Connected nodes are held strongly; detached ones are
demoted to weak references and released through a `FinalizationRegistry` that
calls `node.release`. This avoids leaking detached wrappers while preserving
identity for connected nodes.

Event callbacks are registered in an engine-private registry (`__nx.register`)
and invoked by id (`__nx_dispatch`, `__nx_eventDone`, `__nx_releaseListener`).
Scripts cannot enumerate or call the registry directly.

## Error mapping

The host returns an envelope shaped like:

```json
{"error": {"type": "HierarchyRequestError", "message": "..."}}
```

or `{"ok": ...}`. The prelude maps known DOM error names to `DOMException` and
other names to `Error`/`TypeError`/`RangeError`/`SyntaxError` where available.
Dart `JavaScriptHostError` types become script-visible errors; unexpected Dart
exceptions become a generic `Error` and are reported to the host error callback.
Do not put secrets or Dart stack traces into host error messages.

## Events

The DOM owns event dispatch, but the engine owns listener functions:

- `addEventListener` sends the target id, type, capture flag, and a callback id
  to Dart;
- Dart stores the callback reference and invokes it with a serialized event;
- propagation, `preventDefault`, `stopPropagation`, and trusted flags are
  decided by `nativa_dom`;
- listener exceptions go to `document.onListenerError` / window listener error
  handler and then `onScriptError`;
- `once`, signal, passive, and options are implemented to the documented subset;
  inspect `bindings_test.dart`/WPT event results for exact gaps.

Synthetic events are untrusted unless Dart marks them trusted. Security tests
check that a programmatic click does not gain trusted privileges.

## Timers and entries

`TimerHost` lives in Dart and calls back into the engine. Each timer callback is
a separate engine entry:

- the callback runs on the UI isolate (unless a worker);
- microtasks are drained after the entry;
- the QuickJS execution budget applies per entry;
- a timer error does not kill the page; it is reported.

The engine's `__nx_dispatch` and `callGlobal` are synchronous. A host callback
that needs asynchronous work must return a promise/port and deliver the result
later through another engine entry; it must not block waiting for a Dart future
inside the UI isolate.

## Native buffers and SharedArrayBuffer

QuickJS uses native buffers for large byte payloads so bytes are not copied
through JSON. The prelude captures `takeBuffer`/`putBuffer` functions; scripts
cannot reach the raw C callbacks after installation. SharedArrayBuffer support
uses `__nx_sab_share`/`__nx_sab_open` and is present on QuickJS; V8 sets both to
null.

V8 also has native buffer callbacks (`nv8_set_buffer_callbacks`) for typed
arrays, but its prelude does not expose SAB or WebGL.

## App handlers

The host can register named handlers:

```dart
NativaXRuntimeConfig(
  appHandlers: {
    'save': (args) => {...},
  },
)
```

Scripts call `nativax.invoke('save', ...)`. Handlers receive JSON-compatible
arguments and must return JSON-compatible values. They are an application API,
not a trusted capability: validate every argument and return value.

## Hardening checklist

1. Install all preludes that need the raw host bridge before `harden()`.
2. Never expose `NativeCallable`, `Pointer`, `DynamicLibrary`, Dart closures, or
   arbitrary objects through a host function.
3. Validate every id against the live registry; never trust a script-supplied id
   as a pointer or array index without bounds checks.
4. Cap string/byte payloads (for example `crypto.getRandomValues` is limited to
   65,536 bytes) and reject invalid counts.
5. Return stable, non-secret error messages.
6. Test `__nx` after hardening; the security suite's
   `bridge.raw_host_hardened` case checks it.
7. Do not add a host function that performs filesystem, process, or unrestricted
   network access just because a page asked for it.

## Known limits

- The bridge is synchronous and runs on the calling isolate; there is no
  preemptive interruption of host Dart callbacks.
- V8 does not enforce the execution budget or job cap; a long V8 host call or
  script can block the UI isolate.
- A custom `JavaScriptEngine` can violate the JSON-only contract; tests and
  review must enforce it at the boundary.
- `FinalizationRegistry` timing is engine/GC-dependent; wrapper release is not a
  deterministic memory guarantee.

## Tests

- `packages/nativa_dom_bindings/test/bindings_test.dart`
- `packages/nativa_dom_bindings/test/web_platform_test.dart`
- `packages/nativa_dom_bindings/test/messaging_test.dart`
- `packages/nativa_js/test/quickjs_engine_test.dart`, `v8_engine_test.dart`
- `debug/engines/security` cases for globals, raw bridge, trusted events,
  reentrancy, and post-dispose calls

## Related

- [`../architecture/javascript-engines.md`](../architecture/javascript-engines.md)
- [`../security/threat-model.md`](../security/threat-model.md)
- [`limits-and-memory.md`](limits-and-memory.md)
- [`../javascript-supported.md`](../javascript-supported.md)
