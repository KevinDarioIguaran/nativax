# NativaX performance suite

Measures whether NativaX renders and reacts like a browser **without a WebView,
Chromium embedded, or a browser toolkit inside the runtime**. Chromium is only
the reference instrument; both engines run the same page and the same JS.

This is separate from the visual-fidelity judge in `debug/engines/visual_comparison`:
`debug/engines/visual_comparison` answers *does it look the same?*; this suite answers *does it
stay fast, responsive and within its memory budget?*

```bash
# Built-in DOM/scroll/JS scenarios + vendored external benchmarks
dart run debug/engines/performance/bin/perf.dart run --out .perf/latest

# Include the real Flutter Linux app idle measurement (opens its window ~8 s)
dart run debug/engines/performance/bin/perf.dart run --app-idle --out .perf/latest

# Just the desktop app on a blank page
dart run debug/engines/performance/bin/perf.dart idle-app --seconds 5 --build

# Tkinter dashboard: summary, performance, visual fidelity, idle, reports
python3 debug/engines/performance/gui/perf_gui.py

# Both quality suites end to end
tools/quality_report.sh --gui

# Headless quality gate (visual + performance + compatibility)
python3 tools/quality_gate.py --run
python3 tools/quality_gate.py --json

# Rendered Markdown preview
tools/preview_report.sh
```

## Scenarios

The registry contains **245 scenarios**: 239 built-in and 6 resolved external
benchmarks (Browser-Bench, js-framework-benchmark, Cerious-Scroll and uibench).
They cover DOM, scroll, pure JS, flex/grid/table layout, forms, animation and
canvas. The checked-in `scenarios.json` drives the dashboard's pending rows; it
is regenerated with:

```bash
dart run debug/engines/performance/bin/perf.dart list --json > debug/engines/performance/scenarios.json
```

Each scenario writes an atomic `results.json` snapshot when it finishes, so the
dashboard follows a run live. It also polls every second, which covers runs
started outside the panel.

| Scenario | What runs | Source / model |
|---|---|---|
| `dom.rows-create-1k` / `10k` | append rows, force layout | uibench, js-framework-benchmark, million-rows |
| `dom.rows-update-10k` | update every 10th row | js-framework-benchmark |
| `dom.rows-remove-10k` | clear 10k rows | js-framework-benchmark |
| `scroll.rows-10k` | 20 scroll+layout steps | cerious-scroll, PassMark 2D HTML Scroll |
| `scroll.2d-tiles` | 900 gradient tiles, 2D scroll | PassMark 2D HTML Scroll (equivalent) |
| `js.arrays/objects/strings/json` | pure JS workloads | Browser-Bench |
| `idle.blank` | blank page, 2.5 s idle | baseline |
| `external.browserbench-quick` | the page's own Quick Run | Browser-Bench (MIT) |
| `external.jsfb-create-1k/10k`, `-clear` | official vanilla keyed implementation | js-framework-benchmark (Apache-2.0) |
| `external.cerious-load-scroll` | real benchmark page, load+scroll | cerious-scroll (MIT) |
| `external.uibench-load-scroll` | fetched UI Benchmark | localvoid/uibench (fetched, no license) |
| `external.millionrows-load-scroll` | only if built manually | million-rows (fetched, no license) |

The vendored fixtures live in `fixtures/` with their licenses and provenance.
Unlicensed suites are downloaded to `.perf/suites/` and never redistributed.

PassMark's 2D HTML Scroll page is proprietary and not publicly redistributable;
`scroll.2d-tiles` reproduces the same workload and cites it.

## What is measured

| Metric | Chromium | NativaX |
|---|---|---|
| Scenario/workload time | in-page `performance.now()` | JS eval wall time |
| Frame/render work | `LayoutDuration + RecalcStyleDuration` (CDP) | `tester.pump()` cost (offscreen) |
| Node count | `getElementsByTagName('*').length` | same |
| Heap | `JSHeapUsedSize` | not exposed (reported as `—`) |
| RSS / CPU | `/proc` PSS/CPU of the whole process tree | same |
| GPU busy | `/sys/class/drm/.../gpu_busy_percent` when exposed | same |
| Page's own score | `window.__lastRun` when the benchmark exposes it | same |

`Work = scenario + render`. Chromium's frame number is main-thread layout/style;
NativaX's is an offscreen pump (build/layout/paint). They are related but not the
same clock: use the ratio as a signal, not as FPS.

## Targets and verdicts

- Frame p95 ≤ **16.7 ms** and max frame ≤ **100 ms** for NativaX scroll.
- Work ratio NativaX / Chromium ≤ **3×** (not applied to scroll: Chromium's
  compositor scroll can be sub-millisecond and the comparison would be
  meaningless).
- Node count within **5 %** of Chromium.
- Desktop app idle: RSS ≤ **250 MB**, CPU ≤ **1 %**.
- `PASS` all checks, `WARN` one, `FAIL` two or more; any frame >100 ms fails.
- A failed engine/harness is `FAIL`, never silently `PASS`.
- `idle.blank` is the **offscreen harness** baseline (includes `flutter test`);
  it is reported as a warning at most and is not the 250 MB app target.

