# Compatibility runner validation subset

Hand-verified cases used to check that the conformance runners in
`debug/engines/compatibility` report PASS, FAIL, SKIP and ERROR correctly.

- `suites/` mimics the checkout layout each runner expects (`test262/`,
  `html5lib-tests/`, `wpt/`). Every file was written for this subset. Nothing is
  copied from the upstream suites, and the Test262 harness is a minimal
  rewrite.
- `expected.json` lists each case's expected status and the reason for it (spec
  rule, deliberately wrong fixture, or documented runner policy). The statuses
  were written before the runners were run on the subset.

```bash
cd debug/engines/compatibility
dart run bin/validate_runners.dart
dart test test/validation_test.dart
```

Results and limitations:
[`../../architecture/metrics-gate-compat.md`](../../architecture/metrics-gate-compat.md).
