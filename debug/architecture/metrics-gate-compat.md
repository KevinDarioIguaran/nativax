# Quality gate and compatibility runners: metrics and validation

This document covers two engines of the debug suite:

- `debug/engines/quality_gate`: compares a visual/performance/compatibility
  snapshot with a baseline;
- `debug/engines/compatibility`: Test262, html5lib, URL, WPT tree construction
  and WPT testharness runners.

It answers sections 9 and 3 of [`engine-inventory.md`](engine-inventory.md):
the gate used fixed tolerances and never checked comparability, and the
runners had never been checked against hand-verified outcomes.

Everything here is deterministic; no model or network is involved.

## 1. Quality gate

### 1.1 Statuses

Each metric gets one status:

| Status | Meaning |
|---|---|
| `improved` | the change is at least the minimum effect, above the noise threshold, in the good direction |
| `regressed` | the same, in the bad direction |
| `unchanged` | the change is smaller than the minimum effect |
| `inconclusive` | the change is at least the minimum effect but inside the noise threshold |
| `not_comparable` | the area's context differs between the runs, or the metric exists in only one of them |

The overall verdict uses this precedence:
`regressed > not_comparable > improved > inconclusive > unchanged`. A
regression in a comparable area is reported even when another area is not
comparable. The gate never claims an improvement while any metric is not
comparable. `inconclusive` metrics are listed but do not block. Without a
baseline the verdict is `no_baseline`.

Exit codes: `0` for unchanged, improved, inconclusive or no baseline, `2` for
regressed, `3` for missing measurements, `4` for not comparable.

### 1.2 Formulas

For one metric with baseline value `b` and current value `a`:

```
delta       = a - b
min_effect  = max(abs_tol, rel_tol * |b|)
se          = sqrt(sd_b^2 / n_b + sd_a^2 / n_a)
noise_thr   = K * se,  K = 3

|delta| <  min_effect                 -> unchanged
|delta| <= noise_thr                  -> inconclusive
sign(delta) agrees with the direction -> improved, otherwise regressed
```

`sd` and `n` come from repeated runs. `--current a.json b.json c.json`
aggregates the runs into their mean and sample standard deviation
(`n - 1` denominator) and stores them in the snapshot's `noise` section, so a
baseline saved from an aggregate carries its noise too. A side with a single
run uses an *assumed* standard deviation, `max(assumed_sd_abs,
assumed_sd_rel * |value|)` with `n = 1`. Assumed values are priors, not
measurements (see §1.6). `K = 3` puts the false-alarm rate near 0.3 % when the
noise is normal and its standard deviation is right.

### 1.3 Per-metric specification (`gate_compare.py`)

| Metric id | Unit | Better | abs_tol | rel_tol | Assumed sd |
|---|---|---|---:|---:|---|
| `visual/{overall,position,layout,color,design}` | pp | higher | 0.5 | — | 0 (deterministic judge) |
| `visual/PASS pages` | pages | higher | 0.5 | — | 0 |
| `visual/FAIL pages` | pages | lower | 0.5 | — | 0 |
| `visual/mismatched %` | pp | lower | 0.1 | — | 0 |
| `visual/ink %` | pp | lower | 1.0 | — | 0 |
| `performance/<scenario>` (scenario + render ms) | ms | lower | 1.0 | 10 % | max(0.5 ms, 5 %) |
| `performance/{PASS,FAIL} scenarios` | scenarios | higher / lower | 0.5 | — | 0 |
| `idle/RSS MB` | MB | lower | 5.0 | — | 2 MB |
| `idle/CPU %` | pp | lower | 0.25 | — | 0.2 pp |
| `compatibility/<suite>/passRate` | pp | higher | 0.01 | — | 0 (deterministic) |
| `compatibility/<suite>/PASS tests` | tests | higher | 0.5 | — | 0 |

A count tolerance of 0.5 means a change of one page, scenario or test counts.
The old `images` metric (the number of PNG files on disk) was dropped because
it measures artifacts, not quality. `mismatched %` and `PASS tests` are new.

### 1.4 Comparability

A snapshot has a `context` section. `global` applies to every area, and each
area adds its own keys:

| Area | Keys |
|---|---|
| `global` | `environment_class` = `<os>-<arch>-<logical cpus>cpu-<cpu model>` |
| `visual` | `catalog_size`, `catalog_digest` (sha256 of the sorted page names, 16 hex), `tool_version`, `reference` (Chrome version), `viewport`, `scheme`, `suites` |
| `performance` | `catalog_size`, `catalog_digest` (scenario ids), `tool_version`, `reference`, `viewport`, `targets`, `command`, `engine` (NativaX engine labels) |
| `idle` | global keys only |
| `compatibility/<suite>` | `total_tests` (sum of the counts), `suiteCommit`, `runnerVersion`, `command`, from the runner summary |

