# Limits, memory, and lifecycle

NativaX is not an OS sandbox. It has in-process limits that make casual hostile
input bounded, but a determined attacker with access to native code paths,
unbounded host callbacks, or an unpatched engine can still compromise the
process. This page lists the actual limits and the evidence gaps.

## Limits at a glance

| Layer | Limit | Default | Enforced by | Notes |
|---|---|---:|---|---|
| HTML input | `maxInputLength` | 4 MiB chars | `HtmlParserLimits` | Rejected before tokenizing |
| HTML parse nodes | `maxNodes` | 100,000 | `HtmlParserLimits` | `HtmlLimitException` |
| HTML parse depth | `maxDepth` | 200 | `HtmlParserLimits` | Deeper tags become siblings; diagnostic |
| HTML errors | `maxErrors` | 1,000 | `HtmlParserLimits` | Later errors counted, not stored |
| DOM tree | `DocumentLimits.maxNodes` | 100,000 | `nativa_dom` | Connected nodes |
| DOM depth | `DocumentLimits.maxDepth` | 256 | `nativa_dom` | Bounds recursive style/render |
| JS heap | `memoryLimitBytes` | 64 MiB (page) | QuickJS allocator; V8 near-heap callback | V8 terminates at the limit; QuickJS raises |
| JS stack | `maxStackBytes` | 256 KiB | QuickJS | V8 native call ignores the value |
| JS budget | `executionBudget` | 10 s page / 1 s engine default | QuickJS | Not enforced by current V8 |
| JS jobs | `maxJobsPerDrain` | 1,000,000 page / 10,000 engine default | QuickJS | Not enforced by current V8 |
| Microtask slice | `microtaskSlice` | zero | QuickJS | Optional yield; zero = full drain |
| Timers | `maxActiveTimers` | 1,000 | `TimerLimits` | `RangeError` beyond |
| Timer interval | `minIntervalMs` | 4 ms | `TimerLimits` | Clamped |
| Storage | `MemoryStorage.quota` | 5 MiB chars | MemoryStorage | Keys + values |
| `crypto.getRandomValues` | request size | 65,536 bytes | bindings | `QuotaExceededError` |
| Network response | `IoNetwork.maxResponseBytes` | 32 MiB | `IoNetwork` | Larger response denied |
| Workers | `maxWorkers` | 16 | `IsolateWorkerLauncher` | More workers fail |
| Worker heap | `memoryLimitBytes` | 1 GiB | QuickJS worker config | Large by design |
| Worker stack | `maxStackBytes` | 1 MiB | QuickJS worker config | Per worker isolate |
| Worker budget | `executionBudget` | 30 s | QuickJS worker | Per entry |
| Wasm | gas per call | 1,000,000,000 | wasm3 bridge | `NX_WASM_GAS_PER_CALL` |
| Style cache | optional | enabled | `StyleEngine` | `NATIVAX_NO_STYLE_CACHE=1` disables |

The page and worker numbers differ. Do not quote a single JS memory limit for all
contexts.

## What the limits do not cover

- **Native host callbacks** can allocate or block without the JS budget.
- **V8 has no wall-clock timeout or job cap** in the current native entry points.
  A long V8 script can freeze the UI isolate until it finishes or hits the heap
  limit. This is a major reason not to run hostile content on V8 without an OS
  process boundary.
- **The UI isolate is shared** with Flutter; a CPU-heavy QuickJS callback that is
  in a host function is not preempted by the engine budget.
- **Images/fonts/canvas** have no universal byte quota in the renderer; a host
  image resolver or decoder can allocate large textures.
- **Network policy** is only as strong as the provided `NativaXNetwork`; the
  default denial is safe, but `IoNetwork` is not a full web security policy.
- **Workers** are in the same process; they are not a sandbox.
- **File system** access exists only through the host's loaders/services. There
  is no public `require`, `process`, or unrestricted file API in script scope,
  but a host function can introduce one; review every added handler.

## Memory evidence

The latest recorded leak run (2026-10-25, `debug/benchmarks/leaks/20261026T030350Z-f47240e`)
ran only `control.release` in the `quick` profile:

- 1 PASS, 0 FAIL, 0 SKIP, 0 INCONCLUSIVE;
- process RSS fell from 476.3 MiB to 290.5 MiB across six samples;
- `activeRuntimes` returned to 0;
- this is **not** a full leak suite result.

The latest performance baseline records **105.0 MB RSS / 0.00 % CPU** for the
desktop app on a blank page. That is process RSS, not live heap, and not a leak
proof. See [`../performance-suite.md`](../performance-suite.md) and
[`../../progress/reports/perf-latest.md`](../../progress/reports/perf-latest.md).

Do not claim “no leaks”. The current evidence supports “one create/dispose smoke
case returned to baseline after release; broader leak scenarios were not run in
the latest artifact.”

## How to run leak evidence

```bash
cd debug/engines/memory

dart run bin/leaks.dart run --profile quick
dart run bin/leaks.dart run --profile full --only dom.detached_listeners
dart run bin/leaks.dart run --list
```

Results are written under `debug/benchmarks/leaks/<run_id>/` with a manifest.
A `PASS` requires a plateau/trend criterion, not one low sample. `INCONCLUSIVE`
is not a pass. See [`../benchmarks.md`](../benchmarks.md) and
[`../debugging.md`](../debugging.md).

## Lifecycle risks

| Risk | Current mitigation | Remaining gap |
|---|---|---|
| Runtime not disposed | `NativaXView` disposes on unmount/reload; `isDisposed` guard | Direct runtime users can forget; no finalizer |
| Timers after dispose | `TimerHost.dispose`; engine disposal | Custom host callbacks can retain timers |
| Detached DOM wrappers/listeners | `FinalizationRegistry` + `node.release`; wrapper release test | GC timing is nondeterministic |
| Worker leaks | Launcher tracks/kills workers | No long-run multi-worker soak |
| Canvas/GL surfaces | Canvas registry disposed with view | Native GL driver resources are host-owned |
| V8 over budget | Startup fallback and `onEngineOverBudget` reload | Post-startup reload loses page state |
| Flutter dispose race | Generation counter discards late loads | Host callbacks must still be safe after dispose |

## Security implications

- Run untrusted content in a separate OS process/sandbox if compromise matters.
- Keep `NATIVAX_ENGINE=quickjs` or a custom bounded engine for adversarial input
  until V8 enforces time/job limits.
- Keep the resource loader narrow; deny network by default.
- Do not expose filesystem/process/network host functions to page scripts.
- Treat the security suite as regression detection, not proof of safety.

## Related

- [`../security/threat-model.md`](../security/threat-model.md)
- [`../security/audit.md`](../security/audit.md)
- [`../security/test-plan.md`](../security/test-plan.md)
- [`../reference/configuration.md`](../reference/configuration.md)
- [`../benchmarks.md`](../benchmarks.md)
