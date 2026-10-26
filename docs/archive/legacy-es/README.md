# Legacy Spanish documentation (archive)

These files are the original Spanish-language project documents that were
superseded by the English documentation system on 2026-10-26. They are kept
verbatim as historical evidence. **Do not update them as current state.**

| File | Original role | Why archived | Current replacement |
|---|---|---|---|
| `idea.md` | Original master prompt, scope, product identity, early architecture | Historical requirements; contains plans and claims that were never implemented | `README.md`, `docs/architecture/`, `docs/reference/` |
| `status-2026-10-20.md` | Session status snapshot | Point-in-time status; numbers and paths are stale | `progress/status.md`, `docs/status.md` |
| `performance-audit-2026-10-21.md` | JavaScript engine performance audit | Historical measurement and JIT investigation; methodology and targets are partly superseded | `docs/benchmarks.md`, `progress/reports/` |
| `nativa-js-jit-plan.md` | JIT plan for NativaJS | Proposal; rejected/deferred as a product direction | `docs/architecture/javascript-engines.md`, `docs/status.md` |
| `nativa-js-jit-quickjs-jit-spike.md` | QuickJS-JIT integration spike | Historical spike result | `docs/architecture/javascript-engines.md` |
| `NOTAS_PERF.md` | Early performance scratch notes | Stale notes; measurements without the current run-manifest provenance | `docs/benchmarks.md`, `progress/reports/` |

## Audit status

- Source of truth before the overhaul: the Spanish files above plus the
  maintained Spanish pages in `docs/`.
- The English overhaul replaced the maintained pages in place or with grouped
  pages; this archive preserves the originals rather than deleting evidence.
- Local links inside archived files are **not** required to resolve. The
  documentation checker excludes `docs/archive/` from link and language
  requirements and records the exclusion in
  `progress/reports/docs-audit-latest.json`.
- Where an archived file conflicts with code or current docs, code and the
  current English docs win.

## Provenance

The files were moved with Git history preserved (`git mv`) from their original
locations. Their contents were not edited during the move.
