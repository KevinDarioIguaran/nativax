# Progress and evidence

This directory holds the current progress record and generated evidence. The
repository source and tests remain authoritative; a report is a projection.

## Files

- [`status.md`](status.md): compact live state, measurements, blockers, next
  step.
- [`conformance.md`](conformance.md): current suite baseline, gaps, and
  methodology.
- [`phases.md`](phases.md): phase checklist and current gates.
- [`log.md`](log.md): chronological work log with commands/results.
- [`history/`](history/): replaced snapshots, including the earlier Spanish
  status/log/phases. Historical; not current guidance.
- [`reports/`](reports/): generated Markdown/JSON reports and latest
  convenience copies. Timestamped conformance summaries and JSONL live in
  `debug/artifacts/conformance/results/`; benchmark runs live in
  `debug/benchmarks/<area>/<run_id>/`.

## Update rules

- A functional change updates `status.md` and appends to `log.md`.
- Generated reports are regenerated, not hand-edited.
- Never copy a number without its command/date/commit and environment.
- Do not turn a SKIP, a single leak control, or a 17-scenario performance run
  into a complete pass.
- Link canonical evidence instead of duplicating long tables here.
- Historical Spanish files remain verbatim; the English `docs/` pages are the
  maintained documentation.

## Related

- [`../docs/status.md`](../docs/status.md): stable maturity view
- [`../docs/information-architecture.md`](../docs/information-architecture.md):
  evidence formats and context policy
- [`../debug/README.md`](../debug/README.md): diagnostics layout
