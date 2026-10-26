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
  fidelity and performance improved or got worse, with charts.
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

The JSON interface audit (`debug/engines/bug_detection`) is an AI-facing tool;
it is run from the command line, not from the dashboard.

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
