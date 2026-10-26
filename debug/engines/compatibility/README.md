# NativaX conformance runners

Measure the implemented engine against official suites without writing
replacement tests and without a browser. The runners use QuickJS and lite DOM
adapters; a result is not a browser result.

## Suites

- [Test262](https://github.com/tc39/test262): ECMAScript language subset.
- [html5lib-tests](https://github.com/html5lib/html5lib-tests): HTML tokenizer.
- WPT DOM/events/CSS selectors through a minimal `testharness.js` adapter.
- WPT tree construction.
- WPT URL fixture cases.

Suite checkouts are pinned and downloaded under
`debug/artifacts/conformance/suites/`; they are gitignored and not
redistributed.

## Commands

```bash
cd debug/engines/compatibility

dart run bin/fetch_suites.dart --suite test262 --suite html5lib --suite wpt

dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_wpt.dart --dirs dom/nodes --limit 2000
dart run bin/run_wpt.dart --dirs dom/events --limit 2000
dart run bin/run_wpt.dart --dirs css/selectors --limit 2000
dart run bin/run_html_tree.dart
dart run bin/run_all.dart
```

`run_all` may run more/longer suites than a quick check. Use a focused command
while iterating.

## Outputs

Each runner writes:

- `debug/artifacts/conformance/results/<suite>-<stamp>.jsonl`: one row per
  test;
- `<suite>-<stamp>.summary.json`: metadata and aggregate counts; `resultsFile`
  points to the JSONL and does not duplicate rows;
- `<suite>-<stamp>.md`: readable report.

The latest per-command baseline and gaps are in
[`../../../progress/conformance.md`](../../../progress/conformance.md). Human
convenience copies live in `progress/reports/`.

## Current baseline

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

## Rules

- `SKIP` is not PASS and is excluded from the rate.
- Adapter/harness corrections are not product compatibility gains; report them
  separately with a per-test delta.
- Test262 runs QuickJS, not V8.
- WPT adapters lack layout, testdriver, reftests, and complete realms.
- Do not change the denominator or reclassify failures to reach a target.
- Keep a real ~1 % compatibility gain as its own commit, separate from
  structural refactors.

## Tests

```bash
cd debug/engines/compatibility
dart test
dart analyze
```

Runner tests include summary/manifest and HTML tree comparison regressions.
