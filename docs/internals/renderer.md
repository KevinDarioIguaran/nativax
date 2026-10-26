# Renderer internals

The renderer turns `ComputedStyle` + DOM into Flutter render objects. This page
focuses on implementation and failure modes; the user-facing property list is
[`../css-supported.md`](../css-supported.md).

## Entry point

`NativaXDocumentView` is a Flutter `StatefulWidget` that implements
`dom.LayoutHost`. It owns:

- a `ScrollController` and viewport scope;
- the mutation subscription;
- a `NativaXWidgetCache`;
- a `CanvasRegistry`;
- focus state for keyboard input;
- fixed/sticky caches;
- a `ValueNotifier<int>` revision that triggers rebuilds;
- optional draw/layout tracing.

On mount it sets `styleEngine.lazySubtrees = true` and registers itself as the
document's `layoutHost`/`canvasHost`. On unmount it unregisters, disposes the
canvas registry, clears the widget cache, and restores document callbacks.

## Invalidation

DOM mutations arrive through `addMutationListener`. The view:

1. clears the fixed-position cache;
2. finds the target element;
3. marks content dirty for child-list, attribute, or character-data changes;
4. invalidates the changed element, its ancestors, and (for style/class/id
   changes) its subtree in `NativaXWidgetCache`;
5. removes detached nodes from the cache;
6. schedules a microtask/post-frame rebuild once.

`NativaXWidgetCache` is the key optimization: a rebuild starts at the root, but
unchanged widgets are returned as the same instance, so Flutter skips their
build/layout subtree. “Invalidate path” keeps siblings cached. This is not a
full incremental layout graph; it is a cached document rebuild with bounded
work.

Resize and scroll also trigger rebuilds/materialization. The view tracks the last
build width/height and can update geometry without recomputing everything.

## The box stack

| Widget/RenderObject | Role |
|---|---|
| `CssBox` / `RenderCssBox` | Box decorations, borders, background, shadows, clipping, hit testing |
| `CssBlockFlow` / `RenderCssBlock` | Block and inline flow, stacking, absolute/fixed children |
| `CssFlexLayout` / `RenderCssFlex` | Flex sizing, wrapping, alignment, gaps, order |
| `CssGridLayout` / `RenderCssGrid` | Track sizing, placement, areas, implicit tracks |
| `CssTransform` / `RenderCssTransform` | 2D transforms and perspective projection |
| `CssSticky` / `RenderCssSticky` | Sticky positioning inside a scroll container |
| `CssContainingBlock` | Establishes a containing block for positioned descendants |
| `CssVirtualBlock` | Materializes a window of large block/flex/grid children |
| `NativaXVirtualScrollView` | Virtual scroll viewport |
| `CssAnimatedBox` | Transition/keyframe interpolation |
| `NativaXWidgetCache` | Reuses unchanged widget subtrees |

The renderer does not use Flutter `Row`/`Column` as the page layout engine. It
uses custom `RenderBox` subclasses so CSS box sizing, margins, absolute
positioning, and intrinsic sizing remain in one place.

## Layout order

A typical frame:

1. `RenderCssBlock`/flex/grid lays out children with CSS constraints.
2. Text is measured with a `TextPainter` using mapped font/line metrics.
3. Intrinsic passes (`min-content`, `max-content`, preferred width) run for
   flex/grid sizing where needed.
4. Positioned children are laid out relative to their containing block.
5. Sticky/fixed boxes are offset against the viewport.
6. The box paints decoration, background, text, images, and canvas/SVG.
7. Geometry is cached for DOM queries and observers.
8. Flutter composites the layer tree.

The `RenderLayoutTimed` wrapper and `LayoutProfile` can attribute build, dry
layout, and intrinsic time when enabled.

## Geometry and DOM queries

The document view exposes `getBoundingClientRect`, offset/scroll metrics,
`elementFromPoint`, `scrollIntoView`, and observer data through the
`LayoutHost` contract. The data comes from:

