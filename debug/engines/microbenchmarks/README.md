# NativaX microbenchmarks

Reproducible measurements of the JavaScript engine, bridge, DOM, style
recomputation, and a native Dart reference. This is not a page-performance or
FPS suite; use `debug/engines/performance` for UI/frame measurements.

## Run

```bash
cd debug/engines/microbenchmarks
dart run bin/benchmark.dart run --warmup 3 --rounds 15
```

Default output is one run directory per invocation:

- `debug/benchmarks/microbench/<run_id>/bench-<stamp>.json`
- `debug/benchmarks/microbench/<run_id>/bench-<stamp>.md`
- `debug/benchmarks/microbench/<run_id>/manifest.json`

Options:

```bash
--only js.arithmetic         # filter by name or category
--no-js | --no-dom | --no-dart
--out DIR                    # explicit results directory
--json FILE --md FILE        # explicit files
--list                       # list cases
```

## Compare two runs

```bash
cd debug/engines/microbenchmarks
dart run bin/benchmark.dart compare \
  --baseline debug/benchmarks/microbench/<run-a>/bench-*.json \
  --current debug/benchmarks/microbench/<run-b>/bench-*.json \
  --threshold 10 --noise 2
```

A difference is a regression only when it exceeds **both** the threshold and
the measured noise (`MAD / median × noise`). Differences inside noise are
labelled `noise`, not `regression`. The command exits 2 when it detects a
regression.

## Categories

| Category | Measures |
|---|---|
| `js` | Arithmetic, functions, objects/prototypes, arrays, strings, recursion, JSON, object churn; includes parse/compile |
| `js_steady` | Script compiled once; measured rounds exclude parse/compile |
| `bridge` | JS → C → Dart → JS round trip without DOM |
| `dom` | Create/query/mutate/remove nodes, events, `innerHTML`, `StyleEngine.recompute` |
| `dart` | Same-process native reference; not an equivalent JS comparison |

`dom.style_recompute` measures DOM → computed styles, **not** GPU frames or
visible UI updates. UI frames require the renderer/performance harness.

## Metadata

Each JSON records:

- engine and version (from `quickjs.h`);
- Dart version and mode (`JIT`, `profile`, `AOT`);
- OS, version, architecture;
- monotonic `Stopwatch` frequency and declared resolution;
- date, command, and notes.

`Stopwatch` is monotonic; the report uses `elapsedTicks / frequency` and
declares the effective resolution as a bound (`1000 / frequency` ms), not a
guaranteed precision.

## Measurement integrity

- Every case returns a deterministic checksum.
- A changed checksum or failed expected value aborts the run.
- The checksum is stored in JSON/Markdown; missing values are not filled with
  zeros.
- Cases do real work in the loop, not an empty call.

## Interpretation

- Compare medians on the same machine and conditions.
- Use `MAD/median` to judge whether a difference is real.
- Do not compare absolute numbers across machines, JIT/AOT modes, or engines.
- `dart.*` may be aggressively optimized; it is context, not a fair JS ratio.
- No V8/JavaScriptCore comparison is included without an equivalent documented
  NativaX DOM run.
- A microbenchmark is not latency, FPS, or conformance.

## Optional V8 (Node.js) steady-state comparison

The `js_steady.*` cases are the correct steady-state comparison: compile once,
then measure only later calls.

```bash
cd debug/engines/microbenchmarks
taskset -c 4 dart run bin/benchmark.dart run \
  --only js_steady --warmup 8 --rounds 21 \
  --json /tmp/nativax-steady.json --md /tmp/nativax-steady.md

taskset -c 4 node node/steady_bench.mjs /tmp/v8-steady.json

python3 node/compare_node.py /tmp/nativax-steady.json /tmp/v8-steady.json
```

`compare_node.py` verifies checksums and reports the geometric mean of
`NativaX time / V8 time`; greater than 1 means NativaX is slower. Cases and
weights are not changed to improve the result. This compares JavaScript engine
steady state, not NativaX rendering, DOM, or modules under V8.

## Tests

```bash
cd debug/engines/microbenchmarks
dart test
```

They cover statistics, checksums, JSON/Markdown formatting, and noise-aware
comparison.

## Related

- [`../../../docs/benchmarks.md`](../../../docs/benchmarks.md)
- [`../../../docs/performance-suite.md`](../../../docs/performance-suite.md)
- [`../memory/README.md`](../memory/README.md)
