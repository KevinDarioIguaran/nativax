# Existing diagnostic system (before the `debug/` refactor)

Snapshot taken at commit `f5151e9` (2026-10-25). Everything below was
verified in the code; line counts are `wc -l` at that commit.

## Components

| Component | Location | Language | Role |
|---|---|---|---|
| Visual fidelity judge | `tools/visual` (pkg `nativa_visual`, 4,811 lib lines, 77 tests) | Dart | NativaX vs headless Chromium: probes, pixels, scores, verdicts |
| Performance suite | `tools/perf` (pkg `nativa_perf`, 3,651 lib lines, 15 tests) | Dart | Scenario timing, frames, RSS/CPU, app idle, Docker matrix |
| Conformance runners | `tools/conformance` (2,727 lib lines, 4 tests) | Dart | Test262, html5lib, URL, WPT DOM/CSS/tree |
| Leak / lifecycle suite | `tools/leaks` (1,640 lib lines, 10 tests) | Dart | Memory growth, listeners, timers, wrappers |
| Security suite | `tools/security` (1,007 lib lines, 4 tests) | Dart | Bridge/host API attack cases |
| Micro-benchmarks | `tools/benchmark` (1,429 lib lines, 10 tests) | Dart | JS engine, bridge, DOM, style recalculation |
| JSON interface audit | `tools/audit` (`nxaudit`, 27 tests; GUI 10 tests) | Python | Generated screens, differential oracles, issues, minimization |
| Recommendations | `tools/recommend.py` (1,217 lines, 9 tests) | Python | Rule engine over the latest visual/perf/leak/security data |
| Quality gate | `tools/quality_gate.py` (433 lines) | Python | Baseline comparison of visual/perf/compat snapshots |
| History | `tools/history.py` (360 lines, 4 tests) | Python | Snapshots of results tables and previous-run deltas |
| Report preview | `tools/render_report.py` (242 lines) | Python | Markdown → HTML/PNG through headless Chrome |
| Dashboard | `tools/perf/gui/perf_gui.py` (4,393 lines) | Python/Tk | Spanish panel: runs, tables, charts, reports, history |
| Audit explorer | `tools/audit/gui` | Python/Tk | Spanish explorer of audit runs |
| Offscreen harnesses | `examples/web-challenge/test/{screenshot,perf_probe,audit_batch}_test.dart` | Dart/Flutter | NativaX rendering for the visual, perf and audit engines |
| Mirror | `tools/mirror` | Bash/JS/Dart | Predecessor of the visual judge; the source of `packages/nativa_render/test/fidelity_test.dart` expectations |
| Container matrix | `tools/perf/container` | Bash/Python | Perf suite under cgroup CPU/RAM quotas |

The Dart engines locate the repository by walking up to the `pubspec.yaml`
named `nativa_workspace`, so they do not depend on their own location. The
Python tools use `Path(__file__).parents[N]`, which does.

## Data flow and storage

Phase 4 adds an immutable per-run layer on top of this: finished runs of an
area are copied into `debug/artifacts/runs/<area>/<run_id>/` with a versioned,
schema-valid manifest and a snapshot of that area's report. The live
directories below are unchanged. Design, flag inventory and limitations:
`debug/architecture/storage.md`.

```
engines ──► debug/artifacts/visual/latest/   (overwritten every run; perf_gui moves the previous run to debug/artifacts/visual/previous)
        ──► debug/artifacts/perf/latest/     (same)
        ──► debug/artifacts/perf/game, game3d (same)
        ──► debug/artifacts/audit/runs/<run>/ (one folder per run) + debug/artifacts/audit/latest
        ──► debug/artifacts/conformance/results/<suite>-<ts>.{jsonl,md,summary.json}   (flat, timestamped)
        ──► debug/benchmarks/leaks/<run_id>/                           (per run + manifest)
        ──► debug/benchmarks/security/<run_id>/                        (per run + manifest)
        ──► debug/benchmarks/microbench/<run_id>/                      (per run + manifest; baselines tracked in baselines/)
history.py ─► debug/artifacts/visual/history/<ts>.json, debug/artifacts/perf/history/<ts>.json (results tables only, no evidence)
recommend.py / perf_gui / quality_gate ─► progress/reports/*-latest.md (tracked; overwritten every run)
```

## Problems found

1. **Evidence is overwritten.** `debug/artifacts/visual/latest` and
   `debug/artifacts/perf/latest` hold a single run. Only the results tables
   survive in `history/`; the screenshots, probes and per-element data of
   earlier runs are lost. `progress/reports/*-latest.md` is rewritten in place.
2. **No common report contract.** Each engine has its own layout and
   timestamp format. Engine version and code revision are not recorded
   consistently. There are no timezone-qualified timestamps and no
   per-report identity.
3. **Mixed responsibilities in `perf_gui.py`.** One file holds the UI,
   process control, data loading, report writing (performance, visual,
   games, recommendations, conformance), history recording and catalog
   regeneration. Before the last snapshot it also contained three duplicated
   method definitions.
4. **"Did it improve?" is undefined.** `history.py` compares a run with the
   previous one, with no compatibility check (budget, suite, environment,
   engine version) and no noise model. A smaller error count is not
   distinguished from a detector that missed errors.
5. **No engine is measured against ground truth**, except the audit engine's
   deliberate-fault benchmark. The other engines' tests check formulas and
   formats, not detection accuracy on known cases.
6. **Language mix.** UI, generated reports and READMEs mix Spanish and
   English.
7. **Production coupling.** The offscreen harnesses live in
   `examples/web-challenge/test`, an example app, and the audit/visual/perf
   engines depend on that example's location.

## Production boundary

No package under `packages/` imports a tool. `tools/test_architecture.py`
guards against browsers and HTTP servers in the runtime. The harness
coupling (problem 7) is the only place where diagnostic code sits inside a
shipped-looking app folder.
