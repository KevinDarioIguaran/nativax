# debug/

Diagnostic engines, immutable runs, generated artifacts, and compact indexes.

## Layout

```
debug/
  engines/          source of the visual, perf, conformance, leak, security,
                    microbenchmark, audit, gate and recommendation engines
  benchmarks/       per-run benchmark results + manifest.json (tracked baselines)
  artifacts/        generated, gitignored: visual/, perf/, conformance/,
                    audit/, runs/, index/
  logic/            storage, schema validation, context index, audit,
                    history, tests
  manifest/         shared Dart package that creates run ids and manifests
  architecture/     engine inventory, storage contract, migration notes
  scripts/          quality_report.sh, preview_report.sh, render_report.py
```

## Interfaces

- **Quality dashboard** (`debug/engines/performance/gui/perf_gui.py`, Spanish,
  the day-to-day panel): runs the visual, performance and game suites live,
  per-area reports, and the **Historial** page that says whether visual
  fidelity, performance, conformance, memory and security improved or got
  worse, with charts.
  `python3 debug/run.py gui`
- **Debug Suite app** (`debug/app`, English): report explorer by folder,
  a dedicated workspace per report type (visual images side by side with zoom
  and regions, performance, memory, security, microbenchmarks, compatibility,
  bug detection A–F), raw evidence inspector, append-only history and
  annotations, comparison of two reports with a compatibility check first,
  and an engine launcher that archives each finished run.
  `python3 debug/app/main.py`
  Layers: `debug/app` (pages, components) → `debug/logic` (catalog,
  workspaces, compare_runs, storage) → engines. Colors and fonts come only
  from `debug/styles` (enforced by `debug/tests/ui/test_app.py`).

- **LLM debug pack** (`python3 debug/run.py llm`, `debug/logic/llm/`): every
  engine's evidence pre-analyzed into minified JSON for models
  (`debug/artifacts/llm/index.json` → `items/<id>.json`); see
  `debug/logic/llm/README.md`.

The JSON interface audit (`debug/engines/bug_detection`) is an AI-facing tool;
it is run from the command line, not from the dashboard.

## How accurate is each engine?

Every engine is audited against data whose answer is known (injected faults,
synthetic pairs, deliberate vulnerabilities, known leaks); never against its
own output. Measured on 2026-10-26:

| Engine | Result | Details |
|---|---|---|
| Bug detection | 287/287 injected faults detected, 251/251 localized, 0/193 clean scenarios flagged, 0 issues in 240 Chromium-vs-Chromium scenarios | [metrics-bug-detection.md](architecture/metrics-bug-detection.md) |
| Visual regions | 11/13 truth boxes localized (was 5/11), 7.4× fewer regions on 283 real pages | [metrics-visual.md](architecture/metrics-visual.md) |
| Memory leaks | 0 false alarms on 45 control runs; `proven_leak` precision 100 %, alarm recall 85.7 % | [metrics-memory.md](architecture/metrics-memory.md) |
| Security | 9/9 deliberate vulnerabilities detected, 0 baseline failures | [metrics-security.md](architecture/metrics-security.md) |
| Microbenchmark comparator | 0.7 % false alarms on synthetic samples; 5.7 % on real same-commit runs with 3 baselines (12.1 % with one) | [metrics-microbenchmarks.md](architecture/metrics-microbenchmarks.md) |
| Report search | precision/recall 1.0 on 15 query classes, including 1-letter typos | [metrics-microbenchmarks.md](architecture/metrics-microbenchmarks.md#part-b--report-search) |
| Recommendations, quality gate | see their own metrics documents | [recommendations](architecture/metrics-recommendations.md), [gate](architecture/metrics-gate-compat.md) |

## Canonical vs derived

Canonical evidence:

- `debug/benchmarks/<area>/<run_id>/manifest.json` and its result files;
- `debug/artifacts/runs/<area>/<run_id>/` (immutable archives);
- `debug/artifacts/conformance/results/<suite>-<stamp>.jsonl` (per-test rows);
- `debug/artifacts/conformance/results/<suite>-<stamp>.summary.json` (metadata).

Derived, safe to regenerate:

- `debug/artifacts/index/{runs,conformance,docs}.jsonl`;
- `progress/reports/*-latest.md` convenience copies;
- HTML previews and charts.

## Commands

```bash
python3 debug/run.py test                  # Python tests under debug/
python3 debug/run.py storage visual        # archived runs, newest first
python3 debug/run.py context brief --budget 2000
python3 debug/run.py context index
python3 debug/logic/ia_audit.py            # refresh IA measurements
```

Run the Dart engines from their package directories; `./tools/test_all.sh`
runs the full suite (currently flaky at `game_play_test.dart`; repeated
2026-10-26 runs produced both exit 0 and SIGABRT, as recorded in
`../progress/status.md`).

Formats and consumer contracts: `../docs/information-architecture.md`.
Run manifest contract: `debug/architecture/storage.md`.
