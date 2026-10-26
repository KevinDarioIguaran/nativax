# NativaX JSON interface audit

Generates JSON interface scenarios, runs each one in **NativaX** (the system
under test) and in **headless Chromium** (the reference), compares them with
oracles that isolate the pipeline stage, groups the divergences into issues,
re-runs them, minimizes them, and writes one report per issue that another
LLM can act on without guessing.

NativaX has no JSON screen format of its own: it renders HTML/CSS/JS. An
audit screen is a JSON component tree that `nxaudit/compile.py` lowers to a
real HTML document; every element carries `id`, `data-nx` (its JSON path, e.g.
`screen.children[0].children[1]`) and `data-nx-type`, so every measurement maps
back to the exact JSON node.

```bash
python3 tools/audit/audit.py run --budget 400 --batch 50 --seed 2   # real audit
python3 tools/audit/audit.py benchmark --budget 120                 # deliberate faults
python3 tools/audit/audit.py self-check --budget 80                 # Chromium vs Chromium
python3 tools/audit/audit.py reanalyze .audit/runs/<run>            # oracles only, no execution
python3 tools/audit/audit.py replay  .audit/latest/issues/NX-XXXXXXXX.json
python3 tools/audit/audit.py verify  NX-XXXXXXXX                    # after a fix
python3 tools/audit/audit.py promote NX-XXXXXXXX                    # minimal case -> regressions/
python3 tools/audit/audit.py generate --family random --count 20 --out /tmp/s
python3 tools/audit/audit.py validate /tmp/s/*.json
python3 tools/audit/audit.py html scenario.json                     # compiled HTML
python3 tools/audit/audit.py catalog                                # nativa_css support check
python3 tools/audit/test_audit.py                                   # engine tests (no browser)
python3 tools/audit/gui/app.py                                      # visual explorer (see gui/README.md)
```

The Tkinter panel (`tools/perf/gui/perf_gui.py`) has an **Auditoría JSON**
page (run, fault benchmark, self-check, issue table, LLM brief, replay /
verify / promote from the row menu) and the reports **Auditoría JSON**,
**Auditoría · fallos inyectados** and **Auditoría · self-check**, separate from
the performance, visual and games reports.

## Pipeline

| Step | Module | What it does |
|---|---|---|
| Catalog | `catalog.py` | 21 component types (20 executable) lowered to real HTML, 49 CSS properties with `valid`/`boundary`/`invalid` value domains, 7 actions. `css_support()` asks `nativa_css.isSupportedProperty` through `dart/css_support.dart`. |
| Generation | `generate.py` | Families `basic`, `combinatorial` (greedy pairwise covering array, 12 factors), `random` (seeded trees), `adversarial` (depth, width, huge/Unicode text, boundary values, tiny viewports), `invalid` (legal JSON, CSS a browser must drop), `schema_invalid` (broken scenario JSON), `interaction` (handlers + click/type/Tab/resize/rebuild with assertions), `mutation` (one recorded edit of an executed scenario), `regression` (`regressions/*.json`). Each scenario is a pure function of family + seed + `GENERATOR_VERSION`; its id ends in a content hash. |
| Validation | `schema.py` | Stdlib JSON Schema subset over `schemas/scenario.schema.json` plus semantic rules (unique ids, action/assertion/handler targets exist, leaf types have no children, nesting limits, non-executable types). Deliberate negatives must be rejected; one that passes is counted as `validator_escapes` (an engine defect). |
| Selection | `explore.py` | Per round: `novelty + UCB(family)`; novelty = share of the candidate's coverage features never executed; UCB rewards families whose scenarios found *new* fingerprints. Every family gets a slot per round; none gets more than `max_share` (35 %). |
| Execution | `execute.py` | **NativaX**: `examples/web-challenge/test/audit_batch_test.dart` mounts a fresh `NativaXView` per scenario in one `flutter_tester` (real taps with `tester.tapAt`, `enterText`, `sendKeyEvent`, viewport resize, remount). FlutterErrors are captured per scenario with stack. A `begin` line before each scenario isolates hangs: the unmatched `begin` becomes `timeout`/`crash` and the batch resumes after it. **Chromium**: one page per chunk runs every scenario in a same-origin `srcdoc` iframe at the scenario viewport. |
| Probe | `probe.py` | One JS probe for both engines: rect, client/scroll size, 65 computed longhands, text, value, checked, activeElement, event log, script errors. |
| Oracles | `compare.py` | `crash`, `script_error`, `missing`, `style` (per property family), `geometry` (first-divergence localization), `overflow`, `events`, `focus`, `state`, `lifecycle` (remount must restore the initial state, no reference needed), explicit `assertion`s, `performance`. A divergence already present in an earlier state is not reported again. |
| Clustering | `diagnose.py` | Only primary findings open issues; fingerprints ignore element ids. Issue id `NX-` + sha1(fingerprint)[:8], stable across runs. |
| Reproduction | `explore.py` | The first scenario of every issue is re-run with an empty cache; `reproducible` is recorded per issue. |
| Minimization | `minimize.py` | Batched reduction with units keyed by node id (drop subtree / declaration / handler / action, halve text, drop extra CSS). Each round runs, in one batch per engine, every single reduction plus the reductions that worked separately last round applied together (all, halves, quarters); the smallest candidate that keeps the fingerprint wins. When no candidate reproduces, the case is 1-minimal and the failed single units become `necessary_conditions`. |
| Diagnosis | `diagnose.py` | Location (JSON path, element, and `file:line` only from a FlutterError stack frame), files to inspect (`git grep -F` hits, labelled as such), evidence-ranked hypotheses with evidence for/against, next checks, rule-based confidence. |
| Reports | `report.py` | `issues/NX-*.json` (validated against `schemas/report.schema.json` before it is written) and `issues/NX-*.md` (investigation brief for an LLM), `summary.{json,md}`, `metrics.json`, `coverage.json`, `ledger.json` (new / known / regression / fixed). |

