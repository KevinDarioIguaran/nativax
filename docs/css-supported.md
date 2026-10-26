# CSS and layout support

NativaX implements CSS with its own parser, cascade, and layout in Flutter
render objects. It is not a browser CSS engine and it is not a wrapper around
one. This page describes what is parsed, what is painted, and what is only
accepted for compatibility.

The visual quality reference is the headless Chromium comparison in
`debug/engines/visual_comparison`; see [`visual-fidelity.md`](visual-fidelity.md).
The latest 51-page baseline is **52.59 %** mean overall and is not a CSS
compatibility percentage.

## Selectors and cascade

Supported selector surface:

- type, class, id, universal, attribute selectors (common operators and `i`/`s`
  flags), and combinators (` `, `>`, `+`, `~`);
- structural pseudo-classes: `:first/last/only-child`,
  `:nth-child`/`:nth-last-child` (including `of S`),
  `:first/last/only-of-type`, `:nth-of-type`/`:nth-last-of-type`, `:empty`,
  `:root`, `:scope`;
- logical: `:not`, `:is`, `:where`, `:has` (relative);
- state: `:hover`, `:active`, `:focus`, `:focus-visible`, `:focus-within`,
  `:target`, `:checked`, `:disabled`, `:enabled`, `:required`, `:optional`,
  `:read-only`, `:read-write`, `:placeholder-shown`, `:valid`, `:invalid`,
  `:user-valid`, `:user-invalid`, `:in-range`, `:out-of-range`,
  `:indeterminate`, `:default`, `:open`, `:modal`, `:defined`, `:link`,
  `:any-link`;
- other: `:dir()`, `:lang()`, `:heading`; `:visited` never matches;
- pseudo-elements: `::before`, `::after` (`content` strings, `attr()`, quote
  keywords), `::placeholder`, `::backdrop`; `::marker`, `::selection`,
  `::first-line`, `::first-letter`, `::part()`, `::slotted()` and vendor-prefixed
  forms are accepted but inert;
- specificity, `!important`, UA/author/inline origins, inheritance,
  `inherit`/`initial`/`unset`, `var()` with fallback;
- SVG presentation attributes as author rules with specificity 0.

`@layer` is parsed and flattened in source order. It is **not** a full cascade
layer implementation with ordering/reversal. Unknown selectors/at-rules produce
warnings where the parser can recognize them; they do not become styles.

## At-rules

| At-rule | Support | Limits |
|---|---|---|
| `@media` | width, height, orientation, `prefers-color-scheme`, `prefers-reduced-motion`, resolution | Nested conditions; no `hover`/`pointer`/`container` queries |
| `@supports` | `and`/`or`/`not`, declarations, `selector()` | Evaluated against the supported property/value contract |
| `@keyframes` | Standard + `-webkit-` | Web Animations API not implemented |
| `@layer` | Parsed/flattened | No layer precedence |
| `@font-face` | `font-family`, `src`, `font-weight`, `font-style`, `font-display` | Resource bytes via host; WOFF containers need SFNT fallback |
| `@import` | **Not supported** | Use a host loader/concatenation |
| `@container` | **Not supported** | No container queries |
| `@property` | **Not supported** | No registered custom-property animation |
| `@page` | **Not supported** | No print layout |

## Values

- Lengths: `px`, `%`, `em`, `rem`, `vw`, `vh`, absolute units (`pt`, `cm`, ...).
- Math: `calc()`, `min()`, `max()`, `clamp()`; percentages resolve in layout
  against the containing block where specified.
- Colors: named colors, 3/4/6/8-digit hex, `rgb()`/`rgba()`/`hsl()`/`hsla()`
  (comma and modern syntax), `transparent`, `currentcolor`.
- `env(safe-area-inset-*)` resolves to the fallback or `0px`; there is no live
  safe-area integration in the CSS layer.
- Custom properties and fallbacks are supported; values are token-preserving,
  not typed at declaration time.

## Box model

- `width`, `height`, `min-*`, `max-*`, `box-sizing`.
- margins (including `auto`), padding, borders (width/style/color/radius).
- `border-radius` in lengths/percentages; `outline` and `outline-offset`.
- `overflow`/`overflow-x`/`overflow-y`: `hidden`/`clip` clip; `auto`/`scroll`
  creates a vertical scroll container; horizontal scrolling is limited to
  intrinsically wide content.
