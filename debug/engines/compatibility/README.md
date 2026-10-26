# NativaX conformance

Runners that measure NativaX compatibility against official suites, without
writing the tests from scratch and without a browser.

## Suites

- [Test262](https://github.com/tc39/test262): the ECMAScript language.
- [html5lib-tests](https://github.com/html5lib/html5lib-tests): the HTML
  tokenizer.
- [WPT](https://github.com/web-platform-tests/wpt): DOM, events and selectors
  through a minimal `testharness.js` adapter, the WHATWG URL fixture
  (`url/resources/urltestdata.json`) and the tree-construction fixtures
  (`html/syntax/parsing/resources/*.dat`).

The checkouts are downloaded into `debug/artifacts/conformance/suites/` and are **not
committed**. `bin/fetch_suites.dart` clones pinned commits from GitHub, so it
needs network access.

## Usage

```bash
cd debug/engines/compatibility

dart run bin/fetch_suites.dart --suite test262 --suite html5lib --suite wpt

dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_html_tree.dart
dart run bin/run_wpt.dart --limit 400
dart run bin/run_all.dart
```

## Output

By default each runner writes:

- `debug/artifacts/conformance/results/<suite>-<timestamp>.jsonl`: one result per test.
- `debug/artifacts/conformance/results/<suite>-<timestamp>.summary.json`: aggregates.
- `debug/artifacts/conformance/results/<suite>-<timestamp>.md`: readable report for the run
  (ignored by git).
- `progress/reports/<suite>-latest.md`: the latest committed report. Reports
  with a timestamp are never committed.

`<suite>` is `test262`, `html5lib-tokenizer`, `wpt-url`, `wpt-html-tree` or
`wpt`. The timestamp in the file name is local time; the summary carries the
zoned time.

`--results-dir DIR` (every runner, and `run_all.dart`) writes the JSONL,
summary and Markdown into `DIR` instead, looks for the automatic baseline in
`DIR`, and **does not** update `progress/reports/<suite>-latest.md`. Adapters
that collect a report directory should always pass it.

```bash
dart run bin/run_url.dart --results-dir /tmp/report/compat
dart run bin/run_all.dart --results-dir /tmp/report/compat
```

The automatic baseline is the newest `<suite>-<timestamp>.summary.json` with
exactly that suite name (so `wpt` never picks a `wpt-url` summary). Pass
`--baseline summary.json` to choose one.

### Summary fields

| Field | Meaning |
|---|---|
| `suite` | suite name, as above |
| `startedAt`, `finishedAt` | ISO 8601 with UTC offset, e.g. `2026-10-26T09:15:02.123-05:00` |
| `timeZone` | local time-zone abbreviation at `startedAt` |
| `runnerVersion` | runner and summary-format version (`lib/src/run_output.dart`, equal to the package version); bumped whenever a change can move verdicts |
| `suiteCommit` | git sha of the suite checkout; `null` when the suite directory is not the top of a git checkout |
| `suiteVersion`, `command` | when known |
| `counts`, `passRate` | per status; the pass rate excludes SKIP |
| `results` | every result |

Compare two summaries only when `suite`, `suiteCommit`, `runnerVersion` and
`command` match; the Markdown delta flags a different suite revision as not
comparable.

## Statuses

`PASS`, `FAIL`, `SKIP`, `ERROR`. A `SKIP` never counts as compatibility: it
means the runner cannot execute the test or the feature is out of scope, and
it always carries a reason. `ERROR` means the harness broke (missing include,
invalid fixture JSON, runner exception), not the engine.

## Runner validation

`debug/datasets/compatibility` holds a small, hand-verified validation subset
(Test262, html5lib, URL, tree construction and WPT testharness cases written
from scratch) with the expected status of every case. The validator runs every
runner on it and also checks that deliberately broken adapters (always PASS,
SKIP as PASS, FAIL hidden as SKIP, ERROR as FAIL, dropped failures, a no-op
Test262 `assert.js`, an always-pass WPT harness) are detected:

```bash
dart run bin/validate_runners.dart [--json out.json] [--markdown out.md]
dart test
```

It needs no network. Formulas and results:
[`../../architecture/metrics-gate-compat.md`](../../architecture/metrics-gate-compat.md).

## Useful options

```bash
# Bounded Test262
dart run bin/run_test262.dart --limit 500 --skip-features Temporal,ShadowRealm

# One WPT file
dart run bin/run_wpt.dart --dirs dom/nodes --grep Element-tagName
```

## Adapter limitations

See
[`../../../.agents/skills/nativa-conformance/references/conformance.md`](../../../.agents/skills/nativa-conformance/references/conformance.md).
In short: Test262 module tests and host APIs (`$262.agent`, `createRealm`,
`detachArrayBuffer`, `IsHTMLDDA`) are skipped; raw tests run verbatim in sloppy
mode only; html5lib runs only from the Data state and DOCTYPE identifiers are
not compared; WPT has no reftests, testdriver, workers or full
`testharness.js`, a test that never completes is a FAIL (harness timeout), and
`assert_implements_optional` failures are SKIP.

## Current baseline (measured before the 2026-10-26 runner fixes)

| Suite | Rate | Tests |
|---|---:|---:|
| Test262 language subset | 97.93 % | 21,098 |
| html5lib tokenizer | 99.26 % | 6,827 |
| WPT URL | 74.22 % | 896 |
| WPT `dom/nodes` | 70.00 % | 327 |
| WPT `css/selectors` | 70.56 % | 528 |
| WPT `dom/events` | 71.23 % | 176 |
| WPT tree construction | 83.03 % | 1,973 |

Rate excludes SKIP. The baseline date/stamps are in
`../../../progress/conformance.md`; do not quote these as full browser
compatibility.

The runner fixes in `metrics-gate-compat.md` change some verdicts; re-run the suites before quoting these rates.

Summaries written since 2026-10-25 are metadata-only: `resultsFile` names the sibling JSONL with one row per test; older summaries embed `results`. Both load through `RunSummary.load`.
