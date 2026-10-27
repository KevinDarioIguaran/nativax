# Microbenchmark comparator audit

`audit.json` is written by `dart run tool/audit_comparator.dart` (from
`debug/engines/microbenchmarks`). It holds the comparator's answers on
deterministic synthetic samples with known true changes, at five noise
levels. Method, results, the real A/A runs and limitations:
[`debug/architecture/metrics-microbenchmarks.md`](../../architecture/metrics-microbenchmarks.md).
