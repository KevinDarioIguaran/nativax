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
