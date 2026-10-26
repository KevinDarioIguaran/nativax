# Engine inventory

One entry per diagnostic engine found in the repository at commit `f5151e9`.
"Defects" lists problems verified in the code or in real runs. "Untested"
lists behaviour that no existing test exercises. Measured accuracy results
are recorded in `metrics.md` once the audits in phase 7 have run. Nothing is
claimed here without that evidence.

## 1. Visual comparison — `tools/visual` → `debug/engines/visual_comparison`

- **Purpose:** decide whether NativaX renders a page like headless Chromium.
- **Implementation:**
  - the same staged page runs in both engines;
  - a JS probe (`probe.dart`) collects rects and 27 computed styles;
  - `pixels.dart` computes a full-viewport CIE76 ΔE, ink mismatch, worst
    tiles and `diff.png`;
  - `score.dart` produces position, layout, color, design and overall
    scores and a strict verdict.
- **Inputs:** page directories (vendored 50projects50days, MDN, Odin
  catalog), viewport, scheme, setup JS.
- **Outputs:** `results.json`, `report.json`, `report.md`, and per-page
  `chrome.png`, `nativax.png`, `diff.png`, probes, `elements.json`, CSV files.
- **Dependencies and assumptions:**
  - Google Chrome is installed;
  - the system fonts aliased identically in the harness;
  - animations are frozen;
  - a calibration offset for `--dump-dom` vs `--screenshot` is applied.
- **Tests:** 77, covering formulas, PNG codec, staging, the Chrome e2e
  viewport and `--self-check` (Chromium vs Chromium must be 100/PASS).
- **Defects:**
  - output overwrites `.visual/latest`;
  - there is no overlay image and no region list (only 12 worst 16×16
    tiles);
  - capture timestamps are not recorded with a timezone.
- **Untested:**
  - detection on image pairs with known differences;
  - localization accuracy;
  - threshold sensitivity;
  - repeat-capture variance on real pages beyond the self-check.
- **Validation strategy:**
  - a deterministic synthetic image-pair dataset with ground-truth regions;
  - repeated Chromium captures for noise.

## 2. Performance — `tools/perf` → `debug/engines/performance`

- **Purpose:** compare the work and frame cost of NativaX against Chromium
  (CDP) on the same scenarios; measure app idle RSS/CPU.
- **Implementation:** a scenario catalog (`scenarios.dart`, `externals.dart`;
  245 entries); `nativa_engine.dart` (perf probe harness); `chrome_engine.dart`
  (CDP); `/proc` sampler; `evaluate.dart` (PASS/WARN/FAIL/INVALID from
  targets).
- **Outputs:** `results.json`, CSV, `report.md`, `timeline.csv`,
  `app-idle.json`, SVG charts, and the container `matrix.json`.
- **Tests:** 15 (CDP e2e, evaluation, report).
- **Defects:**
  - `.perf/latest` is overwritten;
  - the verdict uses fixed targets with no repetition variance, so one
    noisy run can flip it;
  - the hardware, build mode and repetition count of a run are only
    partially recorded.
- **Untested:** the comparator's ability to detect real shifts under noise.
- **Validation strategy:**
  - synthetic distributions with known shifts through the comparator;
  - repeated real runs for variance.

## 3. Compatibility — `tools/conformance` → `debug/engines/compatibility`

- **Purpose:** pass rates on Test262, html5lib, URL, WPT DOM/CSS/tree.
- **Outputs:** `.conformance/results/<suite>-<ts>.{jsonl,md,summary.json}`.
- **Tests:** 4 (tree runner).
- **Defects:** a flat results folder; Spanish README and reports.
- **Untested:**
  - runner correctness against hand-verified expectations, i.e. whether a
    PASS is a real pass and whether a harness failure is counted as SKIP or
    FAIL.
- **Validation strategy:**
  - a small committed subset with expected outcomes verified by hand;
  - deliberately broken adapters must change the outcome.

## 4. Memory — `tools/leaks` → `debug/engines/memory`

- **Purpose:**
  - detect sustained memory growth;
  - detect orphan listeners, pending timers and retained wrappers.
- **Implementation:**
  - cases in `cases/*.dart`;
  - batches with per-batch samples;
  - `analysis.dart` classifies cases as PASS/FAIL/SKIP/ERROR/INCONCLUSIVE;
  - `compare.dart` compares two runs.
- **Outputs:** `benchmarks/leaks/*.{json,jsonl,md}` plus `baseline`/`current`.
- **Tests:** 10 (analysis, report).
- **Defects:**
  - the result model does not separate a proven leak (monotonic retained
    growth after release) from a suspicion or a workload that legitimately
    holds more memory; FAIL covers all of them.
- **Untested:** synthetic leaking vs non-leaking workloads with known truth.
- **Validation strategy:**
  - injected leaking cases (retain listeners, retain wrappers);
  - control cases that allocate and release.

## 5. Security — `tools/security` → `debug/engines/security`

- **Purpose:** probe the JS–Dart bridge and host APIs with attack cases.
- **Outputs:** `benchmarks/security/*`.
- **Tests:** 4.
- **Known result (README):** 13 PASS, 1 FAIL (`internal.callback_globals`
  exposes `__nx_*` on `globalThis`), 1 SKIP.
- **Validation strategy:**
  - each case must fail against a deliberately weakened fixture
    (mutation check), so a PASS means the attack was actually exercised.

