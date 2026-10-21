---
name: nativa-conformance
description: Use when running or interpreting Test262, html5lib, URL, WPT DOM, CSS selectors, or tree construction, or when adding measured web compatibility.
---

# Nativa conformance

Read `references/conformance.md` and `references/test-infrastructure.md` before
running or reporting a suite.

## Workflow

1. Confirm the suite checkout and pinned commit. Do not use an unpinned local
   copy for a baseline claim.
2. Run the affected runner from `tools/conformance`:

```bash
dart run bin/fetch_suites.dart --suite test262 --suite html5lib
dart run bin/fetch_suites.dart --suite wpt
dart run bin/run_test262.dart
dart run bin/run_html5lib.dart
dart run bin/run_url.dart
dart run bin/run_wpt.dart
dart run bin/run_html_tree.dart
```

3. Classify every result as `PASS`, `FAIL`, `SKIP`, or `ERROR` using the
   definitions in the reference.
4. Compare PASS/FAIL per test, not only the percentage.
5. Update `progress/reports/` and the conformance table with the command,
   commit, date, PASS, FAIL, SKIP, ERROR, and rate.
6. For compatibility work, keep each real ~1 % gain as its own commit and stop
   to report it. A runner/adapter correction is not a real compatibility gain.

## Non-negotiables

- `SKIP` never counts as compatibility.
- Do not delete, disable, or reclassify tests to inflate a rate.
- Do not change the denominator or the metric.
- Do not present an unmeasured or simulated result.
- If a suite cannot reach the target, say so and explain the gap.
