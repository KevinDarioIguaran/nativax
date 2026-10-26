# Testing

NativaX has no CI workflow. Verification is script-driven and must be reported
with commands and results. A test file existing is not a passing test; a skipped
test is not coverage; a green subset is not `./tools/test_all.sh`.

## Fast checks

From the repository root:

```bash
git diff --check
python3 -m unittest discover -s debug/logic -p 'test_*.py'
python3 debug/run.py test
python3 tools/check_docs.py
python3 tools/test_check_docs.py
```

For touched Dart/Flutter packages:

```bash
cd packages/nativa_js && dart analyze && dart test
cd packages/nativax && flutter analyze && flutter test
```

Run `dart analyze`/`flutter analyze` and tests from each package directory. Native
assets (QuickJS) are resolved per package; `flutter test packages/nativax` from
the root is not equivalent and the test script says not to use it.

## Full suite

```bash
./tools/test_all.sh
```

Run it from the repository root with the game closed. It:

1. runs `dart test` in `nativa_js`, `nativa_dom`, `nativa_html`, `nativa_css`,
   `nativa_dom_bindings`;
2. runs `flutter test` in `nativa_render` and `nativax`;
3. runs `flutter test` in every example that has a `test/` directory;
4. analyzes/tests `debug/harness`;
5. analyzes `debug/engines/compatibility`;
6. runs `debug/manifest` tests and `debug/run.py test`;
7. runs the documentation checks.

### Current full-suite result: not reliably green

`packages/nativax/test/game_play_test.dart` is **flaky**. On 2026-10-26, three
full runs completed with `exit 0`; a later run on the same tree exited **1** and
reported:

```text
TestDeviceException(Shell subprocess crashed with SIGABRT (-6))
```

The test did not complete. The same failure occurred at clean `HEAD` `f47240e`
on 2026-10-25. Root cause is not established and this documentation work did not
change runtime code. Do not call the suite green; a passing run is not a stable
gate. There is no CI workflow. There are 56 Dart test files.

## Package test map

| Package | Command | Main coverage | Known caveats |
|---|---|---|---|
| `nativa_js` | `dart test` | QuickJS, modules, WASM, GL, V8 (env-gated), JIT prototype | V8 tests skip without `NATIVAX_V8_LIB` |
| `nativa_dom` | `dart test` | DOM, selectors, events, mutations, forms, fuzz | No browser DOM parity |
| `nativa_html` | `dart test` | tokenizer, parser, fragment parsing, fuzz | Default tree uses `package:html` |
| `nativa_css` | `dart test` | parser, cascade, media, flex, style cache, fuzz | Not CSS conformance |
| `nativa_dom_bindings` | `dart test` | bindings, web APIs, storage, network, messaging, WebGL | Security suite is stronger for hostile cases |
| `nativa_render` | `flutter test` | layout, widgets, text, images, canvas, SVG, virtualization, animation | Visual fidelity is a separate measured suite |
| `nativax` | `flutter test` | runtime, view, resources, modules, workers, hot reload, templates | `game_play_test.dart` is flaky: SIGABRT on some runs |
| `debug/harness` | `flutter analyze && flutter test` | offscreen/render probes | Several tests are env-gated and skip |
| `debug/manifest` | `dart test` | run ids/manifests | |
| `debug/logic` | Python tests above | schemas, storage, context, docs links | |
| `tools/test_architecture.py` | `python3 tools/test_architecture.py` | package boundaries | Separate from `test_all` unless invoked |

## Environment-gated tests

V8:

```bash
export NATIVAX_V8_LIB=/absolute/path/to/libnx_v8.so
cd packages/nativa_js && dart test test/v8_engine_test.dart
cd packages/nativax && flutter test test/v8_smoke_test.dart
```

Without the variable, these tests skip. Report them as skipped, not passed.

Harness/perf/audit tests use `NATIVAX_PERF_*`, `NATIVAX_JSON`,
`NATIVAX_AUDIT_MANIFEST`, and screenshot variables. Their skips are expected in a
plain run; a skipped screenshot/perf case is not evidence.

## Analyze and format

```bash
cd packages/nativax && flutter analyze
cd packages/nativa_render && flutter analyze
cd packages/nativa_js && dart analyze
cd packages/nativa_dom && dart analyze
cd packages/nativa_html && dart analyze
cd packages/nativa_css && dart analyze
cd packages/nativa_dom_bindings && dart analyze
```

Format only touched files with the repository's Dart formatter version:

```bash
dart format --output=none --set-exit-if-changed path/to/file.dart
```

Do not reformat unrelated files.

## Conformance

Conformance is separate from unit tests and runs QuickJS through the compatibility
adapters:

```bash
cd debug/engines/compatibility
dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_wpt.dart
dart run bin/run_html_tree.dart
```

Results are recorded in [`../progress/conformance.md`](../progress/conformance.md).
`SKIP` is excluded from the percentage and never counts as compatibility. The
runners' suite subset/adapters are not a browser: a Test262 pass does not measure
V8 or DOM rendering, and a WPT lite pass is not full WPT.

## Visual, performance, leaks, security

```bash
cd debug/engines/visual_comparison
dart run bin/visual_check.dart --suite 50projects50days

cd debug/engines/performance
dart run bin/perf.dart run --list

cd debug/engines/memory
dart run bin/leaks.dart run --profile quick

cd debug/engines/security
dart run bin/security.dart run --list
dart run bin/security.dart run --only bridge
```

These are evidence engines, not unit tests. Read their README/flags before
quoting a result. A `PASS` in the security suite covers only that attack case.
`INCONCLUSIVE` is not a pass.

## How to write a test

Before coding, write the acceptance criterion:

- **Behavior:** what must be observable.
- **Test:** the exact file and assertion.
- **Command:** how to run only it.
- **Metric:** timing/memory/conformance if relevant.
- **Out of scope:** what this does not claim.

Rules:

- Every new feature needs a test; conformance `SKIP` does not count.
- Prefer a failing focused test first.
- Use `StaticEnvironment` and no network for deterministic tests.
- Test denied paths, disposal, and malformed input where relevant.
- Do not use `HtmlElementView`, a WebView, or a browser to make a test pass.
- Do not assert on a screenshot without a tolerance/metric.
- If a test is skipped in the default environment, document how to run it and
  report that it was skipped.

## Evidence format

Report:

```text
command:
cwd:
result:
date/commit:
platform: Linux x86_64, Dart 3.13.0, Flutter 3.47.0
engine/flags:
notes/skips:
```

A report is not evidence if it omits the command or the actual result. Do not
paste a previous run as current.

## Known verification gaps

- Full suite is flaky at `game_play_test.dart`: repeated 2026-10-26 runs
  produced both `exit 0` and SIGABRT; the final run failed. No CI.
- No CI, no coverage measurement, no matrix across Android/iOS/macOS/Windows.
- V8 has only smoke/unit coverage when its library is supplied; no conformance
  or performance baseline.
- Latest leak run covers only `control.release`.
- Latest performance baseline measures 17 of 270 registered scenarios.
- Visual baseline is 51 pages at 52.59 % mean fidelity with 40 FAIL cases.
- No browser-level accessibility tree verification.

## Related

- [`debugging.md`](debugging.md)
- [`benchmarks.md`](benchmarks.md)
- [`performance-suite.md`](performance-suite.md)
- [`visual-fidelity.md`](visual-fidelity.md)
- [`../progress/status.md`](../progress/status.md)
- [`../progress/conformance.md`](../progress/conformance.md)
- [`../progress/reports/docs-audit-latest.md`](../progress/reports/docs-audit-latest.md)
