# Performance suite

The performance suite asks whether NativaX stays fast, responsive, and within
its memory budget while rendering the same page and JavaScript as headless
Chromium. Chromium is only the measuring instrument; nothing browser-like is
embedded in NativaX.

This is separate from the visual judge: visual fidelity asks *does it look the
same?*; this suite asks *how much time, memory, and frame work does it cost?*

## Run it

```bash
# Registered DOM/scroll/JS scenarios + vendored external benchmarks
dart run debug/engines/performance/bin/perf.dart run \
  --out debug/artifacts/perf/latest

# Also measure the real Flutter Linux app idle (opens its window)
dart run debug/engines/performance/bin/perf.dart run --app-idle \
  --out debug/artifacts/perf/latest

# Only the desktop app on a blank page
dart run debug/engines/performance/bin/perf.dart idle-app --seconds 5 --build

# Dashboard: summary, performance, visual, idle, reports, history
python3 debug/engines/performance/gui/perf_gui.py
```

The engine contract, complete scenario table, and output schema are in
[`../debug/engines/performance/README.md`](../debug/engines/performance/README.md).
Offscreen measurements run through `flutter test`; the idle target is the real
Flutter Linux app, not the test harness.

## What is measured

| Metric | Chromium | NativaX |
|---|---|---|
| Scenario/workload time | in-page `performance.now()` | JS evaluation wall time |
| Frame/render work | `LayoutDuration + RecalcStyleDuration` (CDP) | offscreen `tester.pump()` cost |
| Node count | `getElementsByTagName('*').length` | same |
| Heap | `JSHeapUsedSize` | not exposed (`—`) |
| RSS/CPU | PSS/CPU of the process tree from `/proc` | same |
| GPU busy | `/sys/class/drm/.../gpu_busy_percent` when exposed | same |
| Page score | `window.__lastRun` when exposed | same |

`Work = scenario + render`. Chromium's frame number is main-thread layout/style;
NativaX's is build/layout/paint in an offscreen pump. They are related clocks,
not the same clock. The ratio is a regression signal, not FPS.

## Targets and verdicts

- NativaX scroll frame p95 **≤ 16.7 ms**; no frame **> 100 ms**.
- NativaX / Chromium work ratio **≤ 3×** for non-scroll work. Scroll ratios are
  informational because Chromium's compositor can be sub-millisecond.
- Node count within **5 %** of Chromium.
- Desktop app idle: RSS **≤ 250 MB**, CPU **≤ 1 %**.
- `PASS` if all checks hold; `WARN` for one miss; `FAIL` for two or more. Any
  frame over 100 ms is a direct `FAIL`.
- A failed engine or harness is `FAIL`, never a silent `PASS`.
- `idle.blank` is the offscreen harness baseline (includes the test runner); it
  is not the real-app 250 MB target.

## Registered scenarios

The registry contains **270 scenarios**: 264 built-in and 6 resolved external
benchmarks. They cover DOM rows, 1D/2D scroll, pure JS, flex/grid/table layout,
forms, animation, canvas, and idle. The checked-in `scenarios.json` drives the
dashboard's pending rows; it is regenerated with:

```bash
dart run debug/engines/performance/bin/perf.dart list --json \
  > debug/engines/performance/scenarios.json
```

Representative workloads:

| Scenario | Workload |
|---|---|
| `dom.rows-create-1k` / `10k` | Append rows and force layout |
| `dom.rows-update-10k` | Update every tenth row |
| `dom.rows-remove-10k` | Clear 10k rows |
| `scroll.rows-10k` | Scroll and lay out 10k rows |
| `scroll.2d-tiles` | 900 gradient tiles, 2D scroll |
| `js.arrays/objects/strings/json` | Pure JS workloads |
| `idle.blank` | Blank-page offscreen baseline |
| `external.browserbench-quick` | Browser-Bench Quick Run |
| `external.jsfb-create-1k/10k`, `-clear` | Vanilla keyed js-framework-benchmark |
| `external.cerious-load-scroll` | Real Cerious-Scroll page |
| `external.uibench-load-scroll` | uibench load/scroll |
| `external.millionrows-load-scroll` | Only when built manually |

Vendored fixtures and licenses live in `debug/engines/performance/fixtures/`.
Unlicensed suites are downloaded under `debug/artifacts/perf/suites/` and are
not redistributed. PassMark's 2D HTML Scroll is proprietary;
`scroll.2d-tiles` reproduces the workload and cites it.

## Last recorded baseline

The last recorded full measurement is **2026-10-24**, Chrome
152.0.7977.82 headless, viewport 800×900, network blocked, animations frozen.
It measured **17 of 270 registered scenarios**: **5 PASS, 2 WARN, 10 FAIL,
0 INVALID**. This is one baseline, not a full-suite rate.

