# Test infrastructure and evidence

## Principle

Every run must be reproducible, comparable, and auditable. A result without a
command, version, seed, platform, and configuration is not evidence.

## Structure

```text
tools/
  conformance/   # official suites (Test262, WPT, html5lib, URL)
  benchmark/     # JS, Dart, bridge, DOM, CSS, style
  leaks/         # memory, retention, lifecycle
  fuzzing/       # (pending) generators, oracles, minimizer
  security/       # abuse, isolation, limits
  visual/        # (pending) golden images and tolerances
  stress/        # (pending) long-running and exhaustion
  compatibility/ # (pending) platform/version matrix
  test_all.sh    # current local runner
```

`progress/reports/` stores only the latest readable report per suite. Raw
results and dated Markdown archives go to ignored directories (`.conformance/`,
`benchmarks/results/`, `benchmarks/leaks/`, `benchmarks/security/`).

## Execution profiles

| Profile | When | Contents |
|---|---|---|
| `ci-fast` | Every change | unit + widget + analyze + scoped conformance + benchmark smoke |
| `ci-full` | Merge/nightly | all suites, regression thresholds |
| `nightly` | Daily | fuzzing, short long-running tests, visual, extended memory |
| `stress` | Weekly/dedicated | 24–72 h, controlled exhaustion, multi-platform |
| `release` | Before publishing | full matrix, reproducibility, installation, migrations |

## Minimum record per run

- commit and branch,
- NativaX and QuickJS-ng versions,
- OS, architecture, mode (JIT/AOT),
- configuration and profile,
- seed (if randomness is involved),
- date and duration,
- status per case (`PASS/FAIL/SKIP/ERROR/INCONCLUSIVE`),
- raw JSONL results,
- JSON and Markdown summaries,
- comparison with baseline and threshold/noise.

## Central orchestrator

`tools/test_all.sh` is the current local entry point. It must evolve into an
orchestrator that:

1. Discovers suites and profiles.
2. Runs in order and saves partial results if a suite fails.
3. Applies timeouts and limits.
4. Generates one report linking the per-suite reports.
5. Returns distinct exit codes for test failure, regression, and infrastructure
   error.
6. Allows reproducing a case with `--only` and a seed.

## Fuzzing

- Deterministic generators with a seed.
- Oracles: DOM parser/serialization, CSSOM, selectors, JS engine.
- Differential testing only against references that are actually available and
  documented.
- Automatic case minimization.
- Versioned corpus of failures and seeds.
- A fuzzing failure becomes a regression test before it is closed.
- Time/memory limits; dangerous cases run in an isolated process.

## Security

- Host, file, process, and unexposed-API access tests.
- CPU, memory, stack, node, and storage limits.
- Malformed inputs and hostile resources.
- Reentrancy and operations after `dispose()`.
- Dependencies: vulnerabilities, licenses, and maintenance.
- Isolation between contexts/documents.
- Destructive scenarios do not run by default.

## Visual regression

- Golden images per platform/DPI/font.
- Explicit tolerances (antialiasing, hinting).
- Cases: flex, positioning, stacking, images, text, scroll, resize.
- Do not approve a visual difference just because a functional test passes.
- Do not fail because of font differences without comparing on the same
  platform.

## Accessibility and input

- Semantics tree (roles, labels, headers, links, buttons).
- Focus and tab order.
- Keyboard: keydown/keyup, activation, escape, arrows.
- Text scaling and contrast.
- Accessible forms.
- Flutter tests with `SemanticsTester`/`tester.ensureSemantics`.
- Do not claim full accessibility just because labels exist.

## Long-running tests

- Run a reference app with periodic activity.
- Measure RSS, QuickJS heap, nodes, listeners, timers, and handles.
- Check latency (p50/p95/p99) at the start, middle, and end.
- Detect sustained growth, not just that the process is alive.
- Store periodic samples and compare trends.
- Limit RAM/time and abort with a partial report.

## Regressions

- Benchmarks: per-category threshold plus measured noise (MAD/median).
- Conformance: compare PASS/FAIL per test, not just the percentage.
- Leaks: compare state and trend, not a single sample.
- Visual: tolerance per platform.
- Every confirmed regression needs an issue, a minimal case, and a test.

## Reproducing failures

A failure must include:

1. commit,
2. command,
3. profile/configuration,
4. seed,
5. minimal input or steps,
6. expected and actual result,
7. logs/JSONL.

Without these it is an anecdote, not a reproducible bug.

## Quality gating

- `ci-fast` must be fast and stable; if flaky, fix it or quarantine it with an
  owner.
- `ci-full` may be slower; "green" by omitting suites is not allowed.
- Benchmarks do not block because of noise; only a confirmed regression blocks.
- `INCONCLUSIVE` leaks do not block, but they are recorded and reviewed.
- An infrastructure `ERROR` blocks publication.
- Do not publish a platform without a real build and tests on that platform.

## Current state

- Conformance, benchmarks, and leaks have tools and formats.
- Fuzzing, security coverage, visual, accessibility, stress, and compatibility
  are pending; they are not presented as implemented.
- The central orchestrator is still `tools/test_all.sh`; profile evolution is
  part of phase 6.
