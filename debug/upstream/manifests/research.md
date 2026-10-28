# Upstream Test Suite Manifest — NativaX Native (C11 + Sokol)

Research summary for upstream suites relevant to the HTML/CSS/JS stack in NativaX Native.
Commits are latest observed on the default branch (GitHub API, 2026-10-27); no release tags were pinned.

## html5lib-tests

- Canonical repo: https://github.com/html5lib/html5lib-tests
- License: MIT (Copyright 2006-2013 James Graham, Geoffrey Sneddon, and contributors)
- Pinned version/commit: latest `master` — `c777c408b61078ea2eb4acefc2535f54dbc8b28a` (2026-10-01); no release tags
- Format: `.test` files with JSON-like test objects (`description`, `input`, `output`, `errors`); encoding tests in `.dat` sections (`#data`/`#encoding`); serializer tests in `.test`
- Adapter needs: parser for the custom `.test`/`.dat` formats; native tokenizer/serializer adapter to emit and compare token streams, errors, and serialized output; tree-construction cases now live in WPT
- Runnable directly: No

## WHATWG HTML tests

- Canonical repo: https://github.com/web-platform-tests/wpt (under `html/`, including `html/syntax/parsing/`); the WHATWG HTML spec repo (https://github.com/whatwg/html) contains no tests
- License: 3-Clause BSD (WPT `LICENSE.md`)
- Pinned version/commit: latest `master` — `07ce6e987a1606aec4dc84ef80062d9797330e0b` (2026-10-27)
- Format: WPT test files (HTML + `testharness.js`), reftests, and `.dat` parser fixtures under `html/syntax/parsing/resources/` (`#data`/`#errors`/`#document`)
- Adapter needs: WPT harness/runner or native equivalent; HTML parser + DOM serializer for `.dat` tree comparisons; reftest renderer for layout cases
- Runnable directly: No (subset of HTML parsing `.dat` cases can be adapted, but full WPT needs harness/server)

## W3C CSS Test Suite

- Canonical repo: current tests in https://github.com/web-platform-tests/wpt (`css/`); historical repo https://github.com/w3c/csswg-test is archived (last commit `0ddeac116e2176dd7229e9e41196e73b53b3466b`, 2018-03-05) and points to WPT
- License: dual-licensed under W3C Test Suite License and 3-Clause BSD (per W3C CSS Test Suites overview)
- Pinned version/commit: track WPT `master` — `07ce6e987a1606aec4dc84ef80062d9797330e0b` (2026-10-27); archived csswg-test frozen at `0ddeac116e2176dd7229e9e41196e73b53b3466b`
- Format: CSS reftests and `testharness.js` tests with metadata (`<link rel=help>`), plus `support/` files; official suites also published on w3.org
- Adapter needs: CSS parser, layout/rendering engine, reftest pixel comparison, metadata parser, harness runner
- Runnable directly: No

## Web Platform Tests

- Canonical repo: https://github.com/web-platform-tests/wpt
- License: 3-Clause BSD (`LICENSE.md`)
- Pinned version/commit: latest `master` — `07ce6e987a1606aec4dc84ef80062d9797330e0b` (2026-10-27)
- Format: HTML/JS tests, reftests, manual tests, and Python tooling under `tools/`; spec-linked metadata
- Adapter needs: subset selection by feature; WPT runner/harness or native adapter; server for networking/origin tests; rendering comparison for reftests
- Runnable directly: No (some static tests can be subset-adapted; full suite requires browser-like environment)

## Rendering and visual reftests

- Canonical sources:
  - Web Platform Tests reftests: https://github.com/web-platform-tests/wpt (CSS reftests under `css/`, HTML reftests under `html/`)
  - Mozilla Firefox reftests: https://github.com/mozilla-firefox/firefox (`gfx/tests/reftest/`)
  - Servo WebRender reftests: https://github.com/servo/webrender (`wrench/reftests/`)
- License: WPT BSD-3-Clause; Firefox MPL-2.0; Servo MPL-2.0
- Format: reftest.list manifests pairing test HTML with reference HTML/PNG; fuzz tolerances and platform conditionals
- Adapter needs: HTML/CSS renderer, screenshot capture, pixel comparison with tolerance, reftest metadata parser
- Runnable directly: No (requires native rendering implementation and screenshot harness)
- Notes: Native runtime currently renders a smoke scene, not parsed documents; reftests become applicable after layout/paint implementation.

## Test262

- Canonical repo: https://github.com/tc39/test262
- License: BSD (Ecma International, Copyright 2012)
- Pinned version/commit: latest `main` — `0b4e0812022b18236b5276d2804948fdd9f71603` (2026-10-26)
- Format: `.js` test files with YAML frontmatter metadata (`negative`, `includes`, `flags`, `locale`), plus `harness/` includes and `_FIXTURE` modules
- Adapter needs: JS engine runner (NativaX uses JavaScriptCore) implementing Test262 semantics: per-test realms, strict/non-strict execution, `$262`/`print` host APIs, module resolution, async handling, negative tests
- Runnable directly: No (requires runner; engine-level subset possible via JSC adapter)
