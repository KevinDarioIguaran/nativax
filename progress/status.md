# Current status

**Updated:** 2026-10-26 · `HEAD` `f47240e` · working tree contains
uncommitted information-architecture and documentation work.

This is the live, compact status. The chronological record is
[`log.md`](log.md); the older long Spanish snapshot is kept at
[`history/status-2026-10-25.md`](history/status-2026-10-25.md). Generated
evidence lives in [`reports/`](reports/) and `debug/artifacts/`.

## Now

- Diagnostics are consolidated under `debug/`: engines, run manifests,
  generated artifacts, indexes, and Python logic. Root `.visual`, `.perf`,
  `.conformance`, `.audit`, and `.runs` directories are gone.
- Conformance summaries are metadata-only and reference per-test JSONL via
  `resultsFile`; legacy embedded-result summaries remain readable.
- `python3 debug/run.py context ...` provides bounded `brief`, `runs`,
  `conformance`, and `docs` projections plus `measure`/`index`.
- Maintained first-party documentation is in English under `docs/`. Historical
  Spanish material is archived under `docs/archive/legacy-es/`,
  `progress/history/`, and `debug/archive/`; the archive indexes state what
  replaced it.
- `tools/check_docs.py` validates local links, language, repository paths,
  shell entrypoints, and public-API coverage. Its latest report is
  [`reports/docs-audit-latest.md`](reports/docs-audit-latest.md).
- All changes are uncommitted. Do not push/reset/rewrite them; owner approval is
  required before a commit.

## Measured conformance

| Suite | Tests | Rate | Evidence |
|---|---:|---:|---|
| Test262 (language subset) | 21,098 | 97.93 % | `test262-2026-10-23T221334.summary.json` |
| html5lib tokenizer | 6,827 | 99.26 % | `html5lib-tokenizer-2026-10-24T205003.summary.json` |
| WPT URL | 896 | 74.22 % | `wpt-url-2026-10-25T221027.summary.json` |
| WPT `dom/nodes` | 327 | 70.00 % | `wpt-2026-10-24T080256.summary.json` |
| WPT `css/selectors` | 528 | 70.56 % | `wpt-2026-10-24T204139.summary.json` |
| WPT `dom/events` | 176 | 71.23 % | `wpt-2026-10-24T061648.summary.json` |
| WPT tree construction | 1,973 | 83.03 % | `wpt-html-tree-2026-10-25T092140.summary.json` |

Rate excludes SKIP. These are QuickJS runs and lite adapters; they are not
browser/site compatibility. Details: [`conformance.md`](conformance.md).

## Performance, visual, leaks, security

| Area | Last measured | Result | Report |
|---|---|---|---|
| Headless performance | 2026-10-24 | 17 of 270 scenarios: 5 PASS / 2 WARN / 10 FAIL | [`perf-latest.md`](reports/perf-latest.md) |
| Linux app idle | 2026-10-24 | 105.0 MB RSS, 0.00 % CPU | [`perf-latest.md`](reports/perf-latest.md) |
| Visual 50projects50days | 2026-10-26 | 51 pages: 2 PASS / 18 WARN / 31 FAIL; mean 89.62 % (text raster limits PASS) | [`visual-50projects50days-latest.md`](reports/visual-50projects50days-latest.md) |
| Leaks | 2026-10-25 | only `control.release`: 1 PASS / 0 FAIL | `debug/benchmarks/leaks/20261026T030350Z-f47240e/` |
| Security | 2026-10-25 | 45 cases: 44 PASS / 0 FAIL / 1 SKIP | `debug/benchmarks/security/20261026T024956Z-f47240e/` |

The leak run is a smoke control, not a full suite. The performance baseline
covers 17 of 270 registered scenarios. Visual overall is a weighted similarity
score, not CSS support. Security is QuickJS-only and has no OS sandbox.

## Verification and limits

- **Full suite is flaky, not green:** `./tools/test_all.sh` produced both
  `exit 0` and a failure on 2026-10-26 in the same tree. The final validation
  run exited **1** at `packages/nativax/test/game_play_test.dart`:
  `TestDeviceException(Shell subprocess crashed with SIGABRT (-6))` (test did
  not complete). The same failure occurred at clean `HEAD`; root cause is not
  established. Do not use a passing run as a gate.
- **Focused Python:** `python3 debug/run.py test` reported **10/10 test files
  OK**. `python3 tools/test_check_docs.py` reported **7/7 OK**.
- **Documentation audit:** **PASS**, 100 maintained files, 0 issues.
- There are 56 Dart test files. Package tests and Python/debug tests can be run
  separately; see [`../docs/testing.md`](../docs/testing.md).
- JavaScriptCore (`JscEngine`) is opt-in (`NATIVAX_ENGINE=jsc`) and only
  measured on Linux x64 (JSC GTK 2.52.5): Security 43/45 PASS (microtask job
  limit not enforced), Test262 99.17 % vs QuickJS 99.76 %, JS microbenchmarks
  59-99 % faster. See `log.md` 2026-10-27. No modules, WebGL, SAB or workers.
- V8 unit/smoke tests skip unless `NATIVAX_V8_LIB` is supplied. A skip is not
  verification. V8 currently does not enforce execution budget, job limit, or
  stack limit and has no module/WebAssembly/WebGL/SAB host path.
- `debug/artifacts/` is about 1.1 GB and gitignored. Pruning is explicit, never
  automatic.
- No tokenizer library is installed; context token counts are labelled
  `estimate:utf8_bytes/4`, not exact.
- No CI workflows exist under `.github/`; validation is script-driven.
- `repomix-output.xml` is still shown as deleted (` D`) in the working tree. It
  was already absent; this work did not delete it.

## Documentation validation

Maintained documentation is checked by:

```bash
python3 tools/check_docs.py --write
python3 tools/test_check_docs.py
python3 -m unittest discover -s debug/logic -p 'test_*.py'
```

The checker validates local links, English policy for maintained pages,
source-path references, shell command paths, and exported-symbol coverage. It
explicitly lists archived and third-party exclusions; generated reports and
`debug/artifacts/` are not treated as current docs. A pass is a mechanical
result, not proof that every claim is current.

Latest result: **PASS · 100 maintained files · 0 issues**, written to
`progress/reports/docs-audit-latest.{json,md}` and summarized in
[`log.md`](log.md).

## Next step

1. Review the documentation/IA diff with the owner and commit only after
   approval, with no AI attribution.
2. Diagnose the `game_play_test.dart` SIGABRT/flake and make the full suite a
   stable gate; add CI when it is reproducible.
3. Verify one non-Linux platform and add its build/test/security evidence.
4. Add V8 time/job/stack enforcement and run a V8 security/conformance pass.
5. Decide separately whether the `repomix-output.xml` deletion is intentional.

## Commands

```bash
./tools/test_all.sh
python3 debug/run.py test
python3 tools/check_docs.py --write
python3 tools/test_check_docs.py
python3 debug/run.py context brief --budget 2000
python3 debug/run.py context index
python3 debug/run.py gate --json
```
