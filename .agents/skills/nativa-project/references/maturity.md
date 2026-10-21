# Maturity model and expectation level

The central idea: **NativaX does not need more tests; it needs tests that find
real failures, prove they were fixed, and prevent them from returning.**

A high Test262/WPT percentage, a fast benchmark, or a leak suite without
controls does not prove maturity. Maturity is demonstrated with reproducible
evidence under normal and extreme conditions.

## 1. Mandatory areas

| # | Area | Goal | Minimum evidence |
|---|---|---|---|
| 1 | Conformance | Measure real standards compatibility | Test262, WPT, html5lib, URL, DOM, CSS, events, forms, parser |
| 2 | Performance and latency | Per-category/platform performance without hiding the bad parts | JS/Dart benchmarks, startup, DOM, CSS, render, memory, GC, latency |
| 3 | Memory and lifecycle | No unbounded growth under normal use | Leaks, cycles, callbacks, timers, handles, caches, create/destroy |
| 4 | Security | A faulty script cannot compromise the process without limits | Isolation, host access, CPU/RAM, hostile resources, reentrancy, post-dispose |
| 5 | Platforms | Same semantics and documented behavior | Android, iOS, Linux, Windows, macOS; DPI, orientation, input, accessibility |
| 6 | Differential and fuzzing | Discover what nobody wrote by hand | HTML/CSS/JS generators, oracles, minimization, fixed seed |
| 7 | Visual regression | Detect differences functional tests miss | Golden images, tolerances, fonts, images, flex, position, resize |
| 8 | Accessibility and input | Use without relying only on sight/touch | Semantics, reader, focus, tab, contrast, text scaling, gestures |
| 9 | Resources and async | No pending operation corrupts a destroyed view | Failures, cancellation, timeouts, races, late callbacks |
| 10 | Architecture and maintainability | Add features for years without chaos | Stable APIs, bounded modules, contracts, migrations, cross-tests |

## 2. Extreme tests that are still missing

These separate a demo from a framework that survives real use:

| Category | What to try to break |
|---|---|
| Differential fuzzing | Thousands of random HTML/CSS/JS inputs against references |
| Long-running | 24–72 h apps; responsiveness, resources, and degradation |
| Initialization failure | Interrupt creation at every stage |
| Error recovery | Exceptions, corrupt resources, callbacks, native errors |
| Races | Destroy a view with pending loads/tasks |
| Exhaustion | RAM, CPU, descriptors, files, tasks |
| Context changes | Suspend/resume, orientation, resize |
| Backward compatibility | Old projects with a new version |
| Installation | Install, update, uninstall, reinstall |
| Visual stress | Thousands of nodes, long text, images, continuous updates |

For long-running tests, "still alive" is not enough: it must still respond, not
accumulate resources, and not degrade performance.

## 3. Specific security

- **Isolation**: one context cannot read/modify another without authorization.
- **Host**: JS cannot access files, processes, or unexposed native APIs.
- **CPU**: infinite loops and tasks that block the thread.
- **Memory**: massive allocations, deep structures, growth.
- **Hostile resources**: malformed HTML/CSS/images/responses.
- **Reentrancy**: callbacks that re-enter while an operation is being processed.
- **Lifecycle**: references/operations after `dispose()`.
- **Dependencies**: vulnerabilities, incompatible licenses, abandonment.

Dangerous scenarios run with limits and, when feasible, in isolated processes. A
same-thread timeout does not always interrupt a JavaScript infinite loop.

## 4. Rendering quality

"It looks fine" is not enough:

- visual differences against references,
- resize and screen density,
- system/web fonts and substitution,
- images, transparency, clipping, and proportions,
- positioning, stacking contexts, and `z-index`,
- nested scroll, gestures, and touch events,
- focus, virtual keyboard, and forms,
- native accessibility,
- animations and frame stability,
- layout errors after massive mutations.

Visual tests store references and use explicit antialiasing/font tolerances per
platform. A pixel difference is not automatically a failure.

## 5. Quality levels

These are not an official certification; they are an internal scale for stating
honestly where NativaX stands.

### Level 1 — Functional

- Basic components work.
- Unit, integration, and public-contract tests.
- Initial conformance measured.
- Reproducible local build.

### Level 2 — Reliable

- Regressions controlled.
- Conformance measured and published.
- Reproducible builds.
- Supported platforms compiled and tested.
- Benchmarks with baseline and noise threshold.
- Leaks with controls and clear states.

### Level 3 — Resilient

- Continuous fuzzing with minimization.
- Long-running tests.
- Resource limits and failure recovery.
- Leak detection in bridge/runtime/renderer.
- Platform and accessibility matrix.
- Visual regression.

### Level 4 — Production-mature

- Security reviewed and documented.
- Public compatibility and limitations.
- Error diagnostics and version policies.
- Release process and migrations.
- Evidence of stability in real applications.
- Metric and regression history.

**You do not need 100 % in every suite to advance.** Declare what is
implemented, what was measured, and what was not.

## 6. Rules for agents

1. Do not touch a component without studying contracts and dependencies.
2. Do not consider something done just because it compiles.
3. Add a test for every fix.
4. Do not hide failures with `SKIP`.
5. Do not present simulated results or unmeasured metrics.
6. Do not compare performance under incompatible conditions.
7. Do not delete old tests to improve percentages.
8. Do not add public APIs without documentation and tests.
9. Do not accept silent memory, performance, or compatibility regressions.
10. Do not claim platform support without compiling and testing it.

## 7. Priority

1. **Conformance**: DOM, CSS, and tree construction.
2. **Performance**: reliable JS vs Dart baseline.
3. **Memory**: leaks in the JS-Dart bridge and runtime destruction.
4. **Fuzzing and security**.
5. **Visual and multi-platform regression**.
6. **Long-running resilience and publication**.

## 8. Current state (honest)

Live numbers are in `progress/status.md`. At the last checkpoint: 316 tests,
Test262 97.93 %, html5lib 99.26 %, URL 70.98 %, WPT DOM 59.36 %, CSS selectors
10.38 %, tree construction 48.72 %.

| Level | State | Evidence |
|---|---|---|
| 1 — Functional | 🟡 in progress | 316 tests, basic renderer/runtime, measured conformance |
| 2 — Reliable | 🟡 partial | JSON/MD conformance, benchmarks, leaks; CI, platforms, and stable baseline still missing |
| 3 — Resilient | 🔴 no | No fuzzing, security coverage, visual, accessibility, or long-running evidence |
| 4 — Production | 🔴 no | No release, policies, migrations, or real-world evidence |

Phase 4 remains open: the target WPT suites do not reach 70 %.
