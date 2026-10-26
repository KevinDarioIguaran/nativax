# Rendering architecture

NativaX rendering is a CSS layout engine that produces Flutter render objects.
It is not a Flutter widget tree generated from HTML tags alone, and it is not a
browser engine wrapper. The renderer owns box layout, text layout, painting, hit
testing, and the bridge from DOM geometry APIs to Flutter geometry.

The authoritative feature list is [`../css-supported.md`](../css-supported.md).
This page explains how those features are built and where the approximations
are.

## Pipeline

```text
DOM tree + ComputedStyle
        |
        v
NativaXDocumentView  (mutation subscription, rebuild scheduling)
        |
        v
builder in node_view.dart
        |
        +--> CssBox / RenderCssBox          box decoration, border, background
        +--> CssBlockFlow / RenderCssBlock  block flow and inline runs
        +--> CssFlexLayout / RenderCssFlex  flex line resolution
        +--> CssGridLayout / RenderCssGrid  track sizing and placement
        +--> CssTransform / RenderCssTransform
        +--> CssSticky / RenderCssSticky
        +--> text painters, image widgets, canvas, SVG, form controls
        |
        v
Flutter compositing and painting
```

`nativa_render` exposes `NativaXDocumentView`, `NativaXImageResolver`, and the
layout primitives. `nativax` owns the runtime and the public view.

## Style and layout are separate

`nativa_css` computes a `ComputedStyle` for each element from:

- user-agent defaults;
- author stylesheets (`<style>` and loaded `<link>`);
- inline styles;
- inherited properties;
- media/supports evaluation;
- CSS variables and `!important` precedence.

The renderer does not parse CSS. It reads the computed values and maps them to
layout inputs. This separation means a CSS property can be parsed but ignored by
the renderer; it can also be implemented by the renderer without being fully
conformant. [`../css-supported.md`](../css-supported.md) distinguishes these
cases.

## Document view

`NativaXDocumentView`:

- takes a `dom.Document`, a `StyleEngine`, an optional `NativaXImageResolver`,
  and diagnostic callbacks;
- subscribes to document mutation records;
- batches invalidation in a microtask and rebuilds the document widget tree;
- owns the viewport scope, scroll controllers, focus and hit-test helpers;
- exposes `scrollIntoView`, geometry lookup, and image/asset resolution hooks to
  the renderer and bindings.

The current implementation rebuilds the affected document tree rather than
maintaining a fully incremental render-object graph. Widget/style caches and
virtualized subtrees reduce the cost, but this is a documented architectural
limit. A granular per-owner invalidation model is future work.

## Box model

`CssBox`/`RenderCssBox` implement:

- content width and height with min/max constraints;
- padding, borders, border radii, outlines;
- background color, gradients, and images;
- box shadows and opacity;
- clipping and overflow;
- transforms and filters;
- hit testing against the box and its child stack.

Block flow is handled by `RenderCssBlock`; it lays out block children, inline
runs, floats where implemented, and absolute/fixed descendants. The renderer
uses Flutter's `RenderBox` protocol but implements CSS-specific sizing rules
instead of using Flutter's `Column`, `Row`, or `Container` for page layout.

## Flex and grid

Flex and grid are custom render objects:

- `RenderCssFlex` resolves direction, wrapping, grow/shrink, basis, gaps,
  alignment, auto margins, and order.
- `RenderCssGrid` resolves explicit/implicit tracks, `fr`, `minmax()`,
  `repeat()`, named areas, line placement, spans, gaps, and alignment.

These are substantial subsets, not full CSS specifications. Known boundaries
include grid subgrid/dense packing, some intrinsic sizing combinations, and
baseline alignment. The visual suite is the current evidence for approximation
quality; it is not proof of spec compliance.

## Inline text

Text is measured and painted with Flutter's text APIs after mapping the computed
font, size, weight, style, line height, letter spacing, decoration, and shadow.
Inline elements with padding, borders, or backgrounds are painted as atomic
boxes rather than split across lines.

The renderer also handles:

- `white-space` and forced line breaks;
- text alignment, transform, ellipsis, and decoration;
- `::before`/`::after` generated content;
- form-control text and placeholders;
- font fallback and registered `@font-face` families.

