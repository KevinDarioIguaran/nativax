# Recommendation engine metrics

How the deterministic recommendation engine
(`debug/engines/recommendations/recommend.py`) is evaluated, and the measured
results before and after the rule fixes found by that evaluation.

## What a recommendation is now

Every `Recommendation` has:

| Field | Meaning |
|---|---|
| `id` | Stable rule id from `RULES` (e.g. `memory.idle.over_target`). The title can embed numbers; the id never does, so a recommendation can be tracked across runs. |
| `rule` | The condition that fired, as data: `logic` (`all`/`any`), `conditions` (`metric`, `op`, `threshold`, `observed`), an optional per-subject `criterion`, and `subjects` (`perf:<scenario>`, `visual:<page>`, `leak:<case>`, `security:<case>`). |
| `expected_impact` | Which metric should move, in which direction (`decrease`, `increase`, `measure`, `become_true`) and to what target. |
| `measured_impact` | `null` unless `build_recommendations(data, before=...)` gets an earlier snapshot. Then `measure()` reads both snapshots and each expected metric is marked `improved`, `regressed`, `unchanged`, `newly_measured`, `still_unmeasured`, or `inconclusive` when either side lacks the metric. |

`audit(recommendations)` reports, deterministically:

- **duplicates**: the same id twice, or two rules citing the same subject;
- **contradictions**: two rules `RULES` declares exclusive firing together,
  opposite fix-first `ordering` claims (A before B and B before A), or the
  same metric observed with two different values.

All engine output is English. Field names are unchanged, and
`perf_gui.py` still calls the same `load_latest_run` and `build_markdown`
functions.

## Dataset

`debug/datasets/recommendations/` has 46 hand-written cases, one JSON file
each, grouped into missing data, empty catalogs, everything passing,
coverage, idle memory, leaks, security, malformed input, DOM, scroll/JS/games,
cross-signal/visual, capabilities and conflicting signals. Every threshold
has a case just at the boundary and, where it matters, one just past it.

Each case lists the **complete** set of `expected` ids, the `must_not` ids
(in this dataset every other rule id) and optionally `expected_priorities`.
The ground truth comes from the rule intents and thresholds in the dataset
README (rows R1–R18 and principles G1–G5), not from engine output. The
dataset was committed (`84fb38f`) before any rule fix, so the baseline
below is the unchanged engine scored against it.

## Formulas

For each case: `F` = fired ids, `E` = expected ids, `N` = must-not ids.

- TP = |F ∩ E|, FP = |F \ E|, FN = |E \ F|, must-not hits = |F ∩ N|
- Per rule *r*: counts summed over cases where *r* is in that set;
  precision(r) = TP / (TP + FP), recall(r) = TP / (TP + FN); `n/a` when the
  denominator is 0.
- Micro precision and recall use the same formulas on counts summed over
  all rules and cases.
- A case passes only with FN = FP = must-not hits = 0, no priority
  mismatch, no engine error, no duplicate and no contradiction.

Because `must_not` is complete here, every FP is also a must-not hit.

## Results

Command (from the repository root):

```bash
python3 debug/engines/recommendations/evaluate.py
```

### Progression

Every row is the current evaluator and dataset run against the
`recommend.py` of that commit.

| Commit | Change | Cases passed | Precision | Recall | TP | FP | FN | Must-not | Errors | Dup. | Contr. |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `84fb38f` | baseline (ids + English, rules unchanged) | 32/46 | 0.835 | 0.950 | 76 | 15 | 4 | 15 | 1 | 1 | 1 |
| `896dca0` | skip malformed result entries | 33/46 | 0.839 | 0.975 | 78 | 15 | 2 | 15 | 0 | 1 | 1 |
| `94ebff5` | unmeasured visual score is not 0 % | 41/46 | 0.951 | 0.975 | 78 | 4 | 2 | 4 | 0 | 1 | 1 |
| `d460a40` | cross-signal requires failing DOM | 42/46 | 0.963 | 0.975 | 78 | 3 | 2 | 3 | 0 | 1 | 1 |
| `f5e07f7` | game profiles tagged `kind: dom` leave the DOM rule | 43/46 | 0.987 | 0.975 | 78 | 1 | 2 | 1 | 0 | 0 | 1 |
| `918bb7f` | judge `game3d.` profiles from the perf run | 44/46 | 0.988 | 0.988 | 79 | 1 | 1 | 1 | 0 | 0 | 1 |
| `4801774` | idle ok without RSS/CPU is unmeasured | 45/46 | 1.000 | 1.000 | 80 | 0 | 0 | 0 | 0 | 0 | 1 |
| `84f5449` | color and position agree on fix-first order | 46/46 | 1.000 | 1.000 | 80 | 0 | 0 | 0 | 0 | 0 | 0 |

