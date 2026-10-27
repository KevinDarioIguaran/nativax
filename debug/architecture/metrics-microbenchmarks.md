# Microbenchmark comparator and report search: measured accuracy

## Part A — microbenchmark comparator

Scope: `compareRuns` in `debug/engines/microbenchmarks/lib/src/runner.dart`,
the function behind `bin/benchmark.dart compare`. It labels every benchmark
`regression`, `improvement` or `noise`. A change counts only when it exceeds
`max(threshold, noise × multiplier)`; the defaults are 10 % and 2.

### A.1 Synthetic samples with a known change

`dart run tool/audit_comparator.dart` writes
[`debug/datasets/microbenchmarks/audit.json`](../datasets/microbenchmarks/audit.json).

**Setup:**

- Base 10 ms, 15 rounds, log-normal noise with coefficient of variation
  1/3/5/10/20 %, from a fixed LCG seed.
- 13 true changes from −50 % to +50 %, 200 trials per cell.
- **Truth:** a change above 10 % must be reported with its sign, and a change
  of at most 5 % must be `noise`. Cells at ±10 % are not scored.

| Measure | Result |
|---|---|
| False alarms (true change ≤ 5 %) | **0.7 %** (21/3000) |
| Real changes detected (> 10 %) | 85.6 % (6845/8000) |
| Sign errors | 0 |

Correct rate per cell, in %:

| Noise CV | −50 | −30 | −20 | −15 | −5 | 0 | +5 | +15 | +20 | +30 | +50 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 % | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |
| 3 % | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |
| 5 % | 100 | 100 | 100 | 100 | 100 | 100 | 98 | 97 | 100 | 100 | 100 |
| 10 % | 100 | 99 | 86 | 49 | 99 | 100 | 96 | 52 | 79 | 99 | 100 |
| 20 % | 100 | 53 | 17 | 8 | 100 | 100 | 98 | 15 | 26 | 56 | 91 |

With noise of 10 % or more, the comparator says `noise` rather than claim a
change, so a 15–20 % real change is often missed. This is the intended
direction: it favours no false claims over detecting every change.

### A.2 Real runs of the same commit (A/A)

Synthetic noise is independent within one run. Real machines also drift
**between** runs: CPU frequency, cache and background load. To measure that,
the full suite (35 benchmarks, `--warmup 3 --rounds 15`) was run on one
commit with nothing else running. Linux 6.12 x86_64, i7-8700, Dart 3.13 JIT,
QuickJS-ng 0.17.0, 2026-10-26. Every reported change below is a false alarm.

| Comparison | Comparisons | Labelled regression/improvement |
|---|---:|---:|
| 1 baseline vs 1 run (4 pairs) | 140 | **17 (12.1 %)** |
| 3 baselines vs the 4th run (leave-one-out, 4 rounds) | 140 | **8 (5.7 %)** |

Two earlier runs that overlapped a Chromium benchmark on the same machine
were discarded. Against clean runs they showed 19–30 of 35 benchmarks as
"improved". Concurrent load invalidates every comparison.

**Change made from this result:**

- `compare` accepts `--baseline` more than once.
- With several baselines, the reference is the median of their medians.
- Noise also includes the run-to-run spread, `(max − min) / median` of the
  baseline medians.
- With one baseline, the CLI prints a warning that run-to-run noise is not
  measured.

This halves the false alarms on the A/A data, but 5.7 % remain. The
remaining false regressions are all 10–20 % on JS benchmarks of 15–70 ms,
which drifted together in two of the four runs.

**How to read a microbenchmark regression:** it is evidence only when it
appears against at least 3 baseline runs of the same commit, taken with no
other load. One A/B pair is not evidence.

### A.3 Limitations

- One machine; four clean runs are too few to estimate a stable false-alarm
  rate.
- Only QuickJS-ng was measured (`libnx_v8.so` was not built).
- The synthetic noise is log-normal and independent; real noise is not.

## Part B — report search

Scope: `catalog.search` in `debug/logic/catalog.py`, the search box of the
Debug Suite explorer. It is an AND of case-insensitive substrings over id,
type, area, engine, commit, summary, status, path and errors.

`python3 debug/logic/search_audit.py` builds a fixed corpus of 240 report
refs and runs 15 queries. Their expected results come from the fields they
name, not from the search. The output is
[`debug/datasets/search/audit.json`](../datasets/search/audit.json).

| Query class | Before | After |
|---|---|---|
| exact id, other case, id prefix, run number | P 1.0 / R 1.0 | P 1.0 / R 1.0 |
| area, type, commit, engine, path, error text | P 1.0 / R 1.0 | P 1.0 / R 1.0 |
| two terms (AND) | P 1.0 / R 1.0 | P 1.0 / R 1.0 |
| no match, empty query | correct | correct |
| **one-letter typo** (`lekas`, `97d0f91`) | **R 0.0** | **R 1.0, P 1.0** |

**Change made:** a term of 4 or more characters that matches **no** report
falls back to words at Damerau distance 1 (one insertion, deletion,
substitution or adjacent swap). Exact terms never widen. For example, `leak`
still returns only `leaks` reports. The test is
`debug/logic/test_search_audit.py`.

**Limitations:**

- The corpus is synthetic.
- Ranking is not measured, because results are ordered newest first and
  not by relevance.
- Typos of 2 or more letters are not found.
