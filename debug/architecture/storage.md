# Run storage and report contract (phase 4)

Immutable per-run archives for the diagnostic engines, plus the shared schema
validation they stand on. This attacks problems 1 and 2 of
`../archive/existing-system-before-debug-refactor.md`: evidence that is overwritten and reports without a
common identity. Everything below was executed on this checkout; commands and
real outputs are at the end.

## Layout

```
debug/artifacts/runs/<area>/<run_id>/
    manifest.json        versioned record, schema-validated on write
    integrity.json       sha256 + size of every archived file (schema 1.1)
    evidence/            byte copy of the directory the engine wrote
    reports/             snapshot of that area's report at archive time
    history/             append-only entries; the only part written after archiving
debug/artifacts/runs/<area>/   run ids sort oldest -> newest (UTC prefix)
```

`run_id` = `<UTC basic timestamp>Z[-<git short sha>][-N]`, for example
`20261026T020527Z-f47240e`. The `-N` suffix only appears when two runs are
archived in the same second. Sorting run ids lexicographically sorts runs.

The live directories do not change: engines keep writing
`debug/artifacts/visual/latest`, `debug/artifacts/perf/latest`,
`debug/artifacts/perf/game`, `debug/artifacts/perf/game3d` and every existing
reader (`DataStore`, `recommend.py`, `quality_gate.py`, `history.py`) keeps
reading them. Archiving **copies** after the run finishes, so a run directory is
never written twice and `latest` never disappears mid-run.

## Manifest

Schema: `debug/logic/schemas/run-manifest.schema.json`, `schema_version`
`1.1` (1.0 still accepted when reading). Written atomically (temp file + rename) and validated before it is
published; an invalid manifest aborts the archive and removes the partial run.

Real manifest produced on this checkout:

```json
{
  "schema_version": "1.0",
  "run_id": "20261026T020527Z-f47240e",
  "area": "visual",
  "engine": "visual_check.dart",
  "status": "completed",
  "archived_at": "2026-10-25T21:05:27-05:00",
  "git_revision": "f47240e",
  "argv": ["dart", "run", "debug/engines/visual_comparison/bin/visual_check.dart",
           "--suite", "50projects50days", "--out", ".visual/previous"],
  "source": ".visual/previous",
  "evidence": {"files": 14, "bytes": 204673},
  "reports": ["reports/visual-50projects50days-latest.md"],
  "notes": null
}
```

The manifest above was captured before the 2026-10-25 artifact consolidation,
so its `argv`/`source` still name `.visual/previous`; the archive itself now
lives under `debug/artifacts/runs/`.

Fields: `status` is `completed` / `failed` (non-zero exit) / `aborted` (user
pressed stop). `archived_at` always carries a UTC offset. `git_revision` is
`null` outside a checkout. `source` records where the evidence came from;
`evidence` records how much was copied so a truncated copy is detectable.

## Immutability, integrity, history and lineage (manifest 1.1)

- **Read-only after archiving.** `archive()` chmods every file under the run
  (except `history/`) to read-only and the sub-directories to `r-x`. A write
  raises `PermissionError`; `prune()` restores permissions before deleting.
- **Integrity.** `integrity.json` lists `{path, bytes, sha256}` for every
  archived file. `verify(run_dir)` returns the problems: invalid manifest,
  `missing: <path>`, `changed after archiving: <path>`. A 1.0 run returns the
  single note that it carries no hashes, so it cannot be verified (it is
  still readable).
- **History.** `append_history(run_dir, kind, data, author=, refs=)` writes one
  new read-only file `history/<UTC µs stamp>-<seq>-<kind>.json`, validated
  against `schemas/run-history-entry.schema.json`. Kinds: `annotation`,
  `review`, `reevaluation`, `comparison`, `superseded_by`, `verification`,
  `migration_note`. Existing entries are never rewritten; `history(run_dir)`
  lists them oldest first and reports unreadable entries instead of skipping
  them.
