# Memory engine metrics

How `debug/engines/memory` (the leak and lifecycle suite) classifies a case,
how the classifier was measured against a dataset with known truth, and the
measured numbers. All analysis is deterministic arithmetic over the recorded
samples: no model, no LLM.

## 1. Problem

The legacy verdict (`PASS`/`FAIL`/`SKIP`/`ERROR`/`INCONCLUSIVE`) lumps
together a proven leak, a suspicion and a workload that legitimately holds
more memory: all of them can be `FAIL` (`engine-inventory.md` section 4). It
also has a fixed 512 KiB/batch QuickJS-heap threshold, so it misses smaller
leaks. Until now there was no dataset with known truth to measure either
behaviour.

## 2. Classes

| Class | Meaning |
|---|---|
| `proven_leak` | A precise channel (resource counter or QuickJS heap) grows monotonically across batches, the growth is significant, larger than the effect floor, still rising at the end, and it survives the release step. |
| `suspected_leak` | A growth signal below the proof criteria (weaker significance, effect below the floor), or RSS-only evidence that meets the proof criteria (capped). |
| `bounded_high_usage` | Memory or resources well above baseline that plateau, or that the explicit release step returns. |
| `no_leak` | Retained growth and variation below the floor. |
| `inconclusive` | Fewer than 5 post-warm-up batches, or variation at least as large as the floor without a monotonic trend (noise). |

## 3. Inputs

For every case the suite records a baseline sample (batch 0), one sample after
each batch (taken after the batch dropped its references and ran
`collectGarbage`) and, optionally, one **release** sample (`phase:
"release"`) after the case's release step and one more GC. Channels:

- counters: `nodes`, `listeners`, `timers`, `targets` (live DOM node
  wrappers), `activeRuntimes`; used when every batch sample has them;
- `engineHeap`: QuickJS `JS_ComputeMemoryUsage` (`engine.memoryUsed`), when
  every batch sample has it;
- `rss`: `ProcessInfo.currentRss`, always present.

Counters and the engine heap are **precise** channels. After GC the QuickJS
heap is byte-for-byte reproducible: in the product suite every `js.*` and
`matrix.js.*` case moved 47-975 B in the first batch and then 0 B in every
later batch (quick profile, measured before the classifier was written).
That measurement fixed the 1 KiB/batch engine effect floor.

## 4. Formulas

For one channel, `x[0]` is the baseline, `x[1..N]` the batch samples, and `r`
the release sample (or `x[N]` when the case has none).

- Warm-up: the first `w = 1` batch pays one-time setup. Trend series
  `y = x[w..N]`, `n = N - w + 1` points.
- Per-batch deltas: `d[i] = x[i] - x[i-1]`, `i = 1..N` (recorded).
- Peak: `max(x[0..N], r)`. Retained: `r - x[0]`.
- Trend test: one-sided **Mann-Kendall**, `S = sum_{i<j} sign(y[j] - y[i])`,
  `p = P(S' >= S)` under H0 (no trend).
  - `n <= 9`: exact permutation null, enumerating all `n!` orderings of the
    observed values (ties kept). For 5 strictly increasing points
    `p = 1/120 = 0.00833`.
  - `n >= 10`: normal approximation, tie-corrected variance
    `Var(S) = [n(n-1)(2n+5) - sum_t t(t-1)(2t+5)] / 18` and continuity
    correction `z = (S - 1)/sqrt(Var)`.
- Effect size: **Theil-Sen slope** `b` = median of
  `(y[j] - y[i]) / (j - i)`.
- Tail: `t = y[floor((n-1)/2)..]`, the second half including the middle;
  tail slope `b_t` = Theil-Sen of `t`; tail spread = `max(t) - min(t)`.
- Floor: `F = minSlope * n`, the growth a minimal leak would accumulate
  over the trend window.
- Spread: `max(y) - min(y)`.
- Still growing: `b_t >= 0.5 * b` and `b_t >= minSlope`.
- Returned on release (explicit release only):
  `r - x[0] < 0.5 * (x[N] - x[0])` with `x[N] - x[0] > 0`. The reference
  is the level just before the release step, not the peak (section 7).

Decision, in this order:

1. `n < 5`: `inconclusive` (too few samples).
2. `p < 0.01` and `b >= minSlope` and still growing and not returned:
   `proven_leak`.
