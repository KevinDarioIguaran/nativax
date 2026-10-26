# Leaks, retention and lifecycle

Suite that detects sustained memory growth, orphan listeners, pending timers,
retained wrappers and incomplete lifecycles, and classifies the evidence for
each case.

## Run

```bash
cd debug/engines/memory
dart run bin/leaks.dart run --profile quick
```

Profiles:

| Profile | Batches | Iterations | Use |
|---|---:|---:|---|
| `quick` | 5 | 2,000 | CI / smoke |
| `full` | 20 | 10,000 | review |
| `stress` | 60 | 50,000 | dedicated machine |

```bash
# One case
dart run bin/leaks.dart run --only dom.listener_churn

# List cases
dart run bin/leaks.dart run --list

# Ground-truth dataset (deliberate leaks and controls; never in the default run)
dart run bin/leaks.dart run --dataset audit

# Score the classifier on the dataset (confusion matrix, precision/recall,
# stability over repeats)
dart run bin/leaks.dart evaluate --profile quick --repeats 3 --out /tmp/eval

# Compare two revisions
dart run bin/leaks.dart compare \
  --baseline debug/benchmarks/leaks/<run-a>/leaks-*.json \
  --current debug/benchmarks/leaks/<run-b>/leaks-*.json
```

Outputs (gitignored), one directory per run (`--out DIR` overrides it):

- `debug/benchmarks/leaks/<run_id>/leaks-<timestamp>.json`: metadata and one result per case;
- `debug/benchmarks/leaks/<run_id>/leaks-<timestamp>.jsonl`: one sample per batch;
- `debug/benchmarks/leaks/<run_id>/leaks-<timestamp>.md`: human report;
- `debug/benchmarks/leaks/<run_id>/manifest.json`: run manifest (`debug/manifest`).

`evaluate` writes `evaluation.json`, `evaluation.md` and one report directory
per repeat (`repeat-N/`).

## Protocol

Each case:

1. Records a baseline (`batch 0`).
2. Runs batches of work.
3. Drops references and requests GC when the runtime allows it.
4. Records RSS, `maxRss`, the QuickJS heap and resource counters.
5. Optionally runs a release step and records one more sample with
   `phase: "release"` (all dataset cases do).
6. Judges the trend, never a single sample.

## Result fields

Every result keeps the legacy fields (`status` is `PASS`, `FAIL`, `SKIP`,
`ERROR` or `INCONCLUSIVE`, plus `reason`, `evidence`, `thresholdBytes`) and
adds:

- `classification.class`: `proven_leak`, `suspected_leak`,
  `bounded_high_usage`, `no_leak` or `inconclusive`;
- `classification.reason`, `primaryChannel`, `explicitRelease`,
  `peakRssBytes`, `retainedRssBytes`;
- `classification.criteria`: every decision parameter;
- `classification.channels[]`: per channel (`nodes`, `listeners`, `timers`,
  `targets` = live node wrappers, `activeRuntimes`, `engineHeap`, `rss`):
  baseline, peak, last, release, retained, per-batch deltas, Mann-Kendall
  statistics (`s`, `pValue`, `n`, `method`), Theil-Sen slope, tail slope,
  floor, spread and the channel's own class;
- `truth` (dataset cases only): `leaks`, `expected`, `rationale`.

SKIP and ERROR results have no `classification`. The formulas, the mapping
between legacy status and class, and measured accuracy are in
[`debug/architecture/metrics-memory.md`](../../architecture/metrics-memory.md).

Controls in the product suite:

- `control.release`: creates and disposes runtimes; must release.
- `control.retained`: retains runtimes on purpose; the detector must see it.
- `css.style_churn`: stable tree with recomputation; must plateau.
- `dom.detached_listeners`: detached nodes with listeners; checks that
  wrappers and listeners are not retained.

## Rules

- An RSS increase does **not** prove a leak; it can be the allocator or GC.
  RSS-only evidence is capped at `suspected_leak`.
- `proven_leak` requires a precise channel (resource counter or QuickJS heap)
  with a significant monotonic trend, a minimum effect size, growth that is
  still rising at the end of the run, and retention after release.
- Legacy `FAIL` requires sustained growth **and** resource or engine-heap
  evidence; otherwise `INCONCLUSIVE`.
- `ProcessInfo.currentRss` includes Dart, QuickJS, Flutter and the
  allocator; it is not "live heap".
- The `FAIL` of `dom.detached_listeners` once led to fixing `node.release` so
  it frees listeners when the JS wrapper is dropped. Its later `FAIL` was a
  one-time wrapper created in the first batch, not a leak; the legacy rule now
  measures counter growth from the first batch.
- Dangerous scenarios have limits; the `stress` profile is not for CI.

## Limitations

- There is no public API to inspect every internal Dart or Flutter map; the
  suite uses counters and RSS.
- Dart's GC can keep memory even when objects are unreachable.
- Some product cases report counters that are constant by construction
  (`activeRuntimes: 0` after a dispose); a flat constant is weak evidence.
- Flutter view tests need a widget harness; this CLI measures DOM/JS/runtime,
  not frames.
- Renderer memory and image resources are validated separately in widget
  tests (still to be extended).

## Latest recorded run

`20261026T030350Z-f47240e` ran **only** `control.release` with
`--profile quick --only control.release`: 1 PASS, 0 FAIL, 0 SKIP. RSS went
476.3 MiB → 290.5 MiB and `activeRuntimes` returned to 0. This is a smoke
control, not a full leak claim.

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
