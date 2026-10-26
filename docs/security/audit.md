# Security audit

**Snapshot:** 2026-10-26, `HEAD` `f47240e`, Linux x86_64, Dart 3.13.0 (JIT),
QuickJS-ng 0.17.0. Scope: `nativa_js`, `nativa_dom`, `nativa_dom_bindings`,
`nativa_html`, `nativa_css`, and the public runtime.

This is not a declaration that NativaX is “100 % secure” or exploit-proof. It
records the tested cases, the fixes, and the residual risks.

## Suite result

```bash
cd debug/engines/security
dart run bin/security.dart run
```

Latest recorded run `debug/benchmarks/security/20261026T024956Z-f47240e/`:

| PASS | FAIL | SKIP | ERROR | Total |
|---:|---:|---:|---:|---:|
| 44 | 0 | 1 | 0 | 45 |

The SKIP is `platform.flutter_resource_policy`: it needs a Flutter harness and
cannot run in the pure Dart CLI. The run covers QuickJS only; V8 is not part of
this suite.

A PASS means the **specific attack case** did not produce the unauthorized
effect. It does not prove the category is safe.

## Findings

### S-01 — Programmatic click/submit were marked trusted (fixed)

- **Severity:** high if the host trusts `isTrusted` as proof of a user gesture.
- **Cause:** `Element.click()` and `requestSubmit()` always set
  `isTrusted = true`.
- **Reproduction:** a click listener observed `isTrusted == true` after
  `button.click()`.
- **Fix:** `click({bool trusted = false})` and
  `requestSubmit({bool trusted = false})`; the renderer passes `trusted: true`
  only for real host gestures.
- **Regression:** `events.programmatic_click_not_trusted`,
  `events.programmatic_submit_not_trusted`.

### S-02 — Raw `__nx.host` bridge reachable from scripts (fixed in runtime)

- **Severity:** medium.
- **Cause:** the prelude left `__nx.host` on `globalThis`.
- **Impact:** a script could invoke internal operations by name
  (`node.release`, `style.*`, `app.invoke`, etc.). It did not expose the OS, but
  it widened the surface and enabled self-DoS.
- **Fix:** `DomBindings.harden()` removes `__nx` after installing
  timers/console/DOM; preludes keep the reference in closures. `NativaXRuntime`
  calls it before page scripts.
- **Limit:** direct users of `DomBindings` must call `harden()` themselves.
- **Regression:** `bridge.raw_host_hardened`.

### S-03 — Listeners retained after wrapper release (fixed)

- **Severity:** medium (retention/DoS).
- **Cause:** `node.release` removed the target from the map but not its
  listeners.
- **Fix:** release calls `removeAllEventListeners()`.
- **Regression:** `dom.detached_listeners` in the leak suite.

### S-04 — Internal `__nx_*` callbacks visible on `globalThis` (fixed)

- **Severity:** medium.
- **Original evidence:** after `harden()`, `Object.getOwnPropertyNames(globalThis)`
  contained `__nx_dispatch`, `__nx_eventDone`, and `__nx_releaseListener`.
- **Original impact:** a script could forge event callbacks, release listeners
  by id, fire timers early, and with later APIs forge network/WebSocket/worker
  responses.
- **Fix:** the C bridge keeps a private callback registry in `NxRuntime`
  (`__nx_register`, captured and deleted by the host prelude). `callGlobal`
  checks that registry first. `harden()` removes `__nx.register` and
  `__nx.host`.
- **Regression:** `internal.callback_globals` (now verifies no `__nx_*` global
  is reachable/invocable).

### S-09 — Platform APIs added after the first audit

- **Network:** `fetch`, XHR, and WebSocket go through `NativaXNetwork`. The
  default `DeniedNetwork` denies all. `IoNetwork(allow: ...)` requires a host
  allow callback and caps bodies at 32 MiB by default. It is not CORS, cookies,
  certificate pinning, or a redirect re-check.
- **Clipboard/vibration:** require a transient user activation (a trusted
  gesture within the last 5 s).
