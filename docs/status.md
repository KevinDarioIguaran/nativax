# Status and maturity

**Snapshot:** 2026-10-26, `HEAD` `f47240e`, working tree contains uncommitted
information-architecture and documentation changes. This page is the stable
maturity view; [`../progress/status.md`](../progress/status.md) is the live,
short status and [`../progress/conformance.md`](../progress/conformance.md) is
the conformance baseline.

NativaX is **experimental and pre-1.0**. It has a working runtime for real pages
on Linux x86_64 and a substantial standards test suite, but it is not a browser
replacement and does not claim production readiness. The honest summary is:
**the core chain works; coverage, platforms, accessibility, resilience, and
several engine paths are incomplete.**

## What is actually proven

| Area | Status | Evidence | Limits |
|---|---|---|---|
| `HTML → DOM → CSS → Flutter` flow | **Implemented, partial verification** | Widget tests, conformance suites, examples | Visual fidelity is 52.59 % mean on 51 vendored pages |
| Public `NativaXView` / `NativaXRuntime` | **Implemented** | `packages/nativax/test/runtime_test.dart`, `web_platform_render_test.dart` | Full `test_all.sh` is flaky at `game_play_test.dart`; final 2026-10-26 run failed |
| HTML parsing | **Partial** | html5lib tokenizer 99.26 %; tree construction 83.03 % | Tree path delegates to `package:html`; template/quirks gaps; 1,025 tokenizer SKIPs |
| DOM, events, selectors | **Partial** | WPT `dom/nodes` 70.00 %, `dom/events` 71.23 %, CSS selectors 70.56 % | The WPT adapter is deliberately lite; reftests and testdriver are skipped |
| CSS and layout | **Partial** | Renderer tests, 51-page visual baseline | Flex/grid/table/SVG approximations; visual layout score 53.04 % |
| JavaScript language | **Verified for QuickJS subset** | Test262 97.93 % on `language/*` subset | Test262 runs on QuickJS; V8 has not been run through the suite; 1,108 SKIPs |
| Engine selection and fallback | **Implemented, partial verification** | Runtime and V8 tests; V8 memory fallback | V8 lacks modules, WebAssembly, SAB, WebGL; only Linux has a built library in this tree |
| Workers and messaging | **Implemented** | `workers_test.dart`, messaging tests, game boot | Workers use QuickJS; no long-running stress or cross-platform verification |
| Resources and network policy | **Implemented** | Loader tests, network tests under bindings | Flutter resource-policy security case is `SKIP`; host policy is the real boundary |
| Visual fidelity | **Measured, low** | 51 pages, Chromium headless reference | 6 PASS / 5 WARN / 40 FAIL; not a conformance metric |
| Performance | **Measured, misses targets** | 270 scenarios registered; 17 measured in latest pass | Offscreen CPU pumps, not GPU/FPS; latest pass 5 PASS / 2 WARN / 10 FAIL |
| Security | **Partial** | 45 cases: 44 PASS, 0 FAIL, 1 SKIP | No OS sandbox; no fuzzing/SCA; Linux only |
| Platforms | **Linux only verified** | Build/test/measurement records | Android/iOS/macOS/Windows unverified |
| Accessibility | **Unknown / mostly absent** | No dedicated evidence | Do not claim screen-reader, focus, contrast, or text-scaling support |

## Conformance snapshot

Percentages exclude `SKIP`. A `SKIP` is not compatibility. These are the last
recorded suite runs, not a fresh run during this documentation change.

| Suite | PASS | FAIL | SKIP | ERROR | Rate | Recorded |
|---|---:|---:|---:|---:|---:|---|
| Test262 `language/{expressions,statements,types,literals}` | 19,577 | 413 | 1,108 | 0 | 97.93 % | 2026-10-24 |
| html5lib tokenizer | 5,759 | 43 | 1,025 | 0 | 99.26 % | 2026-10-24 |
| WPT URL fixture | 665 | 231 | 0 | 0 | 74.22 % | 2026-10-25 |
| WPT `dom/nodes` | 196 | 84 | 47 | 0 | 70.00 % | 2026-10-24 |
| WPT `css/selectors` | 127 | 53 | 348 | 0 | 70.56 % | 2026-10-24 |
| WPT `dom/events` | 52 | 21 | 103 | 0 | 71.23 % | 2026-10-24 |
| WPT tree construction | 1,556 | 316 | 99 | 2 | 83.03 % | 2026-10-25 |

Two tree-construction gains came from fixing the runner's comparison
attributes/namespaces, not from a product change. They are legitimate
measurement corrections but must not be presented as new engine compatibility.
See [`../progress/conformance.md`](../progress/conformance.md).

## Visual and performance snapshot

Visual judge, 51 vendored pages at 800×900, network blocked, animations frozen:

| Metric | Value |
|---|---:|
| PASS / WARN / FAIL / INVALID | 6 / 5 / 40 / 0 |
| Mean overall | 52.59 % |
| Position | 36.20 % |
| Layout | 53.04 % |
| Color | 45.24 % |
| Design | 96.72 % |
| Pixels with ΔE > 2 | 6,569,980 / 36,720,000 |

The dominant visual failure is layout/positioning, not the cascade. This is a
baseline, not a compatibility rate.

Performance suite, latest measured pass:

| Metric | Value |
|---|---|
| Registered scenarios | 270 |
| Measured scenarios in latest pass | 17 |
| PASS / WARN / FAIL / INVALID | 5 / 2 / 10 / 0 in the latest pass |
| Desktop app idle, blank page | 105.0 MB RSS, 0.00 % CPU |
| Target frame p95 in scroll | ≤ 16.7 ms |
| Target work ratio vs Chromium | ≤ 3× |

The suite misses targets on large row creation/update and 10k-row scroll. A
single pass is not FPS. See [`performance-suite.md`](performance-suite.md) and
[`../progress/reports/perf-latest.md`](../progress/reports/perf-latest.md).

## Engine reality

The default engine is not “QuickJS-only” anymore, and it is not “V8
everywhere” either.

| Context | Engine |
|---|---|
| Linux/macOS/Windows page, V8 library loadable, no module script, no force flag | V8 |
| Linux/macOS/Windows page, V8 library missing or already live on the thread | QuickJS-ng |
| Page with `<script type="module">` | QuickJS-ng |
| Mobile, or `NATIVAX_ENGINE=quickjs`, or `forceQuickJs: true` | QuickJS-ng |
| V8 heap limit reached during startup | Page is recreated on QuickJS |
| V8 heap limit reached after startup | `onEngineOverBudget` fires; the Flutter view reloads on QuickJS |
| Dedicated/in-process worker | QuickJS-ng |

V8 has no ES-module support, WebAssembly, SharedArrayBuffer, or WebGL bridge in
this repository. Pages needing those features must force QuickJS or supply a
custom engine. V8 is also not covered by the recorded Test262/WPT runs, which use
QuickJS. See [`architecture/javascript-engines.md`](architecture/javascript-engines.md).

## What is not proven

- **Full test suite green.** `./tools/test_all.sh` is flaky at
  `packages/nativax/test/game_play_test.dart`. Repeated runs on 2026-10-26
  produced both `exit 0` and `TestDeviceException(Shell subprocess crashed with
  SIGABRT (-6))`; the final run exited 1. The same failure occurred at clean
  `HEAD`, and root cause is not established. There is no CI.
- **Platform support beyond Linux x86_64.** Engine selection code exists for
  other platforms, but no current build/test/security evidence is recorded.
- **Real browser parity.** WPT is a lite adapter. Reftests, testdriver, workers,
  and the full `testharness.js` are not run.
- **Accessibility.** No screen-reader, semantic-tree, focus-order, contrast, or
  text-scaling matrix exists.
- **Long-running resilience.** No 24–72 h soak, no sustained mutation/fuzz
  campaign, no leak proof across platform lifecycles.
- **Security.** 44 PASS on concrete attacks is not an absence-of-vulnerability
  proof. There is no OS sandbox, no SCA/SAST gate, and no fuzzing campaign.
- **V8 performance or conformance.** V8 is integrated for desktop pages, but
  Test262/WPT measurements are QuickJS. V8 memory/RSS data exists, not a
  standards score.
- **Production release process.** No CI workflows, versioning policy, migration
  policy, or supported-platform release artifacts are present in this repo.

## Maturity levels

Using the internal scale from the agent maturity reference:

| Level | State | Reason |
|---|---|---|
| 1 — Functional | **Partial** | Core chain, tests, conformance, and examples exist; full suite is flaky, no CI |
| 2 — Reliable | **Partial** | Baselines and limits exist; CI, cross-platform coverage, and stable release process do not |
| 3 — Resilient | **No** | No long-running/fuzz/accessibility evidence; security scope is narrow |
| 4 — Production-mature | **No** | No release, support, migration, or real-world durability evidence |

The next status change should be driven by evidence, not by adding pages:
diagnose the `game_play_test.dart` SIGABRT, add CI, verify one non-Linux
platform, expand WPT/CSS with the renderer, and add accessibility and long-run
tests. Those are separate changes with their own commits and measurements.

## How to update this page

1. Run the exact suite/benchmark; do not copy an old percentage.
2. Record date, commit, command, platform, engine, and artifact path.
3. Update [`../progress/conformance.md`](../progress/conformance.md) or the
   relevant `progress/reports/*-latest.md` first.
4. Update this page only after the evidence exists.
5. Update [`../progress/status.md`](../progress/status.md) and
   [`../progress/log.md`](../progress/log.md) in the same change.