- **Lineage.** `lineage_key = <area>:<engine>:<sha1 of argv without output
  flags>[:12]` (`--out`, `--out-dir`, `--json`, `--md`, `--jsonl`,
  `--results-dir`, `--markdown` and their values are ignored). A new run
  records `previous_run` only when an earlier run of the same area has the
  same key, and that earlier run gets a `superseded_by` history entry. Runs
  with different keys are never linked, so comparisons only pair runs of the
  same configuration. 1.0 manifests have no key; their lineage is unknown.

Tests: `debug/logic/test_storage.py`, 18 tests (12 original + 6 for the
above: read-only enforcement, tamper and missing-file detection, append-only
history, lineage only within the same configuration, legacy 1.0 handling,
pruning frozen runs).

## Shared schema validation

The JSON Schema subset validator moved from the audit engine to
`debug/logic/json_validate.py` so common code can validate documents without
depending on an engine. `debug/engines/bug_detection/nxaudit/schema.py`
imports it and re-exports `validate`, so `from nxaudit.schema import validate`
and every audit test keep working (27/27 pass).

## API — `debug/logic/storage.py`

| Function | Behaviour |
|---|---|
| `archive(area, source, *, engine, argv, reports, status, notes, runs_root)` | copies `source` into a new run dir, validates and writes the manifest; raises on unknown status or missing source, leaving no run behind |
| `runs(area)` / `latest_run(area)` | run dirs, newest first |
| `load_manifest(run_dir)` | manifest, or `None` when missing/invalid JSON/schema-invalid |
| `check_manifest(manifest)` | schema errors (empty list = valid) |
| `prune(area, keep)` | **the only deletion path**; never called automatically |
| `git_revision()` | short commit, cached, `null` outside a git tree |
| `python3 debug/logic/storage.py <area>` | lists runs: id, status, engine |

Nothing is deleted automatically: evidence is only lost when someone calls
`prune()`.

## Engine output flags (verified inventory)

| Engine | Output flag | Default | Notes |
|---|---|---|---|
| `visual_comparison/bin/visual_check.dart` | `--out <dir>` | `debug/artifacts/visual/latest` | usage line 25, default line 52 |
| `performance/bin/perf.dart run` | `--out <dir>` | `debug/artifacts/perf/latest` | |
| `performance/bin/perf.dart idle-app` | `--out <file>` | `debug/artifacts/perf/app-idle.json` | |
| `bug_detection/audit.py gen` | `--out <dir>` (required) | — | |
| `bug_detection/audit.py run/reanalyze` | none | `debug/artifacts/audit/runs/<run>` + `debug/artifacts/audit/latest` + `progress/reports/audit-*.md` | already per-run; report paths hardcoded |
| `recommendations/recommend.py` | `--out <file>` | `progress/reports/recommendations-latest.md` | |
| `quality_gate/quality_gate.py` | `--out <dir>` (alias `--out-dir`) | nothing is written unless asked; `--legacy-outputs` rewrites `progress/reports/quality-gate-latest.*` | writes `gate.json`, `gate.md`, `snapshot.json` |
| `logic/history/history.py record` | `--out <dir>` | per-area `history/` | |
| `scripts/render_report.py` | `--out <file>` | next to the input | |
| `performance/gui/perf_gui.py` | no flag | `debug/artifacts/perf/live/report-*.md`, `progress/reports/conformance-latest.md` | constants at the top of the file |
| conformance runners (`run_*.dart`) | none | `debug/artifacts/conformance/results/<suite>-<ts>.*` | already timestamped, flat |
| leaks / security / microbenchmarks | none | `debug/benchmarks/{leaks,security,microbench}/<run_id>/` | per-run dirs + manifest (written by `debug/manifest`) |

## Derived indexes

`debug/logic/context.py` reads the manifests and conformance summaries and
writes compact JSONL indexes under `debug/artifacts/index/`:

```
debug/artifacts/index/runs.jsonl           nativax.run.v1
debug/artifacts/index/conformance.jsonl    nativax.conformance.run.v1
debug/artifacts/index/docs.jsonl           nativax.doc.v1
```