| Scenario | Verdict | NativaX ms | Chromium ms | Ratio | Frame p95 | Frame max |
|---|---|---:|---:|---:|---:|---:|
| `idle.blank` | PASS | 0.0 | 0.0 | — | — | — |
| `dom.rows-create-1k` | FAIL | 512.0 | 31.4 | 16.33× | 130.6 | 130.6 |
| `dom.rows-create-10k` | FAIL | — | 263.1 | — | — | — |
| `dom.rows-update-10k` | FAIL | — | 29.0 | — | — | — |
| `dom.rows-remove-10k` | WARN | 161.5 | 6.7 | 23.96× | 98.7 | 98.7 |
| `scroll.rows-10k` | FAIL | 2357.5 | 1.2 | 1964.60×* | 199.0 | 234.0 |
| `scroll.2d-tiles` | PASS | 192.8 | 1.2 | 160.69×* | 8.5 | 74.1 |
| `js.arrays` | PASS | 108.1 | 45.7 | 2.37× | 4.6 | 4.6 |
| `js.objects` | PASS | 46.3 | 16.3 | 2.84× | 5.2 | 5.2 |
| `js.strings` | PASS | 20.3 | 13.8 | 1.47× | 5.1 | 5.1 |
| `js.json` | WARN | 133.9 | 36.0 | 3.72× | 4.9 | 4.9 |
| `external.browserbench-quick` | FAIL | 14780.1 | 11281.4 | 1.31× | 1330.0 | 1330.0 |
| `external.jsfb-create-1k` | FAIL | 3723.4 | 118.0 | 31.55× | 272.6 | 272.6 |
| `external.cerious-load-scroll` | FAIL | 149.7 | 0.2 | 748.62× | 27.9 | 49.9 |
| `external.uibench-load-scroll` | FAIL | 11.4 | 0.5 | 22.75× | 0.2 | 4.1 |

`*` Scroll ratios are informational; the frame p95/max target is the real
criterion.

The desktop app on a blank page measured **105.0 MB RSS and 0.00 % CPU**
(peak sample 25.45 % CPU during startup/measurement). GPU was not exposed by
the kernel, so it is reported as `not exposed`, not invented.

Stable findings:

- Pure JS arrays/objects/strings pass; JSON oscillates between PASS and WARN.
  QuickJS is not the CPU bottleneck for these cases.
- Creating 1k rows is roughly 4–16× slower across passes; 10k rows time out or
  take 6.6–8.2 s.
- Updating/clearing 10k rows in one JS call exhausts the QuickJS execution
  budget. That is a real runtime limit, not a harness retry.
- 10k-row scroll has 108–234 ms p95 frames; the UI visibly stalls.
- 900-tile 2D scroll has 6.8–8.5 ms p95 and matching node counts; that path can
  be smooth.
- Vanilla js-framework-benchmark 1k is 13.6–31.5× slower and leaves a
  ~170–273 ms frame; 10k does not complete.
- Cerious/uibench do not initialize the same set of nodes (416 vs 721; 13 vs
  153), so their ratios include a workload difference.

The per-scenario report is
[`../progress/reports/perf-latest.md`](../progress/reports/perf-latest.md). It
was generated before the documentation-language switch and still contains
Spanish labels; the raw run files remain the canonical evidence.

## Outputs

```text
debug/artifacts/perf/latest/
├── results.json
├── results.csv
├── report.md
├── timeline.csv
├── app-idle.json
├── charts/
└── pages/<scenario>/{chromium,nativax}.json
```

Each scenario writes an atomic `results.json` snapshot, so the dashboard follows
a run live. Runs are not FPS promises and are not conformance rates.

## Dashboard and reports

`python3 debug/engines/performance/gui/perf_gui.py` provides:

- summary, visual/perf verdicts, pixels/ink, worst pages/scenarios;
- all 270 scenarios, pending until measured, with RSS timeline and reasons;
- the 300-page visual catalog (51 measured, the rest pending);
- real app idle versus the 250 MB / 1 % target;
- independent reports for performance, visual, games, conformance, JSON audit,
  and recommendations;
- run history comparison and per-row actions to run one scenario/page.

Generated reports:

```bash
python3 debug/engines/recommendations/recommend.py \
  --out progress/reports/recommendations-latest.md
debug/scripts/preview_report.sh
```

`recommend.py` is deterministic and coverage-aware. It reports missing data as
missing; it is not an LLM recommendation.

## Quality gate

```bash
python3 debug/engines/quality_gate/quality_gate.py --run
python3 debug/engines/quality_gate/quality_gate.py
python3 debug/engines/quality_gate/quality_gate.py --json
```

Exit codes: `0` equal/better or baseline created, `2` regression, `3` missing
measurements. It writes `progress/reports/quality-gate-latest.md` and `.json`.
A missing measurement is not a pass.

## Container isolation

```bash
debug/engines/performance/container/matrix.sh
debug/engines/performance/container/run.sh \
  --cpus 1 --memory 1g --name low --only 'js.arrays'
```

Chromium and `flutter test` run in one Docker container with `--cpus`,
`--memory`, and `--network none`. Limits are cgroup quotas, not real CPU
frequency changes. The RSS in the container table is the **test harness** PSS
(694–720 MB), not the real app; the app idle measurement is the 105 MB figure
above.

## Boundaries and limitations

- Offscreen frames are CPU build/layout/paint, not GPU rasterization or display
  refresh.
- Network is blocked for both engines; external resources are absent.
- Heap is only reported for Chromium.
- A single pass varies; compare medians/trends, not one millisecond.
- The JS execution budget is part of the runtime. Work that exceeds it in one
  call is a runtime failure, not a benchmark artifact.
- There is no V8 performance baseline.
- No CI workflow runs this suite automatically.
- No WebView, Chromium runtime, CEF, or Electron is linked into NativaX.

## Related

- [`benchmarks.md`](benchmarks.md)
- [`debugging.md`](debugging.md)
- [`visual-fidelity.md`](visual-fidelity.md)
- [`../debug/engines/performance/README.md`](../debug/engines/performance/README.md)
- [`../progress/reports/perf-latest.md`](../progress/reports/perf-latest.md)