3. Returned and `x[N] - x[0] >= F`: `bounded_high_usage`.
4. `p < 0.10` and `b > 0` and `b_t > 0` and `y[n] - y[1] > 0` and not
   returned: `suspected_leak`.
5. `retained >= F` and tail spread `< F`: `bounded_high_usage` (plateau).
6. Spread `>= F`: `inconclusive` (noise).
7. Otherwise `no_leak`.

Case class:

- With at least one precise channel: the most severe precise channel wins
  (`proven_leak` > `suspected_leak` > `inconclusive` >
  `bounded_high_usage` > `no_leak`). RSS is **advisory**: if it would be
  `proven_leak` or `suspected_leak`, the reason says so, but the class does
  not change.
- RSS only: the RSS channel's class, with `proven_leak` capped at
  `suspected_leak`. RSS includes Dart, QuickJS and the allocator; it cannot
  prove a leak.

Criteria (all recorded in `classification.criteria`):

| Parameter | Value |
|---|---|
| `warmupBatches` | 1 |
| `minPoints` | 5 |
| `alpha` (proof) | 0.01 |
| `suspectAlpha` | 0.10 |
| `plateauRatio` | 0.5 |
| `releaseRetainFraction` | 0.5 |
| `minSlopeCount` | 1 per batch |
| `minSlopeEngineBytes` | 1 KiB per batch |
| `minSlopeRssBytes` | 1 MiB per batch |
| `rssOnlyCap` | `suspected_leak` |
| `rssWithPreciseChannels` | `advisory` |

With `alpha = 0.01` the quick profile (5 batches, `n = 5`) can only prove a
strictly increasing series; one tie or one dip prevents proof. Longer
profiles use the normal approximation and tolerate a few non-increases.

## 5. Legacy status and the mapping

`status` is still computed by the legacy rule, unchanged except for the
warm-up fix in section 7, over the batch samples only (the release sample is
ignored). Existing baselines and `compare` keep working. `status` and
`classification.class` are independent fields. They relate like this:

| Legacy rule (expectation `released`) | Possible classes |
|---|---|
| `FAIL`: heap growth > 512 KiB/batch × batches with >= 3 increases, or any counter growth after batch 1 | `proven_leak`; `bounded_high_usage` (a pool that fills after batch 1, `audit.control.bounded_wrapper_pool`); `suspected_leak` |
| `PASS` | `no_leak`; `bounded_high_usage`; also `proven_leak` when the leak is below 512 KiB/batch (`audit.leak.js_global_array`, 82 KiB/batch) |
| `INCONCLUSIVE`: RSS rose with no counter | `suspected_leak` (RSS-only cap), `inconclusive` |
| `SKIP`, `ERROR` | no classification |

For positive controls (`expectation: retained`) `PASS` means "retention was
observed", which corresponds to `proven_leak` (`control.retained`).
Consumers should switch to `classification.class`. A suggested gate is
`proven_leak` = fail, `suspected_leak` = investigate, all other classes =
pass.

## 6. Dataset

`debug/datasets/memory/README.md`, 16 `audit.*` cases in
`lib/src/cases/audit_cases.dart`. Truth was fixed when the cases were
written, before evaluation:

- 7 leaking by construction: retained listeners, retained node wrappers,
  unbounded intervals, a global JS array (82 KiB/batch), a slow JS leak
  (480 B/batch, the known hard case), an RSS-only Dart leak (8 MiB/batch)
  and a leak observed for only 3 batches;
- 9 controls: allocate and release, balanced listeners, cleared timers, an
  LRU cache capped at 2000 entries, a 100-wrapper ring buffer,
  grow-then-release, a one-time warm-up step, seeded noise in the heap and
  seeded noise in RSS.

`expected` follows the evidence policy (RSS-only is at most
`suspected_leak`; under 5 points is `inconclusive`). The construction truth
`leaks` is scored separately.

## 7. Analysis bugs found and fixed

Each fix is its own commit and has a regression test.

1. **Legacy: a warm-up step was a leak** (`ff39b40`). Product run, quick:
   `dom.detached_listeners` went `targets` 2 → 3 in batch 1 and stayed at 3.
   The legacy rule measured counter growth from batch 0 and reported `FAIL`.
   Growth is now measured from batch 1. Product suite: 47 PASS / 1 FAIL
   before, 48 PASS after.
2. **Release compared with the peak** (`ebcd778`). First dataset run:
   `audit.control.noisy_engine` has no release step but was classified
   `bounded_high_usage` "returned on release", because its release value was
   below half of an earlier peak. The release is now compared with the last
   batch.
