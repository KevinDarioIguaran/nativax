# Juez de auditoría JSON — interfaz

Visual explorer for the reports written by `tools/audit` (`nxaudit`). It only
reads, organises and displays them. It runs no LLM and fills in no data. The
"Instrucciones" tab shows the brief that `nxaudit/report.py` builds from a
deterministic template.

```bash
python3 tools/audit/gui/app.py                       # root: .audit/
python3 tools/audit/gui/app.py --root /path/to/reports --unit /path/to/reports/x/run-7
python3 tools/audit/gui/test_gui.py                  # data layer, diff, widgets, every section
```

It also opens from the main panel: **Auditoría JSON → Abrir el juez**.

## Reports are independent folders

A report is any folder that contains `summary.json`, `results.jsonl` or
`state.json`. Discovery is recursive (`store.discover`), so reports can sit in
any folder hierarchy (`.audit/runs/…`, `.audit/benchmark/…`,
`equipo/nightly/runs/…`). The left tree expands folders lazily. Its colours
mean:

- red: there is a critical or high issue;
- yellow: there are issues;
- green: no issues;
- grey: the report is incomplete or unreadable.

`latest/` is shown as a *copy of* the run it duplicates, not as another report.

- Opening a report loads **only that folder**. Every section shows only that
  folder's data (`store.Unit`).
- Two reports are combined only in **Comparación**, which labels A and B with
  their paths. It also warns when configuration, commit, generator version or
  engine differ, because then a change in the metrics cannot be attributed to
  the code.
- The GUI never writes inside a report. Exports go to a folder the user picks
  outside the report. A test checks sizes and mtimes of every file before and
  after visiting every section.
- `ledger.json` belongs to an engine home, not to a run. It is labelled that
  way wherever it appears (Regresiones, the "1.ª vez" column, tab F).

## Data inventory → where it is shown

| Engine artifact | Field(s) | Section |
|---|---|---|
| `summary.json` | run_id, seed, system, started/finished, config | top bar, Resumen, Algoritmo, Comparación |
| `metrics.json` (or `summary.metrics`) | every key | Resumen (tiles + full table), Rendimiento, Comparación |
| `summary.coverage` / `coverage.json` | dimension × generated/executed/verified/universe, executed_features | Cobertura (table, chart, executed features, never-exercised types/properties) |
| `summary.strategies` | executed, mean_ms, first_found, yield per family | Algoritmo, Comparación |
| `results.jsonl` | scenario, comparison (status, findings, notes), timings, engine, statuses | Ejecuciones, Catálogo, Inspector (Hallazgos), Trazas, Componentes y propiedades, Rendimiento, discovery curves |
| `observations.jsonl.gz` | per-state probes of both engines, action results, FlutterErrors, RSS | Inspector (Disposición medida, Observación NativaX/Chromium, property table Chromium vs NativaX), Rendimiento (RSS per scenario) |
| `selection.jsonl` | round, rank, novelty, new_features, ucb, bonus, score, chosen, reason | Algoritmo (decision table) |
| `state.json` | executed, budget, updated_at | Informes (incomplete runs), Resumen (pending) |
| `issues/NX-*.json` | the whole report contract | Centro de defectos, Defecto tabs A–F + JSON, Minimización, Comparación |
| `issues/NX-*.md` | template brief | Defecto → Instrucciones |
| `benchmark.json` / `self-check.json` | detection/localization scores | Resumen (metrics table, source labelled), Archivos |
| `<home>/ledger.json` | status, first/last seen, fixed_at | Regresiones, Centro de defectos, Defecto F |
| `tools/audit/regressions/*.json` | promoted minimal cases | Regresiones → Inspector |

## Not available (shown as such, never invented)

- **Per-scenario timestamps.** `results.jsonl` has no time per scenario, so the
  date is per report.
- **Generated-but-not-executed candidates.** Only counters are stored
  (`generated`, `rejected`, …). `selection.jsonl` lists the candidates scored
  in each round (chosen and discarded), but only for runs made after it was
  added. Older runs show the gap explicitly.
- **Code changes that fixed an issue.** Only the `verify` result is stored.
- **Call graph and source column.** Only stack frames (file:line) and
  `git grep` hits labelled as search hits.
- **Screenshots.** The audit harness stores none. *Disposición medida* draws
  the rectangles the probe measured in each engine; it is not a pixel render.
- **Memory per phase.** Only harness RSS before/after each scenario and the
  run maximum are recorded.

## Actions (all call the real engine)

- **Reproducir:** `audit.py replay <issue.json>`.
- **Verificar:** `audit.py verify <id>`. It asks for confirmation because it
  updates that issue's report in `.audit/latest` and the ledger, and it is
  disabled for any other report.
- **Promover:** `audit.py promote <issue.json>`. It writes to
  `tools/audit/regressions/`.
- **Ejecutar el motor:** `run` / `benchmark` / `self-check` with their flags.

The output of each action is shown live. The folder tree reloads when it ends.

## Scale

- Tables filter, search and sort over all rows and insert only the visible
  page (200 rows). The test covers 20,000 rows.
- The component tree and the folder tree expand lazily.
- `observations.jsonl.gz` is read only when a section needs it.
- The JSON viewer truncates its display above 1.5 M characters; "Copiar JSON"
  always copies the whole document.