## Outputs

```
.perf/latest/
├── results.json          # run + scenarios + metrics + samples
├── results.csv           # one row per scenario
├── report.md             # tables, reasons, app-idle section
├── timeline.csv          # RSS/CPU samples per scenario/engine
├── app-idle.json         # real Flutter Linux app idle measurement
├── charts/work-ratio.svg
├── charts/frame-p95.svg
├── charts/rss.svg
└── pages/<scenario>/
    ├── chromium.json
    └── nativax.json
```

## Desktop app idle measurement

The 250 MB / 0 % CPU target is about the **app process**, not the test runner.
`examples/web-challenge` has a small test hook: when `NATIVAX_PERF_PAGE` points
to a directory, it loads that page and its relative files instead of the demo.
`idle-app` builds the Linux release bundle if needed, opens it on a blank page,
waits 3 s + 5 s, samples `/proc`, kills it and writes `app-idle.json`.

GPU busy is reported when the kernel exposes `gpu_busy_percent`; otherwise it is
`not exposed` on that machine instead of inventing a value.

## Dashboard

`python3 debug/engines/performance/gui/perf_gui.py` is the control room, with a sidebar
navigation and the same dark/typographic language as the HTML report:

- **Resumen**: fidelity mean, visual/perf verdict donuts, pixel and ink
  statistics, worst pages and scenarios.
- **Rendimiento**: all 245 scenarios (pending until measured), per-op details,
  log-scale work chart, RSS timeline and reasons. The table, cards and charts
  refresh automatically while a run is active.
- **Fidelidad visual**: all 300 catalog pages (51 measured, the rest pending),
  category bars, pixel/colour charts, worst position/colour/style offenders
  and Chromium/NativaX/diff thumbnails.
- **Idle**: real app RSS/CPU versus the 250 MB / 1 % targets and the sample
  timeline.
- **Informes**: one independent report per area — **Rendimiento**,
  **Visual**, **Juegos**, **Conformidad**, **Auditoría JSON** (plus its fault
  benchmark and self-check) and **Recomendaciones**; none mixes another area's
  data. A finished live run opens its own report. Panel-built reports are
  rebuilt from the current JSON data and rendered as an HTML capture. During a run the text refreshes
  without launching Chromium; the capture is regenerated when the run ends.
  The historical reports remain available as manual snapshots.
- **Historial**: every run can be stored as detailed JSON in
  `.visual/history` and `.perf/history`; the dashboard compares the last two
  runs and shows per-case deltas.
- **Row actions**: right-click a scenario/page (or use **Acciones ▾**) to view
  details or run only that test/page. The single result is merged into the
  table and the detail opens automatically.

The toolbar runs everything, only the visual suite, only performance, the real
app idle, refresh, or stop the current run. Output goes to the in-window log,
so no terminal is needed after launching the dashboard.

```bash
debug/engines/performance/gui/run_gui.sh
```

![Dashboard summary](../../../progress/reports/perf-gui.png)

![Performance table with 245 scenarios](../../../progress/reports/perf-gui-perf.png)

## Recommendations

`python3 tools/recommend.py --out progress/reports/recommendations-latest.md`
builds a deterministic P0/P1/P2 report with measured evidence, an action, an
acceptance criterion and a command. It is rule-based and coverage-aware, not a
black-box model. `quality_report.sh` runs it automatically; the dashboard shows
it under **Informes → Recomendaciones**.

## Container isolation (CPU/RAM)

```bash
debug/engines/performance/container/matrix.sh
debug/engines/performance/container/run.sh --cpus 1 --memory 1g --name low --only 'js.arrays'
```

Both Chromium and `flutter test` run inside one Docker container with
`--cpus`, `--memory` and `--network none`. The first run builds
`nativa-perf:local`; Flutter and the repo are mounted at their real paths.
Results are summarized in `.perf/container/matrix.{json,md}` and shown in the
**Contenedores** page, which has CPU (0.25–4), RAM (512 MB–4 GB), name and test
controls, plus the fixed matrix. Limits are cgroup quotas, not real frequency
changes.

## Integrations and boundaries

- Network is blocked in both engines (`--host-resolver-rules` / resource loader),
  matching NativaX's offline-by-default contract.
- Animations are frozen for deterministic layout measurements.
- `flutter test` runs offscreen; the Flutter Linux app is only used for the
  idle measurement.
- The JS execution budget is part of the runtime. Scenarios that exceed it in a
  single call are reported as failures (for example creating 10,000 rows in one
  script), because that is a real runtime limit, not a harness retry.
- No WebView, Chromium runtime, CEF or Electron is linked into NativaX.

## Tests

```bash
cd debug/engines/performance && dart test && dart analyze

# Chrome-only CDP integration test
NATIVA_PERF_E2E=1 dart test test/cdp_e2e_test.dart
```