- `box-shadow` (multiple; `inset` shadows are not painted), `opacity`,
  `visibility` (`hidden` preserves space), `filter`, `backdrop-filter: blur()`.
- `transform`: translate/scale/rotate/skew/matrix; 3D functions project to 2D;
  `transform-origin` is currently accepted but inert (origin is the center).
- Margins collapse between siblings and through empty boxes; parent/child
  collapse is not implemented.
- `float`, `clear`, multi-column, `writing-mode`, `direction`, `unicode-bidi`,
  `table-layout`, `border-collapse`, and `border-spacing` are accepted/inert or
  parsed without a full layout implementation.

## Backgrounds and effects

- background color, gradients (`linear`, `radial`, `conic`, repeating) and
  images;
- `background-size` (`auto`, `cover`, `contain`, explicit lengths/percentages),
  `background-position` (keywords/percentages/offsets), and
  `background-repeat` for the first layer;
- multiple background layers are parsed, but the renderer paints the first
  image layer;
- gradient geometry is implemented by the renderer; `background-attachment`,
  `background-clip`, `background-origin`, `mask`, `clip-path`, and
  `mix-blend-mode` are inert;
- border styles `solid`, `dashed`, `dotted`, `double`; `groove`/`ridge`/`inset`/
  `outset` are painted solid (diagnostic-worthy approximation).

## Display and layout

| `display` | State |
|---|---|
| `block`, `inline`, `inline-block`, `flow-root` | Implemented |
| `flex`, `inline-flex` | Implemented subset |
| `grid`, `inline-grid` | Implemented subset |
| `list-item`, `contents`, `none` | Implemented |
| two-value syntax (`inline flex`) | Parsed |
| `table`, `table-row`, `table-cell`, etc. | **Approximate**: UA sheet makes rows flex and cells flex items; no table formatting context |

### Flexbox

Direction including reverse, wrapping, `gap`, grow/shrink/basis with
min-content freezing, `justify-content`, `align-items`, `align-self`,
`align-content` for wrapped lines, auto margins, and `order` are implemented.
`baseline` alignment is approximated. It does not implement every intrinsic
sizing and baseline combination from the spec.

### Grid

Explicit/implicit tracks, `px`/`%`/`calc`/`fr`/`auto`/`min-content`/
`max-content`/`fit-content()`/`minmax()`/`repeat()` (including auto-fill/
auto-fit), named areas, line placement, spans, negative lines, gaps, and
alignment are implemented. `subgrid` and `dense` are not. Intrinsic sizing
edge cases diverge.

### Positioning

- `relative`, `absolute` (containing block), `fixed` (viewport layer), `sticky`
  (nearest scroll container, bounded by containing block).
- `z-index` participates in stacking for positioned content.
- Virtualized regions may change geometry; see below.

## Text and fonts

- `font-family` fallback, `font-size`, `font-weight`, `font-style`, `font`
  shorthand, `line-height`, `letter-spacing`.
- `text-align`, `white-space`, `text-transform`, `text-decoration-*`,
  `text-shadow`, `text-overflow: ellipsis` with `nowrap` + overflow.
- `vertical-align: sub`/`super` (and `<sub>`/`<sup>`) shifts the run; other
  vertical-align values are limited.
- Inline elements with padding, borders, or rounded backgrounds paint as atomic
  boxes and do not split across lines.
- `word-break`, `overflow-wrap`, `hyphens`, `text-indent`, `font-variant*`,
  `font-feature-settings`, `font-stretch`, `text-wrap`, `line-clamp`, and
  `writing-mode`/`direction` do not implement full browser behavior.
- Shaping, bidi, and Unicode line breaking are delegated to Flutter/Skia. NativaX
  does not implement its own text stack.
- `@font-face` is supported for SFNT TTF/OTF loaded through the resource loader;
  WOFF/WOFF2 containers are not accepted directly and may use a sibling
  `.ttf`/`.otf` probe.

## Transitions and animations

- `transition` and `@keyframes`/`animation` duration, delay, iteration
  (including infinite), direction, fill mode, play state, and timing function.
- Easing: `linear`, `ease*`, `cubic-bezier()`, `steps()`, step keywords.
- Interpolates lengths, numbers, colors, transforms, and shadows; other
  properties switch discretely.
