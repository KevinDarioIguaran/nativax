# Visual fidelity — 50projects50days (latest)

- Date: 2026-10-26
- Command: `dart run debug/engines/visual_comparison/bin/visual_check.dart --suite 50projects50days --out <dir>`
- Reference: Google Chrome 152.0.7977.82 headless; viewport 800x900, DPR 1, animations frozen
- Fixtures: `debug/engines/visual_comparison/fixtures/50projects50days` @ `c92b0bc3` (MIT)
- Pages: **51** — PASS **2**, WARN **18**, FAIL **31**, INVALID **0**
- Overall: mean **89.62 %**, median **97.69 %**
- Category means: position **83.32 %**, layout **89.74 %**, color **90.95 %**, design **99.75 %**
- Baseline for the same judge before this session (2026-10-26 run in `debug/artifacts/visual/latest`): 2 PASS / 7 WARN / 42 FAIL, mean 78.77 %.

## Known limit: text rasterization

PASS requires ≤ 0.01 % of pixels with ΔE > 2. Chromium on Linux rasterizes
glyphs with a gamma/contrast boost that the Flutter engine does not expose
(measured on toast-notification: NativaX coverage 0.5 renders as 0.61 in
Chromium). Pages with text whose geometry, colour and computed styles match
at 100 % therefore stay WARN. This is not fixed in the renderer.

## Results

