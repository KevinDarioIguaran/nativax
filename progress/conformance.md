# Conformance baseline

**Snapshot:** 2026-10-26. Runners live in `debug/engines/compatibility`; the
official suite checkouts are pinned and downloaded under
`debug/artifacts/conformance/` (gitignored). The latest recorded run per
command is below. **SKIP is excluded from the rate and never counts as
compatibility.**

## Results

| Suite | Scope | PASS | FAIL | SKIP | ERROR | Tests | Rate | Evidence stamp |
|---|---|---:|---:|---:|---:|---:|---:|---|
| Test262 | `language/{expressions,statements,types,literals}` | 19,577 | 413 | 1,108 | 0 | 21,098 | **97.93 %** | `test262-2026-10-23T221334` |
| html5lib tokenizer | all `.test` files | 5,759 | 43 | 1,025 | 0 | 6,827 | **99.26 %** | `html5lib-tokenizer-2026-10-24T205003` |
| WPT URL | 896 fixture cases | 665 | 231 | 0 | 0 | 896 | **74.22 %** | `wpt-url-2026-10-25T221027` |
| WPT `dom/nodes` | 327 files | 196 | 84 | 47 | 0 | 327 | **70.00 %** | `wpt-2026-10-24T080256` |
| WPT `css/selectors` | 528 files | 127 | 53 | 348 | 0 | 528 | **70.56 %** | `wpt-2026-10-24T204139` |
| WPT `dom/events` | 176 files | 52 | 21 | 103 | 0 | 176 | **71.23 %** | `wpt-2026-10-24T061648` |
| WPT tree construction | 1,973 `.dat` cases | 1,556 | 316 | 99 | 2 | 1,973 | **83.03 %** | `wpt-html-tree-2026-10-25T092140` |

Rate = `PASS / (PASS + FAIL)`. The per-suite summaries and full JSONL are under
`debug/artifacts/conformance/results/`. The full summaries use schema 1.0 and
point to the JSONL with `resultsFile`; they do not duplicate every test row.

These are **QuickJS runs**. V8 has no Test262/WPT run in this repository.

## Commands

```bash
cd debug/engines/compatibility
dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_wpt.dart --dirs dom/nodes --limit 2000
dart run bin/run_wpt.dart --dirs css/selectors --limit 2000
dart run bin/run_wpt.dart --dirs dom/events --limit 2000
dart run bin/run_html_tree.dart
# all of the above:
dart run bin/run_all.dart
```

Exploratory runs under 100 tests are hidden from the default context view;
`python3 debug/run.py context conformance --all` lists them.

## 70 % phase gate

| Suite | Target | Current | State |
|---|---:|---:|---|
| Test262 | 70 % | 97.93 % | Met |
| html5lib tokenizer | 70 % | 99.26 % | Met |
| WPT URL | 70 % | 74.22 % | Met |
| WPT `dom/nodes` | 70 % | 70.00 % | Met (no margin) |
| WPT `css/selectors` | 70 % | 70.56 % | Met |
| WPT `dom/events` | 70 % | 71.23 % | Met |
| WPT tree construction | 70 % | 83.03 % | Met |

The gate was reached without changing denominators or turning SKIP into PASS.
Reftests and testdriver-only WPT cases remain excluded/skipped. “70 %” is a
project phase gate, not a claim that websites will work 70 % of the time.

## What each suite actually covers

### Test262

Language semantics through QuickJS, not the DOM, modules, host APIs, or
rendering. Known failure areas: strict-mode early errors, decorators/recent
proposals, destructuring/assignment evaluation order, and `RegExp`/`Symbol`
edge cases. The 1,108 SKIPs include modules, dynamic import, import defer,
source-phase imports, TCO, and host-specific Test262 APIs.

### html5lib tokenizer

Tokenizer only. The 1,025 SKIPs are non-Data states and doctype public/system
identifier variants that the adapter does not model. Remaining failures include
bogus comments (`<!`, `<!-`), ambiguous entity prefixes, attribute edge cases,
and NUL handling. This number is not tree construction.

### WPT DOM, events, and selectors

These use a lite `testharness.js` adapter, not a full browser. They do not have
layout/renderer geometry, testdriver, reftests, or a complete realm model.

- `dom/nodes`: 47 SKIPs; remaining failures include realms/iframes, complete
  `Range`/`TreeWalker`, `DOMParser`/CDATA, and `moveBefore`.
- `dom/events`: 103 SKIPs; the run covers event construction, legacy aliases,
  listeners, capture/bubble, and handler properties in the adapter.
- `css/selectors`: 348 SKIPs, mostly reftests. `:focus-visible`, Shadow DOM,
  quirks mode, namespaced selectors, and parts of `:dir` still fail.

### WPT URL

`URL`/`URLSearchParams` through the bindings. Remaining failures are IDN,
canonical IPv6, file URLs, and WHATWG normalization details. This is a fixture
suite, not a network test.

### Tree construction

The default parser delegates tree construction to `package:html`; the in-house
tokenizer supplies parse errors and limits. The 2026-10-25 runner corrections
fixed attribute comparison and foreign namespace/local-name comparison. Those
changes raised the measured rate from 71.18 % to 83.03 % with the same
denominator and **are harness corrections, not product compatibility gains**.
The dominant remaining real gap is `<template>` content (112 cases);
`package:html` 0.15.x does not implement the template content fragment. There
are also 2 runner errors.

## Evidence and reports

- Per-test rows: `debug/artifacts/conformance/results/<suite>-<stamp>.jsonl`
- Metadata: `debug/artifacts/conformance/results/<suite>-<stamp>.summary.json`
- Human reports: `progress/reports/{test262,html5lib-tokenizer,wpt-url,wpt-dom-nodes,wpt-css-selectors,wpt-html-tree,conformance}-latest.md`
- Context projection: `python3 debug/run.py context conformance`

`progress/reports/*-latest.md` may lag the latest timestamped summary. For a
quoted number, use the summary/JSONL and state the timestamp.

## Interpreting a change

- A runner/adapter fix is not a product gain.
- A SKIP is not a PASS.
- A subset result is not full-suite compatibility.
- Test262 does not cover V8 and does not measure DOM/rendering.
- Visual fidelity and performance are separate measurements.
- A single percentage is not per-site compatibility.

## Next improvements

1. `nativa_html`: template content, quirks/doctype, and remaining tree modes.
2. `nativa_dom_bindings`: realms/iframes, `Range`/`TreeWalker`, `DOMParser`,
   and URL normalization.
3. CSS: layout-aware selectors and remaining state/namespace cases.
4. Repeat `run_all.dart`, record the per-test delta, and keep harness fixes
   separate from compatibility gains.

## Related

- [`../docs/testing.md`](../docs/testing.md)
- [`../docs/javascript-supported.md`](../docs/javascript-supported.md)
- [`../docs/html-supported.md`](../docs/html-supported.md)
- [`../docs/css-supported.md`](../docs/css-supported.md)
- [`status.md`](status.md)
