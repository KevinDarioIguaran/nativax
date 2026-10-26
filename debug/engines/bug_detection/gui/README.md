# JSON audit explorer (GUI)

Read-only visual explorer for reports written by
`debug/engines/bug_detection` (`nxaudit`). It reads, groups, and displays
reports; it runs no LLM and fills in no data. The "Instrucciones" tab shows the
deterministic brief built by `nxaudit/report.py`.

The Tk controls still use Spanish labels; this page keeps those literal labels
in quotes so operators can find them.

```bash
python3 debug/engines/bug_detection/gui/app.py
python3 debug/engines/bug_detection/gui/app.py \
  --root /path/to/reports --unit /path/to/reports/x/run-7
python3 debug/engines/bug_detection/gui/test_gui.py
```

It also opens from the main dashboard: **Auditoría JSON → Abrir el juez**.

## Reports are independent folders

A report is any folder containing `summary.json`, `results.jsonl`, or
`state.json`. Discovery is recursive (`store.discover`), so reports may live in
any hierarchy (`debug/artifacts/audit/runs/...`,
`debug/artifacts/audit/benchmark/...`, or an external nightly tree). The left
tree expands lazily. Colours mean:

- red: critical/high issue;
- yellow: issues present;
- green: no issues;
- grey: incomplete or unreadable report.

`latest/` is displayed as a copy of the run it duplicates, not as another
report.

- Opening a report loads **only that folder** (`store.Unit`).
- Two reports are combined only in **Comparación**, with A/B paths. It warns
  when config, commit, generator version, or engine differ, because then a
  metric change cannot be attributed to the code.
- The GUI never writes inside a report. Exports go to a user-selected folder
  outside the report. A test checks sizes and mtimes before/after visiting every
  section.
- `ledger.json` belongs to an engine home, not to a run. It is labelled that way
  wherever shown (Regresiones, the first-seen column, defect tab F).

## Data inventory → where it is shown

| Engine artifact | Fields | Section |
|---|---|---|
| `summary.json` | run_id, seed, system, start/finish, config | top bar, Resumen, Algoritmo, Comparación |
| `metrics.json` or `summary.metrics` | every key | Resumen, Rendimiento, Comparación |
| `summary.coverage` / `coverage.json` | dimension × generated/executed/verified/universe, executed features | Cobertura |
| `summary.strategies` | executed, mean_ms, first_found, yield per family | Algoritmo, Comparación |
| `results.jsonl` | scenario, comparison/findings/notes, timings, engine, statuses | Ejecuciones, Catálogo, Inspector, Trazas, Componentes, Rendimiento |
| `observations.jsonl.gz` | per-state probes from both engines, action results, FlutterErrors, RSS | Inspector, Rendimiento |
| `selection.jsonl` | round, rank, novelty, new_features, ucb, bonus, score, chosen, reason | Algoritmo |
| `state.json` | executed, budget, updated_at | Informes, Resumen |
| `issues/NX-*.json` | complete issue report | Centro de defectos, Defecto tabs A–F |
| `issues/NX-*.md` | template brief | Defecto → Instrucciones |
| `benchmark.json` / `self-check.json` | detection/localization scores | Resumen, Archivos |
| `<home>/ledger.json` | status, first/last seen, fixed_at | Regresiones, Centro de defectos |
| promoted minimal cases | regression fixtures created by `audit.py promote` | Regresiones → Inspector |

## Not available (shown as missing, never invented)

- **Per-scenario timestamps.** `results.jsonl` has no time per scenario; dates
  are per report.
- **Generated-but-not-executed candidates.** Only counters are stored.
  `selection.jsonl` lists scored candidates for runs made after that file was
  added; older runs show the gap.
- **Code changes that fixed an issue.** Only the `verify` result is stored.
- **Call graph and source column.** Only stack frames and `git grep` search hits
  are available.
- **Screenshots.** The audit harness stores none. “Disposición medida” draws the
  rectangles measured by the probe; it is not a pixel render.
- **Memory per phase.** Only harness RSS before/after each scenario and the run
  maximum are recorded.

## Actions (all call the real engine)

- **Reproducir:** `audit.py replay <issue.json>`.
- **Verificar:** `audit.py verify <id>`. It asks for confirmation because it
  updates that issue report in `debug/artifacts/audit/latest` and the ledger;
  it is disabled for any other report.
- **Promover:** `audit.py promote <issue.json>`. It creates a minimal regression
  fixture under the engine's `regressions/` directory.
- **Ejecutar el motor:** `run` / `benchmark` / `self-check` with their flags.

The output is shown live and the folder tree reloads when the action ends.

## Scale

- Tables filter/search/sort over all rows and insert only the visible 200-row
  page. The test covers 20,000 rows.
- Component and folder trees expand lazily.
- `observations.jsonl.gz` is read only when a section needs it.
- The JSON viewer truncates display above 1.5 M characters; “Copiar JSON”
  copies the whole document.

## Related

- [`../README.md`](../README.md)
- [`../../../../docs/debugging.md`](../../../../docs/debugging.md)
- [`../../../../docs/internals/diagnostics.md`](../../../../docs/internals/diagnostics.md)
