# Chromium mapping for the owned renderer

This is a design-reference map, not a claim that NativaX embeds Blink or
Chromium. No Chromium code is copied. The mechanisms inform `nativa_render` and
`nativa_css`; Chromium is also the external measurement instrument for the
visual suite.

Reference: `chromium/src` at `refs/heads/main`, inspected 2026-10-23. Paths below
are relative to `third_party/blink/renderer/`.

## 1. Locking style/layout/paint for a subtree

**Problem:** a 10,000-row document has style, render objects, layout, and paint
for rows millions of pixels away.

**Chromium:** `core/display_lock/display_lock_context.h` defines
`DisplayLockContext` with per-phase decisions
`ShouldStyleChildren()`, `ShouldLayoutChildren()`, `ShouldPrePaintChildren()`,
and `ShouldPaintChildren()`. `Lock()`/`Unlock()` change state, and
`content-visibility` requests it via `SetRequestedState()`. Display-lock
utilities prevent forcing a locked ancestor.

**NativaX:** `CssVirtualBlock` is the container lock. Outside the culling window
it builds no widgets, so there is no Flutter `Element`, render object, layout,
or style call. The block still exists as a CSS box; its height is composed from
measured and estimated row heights. The decision happens before visiting
children, at the style boundary.

## 2. Culling rect and overscan

**Chromium:** `platform/graphics/paint/cull_rect.h` defines `CullRect` with
intersection helpers. `CullRectUpdater` propagates it recursively, expands for
composited scroll, and clips with transforms.

**NativaX:** the window is a vertical interval,
`viewportTop - overscan <= y < viewportTop + viewportHeight + overscan`, with
one viewport of overscan by default. Rows are located by summing medium heights
with a linear arithmetic pass that does not build widgets. The window is
recomputed once per frame after scroll, not on every mutation.

## 3. Estimated size and correction on entry

**Chromium:** `content-visibility: auto` uses `contain-intrinsic-size` as a
placeholder, then runs real layout when unlocked.

**NativaX:** each block keeps measured heights, a moving average for unmeasured
rows, and an initial structural estimate (declared height, line-height/padding,
tag default). The total is `n * average + sum(measured - average)`. Entering the
window measures the real render box and replaces the estimate; the scroll
controller applies the delta in the same post-frame so the visible anchor does
not jump.

## 4. Scroll anchoring

**Chromium:** `core/layout/scroll_anchor` finds an anchor, computes an
adjustment, applies it, and restores the offset around display locks.

**NativaX:** before correcting heights, it picks the first materialized row whose
top is at or above the viewport, computes the height delta above it, and calls
`jumpTo(offset + delta)` in the same post-frame. If the scroller is at its
maximum, the clamp wins and the next frame re-anchors.

## 5. Activation by navigation, focus, selection, find

**Chromium:** `DisplayLockActivationReason` includes accessibility,
find-in-page, fragment navigation, script focus, `scrollIntoView`, and
selection. Activation commits the subtree, often keeping it unlocked for two
frames.

**NativaX:** `CssVirtualBlockState.ensureBuilt(element)` pins the element,
forces a rebuild, and materializes its render object on the next frame. It is
used by geometry (`LayoutHost.boxOf`), `scrollIntoView`, hash navigation,
focus/Tab, and selection paths. Until materialized, geometry may be estimated.
Selection and find are limited APIs; materialization does not imply Blink-level
compatibility.

## 6. Bounded recycling

**Chromium:** locking detaches the layout subtree; culling avoids paint
fragments outside the cull rect.

**NativaX:** the materialized window is bounded by
`viewport + 2 * overscan`. Widgets leaving the window are removed and their
render objects released. The block keeps light data (heights, indices, DOM
elements), not render trees. The recycle queue keeps at most one window of
built widgets and does not grow with row count. `virtualization_test.dart`
checks live render objects for 100/1,000/10,000 rows remain roughly constant.

## 7. Deliberate differences

- Chromium keeps a `LayoutObject` and locks phases; NativaX builds no render
  object outside the window. This is more aggressive and fits Flutter.
- Chromium derives the intrinsic placeholder from CSS; NativaX starts from a
  structural estimate and corrects with real measurements.
- Flutter owns scrolling, so anchoring lives in the virtual block rather than
  Blink's `ScrollAnchor`.
- Selection/find remain limited; materialization preserves geometry but is not
  full Blink parity.

## 8. CSS: RuleSet, SelectorFilter, MatchedPropertiesCache