Rule: any key that differs, or that only one side records, makes the whole
area `not_comparable`, and the reason names the key. A key that neither side
records does not block. It is listed as *unverified* in the report, because an
old baseline without context can then still be compared with another old
snapshot. A current run against an old baseline is not comparable, since the
current run records keys the baseline lacks. Rewrite the baseline in that case
(`--write-baseline PATH`).

### 1.5 Outputs

| Flag | Writes |
|---|---|
| (none) | nothing; the report goes to stdout |
| `--out DIR` | `DIR/gate.json`, `DIR/gate.md`, `DIR/snapshot.json` |
| `--write-baseline PATH` | the current snapshot as a baseline at PATH |
| `--legacy-outputs` | the old behavior: `progress/reports/quality-gate-latest.{json,md}`, plus `progress/reports/quality-baseline.json` when it is missing (or with `--save-baseline`) |

`--legacy-outputs` exists only because
`debug/engines/performance/gui/perf_gui.py` still links
`progress/reports/quality-gate-latest.md`. `--baseline` is only read.

### 1.6 Dataset and results

`debug/datasets/quality_gate/build_pairs.py` builds `pairs.json`: 37
baseline/current pairs, all derived from one synthetic baseline. Each pair
applies a known change and records the verdict and metric statuses implied by
that construction. The gate is not run to write them. The pairs cover:

- real changes in each area: visual scores and page counts, mismatched pixels,
  scenario work, scenario verdicts, idle RSS/CPU, compatibility pass rate and
  counts;
- changes below the practical tolerance;
- changes above the tolerance but inside the assumed single-run noise;
- measured noise from three runs per side: a quiet regression, a quiet gain
  and a noisy shift that stays `inconclusive`;
- twelve non-comparable pairs: suite revision, catalog size (`--limit`),
  runner version, command, visual catalog, Chrome reference, environment
  class, engine, viewport, an old baseline without context, a missing metric,
  and a real gain alongside a non-comparable area;
- mixed outcomes, and the no-baseline case.

`evaluate_gate.py` scores verdicts and every metric judgment. A metric with no
listed expectation is expected `unchanged`, or `not_comparable` when its area
is listed as such. The previous `compare()` is kept verbatim in
`legacy_compare.py` and scored on the same pairs. Its statuses map
`equal → unchanged`, `better → improved` and `worse → regressed`. Its
verdicts map `EQUAL → unchanged`, `BETTER → improved`, `WORSE/MIXED → regressed`
and `BASELINE → no_baseline`.

Command and result (2026-10-26):

```
python3 debug/engines/quality_gate/evaluate_gate.py
```

| Gate | Pairs | Verdicts correct | Verdict accuracy | Metric judgments | Metrics correct | Metric accuracy | Metrics it judged | Accuracy on those |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| per-metric (new) | 37 | 37 | 100.0 % | 720 | 720 | 100.0 % | 720 | 100.0 % |
| single tolerance (legacy) | 37 | 16 | 43.2 % | 720 | 538 | 74.7 % | 612 | 87.9 % |

| Expected verdict | Pairs | New correct | Legacy correct |
|---|---:|---:|---:|
| improved | 7 | 7 | 2 |
| inconclusive | 3 | 3 | 0 |
| no_baseline | 1 | 1 | 1 |
| not_comparable | 12 | 12 | 0 |
| regressed | 9 | 9 | 8 |
| unchanged | 5 | 5 | 5 |

| Expected metric status | Judgments | New correct | Legacy correct |
|---|---:|---:|---:|
| improved | 10 | 10 | 5 |
| inconclusive | 4 | 4 | 0 |
| not_comparable | 81 | 81 | 0 |
| regressed | 12 | 12 | 10 |
| unchanged | 613 | 613 | 523 |

"Metrics it judged" excludes metrics a gate gave no status at all. The legacy
gate skips missing metrics and did not track `mismatched %` or `PASS tests`.
Two legacy misses are concrete:

- a 20 → 12 ms scenario (40 % faster) was hidden by the fixed 10 ms tolerance;
- one more Test262 test passing (+0.1 pp) was hidden by the 0.5 pp
  tolerance.

The legacy gate also had no status for non-comparable runs or for changes
within the noise.

Python tests: `python3 debug/engines/quality_gate/test_quality_gate.py` gives
`Ran 21 tests ... OK`. They cover judge and comparability rules,
aggregation, verdict precedence, that `pairs.json` matches `build_pairs.py`,
the dataset score, and outputs. The output tests check that the default and
`--out` runs leave `progress/reports/quality-gate-latest.*` and the baseline
untouched (by mtime).

Real-artifact check: comparing the tracked
`progress/reports/quality-baseline.json` with itself
(`--current progress/reports/quality-baseline.json`) gives `unchanged`, exit
0. Every context key is reported as unverified because that baseline predates
context recording, and no file is written.

