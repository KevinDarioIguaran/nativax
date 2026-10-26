# Work log

Newest first. Historical Spanish sessions are in
[`history/log-2026-10-25-es.md`](history/log-2026-10-25-es.md); they are
evidence, not current instructions. Numbers below are copied from recorded
outputs, not reconstructed from memory.

## 2026-10-26 — Documentation and evidence consolidation

Scope: make maintained documentation English and source-backed, consolidate
diagnostics under `debug/`, and add documentation validation. No runtime
behavior, public API, dependency, or package boundary was changed by this work.

Completed in this session:

- Removed the root `benchmarks/` layout; moved tracked baselines and game-player
  phase-0 evidence under `debug/benchmarks/`.
- Added `debug/manifest` and wired run manifests into benchmark, leak, and
  security engines. The schema is
  `debug/logic/schemas/run-manifest.schema.json` (schema 1.0).
- Moved generated `.visual`, `.perf`, `.conformance`, `.audit`, and `.runs`
  data under gitignored `debug/artifacts/`.
- Added compact conformance summaries (`resultsFile` points to JSONL) and
  `run-index`/`conformance-index` schemas.
- Added `debug/logic/context.py` and bounded agent projections (`brief`,
  `runs`, `conformance`, `docs`, `measure`, `index`).
- Added `debug/logic/ia_audit.py`; generated
  `progress/reports/information-architecture-latest.json`.
- Compacted `progress/status.md` and preserved the earlier long snapshot.
- Archived Spanish historical pages under `docs/archive/legacy-es/` and
  `progress/history/`; added archive indexes and a replacement map.
- Rewrote root `README.md`, `docs/README.md`, architecture/guides/reference/
  internals pages, testing/debugging/contributing/agents/glossary/FAQ, and the
  HTML/CSS/JS support pages in English.
- Translated the remaining maintained Spanish task pages and moved the
  phase-0 presentation and JIT baseline pages to `progress/history/` with a
  replacement index.
- Added `tools/check_docs.py` and `tools/test_check_docs.py`. The checker covers
  local links, maintained-document language, backticked source paths, shell
  command paths, and public `nativax` barrel symbols.
- Added docs checks to `tools/test_all.sh` and aligned
  `debug/logic/test_docs_links.py` with the checker's maintained-document scope.
- Archived the pre-consolidation debug-system snapshot and engine inventory
  under `debug/archive/`; fixed stale links and paths left by the docs moves.
- Published `progress/reports/docs-audit-latest.{json,md}`.
- Recorded source-backed corrections:
  - default `documentUrl` is `app://local/index.html`;
  - hard parser limits throw `HtmlLimitException`;
  - the runtime exposes `parseErrors`/`scriptErrors`, not public
    `styleSheets`/`linkedSheets`;
  - `NativaXView` does not reload on config-only changes;
  - `LocalResourceNetwork` falls back to the configured network when a
    same-origin loader returns null, and `/api/` bypasses the loader;
  - V8 does not enforce execution budget, job limit, or stack limit and lacks
    modules/WebAssembly/WebGL/SAB host integration.

Measured or reproduced in this session:

- URL conformance: 665 PASS / 231 FAIL / 0 SKIP / 0 ERROR, 74.22 %, 896 tests.
  Compact summary 289 B vs the legacy 197,504 B summary.
- Security: `20261026T024956Z-f47240e` — 45 cases, 44 PASS, 0 FAIL, 1 SKIP
  (`platform.flutter_resource_policy`).
- Leaks: `20261026T030350Z-f47240e` — only `control.release`, 1 PASS, RSS
  476.3 MiB → 290.5 MiB, `activeRuntimes=0`. Not a full leak suite.
- Compatibility/debug Python tests: **10/10 files OK** after the documentation
  moves. `python3 tools/test_check_docs.py`: **7/7 OK**.
- Documentation audit: **PASS**, 100 maintained files, 0 issues.
- Full `./tools/test_all.sh` is **flaky**. On 2026-10-26 three runs exited 0;
  a later run on the same tree exited **1** and
  `packages/nativax/test/game_play_test.dart` did not complete:
  `TestDeviceException(Shell subprocess crashed with SIGABRT (-6))`. The same
  failure occurred at clean `HEAD` `f47240e`. Root cause is not established.
  Passing package/analyzer stages before the failure are not a green suite.
- `git diff --check`: clean at the final validation checkpoint.

Still open:

- Review the complete diff with the owner and commit only after approval, with
  no AI attribution.
- Diagnose the `game_play_test.dart` SIGABRT/flake and make the full suite a
  stable gate; add CI when it is reproducible.
- Verify a non-Linux platform, enforce V8 time/job/stack limits, and run the
  remaining conformance/security coverage as separate changes.

## 2026-10-25 — Information architecture

- Consolidated debug data under `debug/`; added manifests, schema validation,
  metadata-only conformance summaries, context indexes, and storage/IA audits.
- Kept `debug/artifacts/` gitignored and prunable only by explicit command.
- Preserved old conformance summaries (92 historical summaries were not
  migrated).
- Added bounded context measurements. Token counts are estimates because no
  tokenizer library is installed.

## 2026-10-24 — Conformance, visual, and performance baseline

- Test262: 19,577 PASS / 413 FAIL / 1,108 SKIP, 97.93 %.
- html5lib tokenizer: 5,759 PASS / 43 FAIL / 1,025 SKIP, 99.26 %.
- WPT `dom/nodes`: 196 PASS / 84 FAIL / 47 SKIP, 70.00 %.
- WPT `css/selectors`: 127 PASS / 53 FAIL / 348 SKIP, 70.56 %.
- WPT `dom/events`: 52 PASS / 21 FAIL / 103 SKIP, 71.23 %.
- Tree construction: 1,556 PASS / 316 FAIL / 99 SKIP / 2 ERROR, 83.03 %; the
  2026-10-25 runner corrections that raised this from 71.18 % are harness fixes,
  not product gains.
- Visual 50projects50days: 51 pages, 6 PASS / 5 WARN / 40 FAIL, mean 52.59 %.
- Performance: 17 of 270 scenarios, 5 PASS / 2 WARN / 10 FAIL; Linux app idle
  105.0 MB RSS, 0.00 % CPU.
- Last recorded fully green full test run: 301 tests.

## How to append

Add a dated section with:

- scope and files/areas touched;
- exact commands;
- actual results and run IDs;
- skips/blockers;
- what could not be measured;
- whether the change is committed.

Do not rewrite earlier entries to make a later result look better.
