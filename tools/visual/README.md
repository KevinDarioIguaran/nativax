# NativaX visual fidelity judge

Headless visual comparison between **Chromium** (reference) and **NativaX**
(owned runtime). It never opens a window, never uses a WebView, and never
ships Chromium: the browser is only the measuring instrument.

```bash
# All 51 vendored 50projects50days pages
dart run tools/visual/bin/visual_check.dart --suite 50projects50days

# Full 300-page catalog (50projects + MDN + Odin Project)
dart run tools/visual/bin/visual_check.dart --all --list
dart run tools/visual/bin/visual_check.dart --all

# Same, via the wrapper (works from any directory)
tools/visual/visual_check.sh --suite 50projects50days

# One page or a directory of pages
dart run tools/visual/bin/visual_check.dart examples/test-pages/form.html
dart run tools/visual/bin/visual_check.dart tools/visual/fixtures/50projects50days/progress-steps

# Iterate on one page without re-rendering; re-evaluate cached probes
dart run tools/visual/bin/visual_check.dart --resume --only progress-steps

# Verify the judge itself: Chromium vs a second Chromium render must be 100/PASS
dart run tools/visual/bin/visual_check.dart --self-check --limit 1
```

Outputs land in `.visual/latest/` (git-ignored) by default. The run exits `1`
when any page is `FAIL`/`INVALID`, or below `--fail-under <pct>`.

## Headless pipeline

Both engines render the same staged copy of the page with the same viewport
and the same system fonts:

| Step | Chromium | NativaX |
|---|---|---|
| Process | `--headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1` | `flutter test` + `RenderRepaintBoundary.toImage()` |
| Geometry | `getBoundingClientRect()` for every element | same probe on the DOM |
| Styles | `getComputedStyle()` (27 properties) | same probe through `css.computed` |
| Screenshot | `--screenshot`, cropped to the real `innerHeight` | offscreen PNG |
| Network | blocked with `--host-resolver-rules=MAP * ~NOTFOUND` | resource loader returns `null` for `http(s)` |
| Animation | frozen (`animation/transition: none`) | frozen with the same injected stylesheet |
| Time | `--virtual-time-budget=2000` | 900 ms of pumped frames |

Chromium's `--dump-dom` and `--screenshot` disagree on the layout viewport:
the dump reports `innerHeight = window − frame` (87 px on the test machine)
while the screenshot paints at the full window height. Without a correction,
`100vh`, fixed centring and percentage heights are measured against one
viewport and painted against another. The judge calibrates the offset at
startup, measures with `height + offset` and captures at `height`, so probe
rects and pixels share exactly the same viewport. `test/chrome_e2e_test.dart`
asserts that a `100vh` flex-centred box appears at the probe coordinates.
Viewport, DPR and screenshot size are hard environment checks.

## Scores (0–100 %)

All scores are percentages. Every formula is deterministic and unit-tested.

| Score | Formula |
|---|---|
| **Position** | Per element: `1` when `max(|dx|,|dy|) ≤ 2 px`, linear falloff to `0` at `16 px`; weighted mean with `sqrt(area)` (area capped at 60×60). Missing/extra elements count as `0`. |
| **Layout** | Per element: `0.7 × size falloff + 0.3 × IoU` (`|dw|,|dh|` tolerate 2 px, zero at 16 px). Page flow adds `10 %`: document-height error `0` at 0 %, `1` at ≥15 %. |
| **Color** | Per element, sampled inside its **own** box: mean-colour ΔE76 and dominant-palette ΔE (top 5 colours, 5-bit/channel quantization). `score = 0.6 × paletteScore + 0.4 × meanScore`, where a ΔE of 2 scores 1 and 10 scores 0. Weighted by `sqrt(area)`. |
| **Design** | Weighted equality of 27 computed properties (typography, text/background colour, borders, radii, shadow, display, position, opacity, overflow). Values are canonicalised first: `bold → 700`, `currentcolor` resolved, `border width → 0` when `border-style: none`, unitless `line-height` resolved against `font-size`, spacing/quotes normalised. |
| **Overall** | `0.30 × Position + 0.30 × Layout + 0.25 × Color + 0.15 × Design`, renormalised when colour is not measurable. |
| **Verdict** | `INVALID` if a hard environment check fails. `FAIL` if Position < 50 %, Layout < 50 %, Overall < 70 %, or ≥ 80 % of the visible ink differs while at least 0.2 % of the viewport changed. A ≥ 50 % ink mismatch caps at `WARN`. `WARN` below the 99.99 % target (`passOverall`). `PASS` at ≥ 99.99 % with low ink mismatch. |

**Why per-element colour and not per-pixel colour?** A moved element is a
layout error; sampling the same screen coordinates would count its shift a
second time as a colour error. The colour score samples each element inside
its own rendered box, so it answers "does NativaX use the same colours?" while
the pixel report still shows the positional consequence separately.

### Pixel report ("px a px")

`comparePixels()` visits **every pixel** of the common viewport:

