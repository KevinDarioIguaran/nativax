# Recommendation evaluation dataset

Committed input cases for the deterministic recommendation engine
(`debug/engines/recommendations/recommend.py`). The evaluator
(`debug/engines/recommendations/evaluate.py`) runs the engine on every case
and scores the emitted rule ids against the ground truth written here.

## Where the ground truth comes from

The expected ids were written by hand from the documented threshold and intent
of each rule (the table below), **not** by running the engine. Where the
engine and this table disagree, the evaluator reports it; a fix to the engine
is only made when the table states the intent, and each fix gets its own
regression test.

General principles every case follows:

- **G1. Missing data is reported as missing.** A missing file, list or number
  never produces a failure *or* a pass. Unknown capabilities make no claim.
- **G2. Malformed entries are ignored.** A non-object entry in a result list
  is skipped; it never crashes the engine.
- **G3. Comparable measurements only.** Performance rules judge rows where
  both NativaX and Chromium report `status: ok`; errors stay in the detail
  table.
- **G4. One rule per subject.** A scenario, page or case is the subject of at
  most one rule of the same kind; aggregates (coverage, cross-signal) cite no
  per-row subjects.
- **G5. No opposite orders.** Two recommendations that fire together must not
  tell the reader to fix A before B and B before A.

## Rule intents (ground truth)

| # | Rule id | Priority | Fires when | Boundary |
|---|---|---|---|---|
| R1 | `visual.coverage.missing_pages` | P2 | measured visual rows < visual catalog size (catalog empty → total is the row count) | equal or more rows → no |
| R2 | `perf.coverage.missing_scenarios` | P2 | measured perf rows < perf catalog size | equal → no |
| R3 | `memory.idle.unmeasured` | P1 | `app_idle` missing, status ≠ `ok`, or RSS/CPU not numeric (G1) | — |
| R4 | `memory.idle.over_target` | P0 | idle measured and RSS > 250 MB **or** CPU > 1 % | 250 MB / 1 % exactly → no (acceptance is ≤) |
| R5 | `memory.load_peak.unmeasured` | P2 | idle measured and RSS ≤ 250 MB and CPU ≤ 1 % (the peak under load has no producer yet) | — |
| R6 | `leaks.cases.failing` | P0 | any leak case status FAIL or ERROR (case-insensitive) | — |
| R7 | `leaks.cases.inconclusive` | P2 | no FAIL/ERROR and any INCONCLUSIVE; exclusive with R6 | — |
| R8 | `capability.video.no_playback` | P1 | `capabilities.video` is `false` | missing → no claim |
| R9 | `capability.game_player.unmeasured` | P2 | `capabilities.game_player` is `false` | missing → no claim |
| R10 | `security.checks.failing` | P0 | any security check FAIL or ERROR; SKIP is not a failure | — |
| R11 | `perf.dom.over_target` | P1 | any comparable `kind: dom` row with verdict FAIL/WARN or work ratio > 3, excluding `game.`/`game3d.` scenarios (owned by R14, G4) | ratio 3.0 → no |
| R12 | `perf.scroll.frame_p95_over_target` | P1 | any comparable scroll row with NativaX frame p95 > 16.7 ms | 16.7 → no; no p95 → no |
| R13 | `perf.js.over_target` | P1 | any comparable `kind: js` row with verdict FAIL/WARN or ratio > 3 | ratio 3.0 → no |
| R14 | `perf.game.over_target` | P1 | any comparable `game.` or `game3d.` scenario (perf run or game batches) with verdict FAIL/WARN or ratio > 3 | ratio 3.0 → no |
| R15 | `renderer.dom_layout.cross_signal` | P0 if layout < 70, else P1 | R11 fires **and** measured mean visual layout < 90 **and** measured mean position < 90 | layout 90 → no; layout 70 → P1 |
| R16 | `visual.position.low` | P1 | any visual row with measured position < 70 | 70 → no |
| R17 | `visual.ink.missing` | P1 | no row with position < 70 and any row with ink mismatch ≥ 80 %; exclusive with R16 | 80 → yes |
| R18 | `visual.color.low` | P1 | measured mean color < 60 | 60 → no; no color values → no |

Thresholds come from the acceptance criteria each rule prints (idle ≤250 MB
and ≤1 % CPU, frame p95 ≤16.7 ms, ≤3× Chromium work, position ≥90 % and ink
<50 % as the goal with < 70 / ≥ 80 as the "clearly bad" trigger, color
≥90 % as the goal with < 60 as the trigger).

## Case format

One JSON file per case in `cases/`:

```json
{
  "id": "idle_at_threshold",
  "description": "RSS exactly 250 MB and CPU exactly 1 %.",
  "grounds": ["R4 uses strict >: ..."],
  "input": { "app_idle": { "status": "ok", "rss_tail_mb": 250, "cpu_tail_pct": 1.0 } },
  "expected": ["memory.load_peak.unmeasured"],
  "must_not": ["memory.idle.over_target", "..."],
  "expected_priorities": {}
}
```

- `input` has the same shape `build_recommendations()` receives (`visual`,
  `visual_catalog`, `perf`, `perf_catalog`, `game`, `game3d`, `app_idle`,
  `leaks`, `security`, `capabilities`).
- `expected` is the **complete** set of ids that should fire.
- `must_not` lists ids that would be invalid or harmful here. In this dataset
  it is every other rule id, so any extra id is both a false positive and a
  must-not hit.
- `expected_priorities` optionally pins the priority of an expected id.
- `grounds` cites the rule rows above that justify the expectation.

## Cases (46)

| Group | Cases |
|---|---|
| Missing / empty / passing | `missing_all_data`, `empty_catalogs_and_rows`, `all_passing` |
| Coverage | `visual_coverage_gap`, `visual_rows_exceed_catalog`, `visual_catalog_without_rows`, `perf_coverage_gap` |
| Idle memory | `idle_status_error`, `idle_rss_over`, `idle_cpu_over`, `idle_at_threshold`, `idle_just_over_threshold`, `idle_ok_without_numbers` |
| Leaks | `leaks_fail`, `leaks_error_and_inconclusive`, `leaks_inconclusive_only`, `leaks_lowercase_status` |
| Security | `security_fail`, `security_skip_only` |
| Malformed input | `malformed_rows` |
| DOM | `dom_over_ratio_without_visual`, `dom_ratio_at_threshold`, `dom_ratio_just_over`, `dom_warn_low_ratio`, `dom_engine_error`, `chromium_zero_work` |
| Scroll / JS / games | `scroll_p95_over`, `scroll_p95_at_threshold`, `scroll_p95_missing`, `js_over`, `game_kind_dom_in_perf`, `game3d_in_perf`, `game_batch_payload` |
| Cross-signal / visual | `cross_signal_p0`, `cross_signal_layout_at_70`, `cross_signal_layout_at_90`, `cross_signal_dom_passing`, `visual_position_and_ink`, `visual_ink_only`, `visual_boundaries`, `visual_color_low`, `visual_color_at_60`, `visual_rows_without_metrics`, `visual_position_and_color_low` |
| Capabilities / conflicts | `capabilities_false`, `conflicting_signals` |

## Limits

- The inputs are synthetic and small; they test rule logic, not whether a
  recommendation is the best engineering advice for a real run.
- Measured impact is not evaluated here: it needs before/after runs of the
  real app, which this dataset does not contain.