3. **RSS overrode clean precise channels** (`aaed0bc`). This is a
   **criterion change informed by the dataset**. The first version raised a
   case to `suspected_leak` when its precise channels were clean but RSS met
   the proof criteria. In a fresh process RSS climbs about 1.3 MiB/batch for
   the first cases (allocator and Dart-heap warm-up). In 3 separate-process
   runs, `audit.control.listeners_balanced` was flagged 2 times, and the
   product case `dom.node_churn` was flagged too. Same-process repeats did
   not show it because the process was already warm. RSS is now advisory
   when a precise channel exists. The cost: a native leak that no counter or
   heap channel sees, inside a case that has precise channels, is no longer
   escalated (see limitations).

No other criterion was changed after looking at dataset results. The slow
leak (`audit.leak.js_slow`) was left as a miss, and the floor was not lowered
to catch it.

## 8. Results

Environment: Linux 6.12.90 x86_64 (Intel i7-8700, 12 threads), Dart 3.13.0
JIT, QuickJS-ng 0.17.0. Date 2026-10-26.

Commands (from `debug/engines/memory`, with the final criteria at `aaed0bc`):

```bash
dart run bin/leaks.dart evaluate --profile quick --repeats 3 --out $OUT/eval-quick
for r in 1 2 3 4 5; do
  dart run bin/leaks.dart run --dataset audit --profile quick --json $OUT/sep/r$r.json --out $OUT/sep/r$r
done
dart run bin/leaks.dart evaluate --input $OUT/sep/r1.json ... --input $OUT/sep/r5.json --out $OUT/eval-sep
dart run bin/leaks.dart evaluate --profile full --repeats 3 --out $OUT/eval-full
dart run bin/leaks.dart run --profile quick --json $OUT/product.json --out $OUT/product
```

### 8.1 Summary

| Evaluation | Obs. | Exact class | `proven_leak` precision / recall (vs expected) | Alarm precision / recall (vs `leaks`) | False alarms on controls | Stable cases |
|---|---:|---:|---|---|---:|---:|
| quick, 3 repeats, one process | 48 | 45 (93.8 %) | 100 % / 80.0 % (12/15) | 100 % / 85.7 % (18/21) | 0/27 | 16/16 |
| quick, 5 separate processes | 80 | 75 (93.8 %) | 100 % / 80.0 % (20/25) | 100 % / 85.7 % (30/35) | 0/45 | 16/16 |
| full (20 × 10,000), 3 repeats | 48 | 45 (93.8 %) | 100 % / 80.0 % (12/15) | 100 % / 85.7 % (18/21) | 0/27 | 16/16 |
| Legacy `FAIL`, quick, 3 repeats | 48 | — | — | 75.0 % / 42.9 % (9/21) | 3/27 (11.1 %) | — |

"Alarm" is `proven_leak` or `suspected_leak`. A false alarm is an alarm on a
control (`leaks: false`). `proven_leak` against construction truth: precision
100 %, recall 57.1 %. The 7 leaking cases include the RSS-only and too-few
cases, which by policy cannot be proven.

Before the RSS change, with 3 separate processes: 43/48 exact (89.6 %),
alarm precision 90.0 %, 2/27 false alarms (7.4 %), 15/16 stable cases.
`proven_leak` precision and recall were already 100 % / 80 %.

### 8.2 Confusion matrix (quick, 3 repeats; full and 5-process runs have the same shape)

| expected \ predicted | proven_leak | suspected_leak | inconclusive | bounded_high_usage | no_leak |
|---|---:|---:|---:|---:|---:|
| proven_leak | 12 | 3 | 0 | 0 | 0 |
| suspected_leak | 0 | 3 | 0 | 0 | 0 |
| inconclusive | 0 | 0 | 9 | 0 | 0 |
| bounded_high_usage | 0 | 0 | 0 | 9 | 0 |
| no_leak | 0 | 0 | 0 | 0 | 12 |

The only misses are the 3 observations of `audit.leak.js_slow`. Its 480
B/batch is significant (`p = 0.00833`) but below the 1 KiB/batch floor, so it
is `suspected_leak`.

### 8.3 Per-case values (one quick run)

