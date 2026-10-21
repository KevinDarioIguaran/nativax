# Conformance

## Principle

We do not rewrite what already exists. We reuse official suites and measure what
actually passes. A `SKIP` is not compatibility; it is declared debt.

## Suites

| Suite | What it measures | Where it lives |
|---|---|---|
| [Test262](https://github.com/tc39/test262) | ECMAScript language and built-ins | `.conformance/suites/test262` |
| [html5lib-tests](https://github.com/html5lib/html5lib-tests) | HTML tokenizer and tree construction | `.conformance/suites/html5lib-tests` |
| [WPT](https://github.com/web-platform-tests/wpt) | DOM, events, selectors, parsing | `.conformance/suites/wpt` |
| WPT `url/resources` | URL parsing | `.conformance/suites/wpt/url` |

Checkouts are pinned in `tools/conformance/bin/fetch_suites.dart`. They are not
versioned (`.conformance/` is in `.gitignore`).

## Statuses

| Status | Meaning |
|---|---|
| `PASS` | The test ran and passed. |
| `FAIL` | The test ran and failed, or the functionality does not exist. |
| `SKIP` | The runner cannot execute it or the feature is explicitly out of scope, with a reason. |
| `ERROR` | Runner failure (I/O, harness, crash). |

## Current baseline

These are the live numbers as of the last compatibility checkpoint. Use
`progress/status.md` and `progress/reports/` for the authoritative values.

| Suite | PASS | FAIL | SKIP | Rate |
|---|---:|---:|---:|---:|
| Test262 (selected directories) | 19,577 | 413 | 1,108 | **97.93 %** |
| html5lib tokenizer | 5,759 | 43 | 1,025 | **99.26 %** |
| WPT URL | 636 | 260 | 0 | **70.98 %** |
| WPT `dom/nodes` | 168 | 115 | 44 | **59.36 %** |
| WPT `css/selectors` | 19 | 164 | 345 | **10.38 %** |
| WPT tree construction | 913 | 961 | 99 | **48.72 %** |

The rate excludes `SKIP`. A `SKIP` never counts as compatibility.

## Commands

```bash
cd tools/conformance

dart run bin/fetch_suites.dart --suite test262 --suite html5lib
dart run bin/fetch_suites.dart --suite wpt

dart run bin/run_test262.dart --limit 500
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_wpt.dart --limit 200
dart run bin/run_html_tree.dart
```

Raw results go to `.conformance/results/*.jsonl` and `*.summary.json`. Dated
Markdown archives also stay in `.conformance/results/` and are ignored by git.
Only `progress/reports/<suite>-latest.md` is versioned.

## Known runner limitations

- **Test262 modules**: the bridge evaluates global scripts; tests with
  `flags: [module]` are reported as `SKIP`.
- **Test262 host APIs**: `$262.createRealm`, `$262.detachArrayBuffer`,
  `$262.agent`, and `$262.IsHTMLDDA` are `SKIP` (runner limitation, not a
  language limitation).
- **html5lib initial states**: the tokenizer starts in the Data state; fixtures
  with other `initialStates` are skipped.
- **html5lib DOCTYPE**: `DoctypeToken` exposes only the name; cases with public
  or system identifiers are skipped until the token is extended.
- **WPT**: a "lite" adapter. It does not support reftests, testdriver, workers,
  multiple globals, or the complete `testharness.js`. Those cases are skipped
  with a reason. Tests that use missing platform APIs (`fetch`,
  `getComputedStyle`, Shadow DOM, CSSOM, real layout) fail: those are real gaps.
  URL is implemented and measured separately.

## Policy for adding compatibility

1. Add the conformance test or a minimal regression test.
2. Implement the behavior.
3. Run the suite and compare with the baseline.
4. Update `progress/reports/` and the table in `progress/conformance.md`.
5. If something is skipped, record the reason and the corresponding issue/ADR.
