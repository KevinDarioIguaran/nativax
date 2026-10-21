---
name: nativa-docs
description: Use after a functional change or checkpoint to update progress, status, conformance reports, and public docs consistently and without invented numbers.
---

# Nativa documentation

Read `../nativa-verification/references/working-method.md` and
`../nativa-verification/references/quality-standards.md` for the
evidence and definition-of-done rules.

## Workflow

1. Identify the change type: feature, compatibility increment, refactor,
   benchmark, security finding, or documentation-only.
2. Update the right sources:
   - `progress/status.md`: current state, tests, rates, and next targets.
   - `progress/log.md`: what changed and the exact commands.
   - `progress/conformance.md`: PASS/FAIL/SKIP/ERROR and rates.
   - `progress/reports/`: readable per-suite reports.
   - `docs/`: API contracts, limits, and guides.
   - `STATUS.md`: short session summary.
3. Keep product documentation in Spanish and agent/tool documentation in
   English, matching the existing repository.
4. Every number needs a date, command, commit, and environment. Link the raw
   result or report.
5. Separate measured compatibility, measured performance, observed retention,
   and unconfirmed suspicion.
6. If a number is stale or unknown, say so instead of copying the old one.

## Rules

- Do not update a rate without running the suite.
- Do not present an adapter/harness correction as a product compatibility gain.
- Do not hide a regression because the average improved.
- Do not leave progress and code inconsistent at the end of a session.