| Page | Verdict | Overall | Before | Position | Layout | Color | Design | Pixels |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `3d-boxes-background` | FAIL | 97.88 % | 97.88 % | 94.44 % | 98.50 % | 100.00 % | 100.00 % | 2.20 % |
| `animated-countdown` | FAIL | 97.42 % | 86.00 % | 100.00 % | 99.37 % | 90.43 % | 100.00 % | 0.22 % |
| `animated-navigation` | FAIL | 70.16 % | 69.74 % | 52.37 % | 67.50 % | 76.86 % | 99.86 % | 0.26 % |
| `auto-text-effect` | FAIL | 52.73 % | 48.83 % | 0.85 % | 55.86 % | 82.85 % | 100.00 % | 1.98 % |
| `background-slider` | WARN | 99.75 % | 72.62 % | 99.56 % | 99.60 % | 100.00 % | 100.00 % | 0.00 % |
| `blurry-loading` | WARN | 99.13 % | 99.13 % | 100.00 % | 97.62 % | 100.00 % | 98.98 % | 0.00 % |
| `button-ripple-effect` | WARN | 100.00 % | 98.78 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 0.04 % |
| `content-placeholder` | FAIL | 86.17 % | 73.95 % | 88.87 % | 87.93 % | 72.53 % | 100.00 % | 3.38 % |
| `custom-range-slider` | FAIL | 53.34 % | 50.49 % | 37.02 % | 53.63 % | 47.91 % | 94.46 % | 1.37 % |
| `dad-jokes` | WARN | 99.08 % | 99.06 % | 100.00 % | 99.45 % | 97.00 % | 100.00 % | 0.86 % |
| `double-click-heart` | WARN | 99.10 % | 91.22 % | 100.00 % | 99.79 % | 96.63 % | 100.00 % | 1.71 % |
| `double-vertical-slider` | FAIL | 95.28 % | 94.25 % | 94.53 % | 98.07 % | 90.01 % | 100.00 % | 0.34 % |
| `drag-n-drop` | PASS | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 0.00 % |
| `drawing-app` | FAIL | 94.13 % | 93.43 % | 100.00 % | 94.39 % | 83.46 % | 99.67 % | 2.12 % |
| `drink-water` | WARN | 99.42 % | 99.42 % | 100.00 % | 100.00 % | 97.70 % | 100.00 % | 0.76 % |
| `event-keycodes` | FAIL | 98.17 % | 97.74 % | 100.00 % | 100.00 % | 92.69 % | 100.00 % | 0.18 % |
| `expanding-cards` | WARN | 99.99 % | 80.10 % | 100.00 % | 99.98 % | 100.00 % | 100.00 % | 0.00 % |
| `faq-collapse` | FAIL | 82.65 % | 58.16 % | 57.14 % | 90.37 % | 93.59 % | 100.00 % | 7.71 % |
| `feedback-ui-design` | FAIL | 67.51 % | 60.60 % | 39.17 % | 56.66 % | 95.03 % | 100.00 % | 3.37 % |
| `form-input-wave` | FAIL | 97.69 % | 51.04 % | 100.00 % | 98.95 % | 92.02 % | 100.00 % | 0.72 % |
| `github-profiles` | FAIL | 97.85 % | 89.33 % | 100.00 % | 100.00 % | 91.40 % | 100.00 % | 0.14 % |
| `good-cheap-fast` | FAIL | 92.72 % | 70.95 % | 90.49 % | 93.44 % | 90.26 % | 99.87 % | 0.77 % |
| `hidden-search` | WARN | 99.59 % | 96.54 % | 99.34 % | 99.30 % | 100.00 % | 100.00 % | 0.00 % |
| `hoverboard` | WARN | 99.99 % | 99.98 % | 100.00 % | 100.00 % | 99.96 % | 100.00 % | 0.00 % |
| `image-carousel` | WARN | 99.86 % | 66.59 % | 100.00 % | 100.00 % | 100.00 % | 99.09 % | 0.33 % |
| `incrementing-counter` | FAIL | 48.00 % | 41.04 % | 18.27 % | 44.91 % | 56.19 % | 100.00 % | 2.00 % |
| `insect-catch-game` | FAIL | 87.01 % | 77.21 % | 78.18 % | 78.85 % | 100.00 % | 99.32 % | 0.18 % |
| `kinetic-loader` | PASS | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 0.00 % |
| `live-user-filter` | FAIL | 96.78 % | 73.30 % | 100.00 % | 95.96 % | 92.02 % | 99.86 % | 0.44 % |
| `mobile-tab-navigation` | WARN | 99.01 % | 93.21 % | 99.49 % | 99.54 % | 97.58 % | 99.37 % | 0.10 % |
| `movie-app` | WARN | 99.72 % | 64.17 % | 100.00 % | 99.07 % | 100.00 % | 100.00 % | 0.33 % |
| `netflix-mobile-navigation` | FAIL | 95.11 % | 47.36 % | 99.84 % | 95.51 % | 86.20 % | 99.69 % | 0.22 % |
| `notes-app` | WARN | 99.85 % | 80.27 % | 100.00 % | 99.48 % | 100.00 % | 100.00 % | 0.03 % |
| `password-generator` | FAIL | 93.29 % | 50.67 % | 96.40 % | 97.05 % | 81.17 % | 99.72 % | 1.35 % |
| `password-strength-background` | FAIL | 91.54 % | 47.64 % | 100.00 % | 96.22 % | 70.68 % | 100.00 % | 0.59 % |
| `pokedex` | WARN | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 0.08 % |
| `progress-steps` | FAIL | 96.58 % | 86.71 % | 99.71 % | 99.92 % | 86.76 % | 100.00 % | 0.38 % |
| `quiz-app` | FAIL | 98.36 % | 97.17 % | 100.00 % | 98.80 % | 94.97 % | 99.85 % | 0.63 % |
| `random-choice-picker` | WARN | 99.69 % | 99.18 % | 99.45 % | 99.50 % | 100.00 % | 100.00 % | 0.49 % |
| `random-image-generator` | FAIL | 96.03 % | 96.03 % | 96.30 % | 95.96 % | 94.48 % | 98.20 % | 1.58 % |
| `rotating-nav-animation` | FAIL | 85.67 % | 80.78 % | 74.87 % | 82.79 % | 93.64 % | 99.73 % | 8.75 % |
| `scroll-animation` | FAIL | 57.77 % | 57.77 % | 18.25 % | 51.16 % | 87.80 % | 100.00 % | 13.08 % |
| `simple-timer` | FAIL | 63.14 % | 54.07 % | 0.00 % | 77.12 % | 100.00 % | 100.00 % | 0.35 % |
| `sound-board` | FAIL | 53.18 % | 49.17 % | 0.00 % | 43.92 % | 100.00 % | 100.00 % | 17.10 % |
| `split-landing-page` | FAIL | 59.87 % | 59.03 % | 42.86 % | 70.17 % | 43.86 % | 100.00 % | 1.62 % |
| `sticky-navigation` | FAIL | 87.82 % | 74.85 % | 91.20 % | 75.39 % | 91.37 % | 100.00 % | 3.45 % |
| `testimonial-box-switcher` | WARN | 99.07 % | 98.99 % | 100.00 % | 100.00 % | 96.47 % | 99.72 % | 2.77 % |
| `theme-clock` | FAIL | 84.99 % | 60.43 % | 81.16 % | 85.74 % | 79.70 % | 100.00 % | 1.10 % |
| `toast-notification` | WARN | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 100.00 % | 0.06 % |
| `todo-list` | WARN | 99.76 % | 84.04 % | 99.59 % | 99.62 % | 100.00 % | 100.00 % | 0.30 % |
| `verify-account-ui` | FAIL | 98.68 % | 98.39 % | 99.85 % | 99.54 % | 95.46 % | 100.00 % | 2.46 % |
