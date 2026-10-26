# Phases

This is the current phase map. A checked item is implemented and has evidence;
an open item is **planned or partial**, not a promise. The older detailed
Spanish checklist is historical:
[`history/phases-2026-10-24-es.md`](history/phases-2026-10-24-es.md).

## Phase status

| Phase | State | Evidence / remaining work |
|---|---|---|
| **0. Technical research** | Complete | QuickJS-ng selected/vendored; FFI contract; Linux Flutter build verified |
| **1. Functional skeleton** | Complete for 0.1 | Packages, text/box/block/flex renderer, DOM mutation, click, basic controls, `NativaXRuntime`/`NativaXView`, counter example |
| **2. JavaScript 0.1** | Complete for 0.1 | QuickJS FFI, timers, microtasks, console, DOM/bindings, lifecycle, Test262 97.93 % |
| **3. CSS/layout 0.1** | Complete for 0.1 | Box model, block/flex, inline text, positioning, lists, overflow, media queries, images |
| **4. APIs and robustness** | In progress | 70 % phase gate met on seven suites; full DOM/CSS/tree/browser API coverage is not |
| **5. Real game example** | Experimental | Linux game-player evidence exists; not a product guarantee and game code/assets are owner-controlled |
| **6. Measurable performance** | Partial | 17 of 270 scenarios measured; no general 7× claim; idle 105 MB tested |
| **7. High-performance WebAssembly** | Planned/partial | wasm3 works for supported modules; no WAMR/AOT, SIMD, threads, or full imports/exports |
| **8. JavaScript engine strategy** | Partial | QuickJS portable; optional V8 desktop path; no JavaScriptCore adapter; V8 modules/limits/graphics incomplete |
| **9. Bridge, memory, zero-copy** | Partial | JSON/scalar host contract, buffers/typed arrays, workers; no all-hot-path binary protocol or zero-copy guarantee |
| **10. DOM/CSS/layout conformance** | In progress | 70 % gate met; tables/floats/columns/writing modes, template, realms, and full invalidation remain |
| **11. Renderer/compositing** | Partial | Virtualization, CSS transforms, grid/flex, dialogs, images, SVG subset; incremental ownership and full top-layer parity remain |
| **12. Canvas/WebGL/GPU** | Partial | Canvas 2D subset, WebGL 1/2 wrapper + native bridge; no WebGL conformance run, pixel-read gaps, no WebGPU |
| **13. Media/audio** | Unsupported/partial | Video/audio elements are placeholders; `AudioContext` is a silent graph; no real decoding/playback |
| **14. Workers/parallelism** | Partial | Dedicated QuickJS workers, messaging, SAB/Atomics, OffscreenCanvas, module workers; interruption and full transfer semantics incomplete |
| **15. Security/robustness** | Partial | 45-case QuickJS suite, 44 PASS / 1 SKIP; no OS sandbox, no V8 suite, no security fuzzing |
| **16. Android** | Unknown | Not built/verified in this environment |
| **17. iOS** | Unknown | Not built/verified; no-JIT and graphics path unresolved |
| **18. Desktop release** | Partial | Linux x86_64 dev/test measured; Windows/macOS unverified; packaging/signing absent |
| **19. Tooling/accessibility** | Partial | Debug engines, context indexes, hot reload, dashboard; accessibility tree and full DevTools not implemented |
| **20. Release 1.0** | Planned | Requires reproducible platform matrix, frozen API, security/perf gates, and no invented claims |

## Current gates

- Conformance phase gate: met on the seven recorded suites; keep SKIP excluded
  and do not call it site compatibility.
- Performance: **not met** for 10k-row DOM operations and several external
  benchmarks; idle target passes on the measured Linux run.
- Security: no OS isolation; V8 limits unenforced; mobile/desktop platforms
  except Linux unverified.
- Full test suite: **not green**. `game_play_test.dart` is flaky with a
  `SIGABRT`; repeated 2026-10-26 runs produced both `exit 0` and failure, and
  the final run exited 1. No CI.
- Documentation: English maintained pages + reproducible evidence; validation
  is script-driven, with no CI.

## Rule

A phase is not complete because a feature exists. It is complete when its
acceptance test and evidence are reproducible, its limits are documented, and
the claimed scope is honest.

## Related

- [`status.md`](status.md)
- [`conformance.md`](conformance.md)
- [`../docs/status.md`](../docs/status.md)
- [`../docs/security/audit.md`](../docs/security/audit.md)
