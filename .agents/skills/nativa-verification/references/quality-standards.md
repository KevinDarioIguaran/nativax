# Quality standards

## Definition of "done"

A change is done when:

1. It compiles in the available environment (`dart analyze` or `flutter analyze`
   is clean).
2. Tests fail before and pass after.
3. It does not degrade existing tests or conformance without a documented
   reason.
4. It updates `progress/` and, when a decision changes, `.agents/`.
5. Any new dependency has a justified license, maintenance status, and
   compatibility story.
6. It explicitly states which part of the standard it does not cover.
7. It satisfies `../../nativa-project/references/requirements.md`, `working-method.md`, and `../../nativa-project/references/maturity.md`.
8. Evidence covers the happy path and, when applicable, limits, failures,
   concurrency, memory, and visual regressions.

## Tests

- Unit: one package, without Flutter except in `nativa_render`.
- Widget: layout and renderer behavior with `flutter_test`.
- Integration: HTML + CSS + JS + renderer end-to-end.
- Conformance: external suites; see `../../nativa-conformance/references/conformance.md`.
- Regression: every fixed bug leaves a test with the minimal case.

## Mandatory commands

```bash
# Pure Dart packages
cd packages/nativa_js && dart test
cd packages/nativa_dom && dart test
cd packages/nativa_html && dart test
cd packages/nativa_css && dart test
cd packages/nativa_dom_bindings && dart test

# Flutter packages (run from each package directory: native assets are
# resolved per package; `flutter test packages/...` from the root is not
# equivalent)
cd packages/nativa_render && flutter test
cd packages/nativax && flutter test

# Analysis
dart analyze tools/conformance
flutter analyze packages/nativa_render
flutter analyze packages/nativax

# Everything
./tools/test_all.sh
```

Run `./tools/test_all.sh` with the game closed.

## Benchmarks and leaks

- Benchmarks: warm-up, rounds, median/MAD/percentiles, checksum, metadata, and
  comparison with threshold plus noise. See `tools/benchmark/README.md`.
- Leaks: baseline, batches, GC, positive/negative controls, resource counters,
  and `FAIL` only with a sustained trend. High RSS is not a leak.
- Benchmarks do not replace conformance; leaks are not declared from a single
  sample.
- See the `tools/leaks` contract (in progress) and
  `../../nativa-performance/references/performance.md`.

## Conformance

- `PASS` requires that the test ran and its assertions passed.
- `FAIL` includes both bugs and unimplemented functionality.
- `SKIP` is only for runner limitations or an explicit scope decision; never to
  hide a failure.
- `ERROR` is a runner failure, not a product failure.
- Publish numbers with the suite commit and date.

## Format and style

- Run `dart format` on touched Dart code. Dart 3.13 may reformat old files; do
  not mix large reformatting with functional changes.
- There is no shared `analysis_options.yaml` yet: do not introduce new lints
  without applying them to the whole workspace.
- Code comments are in English; public product documentation is in Spanish.

## Performance

- Do not optimize without measurement.
- Benchmarks live in `tools/benchmark`; results belong in `progress/`.
- Bridge budget: keep a trivial call below 5 µs.
- Frame budget: 16 ms on Linux desktop. Any operation that can exceed it must be
  asynchronous or batched.

## Security

- Scripts never receive Dart objects.
- Every external input (HTML, CSS, JS) has limits.
- A host error does not reveal paths, internal stacks, or Dart details.