- `transitionrun/start/end`, `animationstart/iteration/end` events are emitted.
- Animated inherited properties do not propagate to descendants.
- Web Animations API/animation composition/timeline are not implemented.

## Inline SVG

- `svg` with `viewBox` (`xMidYMid meet`), width/height.
- `rect` (rx/ry), `circle`, `ellipse`, `line`, `polyline`, `polygon`, `path`
  (all commands), `text` with anchor/baseline, `g` with transform.
- fill/stroke, width, dash array, linecap/linejoin, fill rule, opacity, from CSS
  or presentation attributes.
- Pointer hit testing on figures.
- No SVG gradients/patterns via `url(#id)`, `use`, `clipPath`, `mask`, filters,
  markers, or `foreignObject`. This is a small SVG renderer, not a browser SVG
  engine.

## Forms and controls

Text/password/email/number/tel/url/search, textarea, checkbox/radio, range,
color, date/time/datetime-local/month/week, file (button; no picker), select
(single/multiple/size), fieldset/legend, button, and label are rendered with
Flutter controls. `accent-color` and `::placeholder` are supported. Range,
checkbox, and radio ignore authored background/border like
`appearance: auto`. See [`guides/forms-and-navigation.md`](guides/forms-and-navigation.md)
for the missing file picker and validation caveats.

## Images, canvas, media, dialogs

- `img` requires `NativaXImageResolver`; `object-fit`/`alt` are handled by the
  renderer. A null image is a broken placeholder plus diagnostic.
- `<canvas>` is a real 2D canvas subset; it is not WebGL.
- `<video>`, `<audio>`, `<iframe>` reserve space with a placeholder; no playback
  or nested document.
- `<details>`/`<summary>` open/close; `<dialog>` supports `show`, `showModal`,
  top layer, backdrop, Escape, and focus containment. Dialog is DOM-rendered,
  not an OS window.

## Interaction

- Pointer: `:hover`, `:active`, cursor, click coordinates, double click, context
  menu (right click/long press), and HTML5 drag/drop where the host input path
  provides it.
- Keyboard: `keydown`/`keyup` on the focused element; IME/composition is
  platform-dependent and not conformance-tested.
- Scroll: `scroll`, `scrollIntoView`, `scrollTo`, `scroll-padding-top` (the CSS
  property is accepted but inert in the parser list).
- Focus order, screen-reader semantics, and text scaling are not browser parity.

## Virtualization and CSS

Large block/flex/grid containers can virtualize at **24 child slots**. Offscreen
elements may have no render object and use estimated geometry; absolute children,
complex inline runs, generated content, and fixed overlays can disable
virtualization. `data-nativa-virtual="false"` / `data-nv-virtual="false"` opts
out. Do not combine virtualization with code that requires exact offscreen
geometry.

## Diagnostics

`NativaXDocumentView.onDiagnostic` receives renderer approximations and
unresolved images, deduplicated per mount. CSS parser warnings are available from
the parser/sheet. The renderer does not throw on a visual approximation.

## Explicitly not supported

- Full CSS tables, floats, multi-column layout, writing modes/bidi text layout.
- Container queries, `@import`, `@property`, print styles.
- CSS subgrid/dense packing and full intrinsic sizing.
- SVG gradients/patterns/clip paths/masks/filters/`use`.
- A complete CSSOM/Web Animations API.
- Browser pixel parity. The visual suite measures a subset of pages.

## Evidence

- CSS tests: `packages/nativa_css/test/css_test.dart`, `media_matrix_test.dart`,
  `style_cache_test.dart`, `fuzz_test.dart`.
- Renderer tests: `packages/nativa_render/test/`.
- Conformance: WPT CSS selectors **70.56 %** (127 PASS / 53 FAIL / 348 SKIP).
- Visual: 51 pages, 52.59 % mean overall (6 PASS / 5 WARN / 40 FAIL).
- Performance: see [`performance-suite.md`](performance-suite.md); layout
  performance is not a conformance result.

## Related

- [`internals/html-dom-css.md`](internals/html-dom-css.md)
- [`architecture/rendering.md`](architecture/rendering.md)
- [`visual-fidelity.md`](visual-fidelity.md)
- [`html-supported.md`](html-supported.md)
- [`javascript-supported.md`](javascript-supported.md)