They are derived, gitignored and safe to delete. `python3 debug/run.py context
index` rebuilds them; queries fall back to canonical evidence when an index is
missing or older than its sources. The canonical records stay in each run's
`manifest.json` and in the conformance `*.summary.json` / `*.jsonl` pair.

Conformance summaries written after 2026-10-25 are metadata-only and point at
the sibling JSONL through `resultsFile`; historical summaries with embedded
`results` are read by `RunSummary.load` but are not rewritten.

## Integration points

- `perf_gui.py`: `_start(..., areas=[...])` declares which areas a button
  runs; when the process exits, `_archive_pending()` regenerates that area's
  report from fresh data, copies evidence + report into a run and logs
  `[archivo] <área> (<status>): debug/artifacts/runs/...`. Wired: visual (3 buttons + live),
  perf (2 + live), games, games3d, and `quality_report.sh` (`visual` + `perf`).
- `quality_gate.py`: `--out DIR` (alias `--out-dir`) writes `gate.json`, `gate.md` and
  `snapshot.json`; with no flag nothing is written, so running the gate never
  rewrites the tracked `progress/reports/quality-gate-latest.*` unless
  `--legacy-outputs` is passed (statuses and formulas:
  `metrics-gate-compat.md`).
- Fixed in passing (real bug): `perf_gui` recorded visual history from
  `.visual/latest/latest/results.json`, which does not exist, so the visual
  history never recorded anything. Both call sites now use
  `history_sources()` → `debug/artifacts/visual/latest/results.json`.
- Fixed in passing (real bug): five moved shell scripts computed the repo root
  with one `..` level too few (`run_gui.sh`, `visual_check.sh`,
  `mirror/mirror.sh`, `container/run.sh`, `container/matrix.sh`) and then
  referenced `$root/debug/...`. `tools/test_architecture.py` now also guards
  every `BASH_SOURCE` chain and every single-line `ROOT = Path(__file__)...`
  assignment under `tools/` and `debug/` (25 checked; a probe with a broken
  chain exits 1 naming the file).

## Commands and real results (2026-10-25)

```bash
python3 debug/run.py                       # entry point: the 7 Python tests under debug/ (7/7 OK)
python3 debug/run.py storage visual        # lists the archived runs of an area
python3 debug/logic/test_storage.py                 # 12 tests OK
python3 debug/engines/quality_gate/test_quality_gate.py   # 8 tests OK
python3 debug/engines/performance/gui/test_perf_gui.py    # 12 tests OK
python3 debug/engines/bug_detection/test_audit.py         # 27 tests OK (validator extraction)
python3 tools/test_architecture.py                       # guard OK (29 root assignments)
python3 debug/logic/storage.py visual                # lists the archived run
./tools/test_all.sh                                  # flaky at game_play_test.dart (SIGABRT)
```

The archive was executed on real repository data:
`debug/artifacts/runs/visual/20261026T020527Z-f47240e/` = 14 files / 204,673
bytes copied from `debug/artifacts/visual/previous` plus the
`visual-50projects50days` report snapshot, manifest valid against the schema.

The test files all run inside `./tools/test_all.sh` (`python tooling`
section); the archive line is a manual call, kept here as reproducible
evidence of the on-disk layout.

## Limitations (no capability is claimed beyond this)

- Runs started **outside the panel** (`quality_report.sh` from a terminal,
  `quality_gate.py --run`) are not archived automatically; only the panel
  archives. Their outputs stay in `latest` as before.
- `run_idle` is not archived: it writes
  `debug/artifacts/perf/latest/app-idle.json` and archiving would copy the whole
  26 MB perf directory for one file.
- `debug/artifacts/conformance`, `debug/benchmarks/*` and
  `debug/artifacts/audit` keep their own layouts (flat timestamped, per-run, and
  per-run respectively); they are not migrated here.
- `progress/reports/*-latest.md` remain "current pointer" documents that are
  rewritten on purpose; per-run copies live inside each run's `reports/`.
- No retention runs by default: `debug/artifacts/runs/` grows until
  `prune(area, keep)` is called. Symlinks and Windows are not used or tested.