Unsupported text properties are listed in [`../css-supported.md`](../css-supported.md).
Text shaping and bidi behavior rely on Flutter/Skia; NativaX does not implement
its own Unicode line-breaking or shaping engine.

## Images, canvas, SVG, and media

- **Images** are resolved by the host's `NativaXImageResolver`; NativaX never
  fetches `img` URLs implicitly. Broken/denied images use a placeholder and a
  diagnostic. `object-fit` and `alt` are handled by the image widget.
- **Raster/vector images**: the renderer supports Flutter-decodable raster
  formats and has a small inline-SVG renderer. It is not a full SVG engine.
- **Canvas 2D** is implemented by the `nativa_dom_bindings` canvas prelude and a
  `nativa_render` surface. It is not a browser canvas implementation; paths,
  text, gradients, and compositing have a documented subset.
- **Video/audio/iframe** reserve space with a marker. There is no multimedia
  playback or nested document. Do not use these as if they worked.
- **WebGL** is the separate `gl_surface`/native bridge path. V8 pages do not
  expose it; QuickJS pages can use the bridge when the host provides a GL
  context.

## Scrolling and hit testing

Scrolling is implemented with Flutter scroll views and a CSS scroll container
abstraction. `overflow: auto/scroll` creates a vertical scroll container;
horizontal scrolling is limited to intrinsically wide content.

Hit testing follows the painted/stacked order. Transforms and sticky boxes
participate in hit testing. DOM `getBoundingClientRect`, `offsetWidth`,
`scrollIntoView`, `elementFromPoint`, and resize/intersection observers query
the renderer through a geometry registry. Elements inside a virtualized subtree
may report estimated geometry until they are materialized.

Pointer events include coordinates, hover/active state, click/double-click,
context menu, drag/drop, and focus. Keyboard events are delivered to the focused
element. This is an event subset, not a full browser input stack.

## Virtualization

Large in-flow block/flex/grid containers can switch to a virtualized layout:

- threshold: at least **24 child slots**;
- only viewport slots plus overscan are built and styled;
- offscreen DOM elements have no render object and estimated geometry;
- features that require exact geometry (generated content, absolute children
  inside the virtual region, complex inline runs) disable virtualization;
- `data-nativa-virtual="false"` (or `data-nv-virtual="false"`) opts out;
- scroll-to/scrollIntoView materializes the target slot before completing.

This is the NativaX equivalent of a display lock, not full browser rendering.
It exists because a page with thousands of rows would otherwise create thousands
of render objects. The trade-off is approximate geometry and a rebuild when an
offscreen item becomes visible.

## Animation

CSS transitions and `@keyframes` are driven by Flutter tickers and a style
interpolation layer. `CssAnimatedBox` holds animated computed values and notifies
the render object. Supported easing and interpolatable properties are listed in
[`../css-supported.md`](../css-supported.md). Animations do not propagate to
descendants for inherited properties; this is a known divergence.

## Diagnostics and measurement

`NativaXDocumentView.onDiagnostic` receives renderer approximations, unresolved
images, and similar host-visible warnings. The renderer can also emit draw traces
and layout timing when `NATIVAX_TRACE_DRAW=1` or the timed-layout wrapper is
enabled.

Visual quality is measured externally:

```bash
dart run debug/engines/visual_comparison/bin/visual_check.dart --suite 50projects50days
```

The latest recorded baseline is 52.59 % mean overall on 51 pages. Do not convert
that number into “52 % of CSS works”: it is a weighted visual score with fixed
thresholds, not a standards metric.

## Known architectural gaps

- Whole-document rebuild on many mutations; no full incremental layout graph.
- CSS table layout is approximated with flex/block primitives.
- Some flex/grid intrinsic sizing and baseline cases diverge.
- Inline boxes do not split across lines when they have decoration.
- No media playback or nested documents.
- Text shaping/line breaking is delegated to Flutter, not a browser text stack.
- Accessibility semantics are not implemented as a browser accessibility tree.
- Visual fidelity is low, dominated by position and layout errors.

## Related

- [`../internals/renderer.md`](../internals/renderer.md)
- [`../css-supported.md`](../css-supported.md)
- [`../visual-fidelity.md`](../visual-fidelity.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)