### First divergence (localization)

A geometry finding is **primary** only when the element's computed styles
match the reference and either (size) none of its children changed size, or
(position) its parent and its preceding siblings match. Everything else is
recorded as a consequence of the divergence that caused it. A style
divergence inherited unchanged from the parent is a consequence too.

### What is and is not claimed

- `root_cause.status` is `confirmed` only for exceptions with a captured
  stack. Every other cause is `unconfirmed`, with its evidence listed.
- `location.source_file/line` is never filled from a search; search hits go
  to `investigation.files_to_inspect` with `basis: git grep ...`.
- `confidence.level` is rule-based (see `diagnose._confidence`), not a
  calibrated probability.
- Chromium is a reference, not ground truth. An `absolute` assertion that
  fails in both engines is `oracle_conflict` and never counts as a defect.
- `verification` stays `fix_applied: false` until `audit.py verify` re-runs the
  original and minimal cases (fingerprint absent) and the regression set.

## Scenario contract (`schemas/scenario.schema.json`, version 1.0)

Required: `schema_version`, `scenario_id`, `title`, `category`
(`valid` | `boundary` | `invalid_content` | `schema_invalid`), `objective`,
`source` (generator, version, parent, recorded mutations), `seed`, `screen`
(component tree), `environment` (viewport, wait, style mode, extra CSS),
`preconditions`, `actions`, `assertions` (`target`, `property`, `operator`,
`expected`, `oracle: absolute|reference`), `expected` (no crash, no script
errors, reference parity, lifecycle stability), `limits` (nodes, depth, ms,
RSS growth), `tags`.

## Report contract (`schemas/report.schema.json`, version 1.0)

`issue_id`, `run_id`, `scenario_id`, `fingerprint`, `status`, `novelty`,
`severity`, `confidence`, `classification` (kind, subsystem, component,
property, stage), `location` (screen, element, JSON path, minimal-case path,
source file/symbol/line or null), `system` (commit, dirty tree, generator
version, engine), `expected`, `actual`, `difference`, `reproduction` (seed,
numbered steps, original and minimal JSON, compiled minimal HTML, command,
minimization record, reproducible), `evidence`, `root_cause`,
`investigation`, `fix_requirements`, `constraints`, `regression_tests`,
`acceptance_criteria`, `verification`, `occurrences`.

## Limits of the method

- Clicks in the reference are synthetic pointer/mouse/click events at the
  same point (`elementFromPoint`) plus focus of the nearest focusable
  ancestor; NativaX receives real taps. Tab in the reference is a focus
  traversal model; other keys are not reproduced there.
- `change`/`keydown` events are not compared (the reference cannot
  synthesize them like real input).
- Colour/paint is compared through computed styles only; pixel fidelity is
  the visual judge's job (`tools/visual`).
- `image` is in the schema but not executable: the harness passes no
  `imageResolver`.
- Performance findings are per-scenario wall time and RSS growth of the
  harness, not benchmarks; use `tools/perf` for performance claims.