| Case | Class | MK p | Sen slope / batch | Peak − baseline | Retained after release |
|---|---|---:|---:|---:|---:|
| `audit.leak.listeners_retained` | proven_leak | 0.00833 | 50 listeners | 250 | 250 |
| `audit.leak.wrappers_retained` | proven_leak | 0.00833 | 50 wrappers | 251 | 251 |
| `audit.leak.timers_unbounded` | proven_leak | 0.00833 | 10 timers | 50 | 50 |
| `audit.leak.js_global_array` | proven_leak | 0.00833 | 82.4 KiB | 412.3 KiB | 412.3 KiB |
| `audit.leak.js_slow` | suspected_leak | 0.00833 | 480 B | 2.6 KiB | 2.6 KiB |
| `audit.leak.rss_native` | suspected_leak (RSS cap) | 0.00833 | 8.0 MiB | 37.9 MiB | 37.9 MiB |
| `audit.leak.too_few` | inconclusive | — | — | 247.5 KiB | 247.5 KiB |
| `audit.control.alloc_release` | no_leak | 1.0 | 0 B | 151 B | 151 B |
| `audit.control.listeners_balanced` | no_leak | 1.0 | 0 | 0 | 0 |
| `audit.control.timers_cleared` | no_leak | 1.0 | 0 | 0 | 0 |
| `audit.control.bounded_cache` | bounded_high_usage | 0.05 | 234 B | 415.0 KiB | 415.0 KiB |
| `audit.control.bounded_wrapper_pool` | bounded_high_usage | 0.2 | 0 | 100 | 100 |
| `audit.control.grow_then_release` | bounded_high_usage | 0.00833 | 82.4 KiB | 412.3 KiB | 104 B |
| `audit.control.warmup_step` | no_leak | 1.0 | 0 | 0 | 0 |
| `audit.control.noisy_engine` | inconclusive | 0.958 | −89 KiB | 563.7 KiB | 220.1 KiB |
| `audit.control.noisy_rss` | inconclusive | 0.117 | 9.8 MiB | 98.9 MiB | 89.4 MiB |

For `warmup_step` the reported channel is `nodes` (0). `targets` goes 2 → 4
in batch 1 (the cached element and the `document.body` wrapper) and then
stays at 4. That step falls inside the warm-up batch, so the channel is
`no_leak`.

### 8.4 Product suite (48 cases, quick, final criteria)

All 48 are legacy `PASS`. Classes: 44 `no_leak`, 1 `proven_leak`
(`control.retained`, the positive control, as intended) and 3
`suspected_leak` (`matrix.runtime.stack-4`, `-8`, `-9`). The 3 suspicions
are **RSS-only**: those cases take their batch-0 sample without counters, so
no precise channel exists. Their RSS slopes were 368 KiB, 736 KiB and
1.5 MiB/batch, below proof (or capped). They are reported as suspicions,
not as leaks. The same three were flagged in the run before the RSS change.

### 8.5 Cost

Dataset quick × 3 in one process: 9.9 s wall. Full × 3: 21.8 s wall.
Product quick: about 52 s. The exact Mann-Kendall enumeration is at most
9! = 362,880 orderings per channel.

## 9. Limitations

- The dataset is small (16 cases) and synthetic. 100 % precision means
  0 false positives in 27-45 control observations; it is not a bound for
  real pages.
- Stability was measured over 3 same-process repeats, 5 separate processes
  and 3 full-profile repeats on one machine. Other machines, AOT mode and V8
  are not measured. The suite drives QuickJS-ng only.
- The quick profile can prove only strictly increasing series (`p = 1/120`
  at `n = 5`). A real leak with one flat batch is at most `suspected_leak`
  in quick; use `full`.
- Effect floors are fixed: 1 KiB/batch for the heap, 1 per batch for
  counters, 1 MiB/batch for RSS. Leaks below them (`js_slow`) are only
  suspected. The heap floor was set from product-suite controls, not from
  the dataset.
- When a case has precise channels, RSS is advisory. A native or Dart-side
  leak that no counter or heap channel sees is then reported as the precise
  channels' class, with an RSS note in the reason.
- Counters that are constant by construction (`activeRuntimes: 0` after a
  dispose) look like clean precise channels and suppress RSS. Some product
  cases do this.
- `matrix.runtime.stack-*` take their baseline sample without counters, so
  they are classified from RSS only. That is a case-design gap, not
  classifier behaviour.
- Dart heap, Flutter widgets and image memory are not channels.
- The "release" phase only exists where a case records it (all dataset
  cases, no product cases). For product cases, "retained" means retained
  after each batch's own release and GC.