- real `RenderBox` geometry for materialized elements;
- estimated geometry for virtualized offscreen elements;
- a fallback zero/estimated box when an element has no render object.

A script that queries geometry immediately after a style change may see the
previous layout until a frame has run. `scrollIntoView`/geometry may force a
frame in some paths. Do not expect synchronous browser layout everywhere.

## Text and fonts

Fonts are mapped from CSS families to Flutter `TextStyle`s. `@font-face` fonts
are loaded by `nativax` through the resource loader and registered before scripts.
Fallbacks are applied when a family is missing.

Text shaping, bidi, and line breaking are delegated to Flutter/Skia. NativaX
does not implement a Unicode line-break algorithm. `white-space`, alignment,
decoration, ellipsis, and inline atomic boxes are handled by the renderer.

## Images

`NativaXImageResolver` maps an element to a Flutter `ImageProvider?`. The
renderer:

- reserves intrinsic space when possible;
- displays a placeholder for null/broken images;
- applies `object-fit`, `alt`, borders, and clipping;
- emits a diagnostic for unresolved images (deduplicated per mount).

NativaX never calls `Image.network` or fetches an `img` URL implicitly.

## Canvas and WebGL

Canvas 2D is a `nativa_dom_bindings` prelude plus a `nativa_render` surface. It
supports paths, fills/strokes, gradients, text, images, transforms, clipping, and
compositing to a documented degree. It is not a complete browser canvas.

WebGL is the `gl_surface.dart` + native bridge path, available on QuickJS pages
when the host provides a GL context. V8 pages have `__nx_gl_native = null`.
Do not treat canvas 2D support as WebGL support.

## Virtualization

`_virtualContent` in `node_view.dart` decides when a container can virtualize:

- block/list/flex/grid containers with at least 24 child slots;
- not the root/body/fieldset;
- not overlays, fixed HUDs, or containers with features the estimator cannot
  preserve;
- generated content, absolute children inside the region, or complex inline
  runs disable it;
- `data-nativa-virtual="false"` / `data-nv-virtual="false"` opts out.

`CssVirtualBlock` materializes only viewport slots + overscan, estimates the
rest, and registers `virtualOwner` so focus/scroll can materialize a slot.
Offscreen elements have no computed style or render object until materialized.
This is why geometry can be approximate and why virtualization is opt-out for
pages that need exact DOM geometry everywhere.

## Animation

`CssAnimatedBox` owns an `AnimationController` and interpolates computed styles
for `transition` and `@keyframes`. It listens to style changes, updates the
render object, and emits transition/animation DOM events. The interpolator
supports lengths, numbers, colors, transforms, and shadows; other properties
switch discretely. Inherited animated properties do not propagate to descendants.

## Tracing

| Variable | Effect |
|---|---|
| `NATIVAX_TRACE_DRAW=1` | Timestamped draw log; also enables layout profile |
| `NATIVAX_TRACE_RENDER=1` | Alias for draw trace |
| `NATIVAX_RENDER_PROFILE=1` | Layout profile buckets |
| `NATIVAX_NO_STYLE_CACHE=1` | Disables computed-style cache |
| `NATIVAX_NO_BACKDROP=1` | Disables backdrop blur path |

See [`diagnostics.md`](diagnostics.md) for artifact locations and commands.

## Known renderer gaps

- CSS table layout is approximated; `table-row` is flex-like in the UA sheet.
- Some flex/grid baseline and intrinsic sizing combinations diverge.
- Inline decorated boxes are atomic and do not split across lines.
- Sticky/fixed interactions with every scroll container combination are not
  fully covered by tests.
- No media playback or nested documents.
- Geometry inside virtualized regions is estimated until materialized.
- Accessibility semantics are not a browser accessibility tree.
- Visual fidelity is 52.59 % mean on the 51-page baseline; position/layout are
  the weakest categories.

## Related

- [`../architecture/rendering.md`](../architecture/rendering.md)
- [`../css-supported.md`](../css-supported.md)
- [`../visual-fidelity.md`](../visual-fidelity.md)
- [`diagnostics.md`](diagnostics.md)