## 6. Micro-benchmarks — `tools/benchmark` → `debug/engines/microbenchmarks`

- **Purpose:** warm-up and rounds over the JS engine, bridge, DOM, style
  recalculation and a native Dart reference.
- **Outputs:** `benchmarks/results/bench-<ts>.{json,md}`; some baselines are
  tracked.
- **Tests:** 10.
- **Validation strategy:** variance across repeated runs; the comparison
  uses confidence intervals, not single means.

## 7. Bug detection (JSON interface audit) — `tools/audit/nxaudit` → `debug/engines/bug_detection`

- **Purpose:** discover rendering, layout, style, event, focus, state and
  lifecycle defects through generated JSON screens run differentially in
  NativaX and Chromium.
- **Implementation:**
  - 9 generator families and a schema validator;
  - batch executors;
  - 12 oracles with first-divergence localization;
  - fingerprint clustering;
  - re-execution, combined-unit minimization, rule-based diagnosis;
  - a selection log.
- **Real results (400 scenarios, seed 2):**
  - 145 unique issues, 145/145 reproducible, 8 minimized;
  - 2 critical crashes minimized to 7 units: NX-77A5FFB5 (textarea in an
    absolutely positioned form → InputDecorator unbounded width) and
    NX-7874C149 (select with `overflow:auto; white-space:pre` in
    column → grid → RenderFlex unbounded width);
  - 40/40 deliberate negatives rejected.
- **Tests:** 27 (engine) + 10 (GUI).
- **Benchmark:**
  - in the first run, 37/37 injected faults were detected and 36/37 were
    localized, with 0 findings in 23 clean scenarios;
  - the scoring then changed so that injected crashes, which carry no
    element, are excluded from the localization denominator;
  - the benchmark must be re-run after the move.
- **Defects fixed during development:**
  - crash fingerprints included instance ids and stack depth;
  - crash cascades were counted as separate issues;
  - duplicate scenarios were admitted into one batch;
  - the minimizer removed one unit per round.
- **Open issues:**
  - Chromium reference interactions are synthetic events plus a Tab model;
  - `change`/`keydown` are not compared;
  - there is no pixel oracle.
- **Validation strategy:**
  - the extended fault set plus real minimized defects as known positives;
  - identical-engine and look-alike negatives;
  - metrics: precision/recall/F1 per category.

## 8. Recommendations — `tools/recommend.py` → `debug/engines/recommendations`

- **Purpose:** P0/P1/P2 actions derived from measured data (visual, perf,
  idle, leaks, security, coverage).
- **Implementation:** deterministic rules in `build_recommendations()`;
  `Recommendation` carries priority, area, title, evidence, action,
  acceptance, confidence and commands.
- **Tests:** 9.
- **Defects:**
  - no stable recommendation id: identity is the title text, which embeds
    numbers, so a recommendation cannot be tracked across runs or evaluated;
  - the output is in Spanish;
  - there is no slot for measured impact.
- **Untested:**
  - relevance, missed and harmful recommendations, and contradictions
    across rules.
- **Validation strategy:**
  - committed input cases with expected and must-not recommendation ids;
  - measured impact only where before/after runs exist.

## 9. Quality gate — `tools/quality_gate.py` → `debug/engines/quality_gate`

- **Purpose:** compare a visual/perf/compat snapshot with
  `progress/reports/quality-baseline.json` and give a verdict.
- **Defects:**
  - `compare()` uses one absolute tolerance (0.5) for every metric
    regardless of its unit and noise;
  - it does not check that the baseline and the current run are comparable
    (suite size, environment, engine version).
- **Validation strategy:**
  - constructed snapshot pairs with known expected verdicts, including
    non-comparable pairs.

## 10. History — `tools/history.py` → `debug/logic` (replaced by storage + comparison service)

- **Purpose:** immutable snapshots of results tables and previous-run deltas.
- **Defects:**
  - only tables are stored, not evidence;
  - "previous" means the newest file, not a compatible run.

## 11. Search, filter, sort — `tools/audit/gui/store.py` → `debug/logic`

- **Purpose:** report discovery, per-report rows, global search, comparison.
- **Untested:**
  - ranking (results are unranked, in discovery order);
  - typos; recall on large corpora.
- **Validation strategy:**
  - a fixed report corpus with labelled relevant results per query;
  - recall@k and precision@k;
  - filter and sort correctness against brute force.

## Supporting tools (not engines)

| Tool | Destination | Reason |
|---|---|---|
| `tools/render_report.py`, `tools/preview_report.sh` | `debug/scripts/` | report presentation |
| `tools/quality_report.sh` | `debug/scripts/` | orchestrates engines |
| `tools/perf/container/` | `debug/engines/performance/container/` | perf under quotas |
| `tools/summarize_metrics.py`, `tools/bench_game_player.sh` | `debug/engines/performance/game_player/` | game-player JSONL metrics |
| `tools/mirror/` | `debug/engines/visual_comparison/mirror/` | predecessor of the judge; source of `fidelity_test.dart` expectations |
| harness tests in `examples/web-challenge/test/` | `debug/harness/` | diagnostic harness, not part of the example |
| `tools/test_all.sh`, `tools/test_architecture.py`, `tools/analyze_app.py`, `tools/check_purity.py`, `tools/v8-spike/`, `tools/video_profiles.json`, `tools/run_video_contract.py`, `tools/test_video_manifest.py` | stay in `tools/` | repository-wide checks or runtime spikes |
