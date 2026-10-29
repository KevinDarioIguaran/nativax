# Current task

Make the debug laboratory useful for **design comparison**: render the same real
case in Chrome and in NativaX, show both captures plus a pixel diff, and report
numbers that come from the real artifacts.

## Implemented (2026-10-29)

### Chrome vs NativaX visual judge

- `debug/judges/visual/chrome_compare.py`
  - Chrome: Playwright Chromium, headless, 1x scale, fixed viewport.
  - NativaX: `build/nativax-runtime --headless --deterministic`.
  - Metrics: changed pixels %, MAE, RMSE, SSIM, bounding box of all differences.
  - Artifacts: `debug/artifacts/visual/<case>/<WxH>/{chrome,nativax,diff}.png`.
  - Report: `debug/reports/visual/latest.json`.
  - Status is derived from thresholds, never hard-coded:
    `pass` ≤2 % changed + MAE ≤6 + SSIM ≥0.90, `warn` ≤8 %, otherwise `fail`.
  - Remote http(s) requests are blocked by default so Chrome and NativaX see
    the same offline assets; `--allow-remote` opts in.
  - `--self-check` verifies numpy, Pillow, Playwright and a real Chromium launch.

### Dashboard

- `debug/dashboard/index.html` has real tabs: Resumen, Chrome vs NativaX,
  Informes, Historial, Artefactos.
- `debug/dashboard/dashboard.js` renders the three screenshots, metrics,
  result selector, report table, history table and artifact grid.
- `debug/tools/build_dashboard_data.py` embeds the lab report, section reports,
  history index, artifacts and visual report, so the dashboard also works when
  opened as a plain file (not only under pywebview).
- `debug/gui.py` starts a visual run from the UI using the venv interpreter
  (system Python does not have numpy/Pillow/Playwright).

### Honesty fixes

- Responsive horizontal overflow is now a real failure; it used to be recorded
  as `pass` with an `overflow: true` note.
- Responsive sweeps no longer keep every width of every case alive
  (`cache=False`); the 240-case `--all` run used to die in section 14 from
  memory exhaustion and now completes.
- Quality gate excludes `.venv`, caches and `site-packages`, prefers the lab
  venv, and reports real `SKIP` instead of silently passing.
- Render goldens now live in `debug/tests/goldens/counter_window.png` and the
  windowed tests run under `xvfb-run` when there is no DISPLAY.
- s17 gap.020 (Chromium comparison) was removed: the capability now exists and
  is checked by `debug/tests/test_chrome_compare.py`.

## Last verified run (2026-10-29)

Full laboratory, no flags hiding work:

```
python3 debug/lab/run_lab.py --all
total: 265 cases, pass=193 fail=47 blocked=25 error=0 in 592.8s
```

- The 47 failures are all real `horizontal overflow at 320px/770px` results from
  the responsive sweep. They are layout defects in NativaX, not test noise.
- The 25 blocked cases are the documented s17 capability gaps.

Quality gate:

```
python3 debug/judges/quality_gate/gate.py
QUALITY GATE: PASS (0 skip(s))
```

Visual smoke (6 representative cases):

```
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --fresh \
  --case html.001 --case css.001 --case typo.001 --case flex.001 \
  --case a11y.001 --case media.001 --widths 1024,768
11 comparisons: pass=0 warn=0 fail=11 error=0
mean changed pixels 72.4 %, mean SSIM 0.444
```

All eleven fail, which is expected today: NativaX still lacks image paint
wiring (gap.010), some gradient/positioning features, and uses different text
rasterization. `media.001` is 99.998 % different because the case is image
driven and NativaX cannot paint those images. The report keeps the exact
numbers instead of pretending the designs match.

Reports accumulate the last comparison per case; `--fresh` resets them. Every
run is also stored under `debug/reports/visual/runs/` as local evidence.

## Commands

```sh
# build
cmake -S . -B build-new -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build-new -j

# laboratory
python3 debug/lab/run_lab.py --list
python3 debug/lab/run_lab.py --all

# Chrome vs NativaX
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --section 1 --widths 1024
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --case css.001 --widths 320,768,1024
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --self-check

# dashboard (native window; falls back to the browser)
python3 debug/gui.py
```

## Next work

1. Fix the 47 responsive overflow failures (real layout bugs).
2. Implement `img` / background-image paint wiring (gap.010), the largest visual
   difference on template cases.
3. Reduce text metric differences (font selection/font-weight, gap.015).
4. Then rerun the visual judge and track changed-pixel/SSIM trends over time.