**Problem:** every element scanning every rule is dominated by a large
Tailwind/Font Awesome sheet.

**Chromium:**

- `RuleSet` buckets rules by id/class/tag/universal/pseudo subject;
- `SelectorFilter` rejects descendant selectors with an ancestor filter before
  matching;
- `MatchedPropertiesCache` reuses matched declarations and resolved styles for
  equal signatures;
- the style resolver shares styles between siblings with the same inherited
  context.

**NativaX:**

- `StyleEngine` indexes id/class/tag/universal and has a hover-specific bucket
  so non-hoverable nodes do not create a `MouseRegion`;
- `_elementSignature` + `_matchedCache` share cascaded declarations;
- `_computedCache` keys by signature + inherited style identity + structural
  context where needed;
- structural selectors (`:first-*`, `:nth-*`, `:empty`, `:has`, `+`, `~`) are
  detected during indexing, so only those subjects include structural context;
- `useStyleCaches` allows measuring the uncached path; production keeps caches
  on.

Current gap: Chromium's ancestor Bloom filter and full invalidation sets.
NativaX still uses subject buckets + signatures. Measurements with metrics
enabled show style is no longer the dominant cost in the Bible fixture; layout
and paint dominate population frames.

## 9. LayoutNG: ConstraintSpace and LayoutResult

**Problem:** repeated passes (`layout`, dry, intrinsic) can re-measure text.

**Chromium:** immutable `ConstraintSpace`, reusable `LayoutResult` keyed by
constraints/style, explicit flex child spaces, and targeted invalidation
(`SetNeedsLayout`, `SetChildNeedsLayout`) bound relayout.

**NativaX:** `RenderCssFlex` reuses real child layout when a flexible length
does not change the main size. `LayoutProfile` separates `box.layout`,
`box.dry`, `box.paint`, `flex.*`, `text.*`, and `text.intrinsic` per frame.
Not implemented: caching a `LayoutResult` by `(constraints, style)` in
`RenderCssBox`/`RenderCssFlex` and limiting relayout to a boundary. Attempts to
cache intrinsics did not move the metric and were reverted; do not claim a
layout-cache win without new evidence.

## 10. Text and mutation

Chromium caches shaping by `(text, style, width)` and batches document
lifecycle invalidations. NativaX measures text with Flutter's
`RenderParagraph`, attributes timed passes through `LayoutTimed`, and keeps one
style flush per frame in `NativaXDocumentView._flush`, deferring style work for
out-of-view virtualized nodes (`invalidateDeferred`).

## 11. Pseudo-element RuleSet and ElementRuleCollector

**Problem:** `hasPseudoRules()`/`pseudoStyleOf()` scanning every `::before`
rule is expensive with icon fonts.

**Chromium:** pseudo-element rules are indexed by their rightmost subject in
`RuleSet`; `ElementRuleCollector` collects only candidate lists for the element.

**NativaX:** `_RuleBuckets` indexes pseudo rules by subject;
`pseudoStyleOf`/`cascadedDeclarations(..., pseudo:)` iterate only
`buckets.candidates(element)`. `nativaxNeverRenderedTags` excludes
`script/style/head/title/meta/link/noscript/template` before styling.
`StyleEngine.metricsEnabled` (opt-in with `NATIVAX_METRICS=1`) reports selector
counts, candidates, cache hits/misses, and exclusive/self time.

Remaining gap: ancestor Bloom filters and complete invalidation sets. Current
work has reduced style cost; layout/paint is the next bottleneck.

## Status and evidence

This mapping is **design guidance**. Each claim about NativaX must be checked in
source and tests. Relevant files:

- `packages/nativa_render/lib/src/layout/virtualization.dart`
- `packages/nativa_render/lib/src/layout/layout_profile.dart`
- `packages/nativa_render/test/virtualization_test.dart`
- `packages/nativa_css/lib/src/cascade.dart` (`StyleEngine`)
- `packages/nativa_render/lib/src/render/node_view.dart`

The latest measured visual and performance results are in
[`visual-fidelity.md`](visual-fidelity.md) and
[`performance-suite.md`](performance-suite.md). A Chromium mechanism being
described here is not evidence that NativaX already matches it.

## Related

- [`architecture/rendering.md`](architecture/rendering.md)
- [`internals/renderer.md`](internals/renderer.md)
- [`css-supported.md`](css-supported.md)
- [`visual-fidelity.md`](visual-fidelity.md)
