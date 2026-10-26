# Benchmarks, leaks, and security runs

NativaX keeps evidence in separate engines so a visual score, a frame time, a
leak result, and an attack result are never mixed into one number. This page is
the map; each engine's README owns its protocol.

Run benchmark engines from their own directories. They write a run directory
with results plus `manifest.json`; the run directories are gitignored, while
small tracked baselines live in `debug/benchmarks/baselines/` and
`debug/benchmarks/game-player-phase0/`.

## Run layout

```text
debug/benchmarks/<area>/<run_id>/
  <result>.json
  <result>.jsonl          # leaks: one sample per batch
  <result>.md
  manifest.json
```

`<run_id>` is `<UTC timestamp>Z[-<short commit>][-N]` (for example
`20261026T030350Z-f47240e`). The manifest records area, command, commit, dirty
state, timestamps, host, and files, validated by
`debug/logic/schemas/run-manifest.schema.json`. The shared Dart package is
`debug/manifest`; the Python contract is in `debug/architecture/storage.md`.

Areas:

| Area | Engine | Output |
|---|---|---|
| `microbench` | `debug/engines/microbenchmarks` | JS, bridge, DOM, style, Dart reference |
| `leaks` | `debug/engines/memory` | lifecycle/RSS/resource trend |
| `security` | `debug/engines/security` | per-attack PASS/FAIL/SKIP |

Visual and performance engines use their own generated tree under
`debug/artifacts/{visual,perf}/` and are documented in
[`visual-fidelity.md`](visual-fidelity.md) and
[`performance-suite.md`](performance-suite.md).

## Microbenchmarks

```bash
cd debug/engines/microbenchmarks
dart run bin/benchmark.dart run --warmup 3 --rounds 15
dart run bin/benchmark.dart run --only js.arithmetic
dart run bin/benchmark.dart run --list
```

Compare two runs:

```bash
cd debug/engines/microbenchmarks
dart run bin/benchmark.dart compare \
  --baseline debug/benchmarks/microbench/<run-a>/bench-*.json \
  --current debug/benchmarks/microbench/<run-b>/bench-*.json \
  --threshold 10 --noise 2
```

A difference is a regression only when it exceeds both the threshold and the
measured noise (`MAD / median × noise`); otherwise it is labelled `noise`. The
compare command exits 2 on a regression.

Categories:

| Category | Measures |
|---|---|
| `js` | Arithmetic, calls, objects, arrays, strings, recursion, JSON, object churn |
| `js_steady` | Already compiled script; rounds exclude parse/compile |
| `bridge` | JS → C → Dart → JS round trip without DOM |
| `dom` | Create/query/mutate/remove nodes, events, `innerHTML`, style recompute |
| `dart` | Same-process native reference, not an equivalent JS comparison |

Latest representative run (`20261026T024956Z-f47240e`) measured nine
`js_steady.*` cases with `--warmup 1 --rounds 3`; it is a comparison run, not a
full-suite baseline. Its checksums are in the JSON, and the Markdown source is
in Spanish because it was emitted before the documentation-language switch.

Rules:

- Compare medians on the same machine and conditions.
- Do not compare absolute numbers across JIT/AOT modes or engines.
- `dart.*` can be aggressively optimized; it is context, not a fair JS ratio.
- No V8/JavaScriptCore comparison is presented without an equivalent documented
  DOM run.
- `dom.style_recompute` measures DOM → computed style, not GPU/UI frames.
- Every case returns a deterministic checksum; a mismatch aborts the run.

## Leak and lifecycle runs

```bash
cd debug/engines/memory
dart run bin/leaks.dart run --profile quick
dart run bin/leaks.dart run --only dom.listener_churn
dart run bin/leaks.dart run --list
```

Profiles: `quick` (5 batches × 2,000), `full` (20 × 10,000), `stress`
(60 × 50,000, dedicated machine only).

Latest recorded run `20261026T030350Z-f47240e` executed **only**
`control.release`: 1 PASS, 0 FAIL, 0 SKIP. It is a smoke result, not a complete
leak claim. RSS went from 476.3 MiB to 290.5 MiB across batches and
`activeRuntimes` returned to 0. That release control passed; it does not mean
all node/listener/timer paths were measured in that run.

A leak verdict requires a sustained trend **and** resource/heap evidence.
`ProcessInfo.currentRss` includes Dart, QuickJS, Flutter, and the allocator, so
a single RSS rise is not a leak. If the signal is ambiguous, the result is
`INCONCLUSIVE`, not `FAIL` or `PASS`.

## Security suite

```bash
cd debug/engines/security
dart run bin/security.dart run
dart run bin/security.dart run --list
dart run bin/security.dart run --only bridge
```

Latest recorded run `20261026T024956Z-f47240e`: **45 cases — 44 PASS, 0 FAIL,
1 SKIP** (`platform.flutter_resource_policy`). The suite covers exposed host
globals, bridge hardening, trusted events, `innerHTML`/`javascript:` XSS,
forged ids, engine isolation, QuickJS time/microtask limits, parser input,
storage quota, disposal, generated global/URL/`innerHTML` matrices, and the
Flutter-only resource policy path. Details and residuals are in
[`security/audit.md`](security/audit.md).

A PASS covers only the executed attack case. The runtime is not an OS sandbox,
V8 is not covered by this suite, and a SKIP is not a protection.

## Reading a run

```bash
cat debug/benchmarks/security/<run_id>/manifest.json
python3 debug/run.py runs --area security
python3 debug/run.py conformance
```

Check the manifest before quoting a result. Confirm:

- the command and area;
- commit and whether the working tree was dirty;
- date and host;
- engine/profile/limits;
- result files actually present;
- PASS/WARN/FAIL/SKIP/INCONCLUSIVE counts.

`progress/reports/*-latest.md` are convenience copies and can lag. Canonical
per-test conformance data is JSONL under
`debug/artifacts/conformance/results/`; canonical run data is under
`debug/benchmarks/<area>/<run_id>/`. Both are gitignored on this machine.

## What these numbers do not mean

- Microbenchmark speed is not page latency or FPS.
- Offscreen render/frame cost is not GPU rasterization.
- A visual percentage is not CSS compatibility.
- A release control is not a full leak suite.
- A security PASS is not proof of safety or OS isolation.
- A QuickJS result is not a V8 result.

## Related

- [`debugging.md`](debugging.md)
- [`testing.md`](testing.md)
- [`performance-suite.md`](performance-suite.md)
- [`visual-fidelity.md`](visual-fidelity.md)
- [`security/audit.md`](security/audit.md)
- [`../debug/README.md`](../debug/README.md)
- [`../debug/engines/microbenchmarks/README.md`](../debug/engines/microbenchmarks/README.md)
- [`../debug/engines/memory/README.md`](../debug/engines/memory/README.md)
- [`../debug/engines/security/README.md`](../debug/engines/security/README.md)
