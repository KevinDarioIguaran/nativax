# NativaX security threat model

## Assets

- Host process memory, files, environment, credentials and OS capabilities.
- Other NativaX applications/documents in the same process.
- The DOM, style engine and renderer state of each document.
- User input (keystrokes, files, clipboard, navigation) and app data.
- Integrity of the build, native assets and dependency chain.

## Adversaries

1. A malicious app author shipping a NativaX application.
2. An app that renders untrusted HTML/CSS/JS from users or network data.
3. An attacker controlling a resource response, redirect or URL.
4. A hostile document combining scripts, events, forms, images and styles.
5. A script trying to reach Dart/Flutter/native capabilities or the host.
6. A script trying to exhaust CPU, RAM, stack, timers or DOM limits.
7. A compromised dependency or build step.
8. An app that creates/destroys runtimes repeatedly to exploit lifecycle bugs.

## Trust boundaries

| Boundary | Trusted side | Untrusted side |
|---|---|---|
| Script ↔ host | Dart host functions, app handlers | JavaScript, DOM content |
| Document ↔ document | Separate QuickJS runtime + Document | Other document's JS/state |
| App ↔ resource loader | App-defined `NativaXResourceLoader` | External URL/content |
| HTML/CSS parser | Parser implementation | Markup and styles |
| Renderer | Flutter widgets/RenderObjects | DOM/CSS values |
| Process ↔ OS | OS sandbox/permissions | NativaX process |

NativaX is **not** an OS sandbox. It isolates JS logically inside one process;
OS-level isolation is the host application's/operating system's responsibility.

## Threats and current controls

| Threat | Control | Status |
|---|---|---|
| Access to files/process/env/network from JS | Not exposed; only DOM, storage, theme, timers, app.invoke | Tested |
| Raw host bridge | Production runtime calls `DomBindings.harden()`; `__nx` removed from globals | Tested |
| Cross-engine state | One QuickJS runtime/context per engine | Tested |
| CPU infinite loops | QuickJS interrupt + execution budget (1 s default) | Tested |
| Microtask starvation | `maxJobsPerDrain` + `MicrotaskLimitError` | Tested |
| Memory exhaustion | QuickJS memory limit (64 MiB default) | Configured |
| Stack exhaustion | `maxStackBytes` (256 KiB default) | Configured |
| DOM exhaustion | node/depth/input limits | Tested partly |
| Script tags via `innerHTML` | Parser does not execute scripts | Tested |
| `javascript:` URL execution | Not executed; host receives navigation | Tested |
| Forged host IDs | IDs validated; errors become JS exceptions | Tested |
| Listener retention after wrapper release | `node.release` removes listeners | Tested by leak suite |
| Timers after dispose | TimerHost cancels; callbacks no-op | Tested by leak suite |
| Resource fetch by default | `NativaXDenyAllResources` | Config; Flutter path untested |
| Internal JS callback globals | `__nx_dispatch` etc. discoverable | **Open (medium)** |
| Host Dart work during a host call | JS budget does not interrupt Dart work | **Residual** |
| OS-level escape | Not mitigated by NativaX | **Out of scope** |

## Explicit non-goals

NativaX does **not** claim:

- OS/process sandboxing.
- Protection against a malicious host application or compromised Dart code.
- Network policy, TLS validation or CORS (the host resource loader decides).
- Confidentiality of data passed to `app.invoke` handlers.
- A guarantee that every browser security primitive exists.
- That a `PASS` in the security suite proves absence of all vulnerabilities.
