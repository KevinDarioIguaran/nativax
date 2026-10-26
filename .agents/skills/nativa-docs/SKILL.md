---
name: nativa-docs
description: Use after a functional change or checkpoint to update progress, status, conformance reports, and public docs consistently and without invented numbers.
---

# Nativa documentation

Read `../nativa-verification/references/working-method.md` and
`../nativa-verification/references/quality-standards.md` for the evidence and
definition-of-done rules.

## Language and ownership

- Maintained first-party documentation is **English**. This includes `README.md`,
  `AGENTS.md`, `COMPAT.md`, `docs/`, current `progress/` pages, maintained
  `debug/` and `examples/` READMEs, and `.agents/`.
- Historical Spanish evidence is allowed only when explicitly archived:
  `docs/archive/legacy-es/`, `progress/history/`, or `debug/archive/`. Archived
  pages are not current guidance and are excluded from link/language checks.
- Generated reports may retain the language they were emitted in; link to the
  raw run and do not treat a report as a maintained page.
- Third-party copied READMEs are excluded and recorded as third-party in the
  docs audit. Do not rewrite upstream licenses/provenance.
- Do not add a WebView, browser engine, local server, or a dependency for a
  documentation convenience.

## Workflow

1. Identify the change type: feature, compatibility increment, refactor,
   benchmark, security finding, or documentation-only.
2. Update the right sources:
   - `progress/status.md`: live state, tests, rates, blockers, next step.
   - `progress/log.md`: dated change, exact commands, results, run IDs.
   - `progress/conformance.md`: PASS/FAIL/SKIP/ERROR and rates.
   - `progress/reports/`: generated/latest readable reports only.
   - `docs/`: contracts, limits, architecture, guides, support pages.
   - `docs/status.md`: stable maturity view.
3. Every number needs a date, command, commit, environment, and evidence link.
4. Separate measured compatibility, measured performance, observed retention,
   and unconfirmed suspicion.
5. If a number is stale or unknown, say so instead of copying the old one.
6. Run the documentation audit for any documentation change:

   ```bash
   python3 tools/check_docs.py
   python3 tools/test_check_docs.py
   ```

   Use `--write` only when updating
   `progress/reports/docs-audit-latest.{json,md}` intentionally.

## Accuracy rules

- Do not update a rate without running the suite.
- Do not present an adapter/harness correction as a product compatibility gain.
- Do not hide a regression because the average improved.
- Do not turn SKIP, INCONCLUSIVE, an idle control, or a partial scenario run
  into PASS.
- Do not claim V8, mobile, or desktop platform support from a QuickJS/Linux run.
- Do not leave progress, code, and docs inconsistent at the end of a session.
- The checker proves links/language/paths, not that every claim is complete.
  Source review and focused tests remain required.

## Related

- `../../../docs/README.md`
- `../../../docs/information-architecture.md`
- `../../../debug/README.md`
- `../../../tools/check_docs.py`