### 1.7 Limitations

- **The 100 % is not independent evidence.** The pairs and the rules were
  written by the same author. The score shows that the implementation follows
  the specified rules and handles the cases the legacy gate could not. It
  does not show that the tolerances fit real NativaX run-to-run noise.
- **Assumed noise is a prior.** The 5 % per-run sd for scenario work, 2 MB for
  idle RSS and 0.2 pp for idle CPU were not measured. No `.visual`, `.perf` or
  `.conformance` artifacts exist in this checkout. Calibrate with repeated real
  runs (`--current run1.json run2.json run3.json`) before trusting single-run
  verdicts on noisy metrics.
- **Noise is assumed normal and independent between runs.** Warm caches,
  thermal throttling and background load violate that.
- **The environment class describes the machine running the gate**, not the
  machine that produced reused artifacts. The visual and performance tools do
  not record their host.
- **Multiple comparisons.** About 25 performance scenarios at K = 3 still
  give roughly a 7 % chance per gate run that at least one noisy metric
  crosses the threshold, if the noise priors are right.
- **The engine label comes from the performance results.** There is no
  recorded engine version (V8 build or QuickJS-ng release).

## 2. Compatibility runners

### 2.1 Run metadata and output directory

Every runner and `run_all.dart` accept `--results-dir DIR`. JSONL, summary and
Markdown go to `DIR`, the automatic baseline is looked up there, and the
tracked `progress/reports/<suite>-latest.md` is not touched. The default
(`.conformance/results` plus the tracked latest copy) is unchanged.

Summaries now record:

- `runnerVersion` (`0.2.0`, equal to the package version and checked by a
  test);
- `suiteCommit` for every suite, URL and tree construction included. It is
  the HEAD of the suite directory only when that directory is the top of a
  git checkout, otherwise `null`, so the NativaX commit is never reported as a
  suite revision;
- `startedAt`/`finishedAt` with UTC offset, and `timeZone`.

The automatic baseline now matches the exact suite name. `run_wpt` used to
take the newest `wpt-*` summary, which sorts `wpt-url-*` and
`wpt-html-tree-*` after `wpt-2026…`, so the WPT delta was computed against
another suite.

### 2.2 Validation subset

`debug/datasets/compatibility` contains 57 cases written from scratch, plus a
minimal hand-written Test262 harness (`sta.js`, `assert.js`,
`compareArray.js`). Nothing was copied from the upstream suites. The suites
are not downloaded in this checkout, and `fetch_suites.dart` clones from
GitHub, so it is not offline-safe and was not used. `expected.json` gives each
case's expected status and the reason for it: a spec rule, a deliberately
wrong fixture, or a documented runner policy.

| Suite | Cases | PASS | FAIL | SKIP | ERROR | What is exercised |
|---|---:|---:|---:|---:|---:|---|
| test262 | 18 | 8 | 6 | 3 | 1 | assertions, includes, missing include, parse/runtime negatives, phase mismatch, onlyStrict, noStrict, both-mode runs, raw, async $DONE (ok, error, never), module, host API, TCO |
| html5lib-tokenizer | 12 | 6 | 2 | 3 | 1 | tags, case folding, attributes, self-closing, comments, character references, wrong fixtures, DOCTYPE, initial states, xmlViolation, invalid JSON |
| wpt-url | 8 | 6 | 2 | 0 | 0 | normalization, relative resolution, default port, userinfo, expected failures, wrong fixtures |
| wpt-html-tree | 6 | 3 | 1 | 2 | 0 | implied end tags, adoption agency, implied tbody, wrong tree, script-off, foreign fragment |
| wpt | 13 | 3 | 5 | 5 | 0 | sync/async/promise tests, partial failure, top-level error, async timeout, precondition, reftest, module, testdriver, no tests |

Accuracy for one suite is `correct / cases`, where a case is correct when the
runner's status equals the expected one. A missing result counts as wrong.
Results with no expectation are listed and make the suite imperfect.

Broken adapters are checked against the same expectations. An adapter is
*caught* when it gets wrong at least one case that the real runners get
right. The adapters are:

- five rewrites of the runner output: always PASS, SKIP as PASS, FAIL hidden
  as SKIP, ERROR as FAIL, and failures dropped;
- two damaged harnesses: a Test262 `assert.js` whose assertions never throw,
  and a WPT `test()` that reports PASS without running.

### 2.3 Results

Command (≈16 s; no network):

```
cd debug/engines/compatibility && dart run bin/validate_runners.dart
```

Before the runner fixes (commit `06619ef`):