### Baseline per rule (`84fb38f`)

Only rules with findings are listed; the other 12 had precision and recall
1.000.

| Rule | TP | FP | FN | Precision | Recall | Cause |
|---|---:|---:|---:|---:|---:|---|
| `renderer.dom_layout.cross_signal` | 2 | 11 | 0 | 0.154 | 1.000 | an unmeasured layout/position mean was 0.0 %, and any comparable DOM row (passing ones included) counted as a DOM failure |
| `perf.dom.over_target` | 7 | 2 | 0 | 0.778 | 1.000 | `game.`/`game3d.` profiles are `kind: dom` in `scenarios.json` and were restated as DOM cost |
| `visual.color.low` | 2 | 1 | 0 | 0.667 | 1.000 | rows without a color score averaged to 0.0 % |
| `memory.load_peak.unmeasured` | 38 | 1 | 1 | 0.974 | 0.974 | `status: ok` without RSS/CPU read as 0 MB / 0 % ("idle meets the budget"); one miss from the malformed-input crash |
| `memory.idle.unmeasured` | 2 | 0 | 1 | 1.000 | 0.667 | same idle case: should have said "unmeasured" |
| `perf.game.over_target` | 2 | 0 | 1 | 1.000 | 0.667 | `game3d.` rows of the perf run were never read |
| `leaks.cases.failing` | 3 | 0 | 1 | 1.000 | 0.750 | a non-object entry in a result list crashed the engine (`AttributeError`) |

Duplicate: `perf.dom.over_target` + `perf.game.over_target` on the same game
scenario. Contradiction: `visual.position.low` ("fix layout before color")
vs `visual.color.low` ("before touching layout").

### After the fixes (`84f5449`)

46/46 cases, micro precision 1.000, micro recall 1.000 (TP 80, FP 0, FN 0),
0 must-not hits, 0 priority mismatches, 0 errors, 0 duplicates, 0
contradictions. Each fix is its own commit with a regression test in
`test_recommend.py` and a dataset case. `test_evaluate.py` keeps the whole
dataset clean.

## Measured impact

**Measured impact is inconclusive.** No before/after runs of the real app
exist for any recommendation, so none of them has a measured effect on its
metric. `measured_impact` is `null` in every report until two real
snapshots (for example two `.perf/latest` + `app-idle.json` runs, one before
and one after acting on a recommendation) go through
`build_recommendations(after, before=before)`. The dataset scores which rules
fire, not whether acting on them improves NativaX.

## Limits

- The same author wrote the rule intents, the cases and the fixes. The
  dataset was committed before the fixes, but a 1.000 score on 46 synthetic
  cases only shows the rules match their documented intent. It does not
  show the advice is good.
- The cases are small and synthetic, and none comes from a real run
  (`.visual/` and `.perf/` were absent in this checkout).
- Text quality (wording, evidence lines, commands) is not scored.
- One rule text is stale and is not changed here: `perf.js.over_target`
  still suggests evaluating V8 on desktop, but V8 is already the desktop
  default in `AGENTS.md`.

## Reproduce

```bash
python3 debug/engines/recommendations/test_recommend.py
python3 debug/engines/recommendations/test_evaluate.py
python3 debug/engines/recommendations/evaluate.py          # exit 0 only when every case passes
python3 debug/engines/recommendations/evaluate.py --json   # full per-case report
```
