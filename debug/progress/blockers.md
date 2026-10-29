# Blockers

Current, verified blockers (2026-10-29). Older statements in this file that are
no longer true were removed; historical run evidence stays in
`debug/history/` and `debug/reports/`.

## Real runtime/layout gaps

- 47 real cases fail the responsive sweep with horizontal overflow at 320 px or
  770 px. Examples: `a11y.004` (72 boxes, max right edge 335 px),
  `perf.014` (max right edge 1035 px), `media.014` (56 boxes).
- Image paint wiring is still missing (`gap.010`): `<img>` and
  `background-image` do not paint, so every image-heavy template differs from
  Chrome by a large margin.
- `font-weight` is parsed but not applied (`gap.015`); text metrics therefore
  differ from Chrome even when the layout is close.
- CSS `var()`, grid, float, absolute/fixed positioning, `@import`, `@layer`,
  `@supports`, inline SVG, canvas, WebGL, video, localStorage and IndexedDB are
  still documented gaps (see `debug/lab/sections/s17_gaps.py`, 25 cases).
- The runtime tries to resolve remote `http(s)` stylesheet URLs as local paths
  and logs `stylesheet not found`. The comparison tool blocks remote requests
  by default, so this does not hide a Chrome/NativaX difference; it only makes
  the log noisy.
- Text rasterization differs between Chrome and NativaX (different engines and
  fonts), so pixel-perfect equality is not realistic. The judge uses tolerance
  and SSIM thresholds instead of claiming false precision.

## Tooling/environment

- Chrome comparison needs the lab venv (`debug/.venv`) with numpy, Pillow and
  Playwright, plus `playwright install chromium`.
  `python3 debug/bootstrap.py --with-browsers` installs both.
- The native dashboard window needs a pywebview backend. On Debian/Ubuntu this
  means `python3-gi`, `gir1.2-gtk-3.0`, `gir1.2-webkit2-4.1` and pywebview.
  `debug/bootstrap.py` installs them. When the venv Python cannot import GI,
  `debug/gui.py` re-executes with the system Python; if no backend exists at
  all it opens the dashboard in the browser (read-only).
- The windowed golden/determinism tests need an X display. They now run under
  `xvfb-run -a` automatically, so the quality gate reports PASS with 0 skips.

## Not blockers anymore

- Git metadata exists (`git rev-parse HEAD`).
- The style/layout/paint pipeline is implemented; it is incomplete, not absent.
- The visual judge is native Python (numpy/Pillow/Playwright); it no longer
  depends on a Dart engine.
- A benchmark harness exists under `benchmarks/`.