| Suite | Cases | Correct | Accuracy |
|---|---:|---:|---:|
| test262 | 18 | 13 | 72.2 % |
| html5lib-tokenizer | 12 | 12 | 100.0 % |
| wpt-url | 8 | 8 | 100.0 % |
| wpt-html-tree | 6 | 6 | 100.0 % |
| wpt | 13 | 11 | 84.6 % |
| **all** | 57 | 50 | 87.7 % |

Confusion (expected → reported): PASS→PASS 24, PASS→FAIL 2, FAIL→FAIL 13,
FAIL→PASS 3, SKIP→SKIP 12, SKIP→PASS 1, ERROR→ERROR 1, ERROR→FAIL 1.

The seven wrong cases were runner defects:

| Case | Expected | Reported | Cause |
|---|---|---|---|
| test262 `pass-only-strict.js` | PASS | FAIL | `"use strict"` was written after the host prelude, so it was a plain expression statement, not a directive. Every "strict" run was sloppy. |
| test262 `fail-sloppy-only-without-flag.js` | FAIL | PASS | same cause: the strict run of a `with` statement never failed |
| test262 `pass-raw-strict-directive.js` | PASS | FAIL | raw tests got the prelude prepended, which broke their directive prologue |
| test262 `fail-negative-parse-runtime-throw.js` | FAIL | PASS | a parse-phase negative test was satisfied by a SyntaxError thrown at runtime |
| test262 `error-missing-include.js` | ERROR | FAIL | harness problems were counted as engine FAILs |
| wpt `fail-async-timeout.html` | FAIL | PASS | async tests that never completed were ignored once the reported subtests had passed |
| wpt `skip-precondition.html` | SKIP | PASS | `assert_implements_optional` was a no-op |

After the fixes (commit `f36edfe`, unchanged since):

| Suite | Cases | Correct | Missing | Unexpected | Accuracy |
|---|---:|---:|---:|---:|---:|
| test262 | 18 | 18 | 0 | 0 | 100.0 % |
| html5lib-tokenizer | 12 | 12 | 0 | 0 | 100.0 % |
| wpt-url | 8 | 8 | 0 | 0 | 100.0 % |
| wpt-html-tree | 6 | 6 | 0 | 0 | 100.0 % |
| wpt | 13 | 13 | 0 | 0 | 100.0 % |
| **all** | 57 | 57 | | | 100.0 % |

| Broken adapter | Accuracy | Mismatches | Caught |
|---|---:|---:|---|
| always-pass | 45.6 % | 31 | yes |
| skip-as-pass | 77.2 % | 13 | yes |
| fail-as-skip | 71.9 % | 16 | yes |
| error-as-fail | 96.5 % | 2 | yes |
| drop-failures | 71.9 % | 16 | yes |
| noop-test262-assert | 98.2 % | 1 | yes |
| always-pass-wpt-harness | 94.7 % | 3 | yes |

`dart test` in `debug/engines/compatibility` passes all 21 tests:

- 4 tree-runner tests (existing);
- 10 validation tests: the subset is 100 % correct, all four statuses are
  covered, the seven broken adapters are caught, and missing and unexpected
  results are counted;
- 7 output tests: `--results-dir` touches no tracked file, the default output
  is kept, the summary metadata is written, UTC timestamps keep their `Z`, the
  `wpt` baseline is never another suite's, fixtures inside the repo get no
  suite revision, and the runner version equals the package version.

`dart analyze` reports no issues.

### 2.4 Limitations

- **Small and targeted subset.** The cases were written after reading the
  runner code, to hit known classes of mistakes. 100 % here does not measure
  runner accuracy on the full suites. It shows that these classes are handled.
  The noop-test262-assert adapter changes only one case's status, so the
  subset is weak at detecting a silently broken assertion library.
- **Real suite numbers were not re-measured.** The Test262 strict-mode and
  raw fixes and the WPT timeout and precondition fixes will move the published
  Test262 and WPT pass rates. Some tests that passed only because they ran
  sloppy will fail, and some timed-out WPT files will turn FAIL. Those numbers
  need a run with the downloaded suites and must be reported as a runner
  correction, not a compatibility gain. `runnerVersion` changed to 0.2.0 so
  the quality gate treats old and new summaries as not comparable.
- **Product expectations.** The PASS expectations for html5lib, URL, tree
  construction and the DOM cases rely on NativaX implementing those basic
  behaviors. If a PASS case failed, the cause would have to be checked by hand
  before deciding whether the runner or the product is wrong.
- **Raw tests and phases.** A raw negative test cannot carry the
  parse-success marker, so for raw tests the phase is not verified, only the
  error type.
- **WPT policy.** A file with no subtests is SKIP. Real `testharness.js`
  reports it as OK with no subtests, which counts as neither pass nor fail.
- **No upstream harness.** The Test262 harness in the subset is minimal and
  hand-written. Behavior that depends on upstream `assert.js` details is not
  exercised.
