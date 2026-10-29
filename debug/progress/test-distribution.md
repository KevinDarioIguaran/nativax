# Test distribution — current status

The laboratory currently runs **240 real-world cases** in s01–s16 (15 each)
plus **25 documented capability gaps** in s17. The old 1000-test table referred
to sections and capabilities that do not exist on this branch; this file now
reflects the real corpus.

| Section | Area | Cases | Last result (2026-10-29) |
|---|---|---:|---|
| s01 | HTML/structure | 15 | 7 pass · 8 fail (responsive overflow) |
| s02 | CSS selectors/cascade | 15 | 8 pass · 7 fail |
| s03 | Box model | 15 | 15 pass |
| s04 | Typography | 15 | 15 pass |
| s05 | Color/decoration | 15 | 15 pass |
| s06 | Animation | 15 | 15 pass |
| s07 | Responsive | 15 | 14 pass · 1 fail |
| s08 | Flexbox | 15 | 15 pass |
| s09 | Positioning/overflow | 15 | 15 pass |
| s10 | JS/DOM | 15 | 10 pass · 5 fail |
| s11 | Events/forms | 15 | 15 pass |
| s12 | Forms | 15 | 15 pass |
| s13 | Accessibility/responsive templates | 15 | 9 pass · 6 fail |
| s14 | Media/images | 15 | 8 pass · 7 fail |
| s15 | Performance templates | 15 | 7 pass · 8 fail |
| s16 | Integration | 15 | 10 pass · 5 fail |
| s17 | Capability gaps | 25 | 25 blocked |

**Total:** 265 cases — 193 pass, 47 fail, 25 blocked, 0 error.

## Support status

- Supported: box model, typography, colors, animations, flexbox (with the
  documented gap.016 caveat), events/forms, DOM/JS bindings.
- Partial: responsive layout (47 real overflow failures), CSS cascade
  (`var()`, `@import`, `@layer`, `@supports`), positioning (absolute/fixed and
  float missing), images (`img` paint wiring missing), text metrics
  (`font-weight` not applied).
- Blocked: CSS grid, inline SVG, canvas, WebGL, video, localStorage/IndexedDB,
  accessibility tree, RTL/bidi text, platform backends (Windows/macOS/iOS).

Every number above comes from `python3 debug/lab/run_lab.py --all`; see
`debug/reports/lab/latest.json` and `debug/history/` for the raw evidence.
