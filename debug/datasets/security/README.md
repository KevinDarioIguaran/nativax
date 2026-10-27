# Security suite accuracy audit

`audit.json` is written by `dart run bin/security.dart evaluate` (from
`debug/engines/security`). It runs the 45 cases once with no fault and once
per deliberate vulnerability (`lib/src/faults.dart`), and records which
cases caught each one. Method, results and limitations:
[`debug/architecture/metrics-security.md`](../../architecture/metrics-security.md).

The "dataset" here is the list of faults in `SecurityFault`; each one names
the cases whose contract it breaks. Nothing in this directory is used by a
normal `run`.