- CIE76 ΔE per pixel (sRGB → Lab, D65).
- `ΔE ≤ 2` counts as imperceptible/exact; buckets `2–5`, `5–10`, `10–20`, `>20`.
- Mean ΔE, max ΔE, mean absolute RGB error, exact/mismatched counts.
- **Ink mismatch**: the page background is the dominant colour; every pixel
  that differs from it in either screenshot is "ink". The report gives the
  fraction of ink pixels that differ (`ink_mismatch_pct`) plus the ink area of
  each side. This catches a blank render that a whole-screen percentage would
  hide (for example, 0.2 % of an almost-empty page).
- Per-row statistics and the 12 worst 16×16 px tiles.
- `diff.png`: white for `ΔE ≤ 2`, yellow→red heat ramp above it.
- Optional `pixels.csv` (`--pixel-csv`): `x,y,chrome_r,g,b,nativa_r,g,b,delta_e`
  for every mismatched pixel (`--pixel-csv-all` for all pixels).

## Output tree

```
.visual/latest/
├── report.md                 # human summary + worst offenders
├── report.json               # full run, full per-page detail
├── results.json              # results table, one row per page  ←
├── summary.csv               # same table as CSV
└── pages/<suite>/<page>/
    ├── chrome.png            # reference screenshot
    ├── nativax.png           # NativaX screenshot
    ├── diff.png              # per-pixel ΔE heat map
    ├── chrome.json           # geometry + computed styles (reference)
    ├── nativax.json          # geometry + computed styles (NativaX)
    ├── elements.json         # per-element table: positions, ΔE, styles ←
    ├── elements.csv
    ├── positions.csv         # x/y/w/h, dx/dy/dw/dh, IoU, root cause
    ├── colors.csv            # computed + sampled colours, ΔE, score
    ├── pixels.json           # totals, rows, worst tiles
    ├── report.json           # this page only
    └── pixels.csv            # only with --pixel-csv
```

`results.json` has a stable `columns` array and `rows` with:
`page, suite, verdict, overall, position, layout, color, design,
environment_ok, environment_total, matched, missing, extra, order_violations,
pixels, mismatched_pixels, mismatched_pct, ink_mismatch_pct, ink_pixels,
mean_delta_e, max_delta_e, mae, chrome_ms, nativa_ms, artifacts, chrome_png,
nativax_png, diff_png, elements_json, failure`.

## Fixture catalog (300 pages)

`--all` adds five pinned suites:

| Suite | Pages | License | Commit |
|---|---:|---|---|
| `50projects50days` | 51 | MIT | `c92b0bc3…` (vendored) |
| `mdn-css-examples` | 27 | CC0-1.0 | `65b08d22…` |
| `mdn-learning-area` | 67 | CC0-1.0 | `21973263…` |
| `odin-css-exercises` | 21 | MIT | `eae53f9c…` |
| `mdn-dom-examples` | 134 | CC0-1.0 | `03ae1ffb…` |
| **Total** | **300** | | |

The four MDN/Odin suites are downloaded on demand to `.visual/suites/`
(git-ignored; about 270 MB) and are never redistributed. `--list` prints every
page without rendering. In the Tkinter panel, **Fidelidad visual** lists all
300 with pending rows; **Visual 300** runs them. The catalog report is
[`progress/reports/visual-catalog-latest.md`](../../progress/reports/visual-catalog-latest.md).

`fixtures/50projects50days/` is a vendored, unmodified MIT copy of
[bradtraversy/50projects50days](https://github.com/bradtraversy/50projects50days)
at commit `c92b0bc3a87fc95d44b89552b7b6a2eeb36ca481` (51 page directories;
`_project_starter_` is skipped). See `fixtures/50projects50days/NOTICE.md`.
`--suite <id>` uses the vendored copy when present and otherwise downloads the
pinned archive into `.visual/suites/<id>`.

External Google Fonts, CDNs and remote images are blocked in both engines, so
those pages are compared on their local HTML/CSS/JS plus the system font
fallback. Each page reports this as `external-resources`.

## Environment checks

Hard (a failure makes the page `INVALID`): `chromium`, `nativa`, `viewport`,
`device-pixel-ratio`, `elements`, `screenshot-size`.

Soft (reported, warning in the notes): `javascript-errors`,
`document-coverage`, `external-resources`, `animations`.

## Calibration and limitations

- `--self-check` compares two Chromium renders. It must report 100 % / `PASS`;
  otherwise the judge is broken. This is the reference calibration.
- Only the captured viewport is compared. `--height` changes the reference
  window; use a larger value for long pages and read `document-coverage`.
- Animated states are frozen, so scripts that change the page on a timer are
  judged at their resting state, not mid-animation.
- Video, audio, canvas animation timing and WebGL output are not judged.
- Scrollbars are hidden and DPR is fixed at 1.
- Fonts come from the system (the harness maps `sans-serif` to Noto Sans, as
  fontconfig does for Chromium on the test machine). Different systems can
  shift text metrics.
- `SKIP` and `INVALID` never count as compatibility.

## Tests

```bash
cd tools/visual && dart test && dart analyze

# Chrome-only integration test: probe viewport == painted viewport
NATIVA_VISUAL_E2E=1 dart test test/chrome_e2e_test.dart
```

Unit coverage: PNG decode/encode/crop, Lab/ΔE/CSS colours, geometry falloff,
root-cause attribution, style canonicalisation, palette comparison, per-pixel
statistics, scoring/verdicts/invalidations, report + artifacts, fixture
discovery, and the provenance of the vendored suite.
