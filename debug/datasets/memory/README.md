# Memory ground-truth dataset

Workloads whose leak status is known **by construction**, used to measure the
leak classifier in `debug/engines/memory`. The cases live in
`debug/engines/memory/lib/src/cases/audit_cases.dart` (ids `audit.*`). Each
case carries a `LeakTruth`: `leaks` (does the workload retain memory or
resources by construction?) and `expected` (the class a correct detector
should report given the evidence the case exposes). Both are written into
every report under `results[].truth`.

The dataset is not part of the product suite: `run` without `--dataset`
never executes it, so deliberate leaks never turn the product run red.

```bash
cd debug/engines/memory
dart run bin/leaks.dart run --dataset audit --profile quick --out /tmp/audit
dart run bin/leaks.dart evaluate --profile quick --repeats 3 --out /tmp/eval
```

## Protocol

Every case follows the suite protocol: a baseline sample (batch 0), one
sample after each batch (taken after the batch dropped its local references
and ran `collectGarbage`), then one explicit **release** sample (`phase:
"release"`) after the case's release step and another GC. The release step
is what a correct program would do when it is done (clear the body, drop a
holder); a leak survives it by construction. All dataset cases use
`expectation: released`, so the legacy status is the verdict the old
analysis would give on an unknown workload.

Workload sizes are fixed per batch (except where `iterations` is stated), so
quick (5 batches) and full (20 batches) see the same per-batch effect.

## Cases

| Id | Leaks | Expected class | Channel | Construction |
|---|---|---|---|---|
| `audit.leak.listeners_retained` | yes | `proven_leak` | `listeners`, `targets` | 50 detached elements per batch, each with a listener, pushed to a global array that is never cleared. Release clears `document.body`, not the array. |
| `audit.leak.wrappers_retained` | yes | `proven_leak` | `targets` (node wrappers) | 50 elements per batch stored in a global `Map` with no eviction. |
| `audit.leak.timers_unbounded` | yes | `proven_leak` | `timers` | 10 one-hour `setInterval`s per batch; no handle is kept. |
| `audit.leak.js_global_array` | yes | `proven_leak` | QuickJS heap | `iterations/4` objects (~100 B each) pushed to a global array per batch (quick: 500/batch, about 82 KiB). |
| `audit.leak.js_slow` | yes | `proven_leak` | QuickJS heap | 4 small objects per batch (about 480 B/batch). Below the 1 KiB/batch effect floor: the **known hard case**; the classifier is expected to miss it (report `suspected_leak`). It is labelled `proven_leak` because the leak is real and the heap series is deterministic. |
| `audit.leak.rss_native` | yes | `suspected_leak` | RSS only | Dart keeps an 8 MiB filled `Uint8List` per batch. No counter or engine heap sees it; the evidence policy caps RSS-only evidence at `suspected_leak`. |
| `audit.leak.too_few` | yes | `inconclusive` | QuickJS heap | Same leak as `js_global_array`, but only 3 batches regardless of profile (2 post-warm-up points < 5 required). |
| `audit.control.alloc_release` | no | `no_leak` | QuickJS heap | `iterations` arrays of 64 slots allocated and dropped per batch. |
| `audit.control.listeners_balanced` | no | `no_leak` | counters | 50 elements per batch: attach, add listener, remove listener, detach, drop. |
| `audit.control.timers_cleared` | no | `no_leak` | `timers` | 10 intervals per batch, all cleared in the same batch. |
| `audit.control.bounded_cache` | no | `bounded_high_usage` | QuickJS heap | LRU `Map` capped at 2000 entries, 1000 inserts per batch: fills in two batches, then evicts. |
| `audit.control.bounded_wrapper_pool` | no | `bounded_high_usage` | `targets` | Ring buffer of the last 100 element wrappers, 50 new per batch. |
| `audit.control.grow_then_release` | no | `bounded_high_usage` | QuickJS heap | Same growth as `js_global_array`, but the release step drops the holder: legitimate high usage that is fully returned. |
| `audit.control.warmup_step` | no | `no_leak` | `targets` | One wrapper cached once in batch 1, then released churn: the shape of the old `dom.detached_listeners` false alarm. |
| `audit.control.noisy_engine` | no | `inconclusive` | QuickJS heap | Live pool replaced every batch by 0-4000 objects chosen by a seeded LCG: large variation, no trend, nothing released at the end. |
| `audit.control.noisy_rss` | no | `inconclusive` | RSS only | Dart allocates, fills and drops a 0-64 MiB buffer (seeded LCG) per batch. |

Totals: 7 leaking cases (4 expected `proven_leak` that the criteria can
reach, 1 hard `proven_leak`, 1 `suspected_leak`, 1 `inconclusive`) and 9
controls (4 `no_leak`, 3 `bounded_high_usage`, 2 `inconclusive`).

## Rules

- The truth labels were fixed when the cases were written, before the
  classifier was evaluated on them. Changing a label or a criterion after
  looking at results must be stated in `debug/architecture/metrics-memory.md`.
- `expected` encodes the evidence policy: RSS-only evidence can never be
  `proven_leak`, and fewer than 5 post-warm-up batches is `inconclusive`.
  Metrics against construction truth (`leaks`) are reported separately.
- The LCG cases are deterministic (seed 42), so their sequences are the same
  on every run; the noise is in the measured memory, not in the workload.
