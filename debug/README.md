# Debug laboratory

This directory contains the NativaX debug laboratory. It is the single,
honest entry point for exercising the engine: nothing is simulated and every
case either passes against artifacts produced by the real binaries or is
reported as `blocked` because the capability does not exist.

## Layout

```
debug/
  bootstrap.py          # installs deps, builds, smoke-tests, writes lab/env.json
  gui.py                # native pywebview dashboard (browser fallback)
  dashboard/            # tabs: Resumen, Chrome vs NativaX, Informes, Historial, Artefactos
  judges/visual/
    chrome_compare.py   # Chrome vs NativaX screenshots, diff, MAE/RMSE/SSIM
    compare.py          # generic pixel-diff judge
  lab/
    harness.py          # case registry, DOM/selector engine, Page/Lab, assertions
    run_lab.py          # CLI runner
    sections/           # s01.py ... s17_gaps.py (15 real cases per section, except gaps)
    cases/              # 240 self-contained examples imported from public repos
    corpus.json         # manifest with provenance and independent expected facts
    ATTRIBUTION.md      # source repositories, commits and licences
  tests/goldens/        # approved regression captures (counter_window.png)
  artifacts/lab/        # git-ignored run cache
  artifacts/visual/     # Chrome/NativaX/diff captures per case and width
  reports/lab/          # generated JSON + Markdown reports (git-ignored)
  reports/visual/       # latest visual comparison report (git-ignored)
```

## Quick start

```bash
python3 debug/bootstrap.py --with-browsers  # deps + build + smoke test + Chromium
python3 debug/lab/run_lab.py --list # show sections and case counts
python3 debug/lab/run_lab.py --section 1
python3 debug/lab/run_lab.py --all   # 240 real cases + 25 capability gaps, ~10 min
python3 debug/gui.py                 # dashboard (pywebview, browser fallback)
```

## Chrome vs NativaX design comparison

The same real case is rendered twice: once with headless Chromium (Playwright)
and once with the native runtime. The judge writes the two captures and a red
difference map, then reports changed pixels, MAE, RMSE, SSIM and the bounding
box of the differences.

```bash
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --case css.001
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --section 1 --widths 320,768,1024
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --case css.001 --widths 1024,768
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --fresh --section 1
debug/.venv/bin/python debug/judges/visual/chrome_compare.py --self-check
```

Reports accumulate the last comparison per case, so comparing one case does not
erase the rest of the dashboard. `--fresh` resets the report. Every run is also
kept under `debug/reports/visual/runs/` as local evidence.

Status thresholds are explicit:

- `pass`: changed pixels ≤ 2 %, MAE ≤ 6, SSIM ≥ 0.90
- `warn`: changed pixels ≤ 8 %
- `fail`: anything larger, a size mismatch, or a render error

These are **design-audit** thresholds, not a claim that NativaX should match
Chrome pixel for pixel. NativaX implements a documented CSS subset, so a large
diff is real evidence of a gap (image paint, gradients, text metrics, …). The
current full-lab status is 193 pass / 47 fail / 25 blocked; the 47 failures are
real responsive-overflow defects. See `debug/progress/current-task.md`.

## Case convention

- Every case lives in its own numbered folder `debug/lab/cases/sNN/NNN/`.
- Each folder contains a real example copied verbatim from one of the source
  repositories, plus a generated `case.json` with provenance and independent
  expected facts.
- Files keep their original names and assets; no shared design template or
  generated shell is used.
- Nothing is generated at run time: the laboratory runs `build/nativax-debug`
  and `build/nativax-runtime` over those files.
- All test names, descriptions, messages and fixture copy are in English.
- Responsive checks sweep widths 320..1280 px in 50 px steps for every folder and
  fail on horizontal overflow. Overflow is a real failure, never a recorded
  pass.

## Useful flags

- `--filter SUBSTR` filter case ids/names
- `--strict` treat `blocked` as failure
- `--no-responsive` skip the width sweep (debugging only)
- `--min-per-section N` enforce a minimum case count
- `--json` print the summary JSON

## Environment

`debug/bootstrap.py --check` verifies the toolchain without installing anything.
`debug/lab/env.json` records the detected environment (git-ignored).
EOF
echo written