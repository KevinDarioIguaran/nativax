# Visual fidelity

NativaX is compared with headless Chromium without a WebView, embedded browser,
or local server. Chromium is only the reference instrument:
`google-chrome --headless=new` produces the expected capture, and NativaX
produces its own through `flutter test` and
`RenderRepaintBoundary.toImage()`.

The engine lives in `debug/engines/visual_comparison`. Its README owns the
full formula/threshold contract; this page explains how to read the result
without turning it into a compatibility claim.

## What the judge measures

| Category | Question | Method |
|---|---|---|
| **Position** | Is each box where it should be? | `getBoundingClientRect` in both engines; 2 px tolerance, linear falloff to 16 px; weight `sqrt(area)` |
| **Layout** | Does each box have the right size/flow? | Width/height differences, IoU, document-height error |
| **Color** | Are the same colors used? | Mean and top-5 palette per element, ΔE76 in Lab D65; each engine samples its own box to avoid double-counting a shift |
| **Design** | Does computed style agree? | 27 normalized properties: typography, color, background, borders, radii, shadow, display, position, opacity, overflow |
| **Environment** | Is the comparison valid? | Viewport, DPR, capture size, document coverage, JS errors, blocked external resources |
| **Pixels** | What changes pixel by pixel? | ΔE76 per pixel, 2/5/10/20 buckets, rows, 16×16 tiles, diff image, ink mismatch |

Overall renormalizes position 30 %, layout 30 %, color 25 %, design 15 % when
color is not measurable. A hard environment failure marks the page `INVALID`
rather than inventing a score.

`ink_mismatch_pct` exists because a near-blank page can match 99.8 % of pixels
while being completely blank. The judge finds the dominant background, treats
every pixel differing from it in either capture as ink, and reports the
fraction of ink that differs. Blank NativaX versus text in Chromium is 100 %
ink mismatch even when total pixel difference is 0.2 %.

## Run it

```bash
dart run debug/engines/visual_comparison/bin/visual_check.dart \
  --suite 50projects50days
dart run debug/engines/visual_comparison/bin/visual_check.dart \
  examples/test-pages/form.html
dart run debug/engines/visual_comparison/bin/visual_check.dart \
  --self-check --limit 1
```

`--self-check` compares Chromium with a second Chromium capture; it is the
calibration check. Without a passing self-check, the visual judge is not valid.

## Catalog

The full catalog has **300 pages** with `--all`: 51 from 50projects50days, 27
from MDN CSS, 67 from MDN learning-area, 21 from Odin Project, and 134 from MDN
DOM/UI. External suites are fetched at pinned commits into
`debug/artifacts/visual/suites/` and are not redistributed. See
[`../progress/reports/visual-catalog-latest.md`](../progress/reports/visual-catalog-latest.md).

The 51 HTML/CSS/JS projects in
`debug/engines/visual_comparison/fixtures/50projects50days` are an unmodified
copy of `bradtraversy/50projects50days` at
`c92b0bc3a87fc95d44b89552b7b6a2eeb36ca481` (MIT, with provenance). They are
test fixtures; NativaX does not load them from its public runtime.

## Outputs

Each run writes under `debug/artifacts/visual/latest/`:

- `report.md`: human-readable summary and worst root causes;
- `report.json`: complete report;
- `results.json`: stable `columns` and one row per page;
- `summary.csv`;
- `pages/<suite>/<page>/`: `chrome.png`, `nativax.png`, `diff.png`, JSON
  probes, `elements.json`/`.csv`, `positions.csv`, `colors.csv`, and
  `pixels.json` (plus `pixels.csv` with `--pixel-csv`).

Generated captures are not committed. `progress/reports/visual-*-latest.md`
are convenience reports and may lag the raw run.

## Last recorded baseline

The 51 vendored pages at 800×900 with network blocked produced:

| Result | Value |
|---|---|
| Verdicts | **6 PASS, 5 WARN, 40 FAIL, 0 INVALID** |
| Mean overall | **52.59 %** (median 48.54 %) |
| Mean position | 36.20 % |
| Mean layout | 53.04 % |
| Mean color | 45.24 % |
| Mean design | 96.72 % |
| Pixels compared | 36,720,000 |
| Pixels with ΔE > 2 | 6,569,980 (17.89 % mean) |
| Mean ink mismatch | 62.82 % |

The dominant failure is layout/positioning, not the style cascade. This is a
first calibrated baseline, not a regression or a CSS compatibility rate. The
full per-page table is in
[`../progress/reports/visual-50projects50days-latest.md`](../progress/reports/visual-50projects50days-latest.md).

Notable verified cases:

- `hidden-search`: 98.63 % position, 100 % color, 0.04 % pixel difference,
  0.16 % ink. PASS.
- `event-keycodes`: 100 % geometry but 99.21 % ink mismatch; FAIL by the ink
  rule even though overall is 91.91 %. Overall alone would have hidden it.
- `animated-countdown`: a fixed/translated container lands offscreen
  (`-400, -378`), leaving a blank NativaX capture. Position 0 %, ink 100 %.
- `background-slider`: Chromium centers the 560×630 container at `x=120`;
  NativaX puts it at `x=0`, so the slides are shifted 120 px and pixels match
  0 %.

## Chromium viewport calibration

In headless Chromium, `--dump-dom` and `--screenshot` do not agree on the layout
viewport: the dump reports `innerHeight = window − 87 px`, while the screenshot
paints at the full window height. The judge measures that offset at startup,
probes at `height + offset`, and captures at `height`, so probe boxes and pixels
belong to the same viewport. Without this correction, `100vh`, fixed centering,
and percentage heights are measured against one viewport and painted against
another. `test/chrome_e2e_test.dart` verifies a centered box.

## Limitations

- Only the captured viewport is judged; `--height` controls it and
  `document-coverage` warns when the document is taller.
- Animations/transitions are frozen in both engines.
- Network is blocked in both engines: remote fonts, CDNs, and images are absent
  and reported as `external-resources`.
- System fonts differ between machines, so text metrics are not portable.
- Video, audio, animated canvas, and WebGL output are not judged.
- `INVALID` means the measurement is unreliable; it is not compatibility.
- A 52 % overall score is not “52 % of CSS supported”. It is a weighted visual
  baseline on one catalog.

## Related

- [`css-supported.md`](css-supported.md)
- [`performance-suite.md`](performance-suite.md)
- [`benchmarks.md`](benchmarks.md)
- [`debugging.md`](debugging.md)
- [`../debug/engines/visual_comparison/README.md`](../debug/engines/visual_comparison/README.md)
