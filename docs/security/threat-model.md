# NativaX security threat model

## Assets

- Host process memory, files, environment, credentials, and OS capabilities.
- Other NativaX documents/runtimes in the same process.
- DOM, style, renderer, worker, and JavaScript state for each document.
- User input (keystrokes, files, clipboard, navigation) and application data.
- Integrity of the build, native assets, and dependency chain.

## Adversaries

1. A malicious app author shipping a NativaX application.
2. An app rendering untrusted HTML/CSS/JS from users or network data.
3. An attacker controlling a resource response, redirect, or URL.
4. A hostile document combining scripts, events, forms, images, and styles.
5. A script trying to reach Dart, Flutter, native capabilities, or the host.
6. A script trying to exhaust CPU, RAM, stack, timers, DOM, or storage limits.
7. A compromised dependency or build step.
8. An app that creates/destroys runtimes repeatedly to exploit lifecycle bugs.

## Trust boundaries

| Boundary | Trusted side | Untrusted side |
|---|---|---|
| Script ↔ host | Dart host functions, app handlers | JavaScript, DOM content |
| Document ↔ document | Separate engine runtime + Document | Other document's JS/state |
| Worker ↔ page | Host-created worker runtime + port router | Worker script and messages |
| App ↔ resource loader | App-defined `NativaXResourceLoader` | External URL/content |
| App ↔ network policy | `NativaXNetwork` implementation | Request URL/headers/body/response |
| HTML/CSS parser | Parser implementation | Markup and styles |
| Renderer | Flutter widgets/RenderObjects | DOM/CSS values |
| Process ↔ OS | OS sandbox/permissions | NativaX process |

NativaX is **not** an OS sandbox. It separates JavaScript runtimes logically
inside one process; OS-level isolation is the host application's/operating
system's responsibility.

## Threats and current controls

| Threat | Control | Status |
|---|---|---|
| Access to files/process/env from JS | Not exposed; scripts get DOM, storage, theme, timers, app handlers | Tested |
| Raw host bridge | Production runtime calls `DomBindings.harden()`; `__nx.host` and internal callback globals are not reachable | Tested |
| Cross-engine state | One runtime/context per engine; worker runtimes are separate | Tested |
| CPU infinite loops | QuickJS interrupt + 10 s runtime execution budget | Tested |
| Microtask starvation | `maxJobsPerDrain` (1,000,000 runtime default) + `MicrotaskLimitError` | Tested |
| Memory exhaustion | QuickJS memory limit (64 MiB default) | Configured |
| Stack exhaustion | `maxStackBytes` (256 KiB default) | Configured for QuickJS |
| DOM exhaustion | node/depth/input limits | Partly tested |
| Script tags via `innerHTML` | Parser does not execute inserted scripts | Tested |
| `javascript:` URL execution | Not executed; host receives navigation | Tested |
| Forged host ids | Ids validated; errors become JS exceptions | Tested |
| Listener retention after wrapper release | `node.release` removes listeners | Tested by leak suite |
| Timers after dispose | TimerHost cancels; callbacks no-op | Tested by leak suite |
| Resource fetch by default | `NativaXDenyAllResources` + `DeniedNetwork` | Config; Flutter cancellation path SKIP |
| Clipboard/vibration abuse | Requires a trusted transient user activation | Implemented/tested |
| Host Dart work during a host call | JS budget does not interrupt synchronous Dart work | **Residual** |
| V8 time/job/stack enforcement | Not enforced by the current V8 native path | **Open/Critical for V8** |
| OS-level escape | Not mitigated by NativaX | **Out of scope** |

The current 45-case security suite runs **QuickJS only**. It cannot certify V8,
which is the default desktop page engine when `libnx_v8.so` loads. V8 has no
execution-budget, job-limit, or stack-limit enforcement in its native entry
points. A deployment that renders untrusted content must force QuickJS or place
the process behind OS-level isolation until V8 has equivalent enforcement and a
V8 security run.

## Residual findings

- **S-05:** `javascript:` URLs are not executed, but the raw `href` reaches
  `Document.onNavigate`. A host that opens it in an external browser/WebView can
  move the attack outside NativaX. Validate schemes/destinations in the host.
- **S-06:** the QuickJS budget interrupts bytecode, not a synchronous Dart host
  function. A large `innerHTML` or expensive `app.invoke` can still block the UI.
- **S-07:** no OS sandbox. A native/FFI/renderer bug can affect the process.
- **S-08:** the Flutter resource-policy cancellation case is SKIP in the CLI;
  the injected resource loader remains part of the trust boundary.

## Explicit non-goals

NativaX does **not** claim:

- OS/process sandboxing, privilege separation, or protection from a compromised
  host process.
- Network policy, TLS validation, CORS, cookies, or certificate pinning. The
  host `NativaXNetwork`/resource loader decides; `IoNetwork` is an allow-list,
  not a browser security model.
- Confidentiality of data passed to `app.invoke` handlers.
- That every browser security primitive or header exists.
- That QuickJS limits protect V8.
- That a `PASS` in the security suite proves the absence of all vulnerabilities.

## Related

- [`audit.md`](audit.md)
- [`test-plan.md`](test-plan.md)
- [`platform-matrix.md`](platform-matrix.md)
- [`../architecture/javascript-engines.md`](../architecture/javascript-engines.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)
