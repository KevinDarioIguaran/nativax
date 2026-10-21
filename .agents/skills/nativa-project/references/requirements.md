# Hard requirements

These rules are not recommendations. If a task cannot satisfy them, stop and
report the blocker. Do not bypass it with `SKIP`, invented numbers, or semantic
changes.

## 1. Product identity

1. NativaX **is not a browser** and **does not use WebView/Chromium/CEF**. See
   `../../nativa-web-rendering/references/rendering.md`.
2. **NativaX renders its interface through its own runtime**: HTML/CSS/JS are
   interpreted by Nativa packages and the result is painted with Flutter
   widgets and `RenderObject`s. Flutter does not replace the runtime or provide
   a web engine.
3. The final rendering is Flutter widgets and `RenderObject`s; there is no
   embedded browser or page loaded in a WebView.
4. Developers continue to write HTML, CSS, and JavaScript. Dart and Flutter are
   internal details; the public language does not change.
5. JavaScript runs on real QuickJS-ng without JIT. It is not replaced by a toy
   interpreter or text search.
6. Do not claim full WHATWG/W3C compatibility. Declare the subset and measure
   it.

## 2. Correctness and conformance

1. Every new feature needs its own test or a conformance test.
2. `PASS` requires a real run and satisfied assertions.
3. `FAIL` includes bugs and missing functionality. It is not converted to `SKIP`
   to improve a rate.
4. `SKIP` is valid only for:
   - a documented runner limitation,
   - a feature declared out of scope **before** measuring.
   It must include a reason and does not count as compatibility.
5. `ERROR` is a runner failure, not a product failure.
6. Do not delete or disable conformance tests to move faster.
7. Phase 4 does not close until Test262, html5lib, URL, WPT `dom/nodes`, WPT
   `css/selectors`, and WPT tree construction are **≥ 70 %**, with rates
   calculated without `SKIP`.
8. If a suite does not reach the target, say so explicitly. Do not change the
   metric or denominator to fake 70 %.

## 3. Performance

1. Do not claim "faster" without reproducible measurements.
2. Do not compare different engines as equivalent. V8/JavaScriptCore may appear
   only as an external reference, labeled and actually executed.
3. Benchmarks must:
   - use equivalent work,
   - include warm-up and multiple rounds,
   - report median, minimum, maximum, p90/p95/p99, MAD/deviation, and
     uncertainty,
   - include engine, version, OS, architecture, mode, and clock metadata,
   - verify a checksum/result to prove the work was done,
   - separate pure JS, bridge, DOM, CSS/layout, and renderer,
   - save per-round JSONL, summary JSON, and Markdown.
4. A change is a regression only if it exceeds the configured threshold **and**
   the measured noise. Differences within noise are marked `noise`.
5. `dart.*` is a same-process reference, not proof of superiority. The JIT may
   optimize; document that.
6. Do not change JavaScript semantics to improve a score.
7. Do not hide slow cases. Report and explain them.

## 4. Memory, retention, and leaks

1. A one-off RSS increase **does not prove a leak**.
2. To declare `FAIL`, require:
   - a sustained trend across batches,
   - positive and negative controls,
   - resource counters when available (nodes, listeners, timers, wrappers,
     contexts),
   - reproducible evidence.
3. If the data is insufficient: `INCONCLUSIVE`. If it cannot be measured:
   `SKIP` with a reason. If the runner fails: `ERROR`.
4. Every leak test records baseline, batches, cleanup/GC, samples, and trend.
   Do not fill samples with zeros.
5. Distinguish process memory, engine heap, Dart memory, and native resources.
   Do not add overlapping metrics.
6. Respect time, RAM, iteration, and node limits. Extreme tests do not run by
   default.
7. Intentional retention (positive control) must be detected; correct release
   (negative control) must not produce a false positive.
8. Resources released by `dispose()` must reach zero: listeners, timers,
   wrappers, documents, and contexts.

## 5. Code quality

1. `dart analyze`/`flutter analyze` is clean for touched code.
2. Tests are green; no tests are commented out to pass.
3. No debug `print` in libraries.
4. No silently swallowed exceptions without diagnostics.
5. No new dependency without justifying license, maintenance, and compatibility.
6. No public API change without need and documentation.
7. Node, stack, memory, time, and storage limits are part of the contract, not
   hidden options.

## 6. Evidence and documentation

1. Every status claim needs a reproducible command and a real result.
2. Every functional change updates `progress/` in the same session.
3. Numbers are stored with date, suite commit, and environment.
4. Limitations are documented before someone discovers them.
5. Reports distinguish:
   - measured compatibility,
   - measured performance,
   - observed retention,
   - unconfirmed suspicion.
6. Do not deliver "example" results as measurements.

## 7. Security and stability

1. Scripts do not receive Dart objects; only ids, scalars, and JSON.
2. Host errors do not leak paths, stacks, or internal details.
3. Destructive tests have limits and process/isolation when feasible.
4. Do not run unbounded workloads in production or by default.
5. Do not use a runtime after `dispose()`.
6. The engine lives in the isolate that created it; it is not shared across
   isolates.

## 8. Maturity and extreme testing

1. A mature framework is demonstrated with fuzzing, security, memory,
   accessibility, visual, long-running, and multi-platform evidence, not only
   conformance and microbenchmarks.
2. Maturity levels are in `maturity.md`. Do not claim level 3/4 without evidence
   in those areas.
3. Fuzzing, security, and stress tests must be deterministic (seed) and
   reproduce each failure before closing it.
4. Dangerous scenarios run with limits and, when feasible, isolation.
5. Do not claim platform support without compiling and testing that platform.

## 9. Honesty rule

If the goal cannot be met:

- say what is missing,
- show the evidence,
- propose the next step,
- do not falsify the result.

A `SKIP`, `INCONCLUSIVE`, or "not reached" is a valid answer. An invented number
is not.
