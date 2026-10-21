# Performance

## Budgets

| Operation | Target |
|---|---|
| Trivial JS → Dart host call | < 5 µs (measured ~3 µs on Linux) |
| UI frame | 16 ms |
| Script entry | 1 s by default, configurable |
| HTML parsing | linear; no regex over markup |
| Style recomputation | incremental per dirty subtree |

## Current measurement (Linux, Dart JIT, 2026-10-20)

| Scenario | Cost |
|---|---|
| `__nx.host("noop")` | 2.98 µs |
| `__nx.host("sum", i, 1)` | 3.19 µs |
| JS loop, 1e6 iterations | 29.8 ms |
| Parse JSON with 1000 elements | 2.9 ms |

Large payloads (`innerHTML`, `outerHTML`, `getComputedStyle`) dominate the
cost, not the number of small calls.

## Benchmark suite

`tools/benchmark` implements JS, bridge, DOM, style, and Dart-reference
categories with JSONL/JSON/Markdown output, checksums, and noise-aware
comparison. See `docs/benchmarks.md`.

## Leak suite

`tools/leaks` measures retention with a baseline, batches, GC, and controls. It
classifies `PASS/FAIL/SKIP/ERROR/INCONCLUSIVE`. A single RSS sample never proves
a leak. See `../../nativa-project/references/requirements.md` §4. `tools/leaks` implements the
protocol with quick/full/stress profiles and controls.

## Rules

1. Measure before optimizing; keep the benchmark and the result.
2. Avoid JSON in hot operations: batch, reuse buffers, or use a binary protocol.
3. Do not block the UI thread for more than one frame without yielding.
4. Renderer optimization (per owner, not global rebuild) is mandatory before
   claiming end-to-end performance.
5. Final benchmark decisions run in release/AOT; JIT is useful for trends.

## Pending

- Expand `tools/benchmark` with parsing, styles, layout, bridge, and memory.
- Measure CSS recomputation on large documents.
- Profile QuickJS startup per document.

## 7× performance requirement (2026-10-21)

Requested goal: **7× less time / 7× more work per second** than the current
baseline, without changing semantics or hiding work.

### Reproducible baseline

Linux x64, QuickJS-ng 0.17 without JIT vs Node 22 V8 with JIT, identical loops,
3 warm-ups, median of 10 rounds:

| Case | QuickJS-ng | V8 | Gap |
|---|---:|---:|---:|
| Integer arithmetic | 35.9 ms | 1.65 ms | 21.7× |
| Function calls | 22.4 ms | 0.46 ms | 49× |
| Objects/properties | 57.2 ms | 8.1 ms | 7.0× |
| Arrays | 13.9 ms | 3.4 ms | 4.1× |
| Strings | 18.7 ms | 2.6 ms | 7.1× |
| Recursion `fib(24)` | 5.0 ms | 0.85 ms | 5.9× |
| `JSON.parse` | 56.7 ms | 21.6 ms | 2.6× |
| `JSON.stringify` | 9.3 ms | 1.4 ms | 6.6× |
| Object creation | 35.7 ms | 3.5 ms | 10.2× |

Median gap: **~7×**. This is an engine comparison, not a promise that QuickJS
can close it with micro-optimizations.

### Mandatory interpretation

1. **7× in pure JavaScript is not achievable while keeping QuickJS-ng.** QuickJS
   is an interpreter; V8 compiles. Matching or beating V8 in hot code needs a
   JIT engine (V8/JavaScriptCore) on platforms that allow JIT. iOS does not, so
   QuickJS remains the base there.
2. **7× end-to-end is a valid, measurable goal** for app workloads: WebAssembly
   physics, the JS ↔ Dart bridge, DOM/layout, and the renderer. Measure per
   scenario, not with an invented global number.
3. The requirement is met only if:
   - the equivalent benchmark improves ≥ 7× over the saved baseline,
   - functional tests pass,
   - memory/RSS and frame latency do not regress,
   - release/AOT is used for the final decision.
4. The two admitted routes are:
   - **WAMR** (AOT/JIT) for WebAssembly/Rapier, keeping wasm3 as the no-JIT
     fallback, and
   - a **V8/JavaScriptCore adapter** for JS on desktop/Android, keeping
     QuickJS-ng on iOS or as a compatibility mode.
5. Do not accept "7×" by changing the work, checksum, input size, or
   denominator. A microbenchmark that does not represent the game workload is
   not an acceptable result.

### Status

- Requirement recorded, **not achieved**.
- Next measurement: Rapier `world.step` with 103 bodies and a real game frame;
  then evaluate WAMR AOT against wasm3 with the same wasm.

### WebAssembly/Rapier baseline (same scene)

Scene: fixed floor + 100 dynamic spheres, gravity -20, `timestep = 1/60`,
20 warm-up steps and 180 measured steps.

| Engine | 180 steps | Per step |
|---|---:|---:|
| V8 + Rapier 0.19.3 (JIT) | 30.74 ms | 0.171 ms |
| NativaX + wasm3 (interpreter) | 328.54 ms | 1.825 ms |

The current gap is **10.7×**. To meet 7×, the 180 steps must fall to
**≤ 46.9 ms**. WAMR AOT is the realistic route: it aims to approach V8 without
JIT on iOS, keeping wasm3 as a fallback.

## Audit 2026-10-21 (real engine)

- Engine: **QuickJS-ng 0.17.0**, bytecode interpreter without JIT, MIT.
- Build: `-O3`, `NDEBUG`, computed goto (`DIRECT_DISPATCH=1`).
- Reproducible steady-state baseline: **7.58× slower than V8**
  (`js_steady.*`, 8 warm-ups + 21 rounds, checksums verified).
- To be 7× faster than V8 from that baseline requires **53.1×**.
- Rejected experiments with no improvement: LTO, `-O2`, `-march=native`,
  `-fno-semantic-interposition`, raising the GC threshold.
- Details, per-benchmark table, and roadmap: `docs/performance-audit.md`.
- New harness: `tools/benchmark/node/steady_bench.mjs` and
  `tools/benchmark/node/compare_node.py`.
