# Demanding work method

This is the mandatory protocol for every change in Nativa. Do not skip a step
"because it is obvious".

## 1. Inspect before writing

- Read `AGENTS.md`, `docs/status.md`, `progress/`, and the relevant `.agents/` docs.
- Locate the package, API, and existing tests.
- Check existing limits, contracts, and decisions.
- Identify what cannot yet be measured or implemented.
- Do not invent APIs, duplicate subsystems, or replace the engine.

## 2. Define the acceptance criterion

Before coding, write down in the response or in `progress/`:

- what behavior changes,
- which test proves it,
- which command verifies it,
- which metric measures it (if applicable),
- what is explicitly out of scope.

Do not start without a verifiable criterion.

## 3. Design the smallest cut

- Prefer small, reversible changes.
- Keep parser, DOM, CSS, renderer, runtime, and tooling separate.
- Reuse the conventions in `tools/conformance`, `tools/benchmark`, and
  `tools/leaks`.
- Do not mix large refactors with a feature.
- Document approximations and limits in the same change.

## 4. Implement with tests

1. Write the failing test (or the fixture that reproduces the bug).
2. Implement the minimum that makes it pass.
3. Add edge cases: null/undefined, limits, errors, lifecycle.
4. Run:

```bash
dart test            # pure Dart package, from its directory
flutter test         # Flutter package, from its directory
dart analyze
flutter analyze
```

5. Do not continue with unexplained red tests.

## 5. Verify for real

- Run the new test and the existing tests.
- Run `./tools/test_all.sh` with the game closed.
- Run the affected conformance suite if parser/CSS/JS changed.
- Run benchmarks/leaks if performance or lifecycle changed.
- Check that no compatibility rate regressed without documentation.

## 6. Measure without fooling yourself

Performance:

- warm-up,
- multiple rounds,
- median and dispersion (MAD),
- percentiles,
- checksum or identical work,
- environment metadata,
- baseline comparison with both a threshold **and** measured noise.

Memory:

- baseline,
- batches,
- explicit release and GC,
- positive control (retention) and negative control (release),
- resource counters,
- trend, not a single sample,
- `FAIL` only with evidence; otherwise `INCONCLUSIVE`.

## 7. Document in the same change

- `progress/status.md`: state and numbers.
- `progress/log.md`: what was done and the commands used.
- `progress/conformance.md`: rates and gaps.
- `docs/`: API contracts, limits, and guides.
- `.agents/`: new decisions or requirements.
- `docs/status.md`: session summary.

## 8. Report

Every delivery includes:

1. What was implemented.
2. Files created or modified.
3. Exact commands.
4. Real results (tests, rates, medians, memory).
5. What could not be measured and why.
6. A concrete next step.

Do not use "it should work", "probably", or "I think it passes" as evidence.

## 9. Integrity rules

- Do not use `SKIP` to make numbers look better.
- Do not delete slow tests.
- Do not change JavaScript semantics to win a benchmark.
- Do not simulate V8/JavaScriptCore.
- Do not fill missing results with zeros.
- Do not claim 70 % if it was not measured.
- Do not close a phase with pending criteria.
- Do not claim a leak from a single RSS sample.
- Do not hide a regression because the average improved.

## 10. Closing checklist

- [ ] Acceptance criterion written.
- [ ] New and existing tests pass.
- [ ] Analyze is clean.
- [ ] Affected conformance measured (if applicable).
- [ ] Benchmarks/leaks measured (if applicable).
- [ ] Documentation and progress updated.
- [ ] Limitations stated.
- [ ] No invented numbers.
- [ ] Clear next step.

## 11. Phase state

- **Phase 4 is open** until the target WPT suites are ≥ 70 %.
- The benchmark and leak suites are measurement tools, not substitutes for
  conformance.
- A phase is marked ✅ only when its verifiable criterion is met.

## 12. Compatibility increments

- Keep compatibility commits separate from structural refactors.
- Stop, report, and checkpoint after each real ~1 % compatibility gain.
- A measurement-adapter fix is not a real compatibility gain.
- Never mix a compatibility increment with game changes.

## 13. Session report format

```text
Objective:
Changes:
Evidence (commands + results):
Conformance:
Performance/memory:
Limitations:
Next step:
```
