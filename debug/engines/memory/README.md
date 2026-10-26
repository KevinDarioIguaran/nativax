# Leaks, retention, and lifecycle

This engine looks for sustained memory growth, orphaned listeners, pending
timers, retained JS wrappers, and incomplete lifecycle paths. It does not
replace Flutter widget-memory tests.

## Run

```bash
cd debug/engines/memory
dart run bin/leaks.dart run --profile quick
```

Profiles:

| Profile | Batches | Iterations | Use |
|---|---:|---:|---|
| `quick` | 5 | 2,000 | smoke/CI |
| `full` | 20 | 10,000 | review |
| `stress` | 60 | 50,000 | dedicated machine |

```bash
# One case
dart run bin/leaks.dart run --only dom.listener_churn

# List cases
dart run bin/leaks.dart run --list

# Compare two runs
dart run bin/leaks.dart compare \
  --baseline debug/benchmarks/leaks/<run-a>/leaks-*.json \
  --current debug/benchmarks/leaks/<run-b>/leaks-*.json
```

Outputs (gitignored):

- `debug/benchmarks/leaks/<run_id>/*.json`
- `debug/benchmarks/leaks/<run_id>/*.jsonl` (one sample per batch)
- `debug/benchmarks/leaks/<run_id>/*.md`
- `debug/benchmarks/leaks/<run_id>/manifest.json`

## Protocol

Each case:

1. Records a baseline (`batch 0`).
2. Runs batches of work.
3. Releases references and requests GC where the runtime allows.
4. Records RSS, `maxRss`, QuickJS heap, and resource counters.
5. Compares a trend, not a single sample.
6. Reports `PASS`, `FAIL`, `SKIP`, `ERROR`, or `INCONCLUSIVE`.

Controls:

- `control.release`: create/destroy runtimes; must release.
- `control.retained`: deliberately retains runtimes; the detector must see it.
- `css.style_churn`: stable tree with recomputation; must plateau.
- `dom.detached_listeners`: disconnected nodes with listeners; wrappers and
  listeners must not remain retained.

## Latest recorded run

`20261026T030350Z-f47240e` ran **only** `control.release` with
`--profile quick --only control.release`: 1 PASS, 0 FAIL, 0 SKIP. RSS went
476.3 MiB → 290.5 MiB and `activeRuntimes` returned to 0. This is a smoke
control, not a full leak claim.

## Rules

- Rising RSS alone does **not** prove a leak; it can be allocator/GC behavior.
- `FAIL` requires a sustained trend **and** resource or engine-heap evidence;
  otherwise the result is `INCONCLUSIVE`.
- `ProcessInfo.currentRss` includes Dart, QuickJS, Flutter, and the allocator;
  it is not “live heap”.
- The historical `dom.detached_listeners` failure led to `node.release`
  clearing listeners when a JS wrapper is released.
- Dangerous stress profiles are not run in the quick/CI path.
- A skipped case and an `INCONCLUSIVE` case are not passes.

## Limitations

- There is no public API to inspect every Dart/Flutter internal map; the suite
  uses counters and RSS.
- Dart GC may retain memory after objects become unreachable.
- Flutter view/renderer memory needs a widget harness; this CLI measures
  DOM/JS/runtime.
- Image/resource memory is covered separately by renderer tests, not by this
  suite.
- One machine and one platform are not a cross-platform leak claim.

## Tests

```bash
cd debug/engines/memory
dart test
dart analyze
```

## Related

- [`../../../docs/benchmarks.md`](../../../docs/benchmarks.md)
- [`../../../docs/internals/limits-and-memory.md`](../../../docs/internals/limits-and-memory.md)
- [`../../../docs/security/audit.md`](../../../docs/security/audit.md)