- **Workers:** each worker is a separate QuickJS engine with its own budget;
  at most 16 per document. Worker load/fetch is subject to the host resource
  and network policy.
- **JS budget:** the runtime default is 10 s per entry (previously 1 s), so real
  pages are not cut off. A long task still blocks the UI; see S-06.
- **Wrapper identity:** connected nodes retain their wrapper; disconnected
  wrappers are released.

### S-05 — `javascript:` navigation reaches the host (open, low)

- **Severity:** low inside NativaX.
- **Evidence:** `xss.javascript_url_not_executed` confirms the code does not
  execute; the `href` string reaches `Document.onNavigate`.
- **Risk:** if the host opens that URL in an external browser/WebView or treats
  it as an app action, it can introduce XSS outside NativaX.
- **Remediation:** validate schemes/destinations in `onNavigate`; add a default
  URL policy in a later phase.

### S-06 — JS budget does not interrupt Dart host work (residual)

- **Severity:** medium (DoS).
- **Cause:** the QuickJS timeout interrupts bytecode, not a synchronous host
  function doing heavy Dart work (for example a huge `innerHTML` or
  `app.invoke`).
- **Current mitigation:** input/node limits and host responsibility.
- **Pending:** time limits for host operations or execution in an isolated
  process/OS sandbox.

### S-07 — No OS sandbox (architecture)

NativaX executes JavaScript in the app process. A QuickJS, FFI, renderer, or
host bug can affect the whole process. There is no OS-level isolation claim.
Untrusted third-party content should run in a separate OS-sandboxed process
with narrow permissions.

### S-08 — Flutter resource policy not verified in this CLI

The default runtime resource loader is `NativaXDenyAllResources`; the real
policy depends on the injected `NativaXResourceLoader` (scheme validation,
redirects, private network, size, TLS). The Flutter denial/cancellation case is
SKIP here and must be run separately.

### V8 is outside this run

The security suite exercises QuickJS. V8 currently does **not** enforce the
execution budget, `maxJobsPerDrain`, or `maxStackBytes`, and has no host
WebAssembly/SharedArrayBuffer/WebGL path. Do not transfer QuickJS limit results
to V8. A hostile-content deployment should force QuickJS or isolate the
process at the OS level until V8 limits and a V8 security run exist.

## Verified controls

- No `process`, `require`, `File`, `Directory`, `Platform`, `fetch`,
  `XMLHttpRequest`, `WebSocket`, `Deno`, `Bun`, `dart`, or raw `__nx.host` in
  scripts.
- `innerHTML`/`insertAdjacentHTML` do not execute inserted scripts/handlers.
- `javascript:` URLs do not execute in the runtime.
- Forged ids throw and the runtime remains alive.
- Two engines do not share globals.
- An infinite loop is interrupted by the QuickJS budget (test uses 50 ms).
- A self-rescheduling microtask hits `MicrotaskLimitError`; remaining jobs stay
  queued.
- Oversized parser input and storage quota fail with typed errors.
- A disposed engine rejects evaluation.
- Programmatic click/submit are untrusted; host gestures are trusted.

## Residual risk

- S-05, S-06, and S-07 remain open.
- V8 lacks tested/enforced time, job, and stack limits.
- No Android, iOS, Windows, or macOS run.
- No security fuzzing or local-network penetration testing in this iteration.
- No SAST/SCA/supply-chain audit.
- QuickJS is not a formally verified interpreter.
- The renderer and Flutter widget tree are not a security boundary.

## Reproduce

```bash
cd debug/engines/security
dart run bin/security.dart run
dart run bin/security.dart run --only internal.callback_globals
dart run bin/security.dart run --only limits.infinite_loop_interrupted
```

Regression tests also live in `packages/nativa_dom/test`,
`packages/nativa_dom_bindings/test`, and `debug/engines/memory`.

## Related

- [`threat-model.md`](threat-model.md)
- [`test-plan.md`](test-plan.md)
- [`platform-matrix.md`](platform-matrix.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)
- [`../architecture/javascript-engines.md`](../architecture/javascript-engines.md)
