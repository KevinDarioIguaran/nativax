var CeriousScroll = (function (exports) {
    'use strict';

    /**
     * Copyright (c) 2024-2026 Cerious DevTech LLC. All rights reserved.
     *
     * Sliding-window height map. Writes prune; reads do not. Tail indices are
     * pinned so true-bottom survives a prune while the camera is at the top.
     */
    class PerformanceCache {
        /**
         * @param getElementHeight Height lookup used when a row has no measured value
         *   (walks such as {@link findRowFromScrollPosition}).
         * @param provider Optional authoritative height source. When supplied, the
         *   measured-height map and its pruning are bypassed entirely — heights are
         *   computed, not observed, so evicting them would be lossy rather than
         *   merely cold. See {@link HeightProvider}.
         */
        constructor(getElementHeight, provider) {
            this.getElementHeight = getElementHeight;
            this.provider = provider;
            this._isUniformHeight = undefined;
            this._uniformHeightValue = undefined;
            this._measuredHeights = new Map();
            this._lastAccessedIndex = 0;
            // Upper bound on element count, used to keep linear walks bounded. 0 means
            // "unknown"; in that case the cache falls back to its previous behavior.
            this._totalElements = 0;
        }
        /**
         * Tell the cache how many elements exist in the dataset. Used to bound
         * linear walks (e.g. findRowFromScrollPosition) so a malformed scroll
         * position can never spin past the dataset.
         *
         * @param totalElements Dataset length. Ignored if not a finite >= 0 number.
         */
        setTotalElements(totalElements) {
            if (!Number.isFinite(totalElements) || totalElements < 0)
                return;
            this._totalElements = Math.floor(totalElements);
        }
        /**
         * @param index Dataset index.
         * @param height Pixels. Non-finite / negative becomes 1px (detached-node `offsetHeight`).
         */
        setMeasuredHeight(index, height) {
            // A provider is the source of truth; DOM measurements are advisory noise.
            if (this.provider)
                return;
            // NaN/Infinity would poison total-height math for the rest of the session.
            if (!Number.isFinite(index) || index < 0) {
                return;
            }
            if (!Number.isFinite(height) || height < 0) {
                // Fall back to a 1px placeholder rather than throwing; the caller is
                // typically `offsetHeight` which can occasionally yield 0 during
                // measurement of detached/zero-height nodes.
                height = 1;
            }
            this._measuredHeights.set(index, height);
            this._lastAccessedIndex = index;
            this._pruneOldCacheEntries();
            if (this._isUniformHeight === undefined && this._measuredHeights.size >= 10) {
                // Don't Array.from the map just to compare values.
                let firstHeight;
                let allSame = true;
                for (const height of this._measuredHeights.values()) {
                    if (firstHeight === undefined) {
                        firstHeight = height;
                    }
                    else if (height !== firstHeight) {
                        allSame = false;
                        break;
                    }
                }
                // 1px placeholders are measurement failures, not real uniform rows.
                if (allSame && firstHeight !== undefined && firstHeight > 1) {
                    this._isUniformHeight = true;
                    this._uniformHeightValue = firstHeight;
                }
                else if (!allSame) {
                    this._isUniformHeight = false;
                }
            }
        }
        /**
         * @param index Dataset index.
         * @returns Whether a real measurement exists (not an estimate).
         */
        hasMeasuredHeight(index) {
            if (this.provider)
                return true; // every index has a computable height
            return this._measuredHeights.has(index);
        }
        /**
         * Detected uniform row height, or undefined. Lets the renderer skip
         * offsetHeight on new rows during fast scroll.
         *
         * @returns Height in pixels, or `undefined` if rows are not known to be uniform.
         */
        getUniformHeightHint() {
            // The hint lets the renderer skip offsetHeight. With a provider there is no
            // offsetHeight read to skip, and claiming uniformity would make the engine
            // extrapolate positions arithmetically from one height.
            if (this.provider)
                return undefined;
            return this._isUniformHeight === true ? this._uniformHeightValue : undefined;
        }
        /**
         * Hot path: Map.get only. Prune on write, not here.
         *
         * @param index Dataset index.
         * @returns Measured height in pixels, or `undefined` if never measured.
         */
        getMeasuredHeight(index) {
            if (this.provider)
                return this.provider.height(index);
            return this._measuredHeights.get(index);
        }
        _pruneOldCacheEntries() {
            const tailStart = this._totalElements > 0
                ? Math.max(0, this._totalElements - PerformanceCache.TAIL_PIN_COUNT)
                : Number.POSITIVE_INFINITY;
            const tailBudget = this._totalElements > 0 ? PerformanceCache.TAIL_PIN_COUNT : 0;
            if (this._measuredHeights.size <= PerformanceCache.CACHE_PRUNE_THRESHOLD + tailBudget) {
                return;
            }
            const keepWindow = PerformanceCache.MAX_MEASURED_HEIGHTS_CACHE / 2;
            const minKeep = Math.max(0, this._lastAccessedIndex - keepWindow);
            const maxKeep = this._lastAccessedIndex + keepWindow;
            for (const [index] of this._measuredHeights) {
                if (index >= tailStart)
                    continue;
                if (index < minKeep || index > maxKeep) {
                    this._measuredHeights.delete(index);
                }
            }
            const maxSize = PerformanceCache.MAX_MEASURED_HEIGHTS_CACHE + tailBudget;
            if (this._measuredHeights.size > maxSize) {
                const entries = [];
                for (const entry of this._measuredHeights.entries()) {
                    entries.push(entry);
                }
                entries.sort((a, b) => {
                    const aTail = a[0] >= tailStart ? 0 : 1;
                    const bTail = b[0] >= tailStart ? 0 : 1;
                    if (aTail !== bTail)
                        return aTail - bTail;
                    const distA = Math.abs(a[0] - this._lastAccessedIndex);
                    const distB = Math.abs(b[0] - this._lastAccessedIndex);
                    return distA - distB;
                });
                this._measuredHeights.clear();
                for (let i = 0; i < maxSize && i < entries.length; i++) {
                    this._measuredHeights.set(entries[i][0], entries[i][1]);
                }
            }
        }
        /**
         * Sum of heights from row 0 up to, but not including, `row`.
         *
         * @param row Exclusive end index.
         * @returns Pixels. Unmeasured rows contribute 1px.
         */
        getCumulativeHeight(row) {
            if (row <= 0)
                return 0;
            if (this.provider) {
                if (this.provider.cumulativeHeight)
                    return this.provider.cumulativeHeight(row);
                let sum = 0;
                for (let i = 0; i < row; i++)
                    sum += this.provider.height(i);
                return sum;
            }
            if (this._isUniformHeight && this._uniformHeightValue !== undefined) {
                return row * this._uniformHeightValue;
            }
            let cumulativeHeight = 0;
            for (let i = 0; i < row; i++) {
                const measured = this._measuredHeights.get(i);
                cumulativeHeight += measured !== undefined ? measured : 1;
            }
            return cumulativeHeight;
        }
        /**
         * @param scrollPixel Distance from the top of the dataset in pixels.
         * @returns `{ element, offset }` for that pixel. Unmeasured rows are 1px.
         */
        findRowFromScrollPosition(scrollPixel) {
            var _a;
            if (!Number.isFinite(scrollPixel) || scrollPixel <= 0) {
                return { element: 0, offset: 0 };
            }
            if ((_a = this.provider) === null || _a === void 0 ? void 0 : _a.rowAtPosition) {
                return this.provider.rowAtPosition(scrollPixel);
            }
            // Upper bound for any walk. Without an explicit total we fall back to the
            // largest known measured index; if even that's unknown we cap at a
            // generous-but-bounded value so a malformed input can never hot-loop.
            const maxElementIndex = this._totalElements > 0
                ? this._totalElements - 1
                : (this._measuredHeights.size > 0
                    ? Math.max(...this._measuredHeights.keys()) + 1
                    : 1000000);
            if (this._isUniformHeight && this._uniformHeightValue !== undefined && this._uniformHeightValue > 0) {
                let element = Math.floor(scrollPixel / this._uniformHeightValue);
                element = Math.min(element, maxElementIndex);
                const offset = scrollPixel - element * this._uniformHeightValue;
                const clampedOffset = Math.max(0, Math.min(offset, Math.max(1, this.getElementHeight(element)) - 1));
                return { element, offset: clampedOffset };
            }
            let element = 0;
            let cumulativeHeight = 0;
            while (element <= maxElementIndex) {
                const elementHeight = this._measuredHeights.has(element)
                    ? this._measuredHeights.get(element)
                    : 1;
                if (cumulativeHeight + elementHeight > scrollPixel) {
                    break;
                }
                cumulativeHeight += elementHeight;
                element++;
            }
            if (element > maxElementIndex) {
                element = maxElementIndex;
            }
            const elementHeight = Math.max(1, this.getElementHeight(element));
            const offset = Math.max(0, Math.min(scrollPixel - cumulativeHeight, elementHeight - 1));
            return { element, offset };
        }
        invalidateCache() {
            this._isUniformHeight = undefined;
            this._uniformHeightValue = undefined;
            // Heights stay — they are still valid measurements.
        }
        /** Dataset identity changed, not just a resize. */
        clearAllCaches() {
            this.invalidateCache();
            this._measuredHeights.clear();
        }
        /** Whether an authoritative height source replaced DOM measurement. */
        get hasHeightProvider() {
            return this.provider !== undefined;
        }
        /**
         * Total content height from the provider, if it knows one.
         * @returns Pixels, or `undefined`.
         */
        getProvidedTotalHeight() {
            var _a;
            return ((_a = this.provider) === null || _a === void 0 ? void 0 : _a.totalHeight) ? this.provider.totalHeight() : undefined;
        }
        /**
         * @returns Debug snapshot of cache size and uniform-height detection.
         */
        getCacheStats() {
            return {
                measuredElements: this._measuredHeights.size,
                isUniformHeight: this._isUniformHeight,
                uniformHeightValue: this._uniformHeightValue,
                cacheWindowSize: 0,
                cacheWindowStart: 0
            };
        }
    }
    PerformanceCache.MAX_MEASURED_HEIGHTS_CACHE = 200;
    PerformanceCache.CACHE_PRUNE_THRESHOLD = 250;
    // True-bottom walks backward from the last row. If those heights are
    // pruned while the camera is at the top, the renderer remounts ~50
    // sentinel rows every frame. Pin a small tail so that cannot happen.
    PerformanceCache.TAIL_PIN_COUNT = 80;

    /**
     * Copyright (c) 2024-2026 Cerious DevTech LLC. All rights reserved.
     *
     * Sibling strip whose scrollTop is a percentage of the virtual range.
     * Bidirectional sync; programmatic writes are matched by position so their
     * echo isn't treated as a user drag.
     */
    class NativeScrollbar {
        /**
         * Inject the one-time stylesheet that hides the native OS scrollbar on
         * the sibling driver and styles our custom thumb. Done once per document
         * because every CeriousScroll instance uses the same selectors.
         *
         * Consumers can override the thumb appearance via CSS variables on the
         * scroll host (`--cerious-thumb-color`, `--cerious-thumb-color-active`,
         * `--cerious-thumb-width`, `--cerious-thumb-width-active`).
         */
        static ensureStylesInjected() {
            if (this._stylesInjected)
                return;
            if (typeof document === 'undefined')
                return;
            const style = document.createElement('style');
            style.setAttribute('data-cerious-scrollbar-styles', '');
            style.textContent = `
[data-cerious-scrollbar="container"][data-touch="true"] { scrollbar-width: none; -ms-overflow-style: none; }
[data-cerious-scrollbar="container"][data-touch="true"]::-webkit-scrollbar { width: 0; height: 0; display: none; }
[data-cerious-scrollbar="thumb"] {
  position: absolute;
  right: 2px;
  width: var(--cerious-thumb-width, 5px);
  min-height: ${NativeScrollbar.THUMB_MIN_HEIGHT_PX}px;
  border-radius: 999px;
  background: var(--cerious-thumb-color, rgba(0, 0, 0, 0.45));
  opacity: 0;
  transition: opacity 200ms ease, width 120ms ease, background-color 120ms ease;
  pointer-events: auto;
  touch-action: none;
  /* Expand the touch hit target without changing the painted size: a
   * transparent pseudo-element extends the pointer area ~10px in each
   * direction so a fingertip reliably grabs the slim pill. */
  will-change: top, height, opacity;
  z-index: ${NativeScrollbar.DEFAULT_Z_INDEX + 1};
}
[data-cerious-scrollbar="thumb"]::before {
  content: "";
  position: absolute;
  top: -8px;
  bottom: -8px;
  left: -12px;
  right: -12px;
}
[data-cerious-scrollbar="thumb"][data-visible="true"] { opacity: 1; }
[data-cerious-scrollbar="thumb"][data-active="true"] {
  width: var(--cerious-thumb-width-active, 8px);
  background: var(--cerious-thumb-color-active, rgba(0, 0, 0, 0.7));
  opacity: 1;
}
@media (prefers-color-scheme: dark) {
  [data-cerious-scrollbar="thumb"] { background: var(--cerious-thumb-color, rgba(255, 255, 255, 0.5)); }
  [data-cerious-scrollbar="thumb"][data-active="true"] { background: var(--cerious-thumb-color-active, rgba(255, 255, 255, 0.75)); }
}
`;
            document.head.appendChild(style);
            this._stylesInjected = true;
        }
        /**
         * Detect a touch-primary device (mobile/tablet). The custom thumb only
         * applies here — desktop browsers keep the native OS scrollbar on the
         * sibling strip because it works correctly and matches platform chrome.
         */
        static isTouchPrimary() {
            if (typeof window === 'undefined' || typeof window.matchMedia !== 'function')
                return false;
            return window.matchMedia('(hover: none) and (pointer: coarse)').matches;
        }
        /** Monotonic-ish timestamp in ms, with a fallback for non-DOM environments. */
        static _now() {
            return (typeof performance !== 'undefined' && typeof performance.now === 'function')
                ? performance.now()
                : Date.now();
        }
        /**
         * Schedule a callback for the next animation frame. Falls back to a 16ms
         * timer when requestAnimationFrame is unavailable (non-DOM / SSR), so the
         * scroll→render coalescing keeps working everywhere. Returns a cancel handle.
         */
        static _raf(cb) {
            if (typeof requestAnimationFrame === 'function')
                return requestAnimationFrame(cb);
            return setTimeout(cb, 16);
        }
        /** Cancel a handle from {@link _raf}. */
        static _caf(handle) {
            if (typeof cancelAnimationFrame === 'function')
                cancelAnimationFrame(handle);
            else
                clearTimeout(handle);
        }
        /**
         * @param totalElements Dataset length (sets virtual track height).
         * @param getScrollPercentage Current `0`–`100` position.
         * @param getElementHeight Height lookup for a dataset index.
         * @param onScrollPositionChange Called when the strip drives the camera.
         * @param scrollHandlers Navigation engine, or `null` until {@link setScrollHandlers}.
         * @param getViewportHeight Usable height in pixels.
         * @param getCurrentElement Camera row index.
         * @param getScrollOffset Pixels into the camera row.
         * @param getTrueBottomPosition Measured true-bottom camera, or `null`.
         * @param virtualTrackHeight Pixel height of the virtual track. Default 10_000_000.
         * @param onRender Optional. Invoked after a user-driven strip scroll so the host re-renders.
         */
        constructor(totalElements, getScrollPercentage, getElementHeight, onScrollPositionChange, scrollHandlers, getViewportHeight, getCurrentElement, getScrollOffset, getTrueBottomPosition, virtualTrackHeight = 10000000, onRender) {
            this.totalElements = totalElements;
            this.getScrollPercentage = getScrollPercentage;
            this.getElementHeight = getElementHeight;
            this.onScrollPositionChange = onScrollPositionChange;
            this.scrollHandlers = scrollHandlers;
            this.getViewportHeight = getViewportHeight;
            this.getCurrentElement = getCurrentElement;
            this.getScrollOffset = getScrollOffset;
            this.getTrueBottomPosition = getTrueBottomPosition;
            this.virtualTrackHeight = virtualTrackHeight;
            this.onRender = onRender;
            this._scrollbarContainer = null;
            /** Edge the strip is pinned to, remembered so later gutter syncs know which side to pad. */
            this._gutterSide = 'right';
            this._thumbElement = null;
            // Transparent overlay on the right edge of the container (touch only) that
            // makes the whole sibling-scrollbar strip a drag target — so a tap anywhere
            // in the column jumps the thumb and starts a drag, instead of requiring the
            // user to land on the slim painted thumb.
            this._thumbHitZone = null;
            this._thumbHitZoneDown = null;
            this._thumbFadeTimer = null;
            // Active drag state. Captured on pointerdown for the thumb; cleared on
            // pointerup/cancel. We drive scroll by writing to the sibling container's
            // `scrollTop`, which the existing scroll listener already maps to the
            // virtual position — so all scroll math stays in one place.
            this._thumbDrag = null;
            this._syncingScrollbar = false;
            // Last scrollTop value we wrote programmatically (wheel/touch/keyboard sync,
            // reflow, resize). The scroll listener compares the live scrollTop against
            // this: a match (within tolerance) means the event is the async echo of our
            // own write and is ignored; a difference means the user moved the strip and
            // we process it. This is robust to scroll-event coalescing — the browser may
            // collapse many rapid programmatic writes into FEWER scroll events, so a
            // per-write *counter* leaks a positive residual that then swallows the
            // user's subsequent real drags (a "dead zone" until enough events drain it).
            // Matching on the actual position carries no such residual. `null` means
            // "no programmatic write to reconcile yet".
            this._lastProgrammaticScrollTop = null;
            this._contentHeightSource = null;
            // Timestamp (ms) of the last GENUINE user scroll on the strip — i.e. a scroll
            // event that was NOT the echo of our own programmatic write. On desktop the
            // user drags the real native OS scrollbar (there is no custom thumb, so
            // `_thumbDrag` stays null), and the only evidence they are mid-drag is this
            // stream of real scroll events. `syncNativeScrollbar` reads it to defer
            // engine→scrollbar writes while the user is driving. See USER_SCROLL_DEFER_MS.
            this._lastUserScrollTs = 0;
            // Scroll→render coalescing. A native-scrollbar drag can fire several scroll
            // events per animation frame; rendering each one synchronously did 2-3× the
            // work per frame and dropped frames. We instead remember the latest scrollTop
            // and run the map+render ONCE on the next frame (the wheel path is already
            // rAF-driven, which is why it stays smooth). `_scrollRafId` is the pending
            // frame (null = none scheduled); `_pendingScrollTop` is the position to render.
            this._scrollRafId = null;
            this._pendingScrollTop = 0;
            this._cachedScrollbarWidth = undefined;
            // True when the platform uses OVERLAY scrollbars (macOS trackpad default,
            // mobile): the OS paints a thin auto-hiding bar OVER content and reserves no
            // layout width. Measured as a 0-width difference on a probe element. We must
            // not reserve a gutter in that case, or it leaves a dead gap with no visible
            // scrollbar. Cached alongside the width measurement.
            // Track scroll-event listeners so we can remove them on detach to prevent
            // listener leaks when the scrollbar is recreated.
            this._scrollListener = null;
            // Bound pointer handlers, retained so we can remove them on detach.
            this._thumbPointerDown = null;
            this._thumbPointerMove = null;
            this._thumbPointerUp = null;
        }
        /**
         * Inject the navigation engine after construction. NativeScrollbar is
         * created before the engine exists in CeriousScroll's bootstrap order, so
         * a deferred setter avoids the previous `null as any` cast and the
         * accompanying NPE risk if a scroll event fires before assignment.
         *
         * @param handlers Navigation engine instance.
         */
        /**
         * Height of the strip's scrollable surface.
         *
         * Single source of truth for both the creation path and later re-sizes —
         * they used to compute this independently, so installing a content-height
         * source only affected re-sizes and the strip kept its element-count height
         * from creation.
         *
         * @param container Strip element (its clientHeight sets the floor).
         * @returns Pixels.
         */
        computeSurfaceHeight(container) {
            // Nothing to scroll: give the strip no range at all, so the platform paints no thumb.
            //
            // The floor below exists so the thumb renders for a list whose element units would otherwise
            // fit the strip. Applied unconditionally it also guarantees a thumb for a list that genuinely
            // FITS — a folder holding one message got a permanent bar filling ~98% of its track, which
            // says nothing and cannot be moved.
            //
            // `canScroll()` asks the engine rather than guessing: the true-bottom camera is the top of the
            // dataset exactly when the whole of it is already on screen.
            if (!this.canScroll())
                return container.clientHeight;
            // Exceed the container so the thumb renders even for small lists.
            const minHeight = container.clientHeight + NativeScrollbar.ELEMENT_HEIGHT_MULTIPLIER;
            const contentHeight = this._contentHeightSource ? this._contentHeightSource() : undefined;
            const surface = (contentHeight !== undefined && Number.isFinite(contentHeight) && contentHeight > 0)
                ? contentHeight
                // Element count is the right proxy when an element is roughly a row.
                : (this.totalElements + 1) * NativeScrollbar.ELEMENT_HEIGHT_MULTIPLIER;
            // Capped on BOTH branches. The cap used to guard only the content-height
            // path, so a large dataset sized by element count asked for a strip the
            // browser would not give it — ten million rows requested 100,000,010px and
            // silently got 16,777,214. Nothing broke, because the thumb math reads
            // measured geometry, but the engine was reasoning about a number that did
            // not exist.
            const capped = Math.min(surface, NativeScrollbar.MAX_STRIP_HEIGHT_PX);
            return Math.max(Math.round(capped), minHeight);
        }
        /**
         * Whether the dataset can be scrolled at all.
         *
         * `computeTrueBottomPosition` walks back from the last element until it has filled the viewport;
         * when the whole dataset fits it runs out of elements and reports `{ element: 0, offset: 0 }` —
         * the camera is already at the bottom while sitting at the top, so there is nowhere to go. It
         * returns `null` while any tail element is still unmeasured, which is not the same claim, so
         * that case keeps the scrollable behaviour and is corrected on the next resize.
         *
         * @returns `false` only when the engine is certain everything is already visible.
         */
        canScroll() {
            const trueBottom = this.getTrueBottomPosition();
            if (!trueBottom)
                return true;
            return !(trueBottom.element === 0 && trueBottom.offset === 0);
        }
        /**
         * Size the strip by CONTENT height instead of element count.
         *
         * The default is `totalElements * 10px`, which is right when an element is
         * roughly a row: ten track pixels per row is ample resolution. When an element
         * is much larger than a row, that ratio collapses — 400 elements addressing
         * 10M px of content leaves ~3,360 content px per track px, so the position
         * quantizes and scrolling snaps.
         *
         * @param source Returns total content height, or undefined to keep element sizing.
         */
        setContentHeightSource(source) {
            this._contentHeightSource = source;
        }
        setScrollHandlers(handlers) {
            this.scrollHandlers = handlers;
        }
        /**
         * Attached sibling strip, or `null` if none.
         */
        get container() {
            return this._scrollbarContainer;
        }
        /**
         * True while a programmatic `scrollTop` write is in flight. Callers skip
         * re-sync so the echo cannot loop.
         */
        get isSyncing() {
            return this._syncingScrollbar;
        }
        getScrollbarWidth() {
            if (this._cachedScrollbarWidth !== undefined) {
                return this._cachedScrollbarWidth;
            }
            const outer = document.createElement('div');
            outer.style.cssText = 'visibility:hidden;width:100px;height:100px;overflow:scroll;position:absolute;top:-9999px;';
            document.body.appendChild(outer);
            const scrollbarWidth = outer.offsetWidth - outer.clientWidth;
            document.body.removeChild(outer);
            // A 0-width difference means the platform uses overlay scrollbars (they
            // float over content and reserve no space). Record that so the gutter is
            // A 0-width difference means the platform uses overlay scrollbars. Nothing
            // needs to be remembered about that: `syncGutter` measures the strip's own
            // painted width every time, which is 0 on such a platform and releases the
            // gutter on its own — and keeps working if the setting changes mid-session,
            // which a cached flag would not.
            this._cachedScrollbarWidth = scrollbarWidth || NativeScrollbar.DEFAULT_SCROLLBAR_WIDTH;
            return this._cachedScrollbarWidth;
        }
        /** Drop cached OS scrollbar width (zoom / display change). */
        clearScrollbarWidthCache() {
            this._cachedScrollbarWidth = undefined;
        }
        /**
         * @param container Host the strip is attached to.
         * @param viewportHeight New host height in pixels (unused for layout; strip is `height: 100%`).
         */
        handleViewportChange(container, viewportHeight) {
            this.clearScrollbarWidthCache();
            // Do not recreate the strip. It is height:100% so it tracks the host,
            // and recreating reset scrollTop to 0 — a stray scroll event then jumped
            // the viewport to the top, and echo-accounting stayed on the discarded
            // node (dead zone until enough events drained). Caller reflow() re-syncs
            // the thumb; clear the programmatic marker so a resize cannot eat the
            // next genuine scroll.
            this._syncingScrollbar = false;
            this._lastProgrammaticScrollTop = null;
        }
        /**
         * @param container Host element.
         * @param onViewportChange Called on window resize.
         * @returns Detach function.
         */
        setupAutoResizeHandling(container, onViewportChange) {
            const resizeHandler = () => onViewportChange(container);
            window.addEventListener('resize', resizeHandler);
            return () => {
                window.removeEventListener('resize', resizeHandler);
            };
        }
        /**
         * Attach the sibling strip (and touch overlay thumb when appropriate).
         * @param container Host element.
         */
        /**
         * @param side Which edge the strip sits on. Defaults to `'right'`; RTL hosts
         *   pass `'left'`, which is where a right-to-left reader expects it.
         */
        attachNativeScrollbar(container, side = 'right') {
            const existingScrollbar = container.querySelector('[data-cerious-scrollbar="container"]');
            if (existingScrollbar) {
                existingScrollbar.remove();
            }
            const detectedWidth = this.getScrollbarWidth();
            // On touch-primary devices the OS won't paint a scrollbar on this
            // sibling strip (the user's finger drags content, not the strip), so we
            // collapse the strip to zero width and draw our own overlay thumb on top
            // of the content. On desktop the strip carries the real native OS
            // scrollbar, which already adapts to the platform AND the input device
            // (e.g. macOS draws a thin auto-hiding overlay for a trackpad and a wider
            // persistent bar for a mouse) and to the host's `color-scheme`.
            //
            // Crucially we keep the strip fully transparent and borderless: painting
            // our own background/border over it (the previous `#f0f0f0` + `1px #ccc`)
            // drew a fake light "track" that masked the native scrollbar — looking
            // wrong on dark UIs and defeating the device adaptation. Leaving it bare
            // lets the genuine OS scrollbar show through unchanged.
            const touch = NativeScrollbar.isTouchPrimary();
            this._scrollbarContainer = this.createNativeScrollbar(container, {
                width: touch ? '0px' : `${detectedWidth}px`,
                position: side,
                style: {
                    background: 'transparent',
                    borderLeft: 'none',
                    zIndex: String(NativeScrollbar.DEFAULT_Z_INDEX)
                }
            });
        }
        /**
         * Create and attach a native scrollbar that drives virtual scrolling.
         *
         * @param container Host to attach the strip to.
         * @param options Strip width, side, and extra CSS.
         * @param options.width Strip CSS width. Default: measured OS scrollbar width.
         * @param options.position `'left'` or `'right'` (default `'right'`).
         * @param options.style Extra CSS properties written onto the strip.
         * @returns The strip element.
         */
        createNativeScrollbar(container, options = {}) {
            NativeScrollbar.ensureStylesInjected();
            // Remove any existing scrollbar first since we need to create one with current data
            const existingScrollbar = container.querySelector('[data-cerious-scrollbar="container"]');
            if (existingScrollbar) {
                existingScrollbar.remove();
            }
            // Also remove any prior thumb so we don't leak elements across recreations.
            const existingThumb = container.querySelector('[data-cerious-scrollbar="thumb"]');
            if (existingThumb)
                existingThumb.remove();
            const { width = `${this.getScrollbarWidth()}px`, position = 'right', style = {} } = options;
            // Touch-primary devices get the overlay thumb path. We tag the strip so
            // the scoped stylesheet hides its (otherwise-present) native scrollbar.
            const touch = NativeScrollbar.isTouchPrimary();
            const scrollbarContainer = document.createElement('div');
            scrollbarContainer.setAttribute('data-cerious-scrollbar', 'container');
            if (touch)
                scrollbarContainer.setAttribute('data-touch', 'true');
            scrollbarContainer.style.cssText = `
      position: absolute;
      top: 0;
      ${position}: 0;
      width: ${width};
      height: 100%;
      /* auto, not scroll: with no range the strip must show nothing. A platform with classic
         (space-taking) scrollbars paints the track for overflow:scroll whether or not it can
         actually move. */
      overflow-y: auto;
      overflow-x: hidden;
      z-index: ${style['zIndex'] || NativeScrollbar.DEFAULT_Z_INDEX};
      background: ${style['background'] || 'transparent'};
      border-left: ${style['borderLeft'] || 'none'};
      pointer-events: auto;
    `;
            // Create scrollable content (sets scroll range based on element count, not heights)
            // Add +1 to ensure scrollbar can reach 100% (accounts for rounding/boundary conditions)
            // Also ensure the surface always exceeds the container height so the thumb
            // renders even for small lists whose total element units would otherwise
            // fit within the viewport (e.g. paged datasets).
            const scrollableContent = document.createElement('div');
            scrollableContent.setAttribute('data-cerious-scrollbar', 'content');
            scrollableContent.style.cssText = `
      width: 1px;
      height: ${this.computeSurfaceHeight(container)}px;
      pointer-events: none;
    `;
            scrollbarContainer.appendChild(scrollableContent);
            // Position container relatively and ensure it can contain the scrollbar
            if (getComputedStyle(container).position === 'static') {
                container.style.position = 'relative';
            }
            // Mount the strip BEFORE reserving space for it. The gutter has to match the
            // strip's RENDERED width, and only a mounted element reports that — the
            // configured width excludes any `borderLeft` the caller styled on. The strip
            // is absolutely positioned, so mounting it first cannot disturb layout.
            container.appendChild(scrollbarContainer);
            this._gutterSide = position === 'left' ? 'left' : 'right';
            this.syncGutter(scrollbarContainer, parseInt(width) || undefined);
            // The expensive half of a scroll: map the latest scrollTop to a virtual
            // position and render the viewport. Coalesced to ONE run per animation frame
            // (see `_scrollRafId`), so a fast native-scrollbar drag that fires several
            // scroll events in a frame renders only the final position — matching the
            // wheel path's rAF cadence. No extra blank rows (the full viewport is still
            // rendered every frame) and at most ~1 frame of added latency.
            const renderFromScroll = () => {
                this._scrollRafId = null;
                // The strip may have been torn down between scheduling and this frame.
                if (!this.scrollHandlers || !this._scrollbarContainer)
                    return;
                const scrollTop = this._pendingScrollTop;
                const maxScroll = scrollbarContainer.scrollHeight - scrollbarContainer.clientHeight;
                // Calculate percentage based on scrollbar position. Add tolerance for when
                // the scrollbar is at/near bottom (the thumb has a minimum size).
                const BOTTOM_TOLERANCE_PX = 1; // pixels from bottom to treat as 100%
                let percentage;
                if (maxScroll > 0) {
                    percentage = scrollTop >= maxScroll - BOTTOM_TOLERANCE_PX
                        ? NativeScrollbar.PERCENTAGE_MAX // Treat as 100%
                        : (scrollTop / maxScroll) * NativeScrollbar.PERCENTAGE_MAX;
                }
                else {
                    percentage = 0;
                }
                this._syncingScrollbar = true;
                const trueBottom = this.getTrueBottomPosition();
                // Calculate target position based on percentage.
                // Map 0% to element 0 offset 0, and 100% to the true bottom position.
                let targetElement;
                let targetOffset;
                if (trueBottom) {
                    // Linear interpolation between 0% (element 0, offset 0) and 100% (true
                    // bottom). Convert true bottom to a scalar position for interpolation.
                    const trueBottomPosition = trueBottom.element + (trueBottom.offset / this.getElementHeight(trueBottom.element));
                    const targetPosition = (percentage / NativeScrollbar.PERCENTAGE_MAX) * trueBottomPosition;
                    targetElement = Math.floor(targetPosition);
                    const targetProgress = targetPosition - targetElement;
                    targetOffset = Math.round(targetProgress * this.getElementHeight(targetElement));
                }
                else {
                    // Fallback if true bottom is not available.
                    const targetIndexPosition = (percentage / NativeScrollbar.PERCENTAGE_MAX) * (this.totalElements - 1);
                    targetElement = Math.floor(targetIndexPosition);
                    const targetProgress = targetIndexPosition - targetElement;
                    targetOffset = Math.round(targetProgress * this.getElementHeight(targetElement));
                }
                // Check if position actually changed before doing expensive operations.
                const currentElement = this.getCurrentElement();
                const currentOffset = this.getScrollOffset();
                if (targetElement !== currentElement || targetOffset !== currentOffset) {
                    const result = this.scrollHandlers.jumpToPosition(targetElement, targetOffset, true);
                    container.dispatchEvent(new CustomEvent('viewport-change', {
                        detail: { element: result.element, scrollOffset: result.offset, percentage }
                    }));
                    // Trigger render callback - this is what actually updates the DOM.
                    if (this.onRender)
                        this.onRender(result);
                }
                this._syncingScrollbar = false;
            };
            // Bind scroll events - map scrollbar position directly to element index. The
            // cheap, must-stay-synchronous bookkeeping (echo rejection, the user-scroll
            // timestamp, thumb visuals) runs here; the map+render is deferred to a frame.
            const scrollListener = (_e) => {
                if (this._syncingScrollbar)
                    return;
                // Bail out gracefully if the engine hasn't been wired up yet (this can
                // happen if a scroll event fires between scrollbar creation and the
                // CeriousScroll constructor finishing).
                if (!this.scrollHandlers)
                    return;
                const scrollTop = scrollbarContainer.scrollTop;
                // Ignore the asynchronous echo of our own programmatic writes. We compare
                // the live scrollTop against the last value we wrote rather than counting
                // expected echoes: browsers coalesce rapid programmatic writes into fewer
                // scroll events, so a counter accumulates a positive residual that later
                // swallows the user's genuine drags (the wheel-then-drag "dead zone").
                // A position match has no residual, and still distinguishes a user move
                // (different scrollTop) from an echo (same scrollTop) even when a write
                // and a user move coalesce into one event — the live scrollTop then holds
                // the user's value, so it is correctly processed.
                if (this._lastProgrammaticScrollTop !== null &&
                    Math.abs(scrollTop - this._lastProgrammaticScrollTop) <=
                        NativeScrollbar.PROGRAMMATIC_SCROLL_TOLERANCE_PX) {
                    return;
                }
                // This event is a genuine user move (it did NOT match the programmatic
                // marker). Invalidate the marker now. It is only ever set by
                // syncNativeScrollbar (a programmatic write) and is NEVER refreshed by a
                // scrollbar drag — the drag path calls jumpToPosition(skipScrollbarSync).
                // So once the user drags away from a synced position the marker goes
                // stale, and a later drag that lands back on that exact value — most
                // visibly scrollTop 0 at the very top — would be wrongly dropped as our
                // own echo, leaving the engine a few rows short of row 0. The real echo of
                // a programmatic write is still caught above, because it fires before any
                // user move reaches this line.
                this._lastProgrammaticScrollTop = null;
                // Record that the user is actively driving the strip (native-scrollbar
                // drag, track click, or custom-thumb drag — all land here as non-echo
                // events). syncNativeScrollbar uses this to defer engine→scrollbar writes
                // for the duration of the gesture.
                this._lastUserScrollTs = NativeScrollbar._now();
                // Keep the custom thumb visually in sync with the strip position on
                // every user scroll (wheel, drag-on-sibling, touch-driven via
                // syncNativeScrollbar). Cheap: only top/height + a data attribute.
                this._updateThumbVisuals();
                // Coalesce the expensive map+render to one run on the next frame at the
                // LATEST scrollTop (see renderFromScroll).
                this._pendingScrollTop = scrollTop;
                if (this._scrollRafId === null) {
                    this._scrollRafId = NativeScrollbar._raf(renderFromScroll);
                }
            };
            // Remove any previous listener (we recreate the scrollbar on resize)
            if (this._scrollListener && this._scrollbarContainer) {
                try {
                    this._scrollbarContainer.removeEventListener('scroll', this._scrollListener);
                }
                catch ( /* noop */_a) { /* noop */ }
            }
            this._scrollListener = scrollListener;
            scrollbarContainer.addEventListener('scroll', scrollListener);
            // A brand-new element starts at scrollTop 0. Seed the programmatic marker
            // at 0 so a stray initial scroll event (the transient-0 read) is treated as
            // our own and ignored, while any real user drag — which moves scrollTop off
            // 0 — is still processed. This also drops any marker tied to the element we
            // just replaced.
            this._syncingScrollbar = false;
            this._lastProgrammaticScrollTop = 0;
            this._scrollbarContainer = scrollbarContainer;
            // Custom overlay thumb is touch-only. Desktop keeps the platform-native
            // scrollbar on the strip.
            if (touch) {
                this._createThumb(container, scrollbarContainer, position);
                this._updateThumbVisuals();
            }
            return scrollbarContainer;
        }
        /**
         * Synchronize native scrollbar position with virtual scroll position
         *
         * @param scrollbarContainer Strip to write. Defaults to the attached strip.
         */
        syncNativeScrollbar(scrollbarContainer) {
            const container = scrollbarContainer || this._scrollbarContainer;
            if (!container || this._syncingScrollbar)
                return;
            // Defer to a user who is actively driving the scrollbar. While they drag,
            // THEY own the scroll position — the drag moves scrollTop and the scroll
            // listener maps it to the engine. An engine→scrollbar sync here (e.g. a live
            // feed appending rows mid-drag, which re-anchors via jumpToElement) would
            // write scrollTop out from under the drag: it yanks the thumb, and re-arms
            // the programmatic-echo marker so the drag's own moves get swallowed as
            // echoes — the "thumb freezes / bounces while a row is appended" bug.
            //
            // Two signals, because the drag target differs by platform: the touch
            // custom-thumb sets `_thumbDrag`; the desktop native OS scrollbar sets none,
            // so we fall back to "a genuine strip scroll happened within the last frame
            // or two" (USER_SCROLL_DEFER_MS). Either way the next scroll event (or the
            // gesture's end) re-syncs from the final position.
            if (this._thumbDrag ||
                NativeScrollbar._now() - this._lastUserScrollTs < NativeScrollbar.USER_SCROLL_DEFER_MS) {
                return;
            }
            // Re-decide whether there is anything to scroll, now that rows have been measured.
            //
            // The strip is built before the first render, when no tail height is known and the true-bottom
            // camera is therefore unknowable — so attach has to assume the list scrolls. This is the first
            // moment the answer is real, and it is the hook the engine already calls whenever geometry
            // settles (resize, a dataset change, a row changing height), so a list that has just become
            // short enough to fit loses its bar here and one that has outgrown the viewport gains it.
            this.refreshSurface(container);
            const percentage = this.getScrollPercentage();
            if (!Number.isFinite(percentage))
                return;
            const maxScroll = container.scrollHeight - container.clientHeight;
            if (maxScroll <= 0)
                return;
            const targetScrollTop = (percentage / NativeScrollbar.PERCENTAGE_MAX) * maxScroll;
            if (Math.abs(container.scrollTop - targetScrollTop) > 1) {
                this._syncingScrollbar = true;
                container.scrollTop = targetScrollTop;
                // Record the value we actually wrote (read back, since the browser may
                // clamp/round our target) so the scroll listener recognises — and
                // ignores — the asynchronous echo this assignment triggers.
                this._lastProgrammaticScrollTop = container.scrollTop;
                this._syncingScrollbar = false;
            }
            // Reflect the new logical position on the custom thumb (touch-only;
            // no-op on desktop because _thumbElement is null). On touch this path
            // is what fires during touch-driven content scroll, where the OS will
            // never paint a thumb for the sibling strip.
            this._updateThumbVisuals();
        }
        /**
         * Reserve a gutter only while the strip is actually showing a bar, and give it back when it is
         * not.
         *
         * Asking the mounted strip how much room its bar takes (`offsetWidth - clientWidth`) answers
         * every case at once, and answers it by measurement rather than by inference: a touch device
         * and a platform with OVERLAY scrollbars both report zero because their bars float over content
         * and reserve nothing, and so does a list short enough to have no scroll range at all. Only a
         * classic, space-taking bar reports a width, and only then does content need moving aside.
         *
         * @param strip The mounted strip element.
         * @param fallbackWidth Configured width, used when the strip reports none.
         */
        /**
         * Re-decide whether the dataset overflows, and resize the strip (and its gutter) to match.
         *
         * Safe and cheap to call after every render: the true-bottom camera is cached against the
         * viewport height and measurement version, and neither the surface height nor the padding is
         * written unless the answer actually changed.
         */
        refreshScrollRange() {
            if (this._scrollbarContainer)
                this.refreshSurface(this._scrollbarContainer);
        }
        /**
         * Re-measure the strip's scrollable surface and bring the reserved gutter with it.
         *
         * @param strip The mounted strip element.
         */
        refreshSurface(strip) {
            const surface = strip.querySelector('[data-cerious-scrollbar="content"]');
            if (!surface)
                return;
            const height = `${this.computeSurfaceHeight(strip)}px`;
            if (surface.style.height !== height)
                surface.style.height = height;
            const canScroll = this.canScroll();
            // Say it outright rather than leaving it to `auto`. A surface exactly as tall as the strip has
            // nothing to scroll, yet the platform still reserves a bar for it — measured at 10px of a
            // strip 11px wide. `hidden` is the only thing that reliably takes it away.
            const overflowY = canScroll ? 'auto' : 'hidden';
            if (strip.style.overflowY !== overflowY)
                strip.style.overflowY = overflowY;
            // And take the strip itself out of sight. Losing the bar is not enough: the strip is still a
            // mounted element the host may have styled — a themed `borderLeft` is the obvious case — so it
            // goes on drawing a hairline down the full height of a list that cannot scroll. `visibility`
            // rather than `display` so it keeps reporting the widths syncGutter measures.
            const visibility = canScroll ? '' : 'hidden';
            if (strip.style.visibility !== visibility)
                strip.style.visibility = visibility;
            this.syncGutter(strip);
        }
        syncGutter(strip, fallbackWidth) {
            const host = strip.parentElement;
            if (!host)
                return;
            // offsetWidth = content + padding + border + scrollbar, so the borders have to come off or a
            // strip with a 1px `borderLeft` looks like it is reserving a bar when it is not.
            const style = getComputedStyle(strip);
            const borders = (parseFloat(style.borderLeftWidth) || 0) + (parseFloat(style.borderRightWidth) || 0);
            const barWidth = strip.offsetWidth - strip.clientWidth - borders;
            if (barWidth > 0) {
                NativeScrollbar.reserveGutter(host, this._gutterSide, strip.offsetWidth || fallbackWidth || NativeScrollbar.DEFAULT_SCROLLBAR_WIDTH);
            }
            else {
                NativeScrollbar.releaseGutter(host);
            }
        }
        /**
         * Resize the virtual track after the dataset length changes.
         *
         * @param totalElements New dataset length.
         * @param scrollbarContainer Optional strip; defaults to the attached one.
         */
        updateNativeScrollbarHeight(totalElements, scrollbarContainer) {
            this.totalElements = totalElements;
            const container = scrollbarContainer || this._scrollbarContainer;
            if (!container)
                return;
            this.refreshSurface(container);
        }
        /**
         * Remove the strip, thumb, and listeners.
         * @param container Optional host used to find an orphan strip.
         */
        detachScrollbar(container) {
            if (this._scrollbarContainer) {
                const parentContainer = this._scrollbarContainer.parentElement;
                if (this._scrollListener) {
                    try {
                        this._scrollbarContainer.removeEventListener('scroll', this._scrollListener);
                    }
                    catch ( /* noop */_a) { /* noop */ }
                    this._scrollListener = null;
                }
                // Cancel any coalesced scroll→render frame so it can't fire after teardown.
                if (this._scrollRafId !== null) {
                    NativeScrollbar._caf(this._scrollRafId);
                    this._scrollRafId = null;
                }
                // Tear down the custom thumb: pointer listeners (window-scoped during
                // an active drag), fade timer, and the element itself.
                this._teardownThumb();
                this._scrollbarContainer.remove();
                this._scrollbarContainer = null;
                // Give back exactly what was reserved — no more, and nothing at all if the
                // host's own padding already covered the strip and we never widened it.
                NativeScrollbar.releaseGutter(parentContainer);
            }
            else if (container) {
                // If no tracked scrollbar, try to find and remove any existing scrollbar
                const existingScrollbar = container.querySelector('[data-cerious-scrollbar="container"]');
                if (existingScrollbar) {
                    existingScrollbar.remove();
                    NativeScrollbar.releaseGutter(container);
                }
                const orphanThumb = container.querySelector('[data-cerious-scrollbar="thumb"]');
                if (orphanThumb)
                    orphanThumb.remove();
            }
        }
        /**
         * Create the custom thumb overlay on the host container.
         *
         * The thumb lives alongside the scrollbar strip (not inside it) so it is
         * not displaced by the strip's own `scrollTop`. We size and position it in
         * pixel space against the container's client rect.
         */
        _createThumb(container, scrollbarContainer, position) {
            const thumb = document.createElement('div');
            thumb.setAttribute('data-cerious-scrollbar', 'thumb');
            // Honour left/right placement of the strip so the thumb tracks it.
            if (position === 'left') {
                thumb.style.left = '2px';
                thumb.style.right = 'auto';
            }
            container.appendChild(thumb);
            this._thumbElement = thumb;
            // Drag handling. We translate vertical pointer movement to a delta on the
            // sibling strip's `scrollTop`, which fires the existing scroll listener
            // and routes through the same true-bottom mapping the wheel/keyboard
            // paths use. This keeps scroll math in one place.
            const onPointerDown = (e) => {
                if (e.button !== undefined && e.button !== 0)
                    return;
                const sb = this._scrollbarContainer;
                if (!sb)
                    return;
                const clientH = sb.clientHeight;
                const thumbH = thumb.getBoundingClientRect().height;
                const trackPx = Math.max(1, clientH - thumbH);
                this._thumbDrag = {
                    pointerId: e.pointerId,
                    startClientY: e.clientY,
                    startScrollTop: sb.scrollTop,
                    trackPx,
                };
                thumb.setAttribute('data-active', 'true');
                thumb.setAttribute('data-visible', 'true');
                try {
                    thumb.setPointerCapture(e.pointerId);
                }
                catch ( /* noop */_a) { /* noop */ }
                // Suppress fade-out while actively dragging.
                if (this._thumbFadeTimer != null) {
                    window.clearTimeout(this._thumbFadeTimer);
                    this._thumbFadeTimer = null;
                }
                e.preventDefault();
                e.stopPropagation();
            };
            const onPointerMove = (e) => {
                const drag = this._thumbDrag;
                if (!drag || e.pointerId !== drag.pointerId)
                    return;
                const sb = this._scrollbarContainer;
                if (!sb)
                    return;
                const maxScroll = sb.scrollHeight - sb.clientHeight;
                if (maxScroll <= 0)
                    return;
                const deltaPx = e.clientY - drag.startClientY;
                // Convert pixel travel of the thumb on its track into scrollTop. The
                // scroll listener handles the percentage → virtual position mapping.
                const scrollDelta = (deltaPx / drag.trackPx) * maxScroll;
                let next = drag.startScrollTop + scrollDelta;
                if (next < 0)
                    next = 0;
                if (next > maxScroll)
                    next = maxScroll;
                sb.scrollTop = next;
                e.preventDefault();
            };
            const onPointerUp = (e) => {
                const drag = this._thumbDrag;
                if (!drag || e.pointerId !== drag.pointerId)
                    return;
                this._thumbDrag = null;
                thumb.removeAttribute('data-active');
                try {
                    thumb.releasePointerCapture(e.pointerId);
                }
                catch ( /* noop */_a) { /* noop */ }
                // Resume the normal fade-out sequence.
                this._scheduleThumbFade();
            };
            this._thumbPointerDown = onPointerDown;
            this._thumbPointerMove = onPointerMove;
            this._thumbPointerUp = onPointerUp;
            thumb.addEventListener('pointerdown', onPointerDown);
            // Listen on the thumb (pointer is captured) for move/up; covers both
            // mouse and touch via the unified Pointer Events API.
            thumb.addEventListener('pointermove', onPointerMove);
            thumb.addEventListener('pointerup', onPointerUp);
            thumb.addEventListener('pointercancel', onPointerUp);
            // Full-strip touch zone: a transparent column overlay along the right
            // edge (or left, mirroring `position`) so the entire scrollbar lane is a
            // tap/drag target. Tapping outside the thumb jumps it to the touch point
            // (page-jump) and immediately begins a drag from there; tapping on the
            // thumb behaves like a direct grab.
            const hit = document.createElement('div');
            hit.setAttribute('data-cerious-scrollbar', 'hit');
            hit.style.cssText = `
      position: absolute;
      top: 0;
      bottom: 0;
      ${position}: 0;
      width: 24px;
      background: transparent;
      z-index: ${NativeScrollbar.DEFAULT_Z_INDEX};
      touch-action: none;
      pointer-events: none;
    `;
            const onHitPointerDown = (e) => {
                if (e.button !== undefined && e.button !== 0)
                    return;
                const sb = this._scrollbarContainer;
                if (!sb)
                    return;
                const thumbRect = thumb.getBoundingClientRect();
                // If the touch landed within the thumb's vertical band, delegate —
                // the thumb's own pointerdown will run (the thumb sits on top of the
                // hit zone via z-index). For taps outside the thumb, jump the strip's
                // scrollTop so the thumb centers on the touch Y, then start a drag.
                if (e.clientY >= thumbRect.top && e.clientY <= thumbRect.bottom)
                    return;
                const sbRect = sb.getBoundingClientRect();
                const clientH = sb.clientHeight;
                const thumbH = thumbRect.height;
                const trackPx = Math.max(1, clientH - thumbH);
                // Desired thumb-top so the thumb centers on the touch point, clamped.
                let desiredTop = (e.clientY - sbRect.top) - thumbH / 2;
                if (desiredTop < 0)
                    desiredTop = 0;
                if (desiredTop > trackPx)
                    desiredTop = trackPx;
                const maxScroll = sb.scrollHeight - sb.clientHeight;
                const newScrollTop = (desiredTop / trackPx) * maxScroll;
                sb.scrollTop = newScrollTop;
                // Begin a drag anchored at the new position so subsequent move events
                // pan smoothly from the jumped-to location.
                this._thumbDrag = {
                    pointerId: e.pointerId,
                    startClientY: e.clientY,
                    startScrollTop: newScrollTop,
                    trackPx,
                };
                thumb.setAttribute('data-active', 'true');
                thumb.setAttribute('data-visible', 'true');
                try {
                    hit.setPointerCapture(e.pointerId);
                }
                catch ( /* noop */_a) { /* noop */ }
                if (this._thumbFadeTimer != null) {
                    window.clearTimeout(this._thumbFadeTimer);
                    this._thumbFadeTimer = null;
                }
                e.preventDefault();
                e.stopPropagation();
            };
            hit.addEventListener('pointerdown', onHitPointerDown);
            // Re-use the thumb's move/up handlers so the same drag state machine
            // services both entry points.
            hit.addEventListener('pointermove', onPointerMove);
            hit.addEventListener('pointerup', onPointerUp);
            hit.addEventListener('pointercancel', onPointerUp);
            container.appendChild(hit);
            this._thumbHitZone = hit;
            this._thumbHitZoneDown = onHitPointerDown;
        }
        /**
         * Recompute the thumb's `top`/`height` from the strip's current scrollTop
         * and mark it visible. Cheap; called from the user-scroll listener and from
         * `syncNativeScrollbar` (the latter is what fires during touch-driven
         * content scroll on iOS).
         */
        _updateThumbVisuals() {
            const thumb = this._thumbElement;
            const sb = this._scrollbarContainer;
            if (!thumb || !sb)
                return;
            const clientH = sb.clientHeight;
            const scrollH = sb.scrollHeight;
            if (clientH <= 0 || scrollH <= 0)
                return;
            // Thumb height reflects how much of the runway is currently in view.
            // Clamp to a usable grab target.
            const rawHeight = clientH * (clientH / scrollH);
            const thumbHeight = Math.max(NativeScrollbar.THUMB_MIN_HEIGHT_PX, Math.min(clientH, rawHeight));
            const maxScroll = scrollH - clientH;
            const pct = maxScroll > 0 ? sb.scrollTop / maxScroll : 0;
            const top = (clientH - thumbHeight) * pct;
            thumb.style.height = `${thumbHeight}px`;
            thumb.style.top = `${top}px`;
            thumb.setAttribute('data-visible', 'true');
            // Activate the full-strip touch hit zone only while the thumb is
            // visible. Before the first scroll (or after fade-out) the strip is
            // inert so it never intercepts taps on underlying content.
            if (this._thumbHitZone)
                this._thumbHitZone.style.pointerEvents = 'auto';
            this._scheduleThumbFade();
        }
        _scheduleThumbFade() {
            if (typeof window === 'undefined')
                return;
            // Don't fade while a drag is in flight; pointerup will reschedule.
            if (this._thumbDrag)
                return;
            if (this._thumbFadeTimer != null) {
                window.clearTimeout(this._thumbFadeTimer);
            }
            this._thumbFadeTimer = window.setTimeout(() => {
                this._thumbFadeTimer = null;
                if (this._thumbDrag)
                    return;
                const t = this._thumbElement;
                if (t)
                    t.removeAttribute('data-visible');
                // Deactivate the strip hit zone alongside the fade so the column
                // returns to inert after a brief grace window.
                if (this._thumbHitZone)
                    this._thumbHitZone.style.pointerEvents = 'none';
            }, NativeScrollbar.THUMB_FADE_DELAY_MS);
        }
        _teardownThumb() {
            if (this._thumbFadeTimer != null && typeof window !== 'undefined') {
                window.clearTimeout(this._thumbFadeTimer);
                this._thumbFadeTimer = null;
            }
            const thumb = this._thumbElement;
            if (thumb) {
                if (this._thumbPointerDown)
                    thumb.removeEventListener('pointerdown', this._thumbPointerDown);
                if (this._thumbPointerMove)
                    thumb.removeEventListener('pointermove', this._thumbPointerMove);
                if (this._thumbPointerUp) {
                    thumb.removeEventListener('pointerup', this._thumbPointerUp);
                    thumb.removeEventListener('pointercancel', this._thumbPointerUp);
                }
                thumb.remove();
            }
            const hit = this._thumbHitZone;
            const hitDown = this._thumbHitZoneDown;
            const moveHandler = this._thumbPointerMove;
            const upHandler = this._thumbPointerUp;
            this._thumbElement = null;
            this._thumbDrag = null;
            this._thumbPointerDown = null;
            this._thumbPointerMove = null;
            this._thumbPointerUp = null;
            if (hit) {
                if (hitDown)
                    hit.removeEventListener('pointerdown', hitDown);
                if (moveHandler)
                    hit.removeEventListener('pointermove', moveHandler);
                if (upHandler) {
                    hit.removeEventListener('pointerup', upHandler);
                    hit.removeEventListener('pointercancel', upHandler);
                }
                hit.remove();
            }
            this._thumbHitZone = null;
            this._thumbHitZoneDown = null;
        }
        /**
         * Widen the host's padding so the strip does not overlap content, and record
         * the amount added.
         *
         * Reserves the strip's rendered width exactly. The previous implementation
         * reserved `width + 2` and removed a hard-coded 19 on detach, which was wrong
         * in three ways: the gutter was 2px wider than the strip (leaving a dead
         * sliver that a content-aware layout has to work around), detach removed more
         * than attach ever added whenever the strip was not 17px, and a host with its
         * own padding kept none of it after a detach.
         *
         * @param container Host element.
         * @param side Which edge the strip is pinned to.
         * @param renderedWidth Strip width in pixels, as measured after mounting.
         */
        static reserveGutter(container, side, renderedWidth) {
            if (!(renderedWidth > 0))
                return;
            // Publish the width for anything laying out INSIDE the host. Padding cannot reach an
            // absolutely positioned viewport (its containing block is the padding box), so the rows read
            // this instead — see AbsolutePlacement. Set before the early return below, because a host that
            // already reserves its own padding still has rows that need to know.
            container.style.setProperty(NativeScrollbar.GUTTER_VAR, `${renderedWidth}px`);
            const computed = getComputedStyle(container);
            const current = (side === 'left'
                ? parseFloat(computed.paddingLeft)
                : parseFloat(computed.paddingRight)) || 0;
            // A host that already reserves enough keeps its own value, and we record
            // nothing — so detach leaves that padding alone.
            const added = renderedWidth - current;
            if (added <= 0)
                return;
            if (side === 'left')
                container.style.paddingLeft = `${current + added}px`;
            else
                container.style.paddingRight = `${current + added}px`;
            const prop = side === 'left' ? 'paddingLeft' : 'paddingRight';
            container.setAttribute(NativeScrollbar.RESERVED_ATTR, `${prop}:${added}`);
        }
        /**
         * Undo {@link reserveGutter}, restoring the host's original padding.
         *
         * @param container Host element, or null.
         */
        static releaseGutter(container) {
            if (!container)
                return;
            container.style.removeProperty(NativeScrollbar.GUTTER_VAR);
            const record = container.getAttribute(NativeScrollbar.RESERVED_ATTR);
            if (!record)
                return;
            container.removeAttribute(NativeScrollbar.RESERVED_ATTR);
            const sep = record.indexOf(':');
            if (sep < 0)
                return;
            const prop = record.slice(0, sep);
            const added = parseFloat(record.slice(sep + 1));
            if (!Number.isFinite(added) || added <= 0)
                return;
            const computed = getComputedStyle(container);
            if (prop === 'paddingLeft') {
                const current = parseFloat(computed.paddingLeft) || 0;
                container.style.paddingLeft = `${Math.max(0, current - added)}px`;
            }
            else {
                const current = parseFloat(computed.paddingRight) || 0;
                container.style.paddingRight = `${Math.max(0, current - added)}px`;
            }
        }
    }
    NativeScrollbar.DEFAULT_SCROLLBAR_WIDTH = 17;
    /**
     * Marks a host whose padding WE widened, and by how much, as
     * `paddingLeft:8` / `paddingRight:15`.
     *
     * Recorded on the element rather than on the instance so that detach can undo
     * the exact amount even when it runs from a different instance than the one
     * that attached — the orphan-strip cleanup path does exactly that.
     */
    NativeScrollbar.RESERVED_ATTR = 'data-cerious-scrollbar-reserved';
    NativeScrollbar.DEFAULT_Z_INDEX = 10;
    NativeScrollbar.ELEMENT_HEIGHT_MULTIPLIER = 10;
    // Browsers clamp element height (Chrome ~33.5M px). Stay well under it: past
    // the cap the strip silently stops growing and the mapping compresses again.
    /**
     * Ceiling on the strip's scroll range.
     *
     * Browsers silently clamp an element past their own maximum — measured at
     * 16,777,214px (2^24 − 2) in Chrome — so asking for more does not buy
     * resolution, it just means the number the engine reasons about and the
     * number the browser honours stop matching. Kept under the lowest ceiling in
     * circulation (Firefox's ~17.9M).
     */
    NativeScrollbar.MAX_STRIP_HEIGHT_PX = 15000000;
    // Tolerance (px) for recognising the async echo of a programmatic scrollTop
    // write. The browser may clamp/round our written value, so the echo's
    // scrollTop can differ from the target by a sub-pixel; a small window
    // absorbs that without misclassifying a genuine user drag.
    NativeScrollbar.PROGRAMMATIC_SCROLL_TOLERANCE_PX = 2;
    NativeScrollbar.PERCENTAGE_MAX = 100;
    // Window (ms) after a genuine user scroll on the strip during which an
    // engine→scrollbar sync defers to the user. On desktop the user drags the
    // REAL native OS scrollbar (no custom thumb / `_thumbDrag` on non-touch), so
    // the only signal that they are mid-drag is the stream of non-echo scroll
    // events the drag produces. Native drag events fire ~per frame, so a window
    // comfortably wider than a frame bridges the gaps for the whole gesture and
    // then lapses on release. See `syncNativeScrollbar`.
    NativeScrollbar.USER_SCROLL_DEFER_MS = 150;
    // Custom thumb tuning. Sibling-driver strip is fixed width; the thumb
    // floats over the right edge of the host container and is visually
    // independent of that strip width.
    NativeScrollbar.THUMB_MIN_HEIGHT_PX = 24;
    NativeScrollbar.THUMB_FADE_DELAY_MS = 800;
    // One stylesheet for all CeriousScroll instances. Injected lazily on the
    // first scrollbar creation so SSR / non-DOM environments stay clean.
    NativeScrollbar._stylesInjected = false;
    /** Custom property carrying the strip's width to anything laid out inside the host. */
    NativeScrollbar.GUTTER_VAR = '--cerious-gutter';

    /**
     * Copyright (c) 2024-2026 Cerious DevTech LLC. All rights reserved.
     *
     * How a row reaches its y-coordinate. ViewportRenderer owns measure/pool;
     * this owns the DOM writes. The per-frame shift is local (overscan +
     * partial-row offset), never a sum from row 0 — so neither strategy hits
     * the browser max-element-height ceiling.
     *
     * - {@link AbsolutePlacement}: out-of-flow `top`. No compositor layer.
     * - {@link TableFlowPlacement}: real `<tr>`/`<td>` in one table; one
     *   `translateY` on `<tbody>` for column sync. Opt-in GPU layer.
     */
    class AbsolutePlacement {
        constructor() {
            this._style = {
                position: 'absolute',
                left: '0px',
                // Stop short of the scrollbar strip when one is showing.
                //
                // A row's containing block is the viewport's PADDING box, so the gutter the strip reserves as
                // padding on the host is invisible to it and rows ran the full width underneath the bar —
                // their bottom borders crossing it. NativeScrollbar publishes the width it is occupying as
                // `--cerious-gutter`, which inherits down to here; with no strip the fallback is zero and
                // nothing changes.
                //
                // Applied as LOGICAL insets, because the strip is not always on the right: an RTL host puts it
                // on the left, where a physical `right` would reserve the gutter on the side that has no bar
                // and run the rows under the side that does — the original bug, mirrored.
                right: 'var(--cerious-gutter, 0px)',
                visible: 'visible',
                width: '100%'
            };
            this._topBuffer = '';
        }
        prepare(container) {
            if (container.style.visibility === 'hidden') {
                container.style.visibility = this._style.visible;
                container.style.position = this._style.position;
                container.style.left = this._style.left;
                container.style.top = this._style.left; // 0px
                container.style.width = this._style.width;
            }
        }
        clear(container) {
            container.innerHTML = '';
        }
        createRow() {
            const el = document.createElement('div');
            this.applyInsets(el);
            return el;
        }
        initRow(el) {
            this.applyInsets(el);
        }
        /** Edge-to-edge, less the scrollbar gutter, whichever side the strip is on. */
        applyInsets(el) {
            el.style.position = this._style.position;
            el.style.insetInlineStart = this._style.left;
            el.style.insetInlineEnd = this._style.right;
        }
        attach(container, el, _index, _region) {
            container.appendChild(el);
        }
        position(el, top, _region) {
            // createRow/initRow already set position:absolute. Rewriting it every
            // frame for every visible row was wasted style invalidation. Only write
            // `top` when the pixel value actually changed (reflow-without-scroll).
            this._topBuffer = top + 'px';
            if (el.style.top !== this._topBuffer) {
                el.style.top = this._topBuffer;
            }
        }
        detach(container, el) {
            if (el.parentNode === container) {
                container.removeChild(el);
            }
        }
        commit(_container, _firstRowTop) { }
    }
    /** Real `<tr>` in one table; `translateY` on tbody. DOM order and offscreen tail measure live here. */
    class TableFlowPlacement {
        /**
         * @param options Table scaffold / column-sizing options.
         */
        constructor(options = {}) {
            this.options = options;
            this.container = null;
            this.table = null;
            this.measureTable = null;
            this.thead = null;
            this.tbodyMain = null;
            this.tbodyMeasure = null;
            // autoSizeColumns: pinned after the first window is measured; reset on clear()
            // of the dataset so a data reset re-measures.
            this._columnsSized = false;
            // Reused buffers to avoid per-frame allocations.
            this._transformBuffer = '';
            this._sortBuffer = [];
            this._colWidthBuffer = [];
        }
        prepare(container) {
            if (this.table && this.container === container)
                return; // scaffold already built
            this.container = container;
            // Clip rows translated outside the viewport, and establish a positioning
            // context for the offscreen measure table. Don't clobber an overflow the
            // host already manages (e.g. a content element with `overflow-y: clip` and
            // `overflow-x: auto` for horizontal scrolling).
            const s = container.style;
            if (!s.overflow && !s.overflowY && !s.overflowX)
                s.overflow = 'hidden';
            if (typeof getComputedStyle === 'function' &&
                getComputedStyle(container).position === 'static') {
                container.style.position = 'relative';
            }
            // Single shared table: <thead> + body <tbody>. One formatting context => the
            // browser auto-aligns header and body columns, like any normal table.
            const table = document.createElement('table');
            table.style.width = '100%';
            // Note: table-layout / border-collapse are left to CSS. Prefer
            // `border-collapse: separate` in table mode — collapsed borders are painted
            // by the (untransformed) table, so they would NOT move with the tbody
            // transform during scroll. `table-layout: fixed` also avoids a horizontal
            // scrollbar from content-sized columns.
            if (this.options.tableClassName)
                table.className = this.options.tableClassName;
            // Fixed column widths shared with an (optional) external header table.
            const bodyColgroup = this.buildColgroup();
            if (bodyColgroup)
                table.appendChild(bodyColgroup);
            // Only build an in-table header when a populator is given. Omitting it keeps
            // the body free of a top inset (see class doc) so the scroll math matches the
            // default placement exactly — the recommended setup for a frozen header.
            let thead = null;
            if (this.options.header) {
                thead = document.createElement('thead');
                if (this.options.theadClassName)
                    thead.className = this.options.theadClassName;
                // Keep the header painting above body rows that translate up under it.
                thead.style.position = 'relative';
                thead.style.zIndex = '1';
                this.options.header(thead);
                table.appendChild(thead);
            }
            const tbodyMain = document.createElement('tbody');
            if (this.options.tbodyClassName)
                tbodyMain.className = this.options.tbodyClassName;
            // Hint the compositor: the body is the one element we transform each frame.
            tbodyMain.style.willChange = 'transform';
            table.appendChild(tbodyMain);
            container.appendChild(table);
            // Offscreen, non-interactive table whose only job is to hold tail rows long
            // enough to measure their heights for true-bottom math. It carries the SAME
            // class as the visible table so column layout (and therefore measured row
            // heights) match, and so it can't widen the scroll region differently than
            // the real one.
            const measureTable = document.createElement('table');
            measureTable.setAttribute('aria-hidden', 'true');
            if (this.options.tableClassName)
                measureTable.className = this.options.tableClassName;
            measureTable.style.cssText =
                'position:absolute;top:0;left:0;width:100%;' +
                    'visibility:hidden;pointer-events:none;';
            const measureColgroup = this.buildColgroup();
            if (measureColgroup)
                measureTable.appendChild(measureColgroup);
            const tbodyMeasure = document.createElement('tbody');
            measureTable.appendChild(tbodyMeasure);
            container.appendChild(measureTable);
            this.table = table;
            this.measureTable = measureTable;
            this.thead = thead;
            this.tbodyMain = tbodyMain;
            this.tbodyMeasure = tbodyMeasure;
        }
        /** Build a `<colgroup>` from `columnWidths`, or null if none configured. */
        buildColgroup() {
            const widths = this.options.columnWidths;
            if (!widths || widths.length === 0)
                return null;
            const colgroup = document.createElement('colgroup');
            for (const w of widths) {
                const col = document.createElement('col');
                if (w && w !== 'auto')
                    col.style.width = w;
                colgroup.appendChild(col);
            }
            return colgroup;
        }
        clear(_container) {
            if (this.tbodyMain)
                this.tbodyMain.textContent = '';
            if (this.tbodyMeasure)
                this.tbodyMeasure.textContent = '';
            this._cachedTopInset = undefined;
        }
        createRow() {
            return document.createElement('tr');
        }
        initRow(_el) { }
        attach(_container, el, _index, region) {
            // Attach immediately so the row is in a <table> and measurable right after
            // renderElement. Final ordering of the window is fixed in commit().
            const tbody = region === 'bottom' ? this.tbodyMeasure : this.tbodyMain;
            tbody.appendChild(el);
        }
        position(el, _top, region) {
            // Vertical placement is handled once per frame by the tbody transform in
            // commit(); there is no per-row `top`. The only work here is relocating a
            // reused row whose region changed since the last frame (e.g. a tail row that
            // scrolled into the window, or vice versa).
            const tbody = region === 'bottom' ? this.tbodyMeasure : this.tbodyMain;
            if (el.parentNode !== tbody)
                tbody.appendChild(el);
        }
        detach(_container, el) {
            if (el.parentNode)
                el.parentNode.removeChild(el);
        }
        commit(_container, firstRowTop) {
            const tbody = this.tbodyMain;
            if (!tbody)
                return;
            this.reorder(tbody);
            this.maybeAutoSizeColumns();
            this._transformBuffer = 'translateY(' + firstRowTop + 'px)';
            tbody.style.transform = this._transformBuffer;
        }
        /**
         * If `autoSizeColumns` is on and not yet applied, measure each column's natural
         * content width from the first rendered window (header + body cells) and pin it
         * via a `<colgroup>` + `table-layout: fixed`. Runs once: thereafter columns are
         * stable. Skipped when explicit `columnWidths` were given.
         */
        maybeAutoSizeColumns() {
            var _a;
            if (!this.options.autoSizeColumns || this._columnsSized)
                return;
            if (this.options.columnWidths && this.options.columnWidths.length)
                return;
            const tbody = this.tbodyMain;
            const table = this.table;
            if (!tbody || !table || tbody.children.length === 0)
                return;
            // Query <td>/<th> rather than direct children: framework wrappers may nest
            // cells inside a `display: contents` element, so the cells are descendants of
            // the <tr>, not its immediate children.
            const colCount = tbody.children[0].querySelectorAll('td').length;
            if (colCount === 0)
                return;
            // Measure max natural cell width per column. The table is still auto-layout
            // here, so each cell's offsetWidth is its content-driven width.
            const widths = this._colWidthBuffer;
            widths.length = 0;
            for (let i = 0; i < colCount; i++)
                widths.push(0);
            const measureCells = (cells) => {
                for (let i = 0; i < colCount && i < cells.length; i++) {
                    const w = cells[i].offsetWidth;
                    if (w > widths[i])
                        widths[i] = w;
                }
            };
            const headRow = (_a = this.thead) === null || _a === void 0 ? void 0 : _a.querySelector('tr');
            if (headRow)
                measureCells(headRow.querySelectorAll('th'));
            for (let r = 0; r < tbody.children.length; r++) {
                measureCells(tbody.children[r].querySelectorAll('td'));
            }
            // Pin the widths and switch to fixed layout (stable from now on). Apply to
            // the offscreen measure table too so tail row heights stay consistent.
            this.applyMeasuredColgroup(table, widths);
            if (this.measureTable)
                this.applyMeasuredColgroup(this.measureTable, widths);
            table.style.tableLayout = 'fixed';
            if (this.measureTable)
                this.measureTable.style.tableLayout = 'fixed';
            this._columnsSized = true;
        }
        /** Replace (or insert) a `<colgroup>` of fixed px widths at the top of a table. */
        applyMeasuredColgroup(table, widths) {
            const existing = table.querySelector('colgroup');
            if (existing)
                existing.remove();
            const colgroup = document.createElement('colgroup');
            for (const w of widths) {
                const col = document.createElement('col');
                col.style.width = w + 'px';
                colgroup.appendChild(col);
            }
            table.insertBefore(colgroup, table.firstChild);
        }
        getTopInset() {
            // Use the sub-pixel-accurate rendered height, not offsetHeight (which rounds
            // to an integer). On fractional-scale displays (Retina) a rounded inset
            // throws off the body-area height by up to ~1px, which accumulates into the
            // true-bottom anchor and clips the last row. getBoundingClientRect is exact.
            // Cache the result: scroll() and renderViewport() used to force a layout on
            // every wheel/touch event. Don't cache 0 — an async header may still mount.
            if (this._cachedTopInset !== undefined)
                return this._cachedTopInset;
            if (!this.thead)
                return 0;
            const h = this.thead.getBoundingClientRect().height;
            const inset = h > 0 ? h : this.thead.offsetHeight;
            if (inset > 0)
                this._cachedTopInset = inset;
            return inset;
        }
        invalidateTopInset() {
            this._cachedTopInset = undefined;
        }
        /**
         * DOM order drifts after recycle; normalize by `data-element-index`.
         */
        reorder(tbody) {
            const children = tbody.children;
            const n = children.length;
            if (n < 2)
                return;
            const arr = this._sortBuffer;
            arr.length = 0;
            for (let i = 0; i < n; i++)
                arr.push(children[i]);
            arr.sort((a, b) => { var _a, _b; return (+((_a = a.dataset.elementIndex) !== null && _a !== void 0 ? _a : 0)) - (+((_b = b.dataset.elementIndex) !== null && _b !== void 0 ? _b : 0)); });
            let ordered = true;
            for (let i = 0; i < n; i++) {
                if (children[i] !== arr[i]) {
                    ordered = false;
                    break;
                }
            }
            if (ordered)
                return;
            for (let i = 0; i < arr.length; i++)
                tbody.appendChild(arr[i]);
        }
    }

    /**
     * Copyright (c) 2024-2026 Cerious DevTech LLC. All rights reserved.
     *
     * Mounts the visible window, measures rows, pools nodes. Positioning is
     * delegated to RowPlacement. Heights come from the DOM (or the uniform hint).
     */
    class ViewportRenderer {
        /** Debug harness only. */
        get renderedElementCount() {
            return this.currentlyRendered.size;
        }
        /** Debug harness only. */
        get lastRenderedRange() {
            return { startElement: this.lastStartElement, endElement: this.lastEndElement };
        }
        /**
         * @param totalElements Dataset length.
         * @param getCurrentElement Camera row index.
         * @param getScrollOffset Pixels into the camera row.
         * @param getCalculateScrollPercentage Current `0`–`100` position.
         * @param setMeasuredHeight Write a measured row height.
         * @param hasMeasuredHeight Whether a real measurement exists.
         * @param getMeasuredHeight Read a cached height (undefined if missing).
         * @param getUniformHeightHint Detected uniform height, or undefined.
         * @param placement How rows are created and positioned. Default: absolute `top`.
         */
        constructor(totalElements, getCurrentElement, getScrollOffset, getCalculateScrollPercentage, setMeasuredHeight, hasMeasuredHeight, getMeasuredHeight, 
        // Uniform rows: skip the per-new-row offsetHeight (forced layout).
        getUniformHeightHint, placement = new AbsolutePlacement()) {
            this.totalElements = totalElements;
            this.getCurrentElement = getCurrentElement;
            this.getScrollOffset = getScrollOffset;
            this.getCalculateScrollPercentage = getCalculateScrollPercentage;
            this.setMeasuredHeight = setMeasuredHeight;
            this.hasMeasuredHeight = hasMeasuredHeight;
            this.getMeasuredHeight = getMeasuredHeight;
            this.getUniformHeightHint = getUniformHeightHint;
            this.placement = placement;
            this._lastRenderedElement = null;
            this.currentlyRendered = new Map();
            // Detached nodes reused on the next miss. Content is always re-rendered.
            this.recycledElements = [];
            this.createdElementsTotal = 0;
            this.reusedElementsTotal = 0;
            this.lastFrameCreated = 0;
            this.lastFrameReused = 0;
            this.lastStartElement = -1;
            this.lastEndElement = -1;
            this._shouldBeVisibleSet = new Set();
            this._toRemoveArray = [];
            this._sortedIndicesArray = [];
            // Reused every frame; the returned snapshot aliases this array.
            this._renderedRowsArray = [];
            this._bottomElementsToRenderArray = [];
            this._bufferHeightArray = [];
            this.bottomMeasurementVersion = 0;
            this.trueBottomCache = null;
            /** Adopt pre-rendered rows on the first frame instead of replacing them. */
            this.hydrate = false;
            this.hydrated = false;
        }
        /** Last row from the dataset currently in the DOM, if any. */
        get lastRenderedElement() {
            return this._lastRenderedElement;
        }
        /** Drop mounted-index tracking and the recycle pool. Call when the dataset identity changes. */
        clearRenderTracking() {
            this.currentlyRendered.clear();
            this.recycledElements.length = 0;
            this.lastFrameCreated = 0;
            this.lastFrameReused = 0;
            this.lastStartElement = -1;
            this.lastEndElement = -1;
            this._shouldBeVisibleSet.clear();
            this._toRemoveArray.length = 0;
            this._sortedIndicesArray.length = 0;
            this.invalidateTrueBottomCache();
        }
        /**
         * Indices currently mounted.
         * @returns Dataset indices in the live window.
         */
        getRenderedIndices() {
            return Array.from(this.currentlyRendered.keys());
        }
        /**
         * @param index Dataset index.
         * @returns Live row element, or `null` if not mounted.
         */
        getRenderedElement(index) {
            return this.currentlyRendered.get(index) || null;
        }
        /**
         * Re-run the host renderer on live rows and re-measure. Needed when height
         * changed in place: the normal pass skips already-rendered indices and would
         * re-read the stale offsetHeight.
         *
         * @param renderElement Same callback passed to `renderViewport`.
         */
        refreshVisible(renderElement) {
            var _a;
            if (this.currentlyRendered.size === 0)
                return;
            // Same uniform-height shortcut the first render takes. Reading offsetHeight
            // right after running the renderer is a write-then-read, so it forces a
            // synchronous layout — once PER ROW, over everything mounted. On a grid
            // panning sideways that was ~24 forced layouts per column step and the
            // dominant cost of the frame, all to re-measure rows whose height is fixed
            // and already known.
            const hint = (_a = this.getUniformHeightHint) === null || _a === void 0 ? void 0 : _a.call(this);
            for (const [index, element] of this.currentlyRendered) {
                renderElement(index, element);
                this.setMeasuredHeight(index, hint !== undefined ? hint : element.offsetHeight);
            }
            this.invalidateTrueBottomCache();
        }
        /**
         * Prefer the cache (avoids layout). On miss, read offsetHeight and write
         * it back — otherwise an in-place height change is lost until the row
         * scrolls out and back.
         */
        measureReused(index, element) {
            var _a;
            if (this.hasMeasuredHeight(index)) {
                return this.getMeasuredHeight(index);
            }
            const hint = (_a = this.getUniformHeightHint) === null || _a === void 0 ? void 0 : _a.call(this);
            if (hint !== undefined) {
                this.setMeasuredHeight(index, hint);
                return hint;
            }
            const height = element.offsetHeight;
            this.setMeasuredHeight(index, height);
            return height;
        }
        /**
         * Take ownership of rows that are already in the DOM (hydration).
         *
         * Runs once, before the first frame decides anything. Server-rendered markup
         * is otherwise discarded on that frame — the renderer has no record of those
         * elements, so it builds its own and the server's work flashes away — and the
         * recycler cannot adopt what it does not know about. Matching on
         * `data-element-index` is what makes the two halves agree on identity, which
         * is why the attribute is written for every row rather than only in debug.
         *
         * Heights are NOT taken on trust here: they are measured from the adopted
         * elements on this same frame, exactly as a freshly rendered row would be.
         */
        adoptExistingRows(container) {
            if (!this.hydrate || this.hydrated)
                return;
            this.hydrated = true;
            const existing = container.querySelectorAll('[data-element-index]');
            for (let i = 0; i < existing.length; i++) {
                const el = existing[i];
                const index = Number(el.dataset.elementIndex);
                if (!Number.isInteger(index) || index < 0 || index >= this.totalElements)
                    continue;
                if (this.currentlyRendered.has(index))
                    continue;
                this.placement.initRow(el);
                this.currentlyRendered.set(index, el);
            }
        }
        /**
         * Bind an element to a dataset index.
         *
         * Every path that puts a row on screen goes through here, which is what lets
         * anything index-derived — the debug attribute, ARIA position — be written in
         * exactly one place instead of at each of the four render paths.
         */
        bindRow(el, index) {
            var _a;
            el.dataset.elementIndex = String(index);
            (_a = this.decorateRow) === null || _a === void 0 ? void 0 : _a.call(this, el, index);
        }
        acquireRow() {
            const pooled = this.recycledElements.pop();
            if (pooled) {
                this.reusedElementsTotal++;
                this.lastFrameReused++;
                pooled.textContent = '';
                this.placement.initRow(pooled);
                return pooled;
            }
            const created = this.placement.createRow();
            this.createdElementsTotal++;
            this.lastFrameCreated++;
            return created;
        }
        /**
         * Measure a newly rendered row. Uniform hint skips offsetHeight. Cached
         * height is trusted here too (overscan last frame) — no version bump.
         */
        measureNew(index, element) {
            var _a;
            const hint = (_a = this.getUniformHeightHint) === null || _a === void 0 ? void 0 : _a.call(this);
            if (hint !== undefined) {
                this.setMeasuredHeight(index, hint);
                if (this.shouldTrackIndexForBottom(index)) {
                    this.bumpBottomMeasurementVersion();
                }
                return hint;
            }
            // Already measured (was overscan last frame). Skip offsetHeight — that
            // read-after-write layout dominates fast scrollbar-drag frames.
            if (this.hasMeasuredHeight(index)) {
                return this.getMeasuredHeight(index);
            }
            const height = element.offsetHeight;
            this.setMeasuredHeight(index, height);
            if (this.shouldTrackIndexForBottom(index)) {
                this.bumpBottomMeasurementVersion();
            }
            return height;
        }
        get lifecycleStats() {
            return {
                poolSize: this.recycledElements.length,
                createdTotal: this.createdElementsTotal,
                reusedTotal: this.reusedElementsTotal,
                lastFrameCreated: this.lastFrameCreated,
                lastFrameReused: this.lastFrameReused
            };
        }
        /**
         * Fill the window: overscan above, visible rows until height is covered,
         * overscan below. Tail rows are mounted only while their heights are unknown.
         *
         * @param windowHeight Usable viewport height in pixels.
         * @param container Host rows are attached to.
         * @param renderElement `(index, element) => void` — populate the row.
         * @returns Snapshot of the pass. `renderedElements` is reused; do not retain it.
         */
        renderViewport(windowHeight, container, renderElement) {
            var _a, _b;
            this.lastFrameCreated = 0;
            this.lastFrameReused = 0;
            const currentElement = this.getCurrentElement();
            const scrollOffset = this.getScrollOffset();
            const startElement = currentElement;
            const offset = scrollOffset;
            // Returned snapshot aliases this array — treat it as ephemeral.
            const renderedRows = this._renderedRowsArray;
            let renderedRowsCount = 0;
            let totalRenderedHeight = 0;
            this._shouldBeVisibleSet.clear();
            this.adoptExistingRows(container);
            if (Math.abs(startElement - this.lastStartElement) > 100) {
                // Pool the live window before clear(). Skipping this used to leak the
                // whole window on every far jump; clear() only detaches, so the
                // references we push stay valid and the rebuild pops them back.
                this.currentlyRendered.forEach((element) => {
                    this.recycledElements.push(element);
                });
                this.placement.clear(container);
                this.currentlyRendered.clear();
            }
            this.placement.prepare(container);
            // Overscan above — heights needed to place startElement.
            const bufferStart = Math.max(0, startElement - ViewportRenderer.OVERSCAN_BUFFER);
            let bufferAboveHeight = 0;
            const bufferHeights = this._bufferHeightArray;
            bufferHeights.length = 0;
            for (let i = bufferStart; i < startElement; i++) {
                this._shouldBeVisibleSet.add(i);
                let elementToRender;
                let measuredHeight;
                if (this.currentlyRendered.has(i)) {
                    elementToRender = this.currentlyRendered.get(i);
                    measuredHeight = this.measureReused(i, elementToRender);
                }
                else {
                    elementToRender = this.acquireRow();
                    this.bindRow(elementToRender, i);
                    // Position after all buffer heights are known.
                    this.placement.attach(container, elementToRender, i, 'window');
                    renderElement(i, elementToRender);
                    measuredHeight = this.measureNew(i, elementToRender);
                    this.currentlyRendered.set(i, elementToRender);
                }
                bufferHeights.push(measuredHeight);
                bufferAboveHeight += measuredHeight;
            }
            // Place buffer rows, then fill the window from startElement.
            let cumulativeTop = -offset - bufferAboveHeight;
            // Most-negative top; table mode applies this once in commit().
            const firstRowTop = cumulativeTop;
            for (let i = bufferStart; i < startElement; i++) {
                const element = this.currentlyRendered.get(i);
                this.placement.position(element, cumulativeTop, 'window');
                cumulativeTop += bufferHeights[i - bufferStart];
            }
            cumulativeTop = -offset;
            let accumulatedViewportHeight = -offset; // first row is partially scrolled
            let elementIndex = startElement;
            while (elementIndex < this.totalElements && accumulatedViewportHeight < windowHeight) {
                this._shouldBeVisibleSet.add(elementIndex);
                let elementToRender;
                let measuredHeight;
                if (this.currentlyRendered.has(elementIndex)) {
                    elementToRender = this.currentlyRendered.get(elementIndex);
                    this.placement.position(elementToRender, cumulativeTop, 'window');
                    measuredHeight = this.measureReused(elementIndex, elementToRender);
                }
                else {
                    elementToRender = this.acquireRow();
                    this.bindRow(elementToRender, elementIndex);
                    this.placement.attach(container, elementToRender, elementIndex, 'window');
                    this.placement.position(elementToRender, cumulativeTop, 'window');
                    renderElement(elementIndex, elementToRender);
                    measuredHeight = this.measureNew(elementIndex, elementToRender);
                    this.currentlyRendered.set(elementIndex, elementToRender);
                }
                const entry = (_a = renderedRows[renderedRowsCount]) !== null && _a !== void 0 ? _a : (renderedRows[renderedRowsCount] = { index: 0, height: 0 });
                entry.index = elementIndex;
                entry.height = measuredHeight;
                renderedRowsCount++;
                totalRenderedHeight += measuredHeight;
                accumulatedViewportHeight += measuredHeight;
                cumulativeTop += measuredHeight;
                elementIndex++;
            }
            const bufferEnd = Math.min(this.totalElements - 1, elementIndex + ViewportRenderer.OVERSCAN_BUFFER - 1);
            for (let i = elementIndex; i <= bufferEnd; i++) {
                this._shouldBeVisibleSet.add(i);
                let elementToRender;
                let measuredHeight;
                if (this.currentlyRendered.has(i)) {
                    elementToRender = this.currentlyRendered.get(i);
                    this.placement.position(elementToRender, cumulativeTop, 'window');
                    measuredHeight = this.measureReused(i, elementToRender);
                }
                else {
                    elementToRender = this.acquireRow();
                    this.bindRow(elementToRender, i);
                    this.placement.attach(container, elementToRender, i, 'window');
                    this.placement.position(elementToRender, cumulativeTop, 'window');
                    renderElement(i, elementToRender);
                    measuredHeight = this.measureNew(i, elementToRender);
                    this.currentlyRendered.set(i, elementToRender);
                }
                cumulativeTop += measuredHeight;
            }
            const endElement = Math.min(elementIndex - 1, this.totalElements - 1);
            // Tail heights exist only for true-bottom. Once cached (and pinned),
            // extra DOM sentinels are recycled rather than repositioned every frame.
            const datasetLastIndex = this.totalElements - 1;
            const bottomElementsToRender = this._bottomElementsToRenderArray;
            bottomElementsToRender.length = 0;
            if (datasetLastIndex >= 0 && endElement < datasetLastIndex) {
                let bottomAccumulatedHeight = 0;
                const MAX_BOTTOM_ELEMENTS = 50;
                let missingMeasurement = false;
                for (let i = datasetLastIndex; i >= 0; i--) {
                    if (i <= endElement)
                        break;
                    if (bottomElementsToRender.length >= MAX_BOTTOM_ELEMENTS)
                        break;
                    bottomElementsToRender.push(i);
                    if (this.hasMeasuredHeight(i)) {
                        bottomAccumulatedHeight += this.getMeasuredHeight(i);
                        if (bottomAccumulatedHeight >= windowHeight)
                            break;
                    }
                    else {
                        missingMeasurement = true;
                    }
                }
                bottomElementsToRender.reverse();
                if (missingMeasurement) {
                    // Keep unmeasured tail rows alive through recycle.
                    for (let i = 0; i < bottomElementsToRender.length; i++) {
                        this._shouldBeVisibleSet.add(bottomElementsToRender[i]);
                    }
                }
                else {
                    bottomElementsToRender.length = 0;
                }
            }
            this._toRemoveArray.length = 0;
            this.currentlyRendered.forEach((element, index) => {
                if (!this._shouldBeVisibleSet.has(index)) {
                    this._toRemoveArray.push(index);
                    this.placement.detach(container, element);
                    this.recycledElements.push(element);
                }
            });
            this._toRemoveArray.forEach(index => this.currentlyRendered.delete(index));
            this.lastStartElement = startElement;
            this.lastEndElement = endElement;
            this._lastRenderedElement = (_b = this.currentlyRendered.get(datasetLastIndex)) !== null && _b !== void 0 ? _b : null;
            if (datasetLastIndex >= 0 && endElement < datasetLastIndex && bottomElementsToRender.length > 0) {
                for (const elemIndex of bottomElementsToRender) {
                    let bottomElement;
                    let bottomHeight;
                    if (this.currentlyRendered.has(elemIndex)) {
                        bottomElement = this.currentlyRendered.get(elemIndex);
                        this.placement.position(bottomElement, cumulativeTop, 'bottom');
                        bottomHeight = this.measureReused(elemIndex, bottomElement);
                    }
                    else {
                        bottomElement = this.acquireRow();
                        this.bindRow(bottomElement, elemIndex);
                        this.placement.attach(container, bottomElement, elemIndex, 'bottom');
                        this.placement.position(bottomElement, cumulativeTop, 'bottom');
                        renderElement(elemIndex, bottomElement);
                        bottomHeight = this.measureNew(elemIndex, bottomElement);
                        this.currentlyRendered.set(elemIndex, bottomElement);
                    }
                    cumulativeTop += bottomHeight;
                    if (elemIndex === datasetLastIndex) {
                        this._lastRenderedElement = bottomElement;
                    }
                }
            }
            this.placement.commit(container, firstRowTop);
            const scrollPercentage = this.getCalculateScrollPercentage();
            renderedRows.length = renderedRowsCount;
            return {
                startElement: startElement,
                endElement: endElement,
                scrollPercentage,
                viewportElements: endElement - startElement + 1,
                renderedElements: renderedRows,
                totalRenderedHeight
            };
        }
        /**
         * @param totalElements New dataset length.
         */
        updateTotalElements(totalElements) {
            if (this.totalElements !== totalElements) {
                this.totalElements = totalElements;
                this.bumpBottomMeasurementVersion();
            }
            else {
                this.totalElements = totalElements;
            }
        }
        /**
         * Camera position where the last row's bottom meets the viewport bottom.
         * Null until the tail has been measured.
         *
         * @param viewportHeight Usable height in pixels.
         * @returns `{ element, offset }` or `null` if the tail is unmeasured.
         */
        calculateTrueBottomPosition(viewportHeight) {
            if (this.trueBottomCache &&
                this.trueBottomCache.viewportHeight === viewportHeight &&
                this.trueBottomCache.totalElements === this.totalElements &&
                this.trueBottomCache.measurementVersion === this.bottomMeasurementVersion) {
                return this.trueBottomCache.value;
            }
            const value = this.computeTrueBottomPosition(viewportHeight);
            this.trueBottomCache = {
                viewportHeight,
                totalElements: this.totalElements,
                measurementVersion: this.bottomMeasurementVersion,
                value: value
            };
            return value;
        }
        /**
         * Drop the cached true-bottom camera. Next {@link calculateTrueBottomPosition}
         * recomputes from measured tail heights.
         */
        invalidateTrueBottomCache() {
            this.trueBottomCache = null;
        }
        computeTrueBottomPosition(viewportHeight) {
            const lastIndex = this.totalElements - 1;
            if (lastIndex < 0)
                return null;
            let accumulatedHeight = 0;
            let targetElement = lastIndex;
            let targetOffset = 0;
            for (let i = lastIndex; i >= 0; i--) {
                if (!this.hasMeasuredHeight(i)) {
                    return null;
                }
                const height = this.getMeasuredHeight(i);
                if (accumulatedHeight + height >= viewportHeight) {
                    targetElement = i;
                    targetOffset = Math.max(0, accumulatedHeight + height - viewportHeight);
                    break;
                }
                accumulatedHeight += height;
                if (i === 0) {
                    targetElement = 0;
                    targetOffset = 0;
                    break;
                }
            }
            return { element: targetElement, offset: targetOffset };
        }
        shouldTrackIndexForBottom(index) {
            const watchStart = Math.max(0, this.totalElements - ViewportRenderer.TRUE_BOTTOM_WATCH_RANGE);
            return index >= watchStart;
        }
        bumpBottomMeasurementVersion() {
            this.bottomMeasurementVersion++;
            this.invalidateTrueBottomCache();
        }
    }
    ViewportRenderer.OVERSCAN_BUFFER = 5;
    ViewportRenderer.TRUE_BOTTOM_WATCH_RANGE = 400;

    /**
     * Copyright (c) 2024-2026 Cerious DevTech LLC. All rights reserved.
     *
     * Column geometry for `layout: 'masonry'`.
     *
     * Serves both determinism modes (see `MasonryDeterminism`). The difference is
     * not in this file's algorithm but in how far the caller lets the frontier chain
     * run: canonical mode chains from card 0 so a position is a function of the
     * dataset, while local mode anchors at the landing so random access is constant
     * time. {@link anchorFlushAt} is the primitive that expresses that choice.
     *
     * Masonry is path-dependent: which column an item lands in depends on the
     * column frontier left by every item before it. Storing that per item is O(n)
     * memory, which the scroller refuses. Storing it per *segment* is not: this
     * keeps the real column frontier every K items — `columns` floats per snapshot
     * — and resumes the next run from it.
     *
     * The result is bit-identical to laying out every item in one pass from index
     * 0, so there is no seam anywhere and every gutter is exactly `gap`. The costs
     * are a snapshot table of `columns * (n / segmentSize)` floats (~12KB for 1M
     * items at the default K) and a sequential walk to reach a cold position, which
     * {@link MasonryLayout.chainAhead} spreads across frames.
     *
     * Heights come from {@link MasonryOptions.getItemHeight}, never from the DOM.
     * Segment replay must price items that were never mounted — a scrollbar drag
     * landing mid-dataset — so measuring is not available to it. In exchange the
     * scroll path performs no layout reads at all.
     */
    class MasonryLayout {
        constructor(options) {
            /**
             * Real column frontier at each segment boundary, `columns` floats per entry.
             * This is the whole memory cost of having no seam, and it doubles as a
             * prefix-sum table — {@link segmentOrigin} is a lookup, not a walk.
             */
            this.frontiers = [];
            /**
             * Frontiers are known for the CONTIGUOUS range [chainBase, frontierKnown].
             *
             * A single high-water mark is not enough once {@link anchorFlushAt} exists:
             * anchoring jumps forward without filling the gap behind it, so a bare
             * "known up to N" would claim segments that were never written and hand back
             * undefined. The pair states the real invariant.
             */
            this.frontierKnown = -1;
            this.chainBase = 0;
            /**
             * Segments below this were packed UPWARD by {@link extendBack} and must be
             * read back the same way. `0` means the whole range is ordinary forward work.
             */
            this.reverseBelow = 0;
            /** Full geometry for the few segments actually being drawn. */
            this.itemCache = new Map();
            this.opts = Object.assign(Object.assign({}, options), { segmentSize: Math.max(1, Math.floor(options.segmentSize)) });
            this.colH = new Array(this.opts.columns).fill(0);
            this.chainColH = new Array(this.opts.columns).fill(0);
        }
        get columns() { return this.opts.columns; }
        get columnWidth() { return this.opts.columnWidth; }
        get gap() { return this.opts.gap; }
        get segmentSize() { return this.opts.segmentSize; }
        /** Number of segments the dataset divides into. */
        segmentCount() {
            return Math.max(1, Math.ceil(this.opts.totalItems / this.opts.segmentSize));
        }
        /** First item index of a segment. Pure arithmetic — no chaining required. */
        segmentStart(segment) {
            return Math.min(segment * this.opts.segmentSize, this.opts.totalItems);
        }
        /**
         * Vertical extent of a segment, as the scroll engine consumes it.
         *
         * Interior segments measure to the SHALLOWEST column: the next segment's
         * cards resume from each column's real frontier and absorb the overhang, so
         * the segments tile exactly. The FINAL segment has nothing after it to absorb
         * anything, so it measures to the deepest column — otherwise the last cards
         * sit below where the engine believes the dataset ends and cannot be reached.
         *
         * @param segment Segment index.
         * @returns Height in pixels.
         */
        getSegmentHeight(segment) {
            const origin = this.segmentOrigin(segment);
            return this.segmentOrigin(segment + 1) - origin;
        }
        /**
         * Absolute y of a segment's top, from the start of the dataset.
         *
         * O(1) once the chain has reached `segment`, because the frontier table is
         * already a prefix-sum table. Reaching an unchained segment walks there.
         *
         * @param segment Segment index. `segmentCount()` is the past-the-end boundary.
         * @returns Pixels from the top of the dataset.
         */
        segmentOrigin(segment) {
            // Not an unconditional 0: a backwards extension gives segment 0 a real
            // origin above the anchor, which is negative in the range's own coordinates.
            if (segment <= 0)
                return this.hasFrontier(0) ? this.readOrigin(0) : 0;
            const clamped = Math.min(segment, this.segmentCount());
            this.ensureFrontier(clamped);
            return this.readOrigin(clamped);
        }
        /**
         * Fold a stored frontier into a single origin.
         *
         * Past-the-end uses the DEEPEST column so total height covers the ragged tail;
         * interior boundaries use the shallowest, which is what tiles exactly.
         */
        readOrigin(segment) {
            const off = segment * this.opts.columns;
            const atEnd = segment >= this.segmentCount();
            let v = this.frontiers[off];
            for (let c = 1; c < this.opts.columns; c++) {
                const o = this.frontiers[off + c];
                if (atEnd ? o > v : o < v)
                    v = o;
            }
            return v;
        }
        /**
         * Segment containing an absolute pixel position, and the offset into it.
         *
         * @param y Pixels from the top of the dataset.
         * @returns `{ segment, offset }`.
         */
        segmentAtY(y) {
            if (!(y > 0))
                return { segment: 0, offset: 0 };
            let lo = 0;
            let hi = this.segmentCount() - 1;
            while (lo < hi) {
                const mid = (lo + hi + 1) >> 1;
                if (this.segmentOrigin(mid) <= y)
                    lo = mid;
                else
                    hi = mid - 1;
            }
            return { segment: lo, offset: Math.max(0, y - this.segmentOrigin(lo)) };
        }
        /**
         * Total content height. Exact once the chain reaches the end, extrapolated
         * from the chained prefix before that.
         *
         * The scrollbar needs a total immediately, but chaining to the last segment is
         * the full sequential walk. Segment heights cluster tightly (each holds the
         * same item count), so the mean of what is known is a good stand-in until a
         * background pass finishes.
         *
         * @returns Height in pixels, and whether it is exact yet.
         */
        totalHeight() {
            const segments = this.segmentCount();
            if (this.frontierKnown >= segments) {
                return { height: this.segmentOrigin(segments), exact: true };
            }
            if (this.frontierKnown <= 0) {
                return { height: this.getSegmentHeight(0) * segments, exact: false };
            }
            const known = this.frontierKnown;
            return { height: (this.segmentOrigin(known) / known) * segments, exact: false };
        }
        /**
         * Cards in a segment, positioned relative to that segment's origin.
         *
         * @param segment Segment index.
         * @returns Cached array — read it, do not mutate or retain it.
         */
        getSegment(segment) {
            const hit = this.itemCache.get(segment);
            if (hit)
                return hit;
            const items = [];
            this.layoutSegment(segment, items);
            this.itemCache.set(segment, items);
            if (this.itemCache.size > MasonryLayout.ITEM_CACHE_LIMIT) {
                const oldest = this.itemCache.keys().next().value;
                this.itemCache.delete(oldest);
            }
            return items;
        }
        /**
         * Cards in a segment that intersect a pixel window.
         *
         * @param segment Segment index.
         * @param offset Window top, in pixels from the segment origin.
         * @param windowHeight Window height in pixels.
         * @param out Reused output array.
         * @returns `out`, filled with intersecting cards.
         */
        itemsInWindow(segment, offset, windowHeight, out) {
            out.length = 0;
            const items = this.getSegment(segment);
            const bottom = offset + windowHeight;
            for (let i = 0; i < items.length; i++) {
                const it = items[i];
                if (it.y + it.height >= offset && it.y <= bottom)
                    out.push(it);
            }
            return out;
        }
        /**
         * Absolute y of a single card, for re-anchoring across a relayout.
         *
         * @param index Item index.
         * @returns `{ segment, y }` with `y` absolute, or null if out of range.
         */
        locateItem(index) {
            if (!Number.isFinite(index) || index < 0 || index >= this.opts.totalItems)
                return null;
            const segment = Math.min(Math.floor(index / this.opts.segmentSize), this.segmentCount() - 1);
            const items = this.getSegment(segment);
            for (let i = 0; i < items.length; i++) {
                if (items[i].index === index) {
                    return { segment, y: this.segmentOrigin(segment) + items[i].y };
                }
            }
            return null;
        }
        /**
         * Change column geometry and discard everything derived from it.
         *
         * Every height depends on `columnWidth` (the oracle takes it) and every
         * frontier depends on those heights, so nothing survives a width change. The
         * caller must re-anchor afterwards: the camera is expressed in the old
         * geometry, and item N now lives somewhere else entirely.
         *
         * Segment count is unaffected, so the engine's element count does not change.
         *
         * @param columns New column count (>= 1).
         * @param columnWidth New column width in pixels (> 0).
         * @returns Whether anything changed.
         */
        resize(columns, columnWidth) {
            if (!Number.isFinite(columns) || columns < 1)
                return false;
            if (!Number.isFinite(columnWidth) || columnWidth <= 0)
                return false;
            if (columns === this.opts.columns && columnWidth === this.opts.columnWidth)
                return false;
            const sameCols = columns === this.opts.columns;
            this.opts.columns = columns;
            this.opts.columnWidth = columnWidth;
            if (!sameCols) {
                this.colH = new Array(columns).fill(0);
                this.chainColH = new Array(columns).fill(0);
            }
            this.invalidate();
            return true;
        }
        /** Drop every cached frontier and segment. */
        invalidate() {
            this.frontiers.length = 0;
            this.frontierKnown = -1;
            this.chainBase = 0;
            this.reverseBelow = 0;
            this.itemCache.clear();
        }
        /**
         * Declare a segment to be a fresh origin, with its columns level.
         *
         * Used when the camera lands somewhere the chain has never reached — a
         * scrollbar drag into never-visited content. Chaining there honestly costs one
         * height per card crossed, which in dynamic-height mode means mounting and
         * measuring every card in between. Starting level costs one flush line at the
         * landing card, which the viewer teleported to and so never scrolled across.
         *
         * No-op when the segment's frontier is already known — a real frontier always
         * beats an assumed one.
         *
         * @param segment Segment to anchor.
         * @returns Whether an anchor was placed.
         */
        anchorFlushAt(segment) {
            if (segment < 0)
                return false;
            if (this.hasFrontier(segment))
                return false;
            const { columns } = this.opts;
            const off = segment * columns;
            for (let c = 0; c < columns; c++)
                this.frontiers[off + c] = 0;
            // The anchor becomes the base of a NEW contiguous range. Everything the old
            // range covered is abandoned rather than silently claimed.
            this.chainBase = segment;
            this.frontierKnown = segment;
            // The old range is abandoned, and with it any block that was mirrored into
            // it. A fresh anchor starts ordinary forward work again.
            this.reverseBelow = 0;
            this.itemCache.clear();
            return true;
        }
        /**
         * Grow the contiguous range BACKWARDS, without moving anything already in it.
         *
         * Scrolling up out of an anchored range is the one case ordinary scrolling
         * cannot chain through: a frontier is a running total of everything ABOVE it,
         * so there is no history behind the base to extend from. Re-anchoring at the
         * new low point is what the caller would otherwise do, and it re-bases the
         * range — which throws away the frontier the camera's offset was computed
         * against and re-packs the columns the reader is looking at.
         *
         * This packs the missing segments UPWARD from the base instead: the mirror of
         * the ordinary algorithm, filling the column whose top edge hangs lowest and
         * growing away from the viewer. Mirroring is what makes the seam free —
         * placing cards against a known bottom edge means every column meets the base
         * frontier at exactly `gap`, where packing downward into it would leave all
         * but one column short. The raggedness that has to go somewhere ends up at
         * the TOP of the block, above everything drawn, where the next extension
         * consumes it just as exactly.
         *
         * Masonry stays locally deterministic either way: these segments have never
         * been placed under this range, so there is no earlier arrangement to
         * contradict. The difference is only that the viewer sees new content appear
         * above them rather than the grid they were reading re-flow.
         *
         * @param segments How many segments to prepend. Larger amortizes better: the
         *   work is one pass over the block, and a block is only ever built once.
         * @returns Whether the range grew.
         */
        extendBack(segments) {
            const base = this.chainBase;
            if (base <= 0 || !this.hasFrontier(base))
                return false;
            const span = Math.max(1, Math.floor(segments));
            const back = Math.max(0, base - span);
            if (back >= base)
                return false;
            const { columns, columnWidth, gap, segmentSize: K, totalItems, getItemHeight } = this.opts;
            const colTop = this.chainColH;
            const off = base * columns;
            for (let c = 0; c < columns; c++)
                colTop[c] = this.frontiers[off + c];
            for (let s = base - 1; s >= back; s--) {
                const lo = s * K;
                const hi = Math.min(lo + K, totalItems);
                for (let i = hi - 1; i >= lo; i--) {
                    // Mirror of "shortest column": fill the one whose top hangs LOWEST,
                    // because that is the one with the most room left above it.
                    let c = 0;
                    for (let k = 1; k < columns; k++)
                        if (colTop[k] > colTop[c])
                            c = k;
                    colTop[c] -= Math.max(1, getItemHeight(i, columnWidth)) + gap;
                }
                const o = s * columns;
                for (let c = 0; c < columns; c++)
                    this.frontiers[o + c] = colTop[c];
            }
            // The block is packed the other way round, so replaying it forwards would
            // not reproduce it. Segments below this mark are read back through the
            // mirrored walk instead — see layoutSegment.
            if (base > this.reverseBelow)
                this.reverseBelow = base;
            this.chainBase = back;
            // Only the block's own geometry is stale; everything from the base down is
            // untouched and must stay cached, or the camera's segment pays to be
            // measured again for a layout that did not change.
            for (const seg of [...this.itemCache.keys()]) {
                if (seg < base)
                    this.itemCache.delete(seg);
            }
            return true;
        }
        /** Whether a segment's frontier is actually written, not merely below the mark. */
        hasFrontier(segment) {
            return segment >= this.chainBase && segment <= this.frontierKnown;
        }
        /** Deepest segment of the current contiguous range. `-1` if none. */
        get frontierReach() {
            return this.frontierKnown;
        }
        /** First segment of the current contiguous range. */
        get frontierBase() {
            return this.chainBase;
        }
        /**
         * Advance the frontier chain toward `targetSegment` within a time budget.
         *
         * The chain is irreducibly sequential — a frontier IS the running column
         * state — so reaching a deep position after an invalidation costs one pass
         * over everything above it. Done in a single call that is a long frame on a
         * large dataset; call this once per animation frame instead until it returns
         * true.
         *
         * Progress is durable: each completed segment is written to the table, so an
         * abandoned rebuild costs nothing and later lookups resume rather than restart.
         *
         * @param targetSegment Segment whose frontier is needed.
         * @param budgetMs Wall-clock budget for this slice.
         * @returns `true` once the chain has reached `targetSegment`.
         */
        chainAhead(targetSegment, budgetMs) {
            const target = Math.max(0, Math.min(targetSegment, this.segmentCount()));
            if (this.hasFrontier(target))
                return true;
            // Behind the current base: there is no history to extend, so this is a
            // re-anchor decision, not a chaining one.
            if (target < this.chainBase)
                return false;
            const { columns, columnWidth, gap, segmentSize: K, totalItems, getItemHeight } = this.opts;
            const colH = this.chainColH;
            this.seedChain(colH);
            const deadline = MasonryLayout.now() + budgetMs;
            let s = Math.max(this.chainBase, this.frontierKnown);
            while (s < target) {
                const lo = s * K;
                const hi = Math.min(lo + K, totalItems);
                for (let i = lo; i < hi; i++) {
                    let c = 0;
                    for (let k = 1; k < columns; k++)
                        if (colH[k] < colH[c])
                            c = k;
                    colH[c] += Math.max(1, getItemHeight(i, columnWidth)) + gap;
                }
                this.storeFrontier(s + 1, colH);
                s++;
                // Checked per segment: a frontier is only meaningful at a boundary, so
                // that is the smallest resumable unit.
                if (MasonryLayout.now() >= deadline)
                    break;
            }
            return this.frontierKnown >= target;
        }
        /** How far the chain has been built, for progress reporting. */
        get chainProgress() {
            return { known: this.frontierKnown, total: this.segmentCount() };
        }
        /**
         * Resolve columns and column width for a container width.
         *
         * @param width Available content width in pixels.
         * @param gap Gutter in pixels.
         * @param fixedColumns Use exactly this many columns, ignoring `targetColumnWidth`.
         * @param targetColumnWidth Preferred column width when the count is responsive.
         * @param minColumns Lower bound for the responsive count.
         * @param maxColumns Upper bound for the responsive count.
         */
        static geometryFor(width, gap, fixedColumns, targetColumnWidth, minColumns, maxColumns) {
            const columns = fixedColumns && fixedColumns > 0
                ? Math.floor(fixedColumns)
                : Math.max(minColumns, Math.min(maxColumns, Math.floor((width + gap) / (targetColumnWidth + gap))));
            // Deliberately NOT floored. Flooring leaves a few pixels of remainder that
            // have to go somewhere, and wherever they go one outer gutter ends up wider
            // than the rest. A fractional width divides the space exactly, which is what
            // CSS grid does for the same reason.
            return {
                columns,
                columnWidth: Math.max(1, (width - gap * (columns - 1)) / columns)
            };
        }
        static now() {
            return typeof performance !== 'undefined' && typeof performance.now === 'function'
                ? performance.now()
                : Date.now();
        }
        /** Load the deepest known frontier into `colH`, seeding segment 0 if needed. */
        seedChain(colH) {
            const { columns } = this.opts;
            if (this.frontierKnown < 0) {
                for (let c = 0; c < columns; c++)
                    colH[c] = 0;
                this.chainBase = 0;
                this.storeFrontier(0, colH);
                return;
            }
            const off = this.frontierKnown * columns;
            for (let c = 0; c < columns; c++)
                colH[c] = this.frontiers[off + c];
        }
        /**
         * Guarantee that `target` has a frontier to read.
         *
         * Chains forward when the target is ahead of the current range. When it is
         * BEHIND the range's base — the range having been re-based by an anchor — the
         * history to chain from no longer exists, so the target becomes a fresh
         * anchor. Reading an unwritten slot instead would return undefined and put
         * NaN into every position derived from it.
         */
        ensureFrontier(target) {
            if (this.hasFrontier(target))
                return;
            if (target >= this.chainBase) {
                // Unbudgeted: callers that care about frame time use chainAhead().
                this.chainAhead(target, Number.POSITIVE_INFINITY);
                if (this.hasFrontier(target))
                    return;
            }
            this.anchorFlushAt(target);
        }
        storeFrontier(segment, colH) {
            const { columns } = this.opts;
            const off = segment * columns;
            for (let c = 0; c < columns; c++)
                this.frontiers[off + c] = colH[c];
            if (segment > this.frontierKnown)
                this.frontierKnown = segment;
        }
        /**
         * Place one segment's cards, continuing from the previous run's real frontier.
         * No flush, so the output matches a single pass from item 0 exactly.
         */
        layoutSegment(segment, out) {
            const { columns, columnWidth, gap, segmentSize: K, totalItems, getItemHeight } = this.opts;
            this.ensureFrontier(segment);
            if (segment < this.reverseBelow) {
                this.layoutSegmentUpward(segment, out);
                return;
            }
            const colH = this.colH;
            const off = segment * columns;
            let originY = Number.POSITIVE_INFINITY;
            for (let c = 0; c < columns; c++) {
                colH[c] = this.frontiers[off + c];
                if (colH[c] < originY)
                    originY = colH[c];
            }
            const start = segment * K;
            const end = Math.min(start + K, totalItems);
            for (let i = start; i < end; i++) {
                let c = 0;
                for (let k = 1; k < columns; k++)
                    if (colH[k] < colH[c])
                        c = k;
                const h = Math.max(1, getItemHeight(i, columnWidth));
                out.push({
                    index: i,
                    column: c,
                    x: c * (columnWidth + gap),
                    y: colH[c] - originY,
                    width: columnWidth,
                    height: h
                });
                colH[c] += h + gap;
            }
            // Only when the boundary is not already established. Normally it is not and
            // this is the write that advances the chain — but a segment laid out at the
            // BOTTOM of a backwards extension ends against a frontier that was
            // deliberately preserved (see {@link extendBack}), and recomputing it there
            // would drag every segment below it, and the whole visible window with them.
            // Everywhere else the recomputed value is identical to the stored one: the
            // same heights from the same start produce the same sum.
            if (!this.hasFrontier(segment + 1))
                this.storeFrontier(segment + 1, colH);
        }
        /**
         * Place one segment's cards by the mirrored walk {@link extendBack} used.
         *
         * Reads the boundary BELOW the segment and grows upward from it, so the cards
         * land exactly where the extension put them. Replaying such a segment forwards
         * would produce a different packing and a torn seam, which is the whole reason
         * `reverseBelow` exists.
         */
        layoutSegmentUpward(segment, out) {
            const { columns, columnWidth, gap, segmentSize: K, totalItems, getItemHeight } = this.opts;
            const colTop = this.colH;
            const below = (segment + 1) * columns;
            for (let c = 0; c < columns; c++)
                colTop[c] = this.frontiers[below + c];
            const start = segment * K;
            const end = Math.min(start + K, totalItems);
            const first = out.length;
            for (let i = end - 1; i >= start; i--) {
                let c = 0;
                for (let k = 1; k < columns; k++)
                    if (colTop[k] > colTop[c])
                        c = k;
                const h = Math.max(1, getItemHeight(i, columnWidth));
                const y = colTop[c] - gap - h;
                out.push({
                    index: i,
                    column: c,
                    x: c * (columnWidth + gap),
                    y,
                    width: columnWidth,
                    height: h
                });
                colTop[c] = y;
            }
            // Built bottom-up; hand it back in index order like every other segment.
            for (let lo = first, hi = out.length - 1; lo < hi; lo++, hi--) {
                const t = out[lo];
                out[lo] = out[hi];
                out[hi] = t;
            }
            // y is absolute so far — rebase it on the segment origin, which is the
            // topmost card, exactly as the forward walk reports it.
            let originY = Number.POSITIVE_INFINITY;
            for (let c = 0; c < columns; c++)
                if (colTop[c] < originY)
                    originY = colTop[c];
            for (let i = first; i < out.length; i++)
                out[i].y -= originY;
        }
    }
    MasonryLayout.ITEM_CACHE_LIMIT = 3;

    /**
     * Copyright (c) 2024-2026 Cerious DevTech LLC. All rights reserved.
     *
     * DOM half of `layout: 'masonry'`.
     *
     * The default renderer mounts one node per virtual element. Masonry cannot use
     * it: its virtual element is a SEGMENT of hundreds of cards, so one node per
     * element would be one node per segment. This mounts cards instead, and takes
     * the camera from the engine rather than computing one.
     *
     * The split is what keeps masonry off everyone else's hot path — the engine's
     * own render loop is untouched and gains no branches.
     */
    /**
     * The height a mounted card was laid out against, parked on the element.
     *
     * A symbol rather than a dataset entry: this is read and written on the render
     * path, and `dataset` stringifies and writes a real attribute every time.
     */
    const PLACED_HEIGHT = Symbol('cerious-masonry-placed-height');
    function setPlacedHeight(el, height) {
        el[PLACED_HEIGHT] = height;
    }
    function placedHeightOf(el) {
        return el[PLACED_HEIGHT];
    }
    class MasonryRenderer {
        /**
         * @param host Container whose width drives the column geometry.
         * @param totalItems Number of cards.
         * @param options Masonry configuration.
         */
        constructor(host, totalItems, options) {
            var _a, _b, _c, _d, _e, _f;
            this.host = host;
            this.options = options;
            this.content = null;
            this.mounted = new Map();
            this.pool = [];
            this.lastWidth = 0;
            this.resizeRaf = null;
            this.cardResizeRaf = null;
            this.resizeObserver = null;
            this.resizedCards = new Map();
            /** Topmost card still intersecting the viewport, and where it sat. */
            this.anchor = null;
            this.rebuilding = false;
            this.rebuildRaf = null;
            this.pendingAnchor = null;
            this.tailRaf = null;
            /**
             * Cached padding of the content box. Read once per geometry change — never
             * per frame, since getComputedStyle forces a layout.
             */
            this.pad = { left: 0, right: 0, top: 0 };
            /**
             * Half the width left over after flooring the column width. Columns are
             * integer-width, so `usable - (columns * w + gap * (columns - 1))` is usually
             * a pixel or two; without this it all lands on the right and the outer gutters
             * are visibly unequal.
             */
            this.centerOffset = 0;
            /**
             * Dynamic-height mode only. Measured card heights, bounded like the row
             * engine's cache. Evicting is safe: a stored frontier is a SUM, so it stays
             * valid — only placing cards inside a segment needs the individual values,
             * and those are re-measured on revisit.
             */
            this.heights = null;
            this.heightOrder = [];
            /** Offscreen element used to measure a card without disturbing the view. */
            this.probe = null;
            /** Draw columns from the right. Set by the engine from the resolved direction. */
            this.rtl = false;
            this.buf = [];
            this.needed = new Set();
            this.evict = [];
            this.gap = (_a = options.gap) !== null && _a !== void 0 ? _a : 16;
            this.overscan = (_b = options.overscan) !== null && _b !== void 0 ? _b : 400;
            this.sliceMs = (_c = options.rebuildSliceMs) !== null && _c !== void 0 ? _c : 6;
            this.dynamic = typeof options.getItemHeight !== 'function';
            this.estimatedHeight = (_d = options.estimatedItemHeight) !== null && _d !== void 0 ? _d : 300;
            this.maxChainSegments = (_e = options.maxChainSegments) !== null && _e !== void 0 ? _e : 4;
            if (this.dynamic)
                this.heights = new Map();
            // Create the content box up front so width is measured from the element the
            // cards actually live in, not from the host.
            this.ensureContent(host);
            this.measurePadding();
            this.lastWidth = this.availableWidth();
            const geo = this.geometryFor(this.lastWidth);
            this.setCenterOffset(this.lastWidth, geo.columns, geo.columnWidth);
            this.layout = new MasonryLayout({
                totalItems,
                columns: geo.columns,
                columnWidth: geo.columnWidth,
                gap: this.gap,
                // Dynamic mode uses MUCH smaller segments. A segment is laid out in full
                // whenever it is touched — its end frontier depends on every card in it —
                // so K is the measurement quantum, and measuring is the expensive thing
                // here. K=100 meant ~300 measurements to draw ~25 cards on every landing;
                // at this size the overhead is roughly one measurement per card drawn,
                // which is the same rate the row engine measures at.
                segmentSize: (_f = options.segmentSize) !== null && _f !== void 0 ? _f : (this.dynamic ? 24 : 500),
                getItemHeight: this.dynamic
                    ? (index, columnWidth) => this.measuredHeight(index, columnWidth)
                    : options.getItemHeight
            });
        }
        /** Segment count — this is what the engine uses as its element count. */
        get segmentCount() {
            return this.layout.segmentCount();
        }
        get columns() { return this.layout.columns; }
        get columnWidth() { return this.layout.columnWidth; }
        /** Cards currently in the DOM. Debug/telemetry. */
        get mountedCount() { return this.mounted.size; }
        /**
         * The card this renderer will hold in place across a relayout, and where it
         * currently sits relative to the viewport top.
         *
         * This is the reading position: a relayout re-derives the camera from it, so
         * it is the one card guaranteed not to move. Null before the first render.
         */
        get anchorItem() {
            return this.anchor ? { index: this.anchor.index, screenY: this.anchor.screenY } : null;
        }
        /**
         * Absolute y of a segment's top. Mirrors {@link segmentAtY}; together they
         * convert between the engine's camera and content coordinates.
         *
         * @param segment Segment index.
         * @returns Pixels from the top of the dataset.
         */
        segmentOrigin(segment) {
            return this.layout.segmentOrigin(segment);
        }
        /** Whether heights come from the DOM rather than from an oracle. */
        get isDynamic() { return this.dynamic; }
        /**
         * The determinism guarantee this layout provides. See {@link MasonryDeterminism}.
         *
         * `'canonical'` when an oracle prices cards, so a card's column is a function
         * of the dataset. `'local'` when heights are measured, so a card's column is a
         * function of the dataset AND how the viewer reached it.
         */
        get determinism() {
            return this.dynamic ? 'local' : 'canonical';
        }
        /**
         * Height lookups the engine installs in place of its own measured cache.
         *
         * Oracle mode answers everything exactly, including a total content height, so
         * the scrollbar strip can be sized in real pixels.
         *
         * Dynamic mode deliberately answers less. `totalHeight` is omitted, which
         * leaves the strip sized by element COUNT — the engine's existing behavior,
         * and the reason a dataset with nothing measured still maps the thumb
         * correctly. `cumulativeHeight` is likewise not offered, because summing to a
         * distant segment would mean measuring every card on the way there. Neither is
         * needed: position is expressed as (segment, offset) and the thumb as a
         * fraction of the card count.
         */
        heightProvider() {
            const L = this.layout;
            const base = {
                height: (segment) => this.segmentHeight(segment)
            };
            if (this.dynamic)
                return base;
            return Object.assign(Object.assign({}, base), { cumulativeHeight: (segment) => L.segmentOrigin(segment), rowAtPosition: (pixels) => {
                    const r = L.segmentAtY(pixels);
                    return { element: r.segment, offset: r.offset };
                }, totalHeight: () => L.totalHeight().height });
        }
        /**
         * Height of a segment, estimated when the camera has not reached it.
         *
         * Mirrors how an unmeasured row reports a default today: the value is only
         * used for segments the engine has not learned, and is replaced by the real
         * one the moment the camera arrives and the cards are measured.
         */
        segmentHeight(segment) {
            if (!this.dynamic)
                return this.layout.getSegmentHeight(segment);
            // A HEIGHT QUERY MUST NEVER MUTATE LAYOUT STATE. Asking the layout for a
            // segment outside the established range makes it anchor there, which
            // re-bases the range and discards the window the camera is using. The
            // engine queries heights constantly — the boundary guardian and the
            // true-bottom walk both probe the LAST segment — so a single unguarded read
            // re-anchors to the end of the dataset on every frame and every card gets
            // re-measured. Both ends of the span must be in range before trusting it.
            if (this.layout.hasFrontier(segment) && this.layout.hasFrontier(segment + 1)) {
                return this.layout.getSegmentHeight(segment);
            }
            const perRow = this.estimatedHeight + this.gap;
            return (this.layout.segmentSize / Math.max(1, this.layout.columns)) * perRow;
        }
        /**
         * Height of one card, measuring it offscreen if it has not been seen.
         *
         * The probe is a detached-but-laid-out box of exactly one column's width, so
         * the height it reports is the height the card will have once placed. It never
         * touches the visible tree, which matters because this runs while the frontier
         * is being computed — before anything is positioned.
         */
        measuredHeight(index, columnWidth) {
            const cached = this.heights.get(index);
            if (cached !== undefined)
                return cached;
            let height = this.estimatedHeight;
            const probe = this.ensureProbe();
            if (probe) {
                probe.style.width = columnWidth + 'px';
                probe.textContent = '';
                this.options.renderItem(index, probe);
                const h = probe.offsetHeight;
                if (h > 0)
                    height = h;
                probe.textContent = '';
            }
            this.heights.set(index, height);
            this.heightOrder.push(index);
            if (this.heightOrder.length > MasonryRenderer.HEIGHT_CACHE_MAX) {
                // Oldest-first eviction, skipping anything currently on screen. Frontiers
                // already folded these into a sum, so dropping a value is safe for the
                // layout — but a MOUNTED card is still being observed, and dropping its
                // height loses the baseline its next observation is judged against.
                const want = this.heightOrder.length >> 1;
                const keep = [];
                let dropped = 0;
                for (let i = 0; i < this.heightOrder.length; i++) {
                    const idx = this.heightOrder[i];
                    if (dropped < want && !this.mounted.has(idx)) {
                        this.heights.delete(idx);
                        dropped++;
                        continue;
                    }
                    keep.push(idx);
                }
                this.heightOrder = keep;
            }
            return height;
        }
        ensureProbe() {
            var _a;
            if (this.probe)
                return this.probe;
            if (typeof document === 'undefined')
                return null;
            const el = document.createElement('div');
            el.setAttribute('data-cerious-masonry', 'probe');
            el.setAttribute('aria-hidden', 'true');
            // Laid out (so it has a height) but out of flow, invisible, inert.
            el.style.cssText =
                'position:absolute;left:-99999px;top:0;visibility:hidden;pointer-events:none;';
            ((_a = this.content) !== null && _a !== void 0 ? _a : this.host).appendChild(el);
            this.probe = el;
            return el;
        }
        /**
         * Make sure the camera's segment has a frontier to lay out from.
         *
         * Ordinary scrolling walks forward a segment at a time, which is a short chain
         * and worth paying for. A jump into content the chain has never reached is
         * not: honouring it would mean measuring every card in between. Past
         * `maxChainSegments` the landing segment is anchored level instead.
         */
        ensureWindowFrontier(camera, segments, windowHeight, offset) {
            if (!this.dynamic)
                return Math.min(segments - 1, camera + 1);
            // Establish ONE contiguous range covering the whole drawn window, lowest
            // segment first. Doing it piecemeal thrashes: the neighbour above the camera
            // sits below the current range base, so laying it out re-anchors backwards,
            // which discards the range the camera was just using — and every frame pays
            // to measure it all again.
            let first = Math.max(0, camera - 1);
            // Near the end, cover a few segments back from the LAST one rather than
            // just the camera's neighbour. The engine's bottom-boundary correction walks
            // the tail, and it walks it through getElementHeight — which answers with an
            // estimate for anything outside the range. Correcting against an estimate is
            // what drags the camera off the end: measured, a camera placed at the final
            // segment came back two segments earlier with an offset larger than the
            // segment is tall, leaving the viewport empty.
            const tailGuard = MasonryRenderer.TAIL_REAL_SEGMENTS;
            if (camera >= segments - 1 - tailGuard) {
                first = Math.max(0, Math.min(first, segments - 1 - tailGuard));
            }
            if (!this.layout.hasFrontier(first)) {
                const reach = this.layout.frontierReach;
                const base = this.layout.frontierBase;
                if (reach >= 0 && first >= base && first - reach <= this.maxChainSegments) {
                    this.layout.chainAhead(first, this.sliceMs);
                }
                else if (reach >= 0 && first < base && base - first <= MasonryRenderer.MAX_BACK_SEGMENTS) {
                    // Scrolling UP out of the range — the one direction a chain cannot be
                    // walked. Anchoring at `first` is the obvious move and the wrong one: it
                    // re-bases the range and re-packs the columns the reader is looking at.
                    // Prepend a block instead, which leaves every frontier from the base
                    // down exactly as it was. Done in CHUNKS, so a long scroll up pays for
                    // it a few times rather than once per segment.
                    this.layout.extendBack(Math.max(base - first, MasonryRenderer.BACK_CHUNK_SEGMENTS));
                }
                if (!this.layout.hasFrontier(first))
                    this.layout.anchorFlushAt(first);
            }
            // Walk forward until the window is actually covered, rather than stopping at
            // a fixed neighbour. Segment heights vary with content, so a fixed count
            // sometimes falls short of the viewport and leaves the bottom blank.
            //
            // UNBUDGETED on purpose: a budgeted chain that runs out leaves the segment
            // without a frontier, and a segment without a frontier is skipped — which is
            // the blank band this is fixing. The span is bounded instead, so the work is
            // bounded without ever stopping halfway.
            // Coverage is measured in SCREEN space, so it starts at the camera's own
            // origin (-offset), not at the top of the camera's segment. Ignoring the
            // offset over-reports how far the content reaches and stops the sweep early
            // — precisely the blank band being fixed.
            const need = windowHeight + this.overscan;
            let covered = -offset;
            let last = camera;
            for (let guard = 0; guard < MasonryRenderer.MAX_WINDOW_SEGMENTS; guard++) {
                if (!this.layout.hasFrontier(last)) {
                    this.layout.chainAhead(last, Number.POSITIVE_INFINITY);
                    if (!this.layout.hasFrontier(last))
                        break;
                }
                covered += this.segmentHeight(last);
                if (covered >= need || last >= segments - 1)
                    break;
                last++;
            }
            // One past the covered span, so a card overhanging the boundary is drawn —
            // and note this reaches `segments`, the PAST-THE-END boundary, not
            // `segments - 1`. A segment's height is the delta between its own frontier
            // and the next one, so the final segment has no real height until the
            // boundary after it exists. Without that the camera settles against an
            // estimate at the end of the dataset and the viewport comes up empty.
            const tail = Math.min(segments, last + 1);
            if (!this.layout.hasFrontier(tail)) {
                this.layout.chainAhead(tail, Number.POSITIVE_INFINITY);
            }
            return Math.min(segments - 1, this.layout.hasFrontier(tail) ? tail : last);
        }
        /**
         * Width the cards may actually occupy.
         *
         * NOT `host.clientWidth`: attaching the native scrollbar puts a
         * `padding-right` on the host for the strip, and `clientWidth` INCLUDES
         * padding. Measuring the host therefore counts space the cards cannot use, and
         * the rightmost column renders underneath the strip and is clipped — by
         * exactly the strip width.
         *
         * The content box already excludes it, so measure that instead.
         */
        availableWidth() {
            const el = this.content;
            if (!el)
                return this.host.clientWidth;
            // Measure to the scrollbar strip when one is present, not to the content
            // box. The host reserves padding for the strip, but that reservation is not
            // required to equal the strip's rendered width — here it is 17px of padding
            // for a 15px strip — so the content box's right edge sits a couple of pixels
            // short of the strip. Measuring the real distance keeps the last gutter
            // equal to the others instead of inheriting that slack.
            let span = el.clientWidth;
            const strip = this.host.querySelector('[data-cerious-scrollbar="container"]');
            if (strip && typeof el.getBoundingClientRect === 'function') {
                const gap = strip.getBoundingClientRect().left - el.getBoundingClientRect().left;
                if (gap > 0)
                    span = gap;
            }
            const inner = span - this.pad.left - this.pad.right;
            return inner > 0 ? inner : this.host.clientWidth;
        }
        /**
         * Read the content box's padding so cards can be inset from its edges.
         *
         * Rows can be full-bleed; cards cannot — a card flush against the container
         * edge reads as clipped. Honouring CSS padding here means a gutter is styled
         * normally, with no extra option. `clientWidth` INCLUDES padding, and an
         * absolutely positioned child is laid out against the padding box rather than
         * the content box, so both the available width and each card's x must account
         * for it explicitly.
         */
        measurePadding() {
            if (!this.content || typeof getComputedStyle !== 'function')
                return;
            const cs = getComputedStyle(this.content);
            this.pad.left = parseFloat(cs.paddingLeft) || 0;
            this.pad.right = parseFloat(cs.paddingRight) || 0;
            this.pad.top = parseFloat(cs.paddingTop) || 0;
        }
        /** Recompute the centering offset for a resolved geometry. */
        setCenterOffset(usable, columns, columnWidth) {
            const grid = columns * columnWidth + this.gap * (columns - 1);
            this.centerOffset = Math.max(0, Math.floor((usable - grid) / 2));
        }
        geometryFor(width) {
            var _a, _b, _c;
            return MasonryLayout.geometryFor(width, this.gap, this.options.columns, (_a = this.options.targetColumnWidth) !== null && _a !== void 0 ? _a : 280, (_b = this.options.minColumns) !== null && _b !== void 0 ? _b : 1, (_c = this.options.maxColumns) !== null && _c !== void 0 ? _c : 8);
        }
        /** Positioned wrapper the cards live in, created on first render. */
        ensureContent(container) {
            if (this.content) {
                const parent = this.content.parentElement;
                // The native surface wraps the existing Masonry viewport in a private
                // scrollable ancestor. It is still the same live viewport for this host;
                // recreating it outside the surface would strand hit-testing and leave an
                // orphan layer behind.
                //
                // Matched by SEARCHING for the surface rather than by naming its exact
                // depth: it inserts a sticky layer of its own between the proxy and the
                // viewport, and a check written against one particular shape silently
                // stops recognising it the day that shape changes — which is how this
                // read as "not mine" and rebuilt the viewport outside the surface.
                const surface = this.content.closest('[data-cerious-native-touch-proxy]');
                const insideNativeSurface = Boolean(surface && surface.parentElement === container);
                if (parent === container || insideNativeSurface)
                    return this.content;
            }
            const el = document.createElement('div');
            el.setAttribute('data-cerious-masonry', 'content');
            el.style.cssText = 'position:relative;width:100%;height:100%;overflow:hidden';
            container.appendChild(el);
            this.content = el;
            return el;
        }
        /**
         * Mount the cards covering the viewport and recycle the rest.
         *
         * Cards overhang segment boundaries — a segment's height is a frontier delta,
         * not a bounding box — so the neighbouring segments are swept too.
         *
         * @param windowHeight Usable viewport height.
         * @param container Host element.
         * @param host Engine surface.
         */
        render(windowHeight, container, host) {
            var _a, _b, _c;
            if (this.rebuilding)
                return; // layout invalidated; hold the current view
            const content = this.ensureContent(container);
            let camera = host.currentElement;
            let offset = host.scrollOffset;
            const segments = this.layout.segmentCount();
            this.needed.clear();
            let anchorIndex = -1;
            let anchorY = Number.POSITIVE_INFINITY;
            let lastSeg = this.ensureWindowFrontier(camera, segments, windowHeight, offset);
            // Settle against the end of the dataset.
            //
            // The camera's offset was chosen from ESTIMATED segment heights — that is
            // what lets the engine navigate content it has never measured. Once the
            // final segment is actually measured, the estimate that put the camera there
            // is usually wrong, and if it was too large the window sits past every card
            // and the viewport is blank. Re-clamp against the real height, then re-read:
            // the camera moved.
            if (this.dynamic && camera >= segments - 1 && this.layout.hasFrontier(camera)) {
                const realHeight = this.segmentHeight(camera);
                const maxOffset = Math.max(0, realHeight - windowHeight);
                if (offset > maxOffset + 0.5) {
                    host.jumpToPosition(camera, maxOffset, true);
                    camera = host.currentElement;
                    offset = host.scrollOffset;
                    lastSeg = this.ensureWindowFrontier(camera, segments, windowHeight, offset);
                }
            }
            for (let seg = camera - 1; seg <= lastSeg; seg++) {
                if (seg < 0 || seg >= segments)
                    continue;
                // Never draw a segment whose frontier is outside the established range:
                // asking for it would silently re-anchor and invalidate the window
                // mid-frame.
                if (this.dynamic && !this.layout.hasFrontier(seg))
                    continue;
                const origin = this.screenOriginOf(seg, camera, offset);
                if (!Number.isFinite(origin))
                    continue;
                // Skip a neighbour that cannot reach the window. Laying one out costs a
                // full segment of measurements in dynamic mode, so paying for a segment
                // that contributes nothing is the difference between a smooth drag and a
                // stalled one.
                if (seg !== camera) {
                    const extent = this.segmentHeight(seg);
                    if (origin + extent < -this.overscan)
                        continue;
                    if (origin > windowHeight + this.overscan)
                        continue;
                }
                const items = this.layout.itemsInWindow(seg, -this.overscan - origin, windowHeight + this.overscan * 2, this.buf);
                for (let i = 0; i < items.length; i++) {
                    const it = items[i];
                    const screenY = origin + it.y;
                    if (screenY + it.height < -this.overscan)
                        continue;
                    if (screenY > windowHeight + this.overscan)
                        continue;
                    if (screenY + it.height > 0 && screenY < anchorY) {
                        anchorY = screenY;
                        anchorIndex = it.index;
                    }
                    this.needed.add(it.index);
                    let el = this.mounted.get(it.index);
                    if (!el) {
                        el = (_a = this.pool.pop()) !== null && _a !== void 0 ? _a : this.createCard();
                        el.dataset.elementIndex = String(it.index);
                        this.options.renderItem(it.index, el);
                        content.appendChild(el);
                        this.mounted.set(it.index, el);
                        if (this.dynamic)
                            (_b = this.resizeObserver) === null || _b === void 0 ? void 0 : _b.observe(el);
                    }
                    // No offsetHeight read: the oracle already supplied the height.
                    this.write(el, it, screenY + this.pad.top);
                }
            }
            this.evict.length = 0;
            this.mounted.forEach((_, index) => {
                if (!this.needed.has(index))
                    this.evict.push(index);
            });
            for (let i = 0; i < this.evict.length; i++) {
                const index = this.evict[i];
                const el = this.mounted.get(index);
                (_c = this.resizeObserver) === null || _c === void 0 ? void 0 : _c.unobserve(el);
                if (el.parentNode)
                    el.parentNode.removeChild(el);
                this.pool.push(el);
                this.mounted.delete(index);
            }
            this.anchor = anchorIndex >= 0 ? { index: anchorIndex, screenY: anchorY } : null;
            host.updateDisplay();
        }
        /**
         * Column order for the current writing direction.
         *
         * Mirrored at the point of WRITING rather than in the layout, so the packing
         * stays one algorithm: column 0 is still the first column the engine fills,
         * it is simply drawn from the other edge. Anything that reasons about column
         * indices — the frontier, determinism, the tests — is untouched.
         */
        mirrorX(x, width) {
            if (!this.rtl)
                return x;
            const span = this.layout.columns * this.layout.columnWidth
                + this.gap * (this.layout.columns - 1);
            return span - x - width;
        }
        write(el, it, screenY) {
            // The height this card was laid out against. handleCardResizes compares
            // observations to THIS rather than to the bounded height cache, so an
            // eviction can never masquerade as a card that grew.
            if (this.dynamic)
                setPlacedHeight(el, it.height);
            const x = this.mirrorX(it.x, it.width) + this.pad.left + this.centerOffset;
            const transform = `translate(${x}px, ${screenY}px)`;
            if (el.style.transform !== transform)
                el.style.transform = transform;
            // In dynamic mode the wrapper must remain intrinsically sized. A fixed
            // height would hide later changes (image loads, expanded content, web-font
            // reflow) from ResizeObserver, because overflowing children do not resize
            // their fixed-height parent.
            const h = this.dynamic ? '' : it.height + 'px';
            if (el.style.height !== h)
                el.style.height = h;
            const w = it.width + 'px';
            if (el.style.width !== w)
                el.style.width = w;
        }
        createCard() {
            const el = document.createElement('div');
            el.style.cssText = 'position:absolute;top:0;left:0;will-change:transform';
            return el;
        }
        /**
         * Screen y of a segment's origin for the current camera.
         *
         * Sums forward rather than special-casing a single neighbour: the window may
         * span several segments when their content is short, and stopping at
         * `camera + 1` is what leaves a blank band under the last drawn card.
         *
         * Always via {@link segmentHeight}, never the layout directly — see the
         * warning there about reads that mutate.
         */
        screenOriginOf(segment, camera, offset) {
            if (segment === camera)
                return -offset;
            if (segment === camera - 1)
                return -offset - this.segmentHeight(camera - 1);
            if (segment > camera) {
                let y = -offset;
                for (let s = camera; s < segment; s++)
                    y += this.segmentHeight(s);
                return y;
            }
            return NaN;
        }
        /**
         * Watch for width changes. Returns a detach function.
         *
         * Observes the CONTENT box rather than the host: the scrollbar strip attaches
         * after construction and squeezes the content without changing the host's own
         * size, so a host observer would never fire for it and the first layout would
         * stay one strip-width too wide.
         */
        observeResize(host, onRender) {
            var _a;
            if (typeof ResizeObserver === 'undefined')
                return () => { };
            const target = (_a = this.content) !== null && _a !== void 0 ? _a : this.host;
            const ro = new ResizeObserver((entries) => {
                let containerChanged = false;
                for (const entry of entries) {
                    if (entry.target === target) {
                        containerChanged = true;
                        continue;
                    }
                    if (!this.dynamic)
                        continue;
                    const el = entry.target;
                    const index = Number(el.dataset.elementIndex);
                    if (!Number.isInteger(index) || this.mounted.get(index) !== el)
                        continue;
                    const height = el.offsetHeight;
                    if (Number.isFinite(height) && height >= 0)
                        this.resizedCards.set(index, height);
                }
                // A drag-resize fires continuously and a width change costs a relayout.
                if (containerChanged && this.resizeRaf === null) {
                    this.resizeRaf = requestAnimationFrame(() => {
                        this.resizeRaf = null;
                        this.handleResize(host, onRender);
                    });
                }
                if (this.resizedCards.size > 0 && this.cardResizeRaf === null) {
                    this.cardResizeRaf = requestAnimationFrame(() => {
                        this.cardResizeRaf = null;
                        this.handleCardResizes(host, onRender);
                    });
                }
            });
            ro.observe(target);
            this.mounted.forEach((el) => { if (this.dynamic)
                ro.observe(el); });
            this.resizeObserver = ro;
            return () => {
                ro.disconnect();
                if (this.resizeObserver === ro)
                    this.resizeObserver = null;
            };
        }
        /** Apply post-render intrinsic height changes and rebuild the local window. */
        handleCardResizes(host, onRender) {
            if (!this.dynamic || this.rebuilding || this.resizedCards.size === 0) {
                this.resizedCards.clear();
                return;
            }
            let changed = false;
            this.resizedCards.forEach((height, index) => {
                // Compare against the height the card was PLACED with, not against the
                // height cache. The cache is bounded and evicts, so a miss there means
                // only "not remembered" — and treating a miss as a change invalidates the
                // layout and reorders the grid under the reader for a card that never
                // moved. The placed height is carried by the element itself, so it is
                // exact for every mounted card and cannot be evicted out from under this.
                const el = this.mounted.get(index);
                const placed = el ? placedHeightOf(el) : undefined;
                const previous = placed !== null && placed !== void 0 ? placed : this.heights.get(index);
                if (previous === undefined) {
                    // Nothing mounted and nothing remembered: record it, but there is no
                    // baseline to call this a change against.
                    if (!this.heights.has(index))
                        this.heightOrder.push(index);
                    this.heights.set(index, height);
                    return;
                }
                if (Math.abs(previous - height) > 0.5) {
                    if (!this.heights.has(index))
                        this.heightOrder.push(index);
                    this.heights.set(index, height);
                    if (el)
                        setPlacedHeight(el, height);
                    changed = true;
                }
            });
            this.resizedCards.clear();
            if (!changed)
                return;
            // A changed height can alter the column choice and y-position of every card
            // after it. Dynamic masonry is locally deterministic, so invalidate and
            // re-anchor at the current reading position instead of replaying the whole
            // dataset from item zero.
            this.pendingAnchor = this.anchor;
            this.layout.invalidate();
            this.rebuilding = true;
            this.scheduleRebuild(host, onRender);
        }
        /**
         * Recompute geometry against the current container, whether or not the width
         * changed since the last measurement.
         *
         * Used once after the scrollbar strip attaches: the constructor necessarily
         * measured before it existed, and a resize observation cannot be relied on to
         * correct that — on a reused host the padding is already present, so the
         * content box never changes size and nothing fires.
         *
         * @param host Engine surface.
         * @param onRender Called when the new geometry is ready to draw.
         */
        remeasure(host, onRender) {
            const width = this.availableWidth();
            if (width <= 0)
                return;
            // With cards on screen this is an ordinary relayout: hold the view, preserve
            // the reading position, rebuild in slices.
            if (this.mounted.size > 0) {
                this.lastWidth = -1;
                this.handleResize(host, onRender);
                return;
            }
            // Nothing has been drawn yet, so there is no view to hold and no camera to
            // preserve. Settle the geometry in place and return WITHOUT rendering:
            // this runs from the engine's constructor, and the usual consumer shape is
            //   scroller = new CeriousScroll(host, n, { onScroll: () => scroller.render... })
            // so invoking the callback here would reach a binding that does not exist
            // yet. The caller's first render picks up the corrected geometry.
            this.lastWidth = width;
            this.measurePadding();
            const geo = this.geometryFor(width);
            if (!this.layout.resize(geo.columns, geo.columnWidth))
                return;
            this.setCenterOffset(width, geo.columns, geo.columnWidth);
        }
        /**
         * Host resized. A height change just re-syncs; a WIDTH change rebuilds the
         * layout, because every height is a function of column width.
         *
         * The camera cannot survive that — it is `(segment, offset)` in the old
         * geometry — so the re-anchor is on CONTENT: the card nearest the viewport top
         * is put back at the same screen position afterwards.
         */
        handleResize(host, onRender) {
            var _a;
            const width = this.availableWidth();
            if (width <= 0 || width === this.lastWidth) {
                if (!this.rebuilding)
                    onRender();
                return;
            }
            this.lastWidth = width;
            this.measurePadding();
            const geo = this.geometryFor(width);
            if (!this.layout.resize(geo.columns, geo.columnWidth)) {
                onRender();
                return;
            }
            this.setCenterOffset(width, geo.columns, geo.columnWidth);
            // Every measured height was taken at the previous column width and is now
            // wrong; a text card reflows when its column narrows.
            (_a = this.heights) === null || _a === void 0 ? void 0 : _a.clear();
            this.heightOrder.length = 0;
            this.pendingAnchor = this.anchor;
            this.rebuilding = true;
            this.scheduleRebuild(host, onRender);
        }
        /**
         * Rebuild the frontier chain in slices, holding the current view meanwhile.
         *
         * Chaining to the camera is one pass over everything above it and cannot be
         * shortened. In a single call that is a long frame on a large dataset; sliced,
         * each frame still has room to paint. The old cards stay mounted throughout so
         * the page holds a stale-but-coherent view rather than blanking.
         */
        scheduleRebuild(host, onRender) {
            if (this.dynamic) {
                // Dynamic mode must NOT chain here. A resize invalidates every frontier,
                // so chaining to the camera means measuring every card above it: after
                // scrolling to card 400,000 a relayout measured 500,010 cards across 384
                // frames. Anchor at the camera's segment instead — the same policy a far
                // jump uses, and for the same reason.
                const target = this.pendingAnchor
                    ? Math.min(Math.floor(this.pendingAnchor.index / this.layout.segmentSize), Math.max(0, this.layout.segmentCount() - 1))
                    : 0;
                // Anchor one segment ABOVE the camera's, not at it. render() always
                // sweeps from `camera - 1`, and a segment below the range base cannot be
                // chained to — so anchoring exactly at the camera guarantees that the
                // very next frame re-anchors at `camera - 1`, re-bases the range, and
                // discards the frontier the camera's offset was just computed against.
                // The reader's card visibly jumps and the columns reshuffle. Starting one
                // segment earlier puts the whole drawn window inside one range.
                this.layout.anchorFlushAt(Math.max(0, target - 1));
                this.finishRebuild(host, onRender);
                return;
            }
            if (this.rebuildRaf !== null)
                return;
            this.rebuildRaf = requestAnimationFrame(() => {
                this.rebuildRaf = null;
                const target = this.pendingAnchor
                    ? Math.floor(this.pendingAnchor.index / this.layout.segmentSize)
                    : 0;
                if (!this.layout.chainAhead(target, this.sliceMs)) {
                    this.scheduleRebuild(host, onRender);
                    return;
                }
                this.finishRebuild(host, onRender);
            });
        }
        finishRebuild(host, onRender) {
            const anchor = this.pendingAnchor;
            this.pendingAnchor = null;
            this.rebuilding = false;
            this.mounted.forEach((el) => {
                var _a;
                (_a = this.resizeObserver) === null || _a === void 0 ? void 0 : _a.unobserve(el);
                if (el.parentNode)
                    el.parentNode.removeChild(el);
                this.pool.push(el);
            });
            this.mounted.clear();
            if (anchor) {
                // Via cameraForItem, never locateItem + segmentAtY: that pair binary
                // searches segment ORIGINS, and every probe outside the range anchors and
                // re-bases. It is the same trap that made jumpToItem take 8.6 seconds.
                const pos = this.cameraForItem(anchor.index, anchor.screenY);
                if (pos)
                    host.jumpToPosition(pos.segment, pos.offset, true);
            }
            host.refreshScrollbarMetrics();
            onRender();
            this.scheduleTailChain(host);
        }
        /**
         * Chain to the very end in the background so the scrollbar stops being an
         * estimate. Smaller slice: this competes with real scrolling, and nothing
         * depends on it finishing.
         *
         * ORACLE MODE ONLY. In dynamic mode a frontier costs a real DOM measurement
         * per card, so chaining to the end means probing the ENTIRE dataset — tens of
         * thousands of forced layouts that never stop, in 3ms slices that land in
         * every frame the user is scrolling through. Worse, those measurements evict
         * the height cache the visible cards were just priced from, and a card that
         * remounts with no cached height reads as a height CHANGE, which invalidates
         * the layout and reorders the grid mid-scroll.
         *
         * Nothing wants the total anyway: {@link heightProvider} deliberately omits
         * `totalHeight` in dynamic mode, so the strip is sized by card count and the
         * exact pixel total is never asked for.
         */
        scheduleTailChain(host) {
            if (this.dynamic)
                return;
            if (this.tailRaf !== null)
                return;
            this.tailRaf = requestAnimationFrame(() => {
                this.tailRaf = null;
                if (!this.layout.chainAhead(this.layout.segmentCount(), 3)) {
                    this.scheduleTailChain(host);
                    return;
                }
                host.refreshScrollbarMetrics();
            });
        }
        /**
         * Absolute y of a card, for `jumpToItem`.
         *
         * In dynamic mode the target segment is anchored FIRST when it is far from the
         * current range. Without that, locating a card walks the frontier all the way
         * to it, measuring every card on the way: jumping to card 400,000 of 500,000
         * took 2.9s and 437,472 measurements — a locked-up tab.
         */
        /**
         * Camera position that puts a card at `screenOffset` from the viewport top.
         *
         * Deliberately avoids absolute y in dynamic mode. Going through
         * `locateItem` + `segmentAtY` means a binary search over segment ORIGINS, and
         * every probe asks for a frontier the range does not hold — so each step
         * anchors, re-bases, and re-measures. Jumping to card 400,000 that way took
         * 8.6 seconds. The segment a card belongs to is pure arithmetic; only its
         * offset inside that segment needs the layout.
         *
         * @param index Card index.
         * @param screenOffset Pixels below the viewport top to place it.
         * @returns `{ segment, offset }`, or null if the card is out of range.
         */
        cameraForItem(index, screenOffset) {
            if (!this.dynamic) {
                const found = this.layout.locateItem(index);
                if (!found)
                    return null;
                const r = this.layout.segmentAtY(Math.max(0, found.y - screenOffset));
                return { segment: r.segment, offset: r.offset };
            }
            const segment = Math.min(Math.floor(index / this.layout.segmentSize), Math.max(0, this.layout.segmentCount() - 1));
            if (segment < 0)
                return null;
            if (!this.layout.hasFrontier(segment)) {
                const reach = this.layout.frontierReach;
                const near = reach >= 0 && segment >= this.layout.frontierBase &&
                    segment - reach <= this.maxChainSegments;
                if (near)
                    this.layout.chainAhead(segment, Number.POSITIVE_INFINITY);
                if (!this.layout.hasFrontier(segment))
                    this.layout.anchorFlushAt(segment);
            }
            // y here is relative to the segment's own origin, which is all the camera
            // needs — (segment, offset) never refers to a global pixel space.
            let within = 0;
            for (const it of this.layout.getSegment(segment)) {
                if (it.index === index) {
                    within = it.y;
                    break;
                }
            }
            return { segment, offset: Math.max(0, within - screenOffset) };
        }
        locateItem(index) {
            if (this.dynamic) {
                const segment = Math.min(Math.floor(index / this.layout.segmentSize), Math.max(0, this.layout.segmentCount() - 1));
                if (!this.layout.hasFrontier(segment)) {
                    const reach = this.layout.frontierReach;
                    const near = reach >= 0 && segment >= this.layout.frontierBase &&
                        segment - reach <= this.maxChainSegments;
                    if (near)
                        this.layout.chainAhead(segment, Number.POSITIVE_INFINITY);
                    if (!this.layout.hasFrontier(segment))
                        this.layout.anchorFlushAt(segment);
                }
            }
            return this.layout.locateItem(index);
        }
        segmentAtY(y) {
            return this.layout.segmentAtY(y);
        }
        dispose() {
            var _a, _b;
            if (this.resizeRaf !== null)
                cancelAnimationFrame(this.resizeRaf);
            if (this.cardResizeRaf !== null)
                cancelAnimationFrame(this.cardResizeRaf);
            if (this.rebuildRaf !== null)
                cancelAnimationFrame(this.rebuildRaf);
            if (this.tailRaf !== null)
                cancelAnimationFrame(this.tailRaf);
            this.mounted.forEach((el) => { if (el.parentNode)
                el.parentNode.removeChild(el); });
            this.mounted.clear();
            (_a = this.resizeObserver) === null || _a === void 0 ? void 0 : _a.disconnect();
            this.resizeObserver = null;
            this.resizedCards.clear();
            this.pool.length = 0;
            if (this.probe && this.probe.parentNode)
                this.probe.parentNode.removeChild(this.probe);
            this.probe = null;
            (_b = this.heights) === null || _b === void 0 ? void 0 : _b.clear();
            this.heightOrder.length = 0;
            if (this.content && this.content.parentNode) {
                this.content.parentNode.removeChild(this.content);
            }
            this.content = null;
        }
    }
    MasonryRenderer.HEIGHT_CACHE_MAX = 1200;
    /** Ceiling on segments swept for one frame, so coverage can never run away. */
    MasonryRenderer.MAX_WINDOW_SEGMENTS = 12;
    /** Segments before the end kept real, so tail corrections use real heights. */
    MasonryRenderer.TAIL_REAL_SEGMENTS = 4;
    /** Segments prepended at once when the camera scrolls above the chain's base. */
    MasonryRenderer.BACK_CHUNK_SEGMENTS = 8;
    /**
     * Furthest back a single extension will reach. Past this the camera did not
     * scroll there, it JUMPED, and building the block would mean measuring every
     * card in between for content the viewer skipped over — the same trade
     * `maxChainSegments` makes in the forward direction.
     */
    MasonryRenderer.MAX_BACK_SEGMENTS = 64;

    /** Pulls the camera back when empty space appears under the last row. */
    class BoundaryGuardian {
        /**
         * @param deps Viewport size, dataset length, and per-row geometry.
         */
        constructor(deps) {
            var _a, _b, _c, _d;
            this.deps = deps;
            this.overshootThreshold = (_a = deps.overshootThreshold) !== null && _a !== void 0 ? _a : 2;
            this.dampingFactor = (_b = deps.dampingFactor) !== null && _b !== void 0 ? _b : 0.9;
            this.smallDatasetThreshold = (_c = deps.smallDatasetThreshold) !== null && _c !== void 0 ? _c : 1000;
            this.nearBottomThreshold = (_d = deps.nearBottomThreshold) !== null && _d !== void 0 ? _d : 100;
        }
        /**
         * @param element Current camera index.
         * @returns Whether bottom clamping should run (small lists, or near the end).
         */
        shouldClamp(element) {
            const total = this.deps.getTotalElements();
            return total <= this.smallDatasetThreshold || element >= Math.max(0, total - this.nearBottomThreshold);
        }
        /**
         * If the last element's bottom sits above the viewport bottom (i.e. there is
         * empty space below the content), pull the scroll position back up to close
         * the gap. `damping` controls how much of the gap is closed in one call
         * (default {@link dampingFactor} for smooth wheel/touch correction; pass `1`
         * for a full re-anchor, e.g. after a container resize that revealed space).
         *
         * @param element Current camera element.
         * @param offset Current pixel offset into that element.
         * @param damping Fraction of the gap to close (`1` = full). Default 0.9.
         * @returns Corrected `{ element, offset }`, or `null` if no overshoot.
         */
        correctBottomOvershoot(element, offset, damping = this.dampingFactor) {
            const total = this.deps.getTotalElements();
            if (total <= 0) {
                return null;
            }
            const lastElementPosition = this.deps.getElementViewportPosition(total - 1);
            const viewportHeight = this.deps.getViewportHeight();
            const overshootAmount = viewportHeight - lastElementPosition.bottom;
            if (overshootAmount <= this.overshootThreshold) {
                return null;
            }
            let remainingGap = overshootAmount * damping;
            let correctedElement = element;
            let correctedOffset = offset;
            while (remainingGap > 0.5 && (correctedElement > 0 || correctedOffset > 0)) {
                if (correctedOffset >= remainingGap) {
                    correctedOffset -= remainingGap;
                    remainingGap = 0;
                }
                else {
                    remainingGap -= correctedOffset;
                    if (correctedElement > 0) {
                        correctedElement--;
                        correctedOffset = Math.max(0, this.deps.getElementHeight(correctedElement) - 1);
                    }
                    else {
                        correctedOffset = 0;
                        remainingGap = 0;
                    }
                }
            }
            const correctedHeight = Math.max(1, this.deps.getElementHeight(correctedElement));
            correctedOffset = Math.max(0, Math.min(correctedOffset, correctedHeight - 1));
            return { element: correctedElement, offset: correctedOffset };
        }
    }

    /** Delta / jump / percentage → (element, offset). Side effects go through deps. */
    class NavigationEngine {
        /**
         * @param deps Camera, height, and scrollbar callbacks.
         */
        constructor(deps) {
            this.deps = deps;
            // Returned from scroll(); mutated in place — copy if you stash it.
            this._scrollResult = { element: 0, offset: 0 };
            this.totalElements = deps.totalElements;
            this.viewportHeight = deps.viewportHeight;
            this.guardian = new BoundaryGuardian({
                getViewportHeight: () => this.viewportHeight,
                getTotalElements: () => this.totalElements,
                getElementViewportPosition: deps.getElementViewportPosition,
                getElementHeight: deps.getElementHeight
            });
        }
        /**
         * @param totalElements Dataset length.
         * @param viewportHeight Usable height in pixels (header inset already subtracted).
         */
        updateConfig(totalElements, viewportHeight) {
            this.totalElements = totalElements;
            this.viewportHeight = viewportHeight;
        }
        /**
         * Re-anchor to the bottom after a viewport size change. If growing the
         * viewport (e.g. a container resize) revealed empty space below the last
         * element, pull the scroll position up so the content stays anchored to the
         * bottom ("if I'm at the bottom, stay at the bottom on resize"). Applies a
         * full correction. Returns the corrected position, or null if none was needed
         * (i.e. not scrolled near the bottom). Does not touch the scrollbar — the
         * caller re-syncs it after.
         *
         * @param viewportHeight Usable height in pixels after the resize.
         * @returns Corrected `{ element, offset }`, or `null` if no pull was needed.
         */
        reanchorBottom(viewportHeight) {
            if (Number.isFinite(viewportHeight) && viewportHeight > 0) {
                this.viewportHeight = viewportHeight;
            }
            const element = this.deps.getCurrentElement();
            const offset = this.deps.getScrollOffset();
            const correction = this.guardian.correctBottomOvershoot(element, offset, 1);
            if (!correction)
                return null;
            this.deps.updateScrollPosition(correction.element, correction.offset);
            this._scrollResult.element = correction.element;
            this._scrollResult.offset = correction.offset;
            return this._scrollResult;
        }
        /**
         * @param deltaY Pixels to move (positive = down).
         * @param viewportHeight Usable height in pixels.
         * @returns Camera after the move. Same object each call — copy if you stash it.
         */
        scroll(deltaY, viewportHeight) {
            var _a, _b;
            // Validate inputs. NaN/Infinity here would propagate into offset and
            // permanently corrupt scroll state, so refuse them with a no-op result
            // returning the current position.
            if (!Number.isFinite(deltaY) || !Number.isFinite(viewportHeight) || viewportHeight <= 0) {
                this._scrollResult.element = this.deps.getCurrentElement();
                this._scrollResult.offset = this.deps.getScrollOffset();
                return this._scrollResult;
            }
            this.viewportHeight = viewportHeight;
            let element = this.deps.getCurrentElement();
            let offset = this.deps.getScrollOffset() + deltaY;
            while (true) {
                const elementHeight = this.deps.getElementHeight(element);
                if (offset >= elementHeight && element < this.totalElements - 1) {
                    offset -= elementHeight;
                    element++;
                    continue;
                }
                if (offset < 0 && element > 0) {
                    element--;
                    const prevHeight = this.deps.getElementHeight(element);
                    offset = prevHeight + offset;
                    continue;
                }
                break;
            }
            offset = Math.max(0, Math.min(offset, this.deps.getElementHeight(element) - 1));
            if (element >= this.totalElements - 1) {
                element = Math.max(0, this.totalElements - 1);
                const lastHeight = Math.max(1, this.deps.getElementHeight(element));
                offset = Math.max(0, Math.min(offset, lastHeight - 1));
            }
            const lastIndex = this.totalElements - 1;
            if (!this.deps.hasMeasuredHeight(lastIndex)) {
                // First frames: last row isn't measured yet. Only walk to it when it
                // could actually sit in the viewport — a full-dataset walk on every
                // pre-render scroll is O(n) for million-row lists.
                if (lastIndex - element <= 100 && deltaY > 0) {
                    const lastElementPosition = this.deps.getElementViewportPosition(lastIndex);
                    if (lastElementPosition.bottom <= this.viewportHeight) {
                        element = this.deps.getCurrentElement();
                        offset = this.deps.getScrollOffset();
                    }
                }
            }
            else if (element <= 0) {
                element = 0;
                offset = Math.max(0, offset);
            }
            else {
                const elementHeight = this.deps.getElementHeight(element);
                offset = Math.max(0, Math.min(offset, elementHeight - 1));
            }
            const shouldClamp = this.guardian.shouldClamp(element);
            let positionUpdated = false;
            if (shouldClamp && deltaY > 0) {
                // If we've scrolled to or past the measured true bottom, snap to it
                // EXACTLY so the last row sits flush against the viewport bottom. The
                // damped overshoot correction below closes only a fraction of the gap per
                // call, which leaves a residual gap when a wheel/touch burst ends near the
                // bottom (most visible with a top inset / on fractional-scale displays).
                const trueBottom = (_b = (_a = this.deps).getTrueBottomPosition) === null || _b === void 0 ? void 0 : _b.call(_a);
                const atOrPastBottom = !!trueBottom && (element > trueBottom.element ||
                    (element === trueBottom.element && offset >= trueBottom.offset));
                if (atOrPastBottom) {
                    element = trueBottom.element;
                    offset = trueBottom.offset;
                    this.deps.updateScrollPosition(element, offset);
                    positionUpdated = true;
                }
                else {
                    this.deps.updateScrollPosition(element, offset);
                    positionUpdated = true;
                    // trueBottom already tells us we are NOT past the end. The overshoot
                    // walk (getElementViewportPosition(last)) is O(distance) and a no-op
                    // in this branch — skip it. Keep the walk only before the tail has
                    // been measured (first frames / short content).
                    if (!trueBottom) {
                        const correction = this.guardian.correctBottomOvershoot(element, offset);
                        if (correction) {
                            element = correction.element;
                            offset = correction.offset;
                            this.deps.updateScrollPosition(element, offset);
                        }
                    }
                }
            }
            // Snap offset to integer pixels. Sub-pixel drift accumulates over many
            // small wheel/touch deltas (browsers commonly emit fractional deltaY) and
            // eventually produces visible mis-alignment with the scrollbar thumb. The
            // outer position math has already clamped against the element height so
            // rounding cannot push past the boundary here.
            offset = Math.round(offset);
            const finalHeight = Math.max(1, this.deps.getElementHeight(element));
            if (offset >= finalHeight) {
                offset = finalHeight - 1;
            }
            if (offset < 0)
                offset = 0;
            if (!positionUpdated) {
                this.deps.updateScrollPosition(element, offset);
            }
            this.deps.syncScrollbar();
            // Same _scrollResult instance every call.
            this._scrollResult.element = element;
            this._scrollResult.offset = offset;
            return this._scrollResult;
        }
        /**
         * @param percentage `0` = top, `100` = bottom. Clamped.
         * @returns Camera after the jump.
         */
        handleScrollPercentage(percentage) {
            if (!Number.isFinite(percentage)) {
                return { element: this.deps.getCurrentElement(), offset: this.deps.getScrollOffset() };
            }
            const clamped = Math.max(0, Math.min(100, percentage));
            if (clamped >= 99.99) {
                this.deps.updateScrollPosition(this.totalElements - 1, 0);
                this.scroll(Number.MAX_SAFE_INTEGER, this.viewportHeight);
                // scroll() corrects the bottom overshoot with smooth damping (~0.9), which
                // leaves a fraction of the gap on a one-shot jump. Finish with a FULL
                // re-anchor so the last row lands flush against the viewport bottom.
                const anchored = this.reanchorBottom(this.viewportHeight);
                if (anchored)
                    return anchored;
                this._scrollResult.element = this.deps.getCurrentElement();
                this._scrollResult.offset = this.deps.getScrollOffset();
                return this._scrollResult;
            }
            if (clamped <= 0.01) {
                return this.jumpToElement(0);
            }
            const targetElement = Math.floor((clamped / 100) * (this.totalElements - 1));
            const currentElement = this.deps.getCurrentElement();
            if (targetElement === currentElement) {
                return { element: currentElement, offset: this.deps.getScrollOffset() };
            }
            const elementDelta = targetElement - currentElement;
            const estimatedHeight = this.deps.getElementHeight(currentElement);
            const approximatePixelDelta = elementDelta * estimatedHeight;
            return this.scroll(approximatePixelDelta, this.viewportHeight);
        }
        /**
         * @param elementIndex Target index. Clamped. `Number.MAX_SAFE_INTEGER` = end.
         * @returns Camera after the jump (offset 0, or true-bottom if past the last visible row).
         */
        jumpToElement(elementIndex) {
            var _a, _b;
            // Validate input - non-finite values are programmer errors that would
            // otherwise silently no-op.
            if (!Number.isFinite(elementIndex)) {
                return { element: this.deps.getCurrentElement(), offset: this.deps.getScrollOffset() };
            }
            // Clamp instead of silently returning current position; surface the clamp
            // so consumers can detect bad indices in development.
            const total = this.totalElements;
            if (total <= 0) {
                return { element: 0, offset: 0 };
            }
            const target = Math.max(0, Math.min(Math.floor(elementIndex), total - 1));
            if (target !== elementIndex && elementIndex !== Number.MAX_SAFE_INTEGER) {
                // MAX_SAFE_INTEGER is the documented "jump to end" sentinel used by the
                // keyboard controller, so suppress the warning for that case only.
                console.warn(`CeriousScroll.jumpToElement: index ${elementIndex} out of range (0..${total - 1}); clamped to ${target}`);
            }
            const trueBottom = (_b = (_a = this.deps).getTrueBottomPosition) === null || _b === void 0 ? void 0 : _b.call(_a);
            if (trueBottom && target >= trueBottom.element) {
                this.deps.updateScrollPosition(trueBottom.element, trueBottom.offset);
                this.deps.requestDisplayUpdate();
                this.deps.syncScrollbar();
                return { element: trueBottom.element, offset: trueBottom.offset };
            }
            this.deps.updateScrollPosition(target, 0);
            this.deps.requestDisplayUpdate();
            this.deps.syncScrollbar();
            return { element: target, offset: 0 };
        }
        /**
         * @param elementIndex Target index. Clamped.
         * @param offset Pixels into that row. Clamped to `[0, height - 1]`.
         * @param skipScrollbarSync When true, do not write the native strip (thumb-drag path).
         * @returns Camera after the jump.
         */
        jumpToPosition(elementIndex, offset, skipScrollbarSync = false) {
            if (!Number.isFinite(elementIndex) || !Number.isFinite(offset)) {
                return { element: this.deps.getCurrentElement(), offset: this.deps.getScrollOffset() };
            }
            let element = Math.max(0, Math.min(Math.floor(elementIndex), this.totalElements - 1));
            const elementHeight = Math.max(1, this.deps.getElementHeight(element));
            // Snap to integer pixels for consistency with scroll(); see comment there.
            let clampedOffset = Math.max(0, Math.min(Math.round(offset), elementHeight - 1));
            this.deps.updateScrollPosition(element, clampedOffset);
            this.deps.requestDisplayUpdate();
            if (this.guardian.shouldClamp(element)) {
                this.deps.requestDisplayUpdate();
                const correction = this.guardian.correctBottomOvershoot(element, clampedOffset);
                if (correction) {
                    element = correction.element;
                    clampedOffset = correction.offset;
                    this.deps.updateScrollPosition(element, clampedOffset);
                    this.deps.requestDisplayUpdate();
                }
            }
            if (!skipScrollbarSync) {
                this.deps.syncScrollbar();
            }
            return { element, offset: clampedOffset };
        }
        /** Camera to element 0, offset 0. */
        reset() {
            this.deps.updateScrollPosition(0, 0);
            this.deps.requestDisplayUpdate();
            this.deps.syncScrollbar();
        }
    }

    /** Derived display fields (visible range, percentage, virtual-track top). */
    class ViewportStateCalculator {
        /**
         * @param deps Live getters for camera, heights, and viewport size.
         */
        constructor(deps) {
            this.deps = deps;
        }
        /**
         * @returns Visible range (plus overscan), scroll percentage, and virtual-track top.
         */
        calculate() {
            const totalElements = Math.max(0, this.deps.totalElements());
            const currentElement = Math.min(Math.max(this.deps.getCurrentElement(), 0), Math.max(totalElements - 1, 0));
            const scrollOffset = this.deps.getScrollOffset();
            const windowHeight = Math.max(0, this.deps.getWindowHeight());
            let startElement = currentElement;
            let offset = scrollOffset;
            let accHeight = -offset;
            let endElement = startElement;
            while (endElement < totalElements && accHeight < windowHeight) {
                accHeight += this.deps.getElementHeight(endElement);
                endElement++;
            }
            endElement = Math.max(0, Math.min(totalElements - 1, endElement - 1));
            let bufferedEndElement = Math.min(totalElements - 1, endElement + this.deps.bufferSize);
            const elementsFromEnd = Math.max(0, totalElements - 1 - currentElement);
            if (elementsFromEnd <= this.deps.nearEndThreshold) {
                bufferedEndElement = Math.max(0, totalElements - 1);
            }
            const scrollPercentage = this.deps.calculateScrollPercentage();
            const trackRange = Math.max(this.deps.virtualTrackHeight - windowHeight, 0);
            const viewportTop = (scrollPercentage / 100) * trackRange;
            return {
                startElement,
                endElement: bufferedEndElement,
                scrollPercentage,
                viewportTop
            };
        }
    }

    /**
     * Wheel → scroll. Large/line/page deltas apply immediately (mouse notches).
     * Small pixel deltas are treated as trackpad and eased if `smooth` is on.
     */
    /**
     * Minimum per-event pixel delta we treat as a discrete mouse-wheel notch.
     * Mouse wheels emit large, quantized steps (commonly ~100-120px/notch);
     * trackpads emit small, high-frequency, often fractional pixel deltas.
     */
    const MOUSE_WHEEL_NOTCH_MIN_PX = 100;
    /**
     * Heuristic: is this wheel event from a trackpad (continuous, inertial) rather
     * than a discrete mouse-wheel notch? There is no definitive browser API, so we
     * classify by the *magnitude* of the pixel delta:
     *
     * - `deltaMode` of line/page granularity is always a mouse wheel.
     * - In pixel mode, only SMALL deltas are trackpad-like (worth easing); a large
     *   step is a wheel notch and must apply instantly, like the OS.
     *
     * Magnitude is checked first on purpose: some mice (free-spin / "hyperscroll"
     * wheels) emit large *fractional* pixel deltas, so a fractional value is NOT a
     * reliable trackpad signal — a 500px step is a wheel notch whether or not it is
     * a round number. Inertial smoothing must only apply to trackpads; a mouse wheel
     * that keeps gliding after the user stops feels wrong, so we err toward "wheel".
     */
    function isLikelyTrackpad(e, notchThresholdPx) {
        if (e.deltaMode !== 0)
            return false; // DOM_DELTA_LINE / _PAGE => wheel
        return Math.abs(e.deltaY) < notchThresholdPx; // small px => trackpad, large => wheel
    }
    class WheelController {
        constructor(deps) {
            this.deps = deps;
            // Mutated in place and passed as CustomEvent.detail.
            this._eventDetail = {
                percentage: 0,
                currentElement: 0,
                scrollOffset: 0,
                result: { element: 0, offset: 0 }
            };
        }
        /**
         * @param container Host to listen on (`{ passive: false }`).
         * @param onScroll After each applied delta.
         * @param wheelOptions Optional overrides.
         * @returns Detach function.
         */
        /**
         * @param nativeProxy Whether a native surface is mounted around `container`
         *   and will be doing the scrolling. Not an option: the engine decides, and
         *   there is nothing for a caller to choose between.
         */
        attach(container, onScroll, wheelOptions, nativeProxy = false) {
            const options = {
                enabled: (wheelOptions === null || wheelOptions === void 0 ? void 0 : wheelOptions.enabled) !== false,
                emitViewportChangeEvent: (wheelOptions === null || wheelOptions === void 0 ? void 0 : wheelOptions.emitViewportChangeEvent) !== false,
                coalesceViewportChangeEvent: (wheelOptions === null || wheelOptions === void 0 ? void 0 : wheelOptions.coalesceViewportChangeEvent) === true,
                smooth: (wheelOptions === null || wheelOptions === void 0 ? void 0 : wheelOptions.smooth) !== false,
                notchThresholdPx: typeof (wheelOptions === null || wheelOptions === void 0 ? void 0 : wheelOptions.notchThresholdPx) === 'number' && wheelOptions.notchThresholdPx > 0
                    ? wheelOptions.notchThresholdPx
                    : MOUSE_WHEEL_NOTCH_MIN_PX,
                smoothFactor: typeof (wheelOptions === null || wheelOptions === void 0 ? void 0 : wheelOptions.smoothFactor) === 'number' && wheelOptions.smoothFactor > 0 && wheelOptions.smoothFactor <= 1
                    ? wheelOptions.smoothFactor
                    : 0.22,
            };
            if (!options.enabled) {
                return () => { };
            }
            if (nativeProxy) {
                return this.attachHorizontalOnly(container);
            }
            let rafId = null;
            let pendingPercentage = 0;
            let pendingCurrentElement = 0;
            let pendingScrollOffset = 0;
            let pendingResult = { element: 0, offset: 0 };
            let cachedInner = null;
            const getInner = () => {
                if (cachedInner && cachedInner.isConnected)
                    return cachedInner;
                cachedInner = container.querySelector('[data-cerious-scroll-content]');
                return cachedInner;
            };
            const dispatchViewportChange = () => {
                rafId = null;
                if (!options.emitViewportChangeEvent)
                    return;
                // Reuse _eventDetail; listeners must not retain it across events.
                this._eventDetail.percentage = pendingPercentage;
                this._eventDetail.currentElement = pendingCurrentElement;
                this._eventDetail.scrollOffset = pendingScrollOffset;
                this._eventDetail.result = pendingResult;
                container.dispatchEvent(new CustomEvent('cerious-viewport-change', {
                    detail: this._eventDetail,
                }));
            };
            const handleWheel = (event) => {
                var _a;
                // Resolve the inner content element once per gesture. Framework wrappers
                // (Vue/React/Angular) put rows into [data-cerious-scroll-content] and
                // that's where overflow-x: auto lives for wide content (e.g.
                // spreadsheet). When present, horizontal wheel deltas are forwarded
                // to its scrollLeft so trackpad two-finger sideways and shift+wheel
                // work; if the gesture is dominantly horizontal we skip the vertical
                // engine scroll. We also use the inner element's clientHeight as the
                // viewport so the engine accounts for the h-scrollbar gutter.
                const inner = getInner();
                const dx = event.deltaX;
                const dy = event.deltaY;
                const hTarget = inner && inner.scrollWidth > inner.clientWidth
                    ? inner
                    : (container.scrollWidth > container.clientWidth ? container : null);
                if (hTarget && dx !== 0) {
                    hTarget.scrollLeft += dx;
                    if (Math.abs(dx) > Math.abs(dy)) {
                        event.preventDefault();
                        return;
                    }
                }
                event.preventDefault();
                const innerH = (_a = inner === null || inner === void 0 ? void 0 : inner.clientHeight) !== null && _a !== void 0 ? _a : 0;
                const viewportHeight = innerH > 0 ? innerH : (container.clientHeight || container.offsetHeight);
                // Apply inertial smoothing ONLY to trackpad input. Discrete mouse-wheel
                // notches go through the instant path so they stop the moment the wheel
                // stops — matching native OS behavior — even when `smooth` is enabled.
                if (!options.smooth || !isLikelyTrackpad(event, options.notchThresholdPx)) {
                    const result = this.deps.scroll(dy, viewportHeight);
                    emitChange(result);
                    onScroll === null || onScroll === void 0 ? void 0 : onScroll(result);
                    return;
                }
                // Smooth path: accumulate the delta into `targetDy` and let the
                // animation loop ease `smoothedDy` toward it (see the loop below). A
                // wheel notch arrives as one large event (~100px); applying it in a
                // single paint reads as a snap, so we spread it over a short exponential
                // follow that matches the feel of native inertial scrolling. Continuous
                // spinning or trackpad flicking simply keeps growing the target, and the
                // follow tracks it without stalling mid-gesture or hopping at the end.
                //
                // Boundary short-circuit: if the engine is already pinned at the top and
                // the delta pushes further up, drop it so held-at-edge input can't build
                // a queue that lurches when the user reverses direction.
                const atTop = this.deps.getCurrentElement() === 0 && this.deps.getScrollOffset() === 0;
                if (atTop && dy < 0 && targetDy <= 0) {
                    return;
                }
                targetDy += dy;
                smoothViewportHeight = viewportHeight;
                // Start the loop on a fresh gesture. Seed `lastFrameTime` to now so the
                // first frame's dt is the real inter-frame gap (not a huge value), and
                // deliberately do NOT touch the clock on subsequent events — that is what
                // lets continuous input accumulate without resetting the follow's
                // progress (the old timeline reset stalled motion until input stopped,
                // then released it as one burst).
                if (smoothRafId == null) {
                    lastFrameTime = performance.now();
                    smoothRafId = requestAnimationFrame(animateSmoothScroll);
                }
            };
            // Smooth-scroll state. We model the rendered position as a value that
            // exponentially chases an accumulating target — the principle behind native
            // inertial scrolling: each frame closes a fixed fraction of the remaining
            // gap, scaled by real elapsed time so the feel is frame-rate independent.
            // New deltas grow the target without resetting any clock, so continuous
            // input tracks closely and, when input stops, the position eases onto the
            // target and snaps the sub-pixel remainder — no end-of-scroll jump.
            let targetDy = 0; // accumulated wheel distance to cover (float px)
            let smoothedDy = 0; // current eased position (float px)
            let emittedDy = 0; // whole px already handed to the engine
            let lastFrameTime = 0; // timestamp of the previous animation frame
            let smoothViewportHeight = 0;
            let smoothRafId = null;
            const FRAME_MS = 1000 / 60;
            // Time constant (ms) of the exponential follow, derived from the public
            // `smoothFactor` (treated as its 60fps-equivalent per-frame catch-up
            // fraction) so the option keeps its meaning while motion stays frame-rate
            // independent. smoothFactor >= 1 ⇒ tau 0 ⇒ instant follow.
            const tau = options.smoothFactor >= 1 ? 0 : -FRAME_MS / Math.log(1 - options.smoothFactor);
            // Below this remaining gap the motion is visually complete: snap and stop
            // so the exponential tail can't dribble sub-pixel steps for hundreds of ms.
            const SETTLE_PX = 0.5;
            // Clamp the per-frame timestep so returning to a backgrounded tab (a single
            // huge dt) can't collapse the whole glide into one jump.
            const MAX_FRAME_MS = 50;
            const emitChange = (result) => {
                if (options.emitViewportChangeEvent) {
                    if (options.coalesceViewportChangeEvent) {
                        pendingPercentage = this.deps.calculateScrollPercentage();
                        pendingCurrentElement = this.deps.getCurrentElement();
                        pendingScrollOffset = this.deps.getScrollOffset();
                        pendingResult = result;
                        if (rafId == null) {
                            rafId = requestAnimationFrame(dispatchViewportChange);
                        }
                    }
                    else {
                        this._eventDetail.percentage = this.deps.calculateScrollPercentage();
                        this._eventDetail.currentElement = this.deps.getCurrentElement();
                        this._eventDetail.scrollOffset = this.deps.getScrollOffset();
                        this._eventDetail.result = result;
                        container.dispatchEvent(new CustomEvent('cerious-viewport-change', {
                            detail: this._eventDetail,
                        }));
                    }
                }
            };
            const animateSmoothScroll = () => {
                smoothRafId = null;
                const now = performance.now();
                let dt = now - lastFrameTime;
                lastFrameTime = now;
                if (!(dt > 0))
                    dt = FRAME_MS; // first frame / clock anomalies
                if (dt > MAX_FRAME_MS)
                    dt = MAX_FRAME_MS;
                const gap = targetDy - smoothedDy;
                // Frame-rate-independent exponential approach: close `alpha` of the gap
                // this frame, where alpha rises toward 1 with elapsed time. Fast input
                // keeps the gap large so steps stay big (tracks the finger/notch); when
                // input stops the gap decays smoothly to zero.
                if (Math.abs(gap) <= SETTLE_PX) {
                    smoothedDy = targetDy; // snap the imperceptible remainder
                }
                else {
                    const alpha = tau > 0 ? 1 - Math.exp(-dt / tau) : 1;
                    smoothedDy += gap * alpha;
                }
                // Hand the engine the whole-pixel delta accumulated since the last frame.
                // Math.round (not floor/ceil) keeps the tail monotonic instead of
                // stranding frames at 0 then landing a 1px correction.
                const intStep = Math.round(smoothedDy) - emittedDy;
                if (intStep !== 0) {
                    const prevElement = this.deps.getCurrentElement();
                    const prevOffset = this.deps.getScrollOffset();
                    const result = this.deps.scroll(intStep, smoothViewportHeight);
                    emittedDy += intStep;
                    emitChange(result);
                    onScroll === null || onScroll === void 0 ? void 0 : onScroll(result);
                    // Boundary clamp: the engine refused to move (pinned at an edge), so
                    // wipe the gesture. A residual target would otherwise keep replaying
                    // against the edge and then lurch when the user reverses direction.
                    if (this.deps.getCurrentElement() === prevElement &&
                        this.deps.getScrollOffset() === prevOffset) {
                        targetDy = 0;
                        smoothedDy = 0;
                        emittedDy = 0;
                        return; // loop stops; the next wheel event restarts it
                    }
                }
                if (Math.abs(targetDy - smoothedDy) > SETTLE_PX) {
                    smoothRafId = requestAnimationFrame(animateSmoothScroll);
                }
                else {
                    // Settled on target — reset the gesture baseline for the next one.
                    targetDy = 0;
                    smoothedDy = 0;
                    emittedDy = 0;
                }
            };
            container.addEventListener('wheel', handleWheel, { passive: false });
            return () => {
                if (rafId != null) {
                    cancelAnimationFrame(rafId);
                    rafId = null;
                }
                if (smoothRafId != null) {
                    cancelAnimationFrame(smoothRafId);
                    smoothRafId = null;
                }
                targetDy = 0;
                smoothedDy = 0;
                emittedDy = 0;
                container.removeEventListener('wheel', handleWheel);
            };
        }
        /**
         * Hand the vertical axis to the browser.
         *
         * The engine's own smoothing is not merely bypassed here, it is REPLACED: the
         * wheel now scrolls the native proxy surface, and the touch controller
         * forwards that surface's scrollTop deltas. So this listener must not call
         * `preventDefault` on a vertical gesture, or there is nothing left to scroll.
         *
         * Horizontal still belongs to us. Wide content (a spreadsheet, a table) puts
         * `overflow-x` on the inner content element, which is INSIDE the proxy, and
         * the proxy itself is `overflow-x: hidden` — so a sideways gesture has no
         * native target and has to be forwarded by hand exactly as it is in manual
         * mode. Only a horizontal-dominant gesture is consumed; anything with more
         * vertical than horizontal travel is left alone so a diagonal trackpad swipe
         * still scrolls the list.
         */
        attachHorizontalOnly(container) {
            let cachedInner = null;
            const getInner = () => {
                if (cachedInner && cachedInner.isConnected)
                    return cachedInner;
                cachedInner = container.querySelector('[data-cerious-scroll-content]');
                return cachedInner;
            };
            const handleWheel = (event) => {
                const dx = event.deltaX;
                if (dx === 0)
                    return;
                const inner = getInner();
                const hTarget = inner && inner.scrollWidth > inner.clientWidth
                    ? inner
                    : (container.scrollWidth > container.clientWidth ? container : null);
                if (!hTarget)
                    return;
                hTarget.scrollLeft += dx;
                // Claim the event only when the gesture is actually sideways, so the
                // vertical component of a diagonal swipe still reaches the proxy.
                if (Math.abs(dx) > Math.abs(event.deltaY))
                    event.preventDefault();
            };
            container.addEventListener('wheel', handleWheel, { passive: false });
            return () => container.removeEventListener('wheel', handleWheel);
        }
    }

    /**
     * Touch → scroll. Vertical engine motion is coalesced to one rAF; velocity
     * is sampled every move. Horizontal overflow is native scrollLeft.
     */
    class TouchController {
        constructor(deps) {
            this.deps = deps;
            // Mutated in place and passed as CustomEvent.detail.
            this._eventDetail = {
                percentage: 0,
                currentElement: 0,
                scrollOffset: 0,
                result: { element: 0, offset: 0 }
            };
        }
        /**
         * @param container Host to listen on (`{ passive: false, capture: true }`).
         * @param onScroll After each applied (or flushed) delta.
         * @param options Optional overrides.
         * @returns Detach function.
         */
        attach(container, onScroll, options) {
            const opts = Object.assign({ enableMomentum: true, momentumFriction: 0.95, momentumThreshold: 0.1, axisLockThreshold: 8 }, options);
            const getHorizontalTarget = opts.getHorizontalScrollTarget;
            // Auto-fallback: if no resolver was supplied, look for a horizontally-
            // scrollable element to use as the touch swipe target. Prefer the inner
            // [data-cerious-scroll-content] (where framework wrappers put rows and
            // typically apply overflow-x: auto for wide content), then fall back to
            // the container itself.
            const resolveHorizontalTarget = () => {
                const explicit = getHorizontalTarget === null || getHorizontalTarget === void 0 ? void 0 : getHorizontalTarget();
                if (explicit)
                    return explicit;
                const inner = getInner();
                if (inner && inner.scrollWidth > inner.clientWidth)
                    return inner;
                if (container.scrollWidth > container.clientWidth)
                    return container;
                return null;
            };
            const originalTouchAction = container.style.touchAction;
            const styleId = 'cerious-touch-action-style';
            let addedStyleElement = null;
            let cachedInner = null;
            const getInner = () => {
                if (cachedInner && cachedInner.isConnected)
                    return cachedInner;
                cachedInner = container.querySelector('[data-cerious-scroll-content]');
                return cachedInner;
            };
            const raf = (cb) => {
                if (typeof requestAnimationFrame === 'function')
                    return requestAnimationFrame(cb);
                return setTimeout(cb, 16);
            };
            const caf = (handle) => {
                if (typeof cancelAnimationFrame === 'function')
                    cancelAnimationFrame(handle);
                else
                    clearTimeout(handle);
            };
            if (!document.getElementById(styleId)) {
                addedStyleElement = document.createElement('style');
                addedStyleElement.id = styleId;
                addedStyleElement.textContent = `
        [data-cerious-touch] * {
          touch-action: none !important;
        }
      `;
                document.head.appendChild(addedStyleElement);
            }
            container.style.touchAction = 'none';
            container.setAttribute('data-cerious-touch', 'true');
            let lastTouchY = 0;
            let lastTouchTime = 0;
            // Velocity in the currently-locked axis (px/ms). Sign matches the
            // direction the engine/scrollLeft moves (drag finger up → positive vertical;
            // drag finger left → positive horizontal).
            let velocity = 0;
            let momentumAnimationId = null;
            let activeTouchId = null;
            // Coalesce vertical engine scroll + render to one rAF, matching the native
            // scrollbar path. Touchmove can fire 2–4× per frame on 120/240Hz displays;
            // applying every event did that many full viewport renders. Deltas are
            // accumulated so the finger distance is preserved; touchend flushes so
            // momentum starts from the final position.
            let pendingDeltaY = 0;
            let pendingViewportHeight = 0;
            let scrollRafId = null;
            // Axis-lock state. Until the gesture exceeds `axisLockThreshold` we don't
            // know whether the user intends a vertical or horizontal scroll. We
            // accumulate raw deltas from the touchstart point and lock once one
            // dimension wins, so subsequent moves are routed to the right consumer.
            let startTouchX = 0;
            let startTouchY = 0;
            let lastTouchX = 0;
            let axis = 'unknown';
            let horizontalTarget = null;
            // Velocity tracking via fixed-size ring buffer to avoid Array.shift() in
            // the hot touchmove path (O(n) per move) and unbounded growth on slow
            // devices.
            const VELOCITY_SAMPLE_MS = 100; // Track last 100ms of movement
            const VELOCITY_RING_SIZE = 16; // Plenty for 100ms even at 240Hz
            const velocityRingValues = new Float64Array(VELOCITY_RING_SIZE);
            const velocityRingTimes = new Float64Array(VELOCITY_RING_SIZE);
            let velocityRingHead = 0; // Next write position
            let velocityRingCount = 0; // Number of valid samples (<= ring size)
            const resetVelocityHistory = () => {
                velocityRingHead = 0;
                velocityRingCount = 0;
            };
            const recordVelocitySample = (velocity, time) => {
                velocityRingValues[velocityRingHead] = velocity;
                velocityRingTimes[velocityRingHead] = time;
                velocityRingHead = (velocityRingHead + 1) % VELOCITY_RING_SIZE;
                if (velocityRingCount < VELOCITY_RING_SIZE)
                    velocityRingCount++;
            };
            const getViewportHeight = () => {
                var _a;
                const inner = getInner();
                const h = (_a = inner === null || inner === void 0 ? void 0 : inner.clientHeight) !== null && _a !== void 0 ? _a : 0;
                return h > 0 ? h : (container.clientHeight || container.offsetHeight);
            };
            const emitVerticalScroll = (result) => {
                this._eventDetail.percentage = this.deps.calculateScrollPercentage();
                this._eventDetail.currentElement = this.deps.getCurrentElement();
                this._eventDetail.scrollOffset = this.deps.getScrollOffset();
                this._eventDetail.result = result;
                container.dispatchEvent(new CustomEvent('cerious-viewport-change', {
                    detail: this._eventDetail
                }));
                onScroll === null || onScroll === void 0 ? void 0 : onScroll(result);
            };
            const flushPendingScroll = () => {
                scrollRafId = null;
                const dy = pendingDeltaY;
                pendingDeltaY = 0;
                if (dy === 0)
                    return;
                const result = this.deps.scroll(dy, pendingViewportHeight);
                emitVerticalScroll(result);
            };
            const handleTouchStart = (event) => {
                if (this.isScrollbarTouch(event.target)) {
                    return;
                }
                if (event.cancelable) {
                    event.preventDefault();
                }
                event.stopPropagation();
                if (momentumAnimationId !== null) {
                    caf(momentumAnimationId);
                    momentumAnimationId = null;
                }
                if (scrollRafId !== null) {
                    caf(scrollRafId);
                    scrollRafId = null;
                }
                pendingDeltaY = 0;
                if (activeTouchId === null && event.touches.length > 0) {
                    const touch = event.touches[0];
                    activeTouchId = touch.identifier;
                    lastTouchY = touch.clientY;
                    lastTouchX = touch.clientX;
                    startTouchX = touch.clientX;
                    startTouchY = touch.clientY;
                    axis = 'unknown';
                    horizontalTarget = resolveHorizontalTarget();
                    lastTouchTime = Date.now();
                    velocity = 0;
                    resetVelocityHistory();
                }
            };
            const handleTouchMove = (event) => {
                if (this.isScrollbarTouch(event.target)) {
                    return;
                }
                if (event.cancelable) {
                    event.preventDefault();
                }
                event.stopPropagation();
                let touch = null;
                for (let i = 0; i < event.touches.length; i++) {
                    if (event.touches[i].identifier === activeTouchId) {
                        touch = event.touches[i];
                        break;
                    }
                }
                if (!touch) {
                    return;
                }
                const currentY = touch.clientY;
                const currentX = touch.clientX;
                const currentTime = Date.now();
                const deltaY = lastTouchY - currentY;
                const deltaX = lastTouchX - currentX;
                const deltaTime = currentTime - lastTouchTime;
                // Axis lock: once the gesture leaves the dead-zone, pick the dominant
                // direction and stay with it for the rest of the gesture.
                if (axis === 'unknown') {
                    const totalDx = Math.abs(currentX - startTouchX);
                    const totalDy = Math.abs(currentY - startTouchY);
                    if (Math.max(totalDx, totalDy) >= opts.axisLockThreshold) {
                        if (totalDx > totalDy && horizontalTarget) {
                            axis = 'horizontal';
                        }
                        else {
                            axis = 'vertical';
                        }
                    }
                }
                if (axis === 'horizontal' && horizontalTarget) {
                    // Forward horizontal delta to the native overflow-x scroller and
                    // track velocity so we can run momentum on touchend (matches the
                    // iOS-style flick behavior used for vertical scrolling).
                    if (deltaX !== 0) {
                        horizontalTarget.scrollLeft += deltaX;
                    }
                    if (deltaTime > 0) {
                        recordVelocitySample(deltaX / deltaTime, currentTime);
                        let totalWeight = 0;
                        let weightedSum = 0;
                        let weight = velocityRingCount;
                        for (let i = 0; i < velocityRingCount; i++) {
                            const idx = (velocityRingHead - 1 - i + VELOCITY_RING_SIZE) % VELOCITY_RING_SIZE;
                            const sampleTime = velocityRingTimes[idx];
                            if (currentTime - sampleTime > VELOCITY_SAMPLE_MS)
                                break;
                            weightedSum += velocityRingValues[idx] * weight;
                            totalWeight += weight;
                            weight--;
                        }
                        velocity = totalWeight > 0 ? weightedSum / totalWeight : 0;
                    }
                    lastTouchY = currentY;
                    lastTouchX = currentX;
                    lastTouchTime = currentTime;
                    return;
                }
                // axis === 'vertical' (or still unknown but trending vertical): run the
                // existing velocity tracking + vertical engine scroll.
                if (deltaTime > 0) {
                    const instantVelocity = deltaY / deltaTime;
                    // Record into ring buffer (O(1)).
                    recordVelocitySample(instantVelocity, currentTime);
                    // Compute time-weighted average over the trailing window. We iterate
                    // newest-to-oldest (so we can early-exit when samples fall outside
                    // the window) and weight by recency.
                    let totalWeight = 0;
                    let weightedSum = 0;
                    let weight = velocityRingCount; // newest gets highest weight
                    for (let i = 0; i < velocityRingCount; i++) {
                        const idx = (velocityRingHead - 1 - i + VELOCITY_RING_SIZE) % VELOCITY_RING_SIZE;
                        const sampleTime = velocityRingTimes[idx];
                        if (currentTime - sampleTime > VELOCITY_SAMPLE_MS)
                            break;
                        weightedSum += velocityRingValues[idx] * weight;
                        totalWeight += weight;
                        weight--;
                    }
                    velocity = totalWeight > 0 ? weightedSum / totalWeight : 0;
                }
                if (Math.abs(deltaY) > 0) {
                    pendingDeltaY += deltaY;
                    pendingViewportHeight = getViewportHeight();
                    if (scrollRafId === null) {
                        scrollRafId = raf(flushPendingScroll);
                    }
                }
                lastTouchY = currentY;
                lastTouchX = currentX;
                lastTouchTime = currentTime;
            };
            const handleTouchEnd = (event) => {
                var _a;
                if (this.isScrollbarTouch(event.target)) {
                    return;
                }
                if (event.cancelable) {
                    event.preventDefault();
                }
                event.stopPropagation();
                let isTrackedTouchEnding = false;
                for (let i = 0; i < event.changedTouches.length; i++) {
                    if (event.changedTouches[i].identifier === activeTouchId) {
                        isTrackedTouchEnding = true;
                        break;
                    }
                }
                if (!isTrackedTouchEnding) {
                    return;
                }
                if ('releasePointerCapture' in container && event.pointerId !== undefined) {
                    try {
                        container.releasePointerCapture(event.pointerId);
                    }
                    catch (_b) {
                        // Ignore release failures (already released or not captured)
                    }
                }
                // Apply any coalesced move before momentum so the flick starts from the
                // finger's final position rather than a frame behind.
                if (scrollRafId !== null) {
                    caf(scrollRafId);
                    flushPendingScroll();
                }
                else if (pendingDeltaY !== 0) {
                    flushPendingScroll();
                }
                activeTouchId = null;
                onScroll === null || onScroll === void 0 ? void 0 : onScroll({ element: this.deps.getCurrentElement(), offset: this.deps.getScrollOffset() });
                const lockedAxis = axis;
                const momentumTarget = lockedAxis === 'horizontal' ? horizontalTarget : null;
                if (opts.enableMomentum && Math.abs(velocity) >= ((_a = opts.momentumThreshold) !== null && _a !== void 0 ? _a : 0) &&
                    (lockedAxis === 'vertical' || (lockedAxis === 'horizontal' && momentumTarget))) {
                    // iOS-style momentum: use exponential decay with cubic-bezier easing
                    const initialVelocity = velocity;
                    const startTime = performance.now();
                    let lastFrameTime = startTime;
                    // Momentum duration scales with initial velocity (faster swipe = longer momentum)
                    const maxDuration = 2000; // Maximum 2 seconds of momentum
                    const minDuration = 300; // Minimum 300ms
                    const duration = Math.min(maxDuration, minDuration + Math.abs(initialVelocity) * 200);
                    const applyMomentum = () => {
                        const now = performance.now();
                        const elapsed = now - startTime;
                        const progress = Math.min(elapsed / duration, 1);
                        // Cubic-bezier easing out (0.25, 0.46, 0.45, 0.94) - iOS-like deceleration
                        const easeOutCubic = (t) => {
                            const t1 = t - 1;
                            return t1 * t1 * t1 + 1;
                        };
                        // Apply easing - velocity decreases smoothly following the curve
                        const easedProgress = easeOutCubic(progress);
                        const remainingVelocity = 1 - easedProgress;
                        const currentVelocity = initialVelocity * remainingVelocity;
                        if (progress >= 1 || Math.abs(currentVelocity) < 0.01) {
                            momentumAnimationId = null;
                            return;
                        }
                        // Use the actual time since the last frame so momentum stays
                        // visually consistent across 60Hz / 120Hz / 240Hz displays and
                        // under main-thread contention. Clamp to a sane range to avoid
                        // huge first-frame deltas after long pauses.
                        const rawFrameTime = now - lastFrameTime;
                        const frameTime = rawFrameTime > 0 && rawFrameTime < 100 ? rawFrameTime : 16;
                        lastFrameTime = now;
                        const delta = currentVelocity * frameTime;
                        if (lockedAxis === 'horizontal' && momentumTarget) {
                            // Stop momentum once we hit a horizontal boundary so it doesn't
                            // burn frames trying to scroll past the edge.
                            const before = momentumTarget.scrollLeft;
                            momentumTarget.scrollLeft = before + delta;
                            if (momentumTarget.scrollLeft === before) {
                                momentumAnimationId = null;
                                return;
                            }
                            momentumAnimationId = requestAnimationFrame(applyMomentum);
                            return;
                        }
                        const result = this.deps.scroll(delta, getViewportHeight());
                        // Reuse eventDetail; listeners must not retain it across events.
                        this._eventDetail.percentage = this.deps.calculateScrollPercentage();
                        this._eventDetail.currentElement = this.deps.getCurrentElement();
                        this._eventDetail.scrollOffset = this.deps.getScrollOffset();
                        this._eventDetail.result = result;
                        container.dispatchEvent(new CustomEvent('cerious-viewport-change', {
                            detail: this._eventDetail
                        }));
                        onScroll === null || onScroll === void 0 ? void 0 : onScroll(result);
                        momentumAnimationId = requestAnimationFrame(applyMomentum);
                    };
                    momentumAnimationId = requestAnimationFrame(applyMomentum);
                }
            };
            const handleTouchCancel = () => {
                activeTouchId = null;
                if (scrollRafId !== null) {
                    caf(scrollRafId);
                    scrollRafId = null;
                }
                pendingDeltaY = 0;
                onScroll === null || onScroll === void 0 ? void 0 : onScroll({ element: this.deps.getCurrentElement(), offset: this.deps.getScrollOffset() });
                if (momentumAnimationId !== null) {
                    caf(momentumAnimationId);
                    momentumAnimationId = null;
                }
            };
            container.addEventListener('touchstart', handleTouchStart, { passive: false, capture: true });
            container.addEventListener('touchmove', handleTouchMove, { passive: false, capture: true });
            container.addEventListener('touchend', handleTouchEnd, { passive: false, capture: true });
            container.addEventListener('touchcancel', handleTouchCancel, { passive: false, capture: true });
            return () => {
                container.removeEventListener('touchstart', handleTouchStart, true);
                container.removeEventListener('touchmove', handleTouchMove, true);
                container.removeEventListener('touchend', handleTouchEnd, true);
                container.removeEventListener('touchcancel', handleTouchCancel, true);
                if (momentumAnimationId !== null) {
                    caf(momentumAnimationId);
                    momentumAnimationId = null;
                }
                if (scrollRafId !== null) {
                    caf(scrollRafId);
                    scrollRafId = null;
                }
                pendingDeltaY = 0;
                container.style.touchAction = originalTouchAction;
                container.removeAttribute('data-cerious-touch');
                if (addedStyleElement) {
                    addedStyleElement.remove();
                }
            };
        }
        isScrollbarTouch(target) {
            if (!(target instanceof Element))
                return false;
            // Recognize both the legacy class-based selector (kept for backwards
            // compatibility) and the data-attribute used by the current
            // NativeScrollbar (strip and overlay thumb). When the touch lands on the
            // overlay thumb the controller must yield so pointer events drive the
            // custom drag handler instead of being preventDefault'd here.
            return Boolean(target.closest('[data-cerious-scrollbar]') ||
                target.closest('.cerious-scrollbar-container'));
        }
    }

    /**
     * Native scrolling without making the virtual content itself the scroll range.
     * A hidden, local overflow surface receives the trusted browser gesture; its
     * scrollTop deltas are forwarded to the existing navigation engine.
     *
     * Touch is the original driver. Wheel can opt in through
     * `wheel.mode: 'native-proxy'`, which is worth doing because the surface is a
     * real scroll container: the browser applies its own per-platform wheel physics
     * to it, rather than the engine trying to reproduce them from raw deltas.
     */
    class NativeTouchController {
        constructor(deps) {
            this.deps = deps;
            this.proxy = null;
            this.driving = false;
            this.syncProxyPosition = null;
            this.eventDetail = {
                percentage: 0,
                currentElement: 0,
                scrollOffset: 0,
                result: { element: 0, offset: 0 },
            };
        }
        static ensureStylesInjected() {
            if (this._stylesInjected || typeof document === 'undefined')
                return;
            const style = document.createElement('style');
            style.setAttribute('data-cerious-native-touch-styles', '');
            style.textContent = `
[data-cerious-native-touch-proxy] {
  scrollbar-width: none;
  -ms-overflow-style: none;
}
[data-cerious-native-touch-proxy]::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}
`;
            document.head.appendChild(style);
            this._stylesInjected = true;
        }
        /**
         * Attach a real overflow scroller around the dedicated content element.
         * The content remains the hit-test target, so mouse/pointer/click behavior is
         * unchanged; the proxy is merely its native scrollable ancestor.
         */
        attach(container, onScroll, _options, driver) {
            NativeTouchController.ensureStylesInjected();
            const content = container.querySelector('[data-cerious-scroll-content], [data-cerious-masonry="content"]');
            if (!content) {
                throw new Error("CeriousScroll: touch.mode 'native-proxy' requires a " +
                    '[data-cerious-scroll-content] element (Masonry supplies its own viewport)');
            }
            /**
             * The element the surface actually wraps: the host's own child that
             * CONTAINS the rows, which is not always the content element itself.
             *
             * A host is free to put something between itself and the content element —
             * a horizontal-scroll wrapper around a wide grid is the common one — and
             * that is a legitimate structure, not a mistake. Wrapping the content
             * element in place would bury the surface inside that wrapper, where it
             * would be sized by it and fight its overflow. Wrapping the host's own
             * child instead keeps the surface exactly where it has always been, one
             * level below the host, whatever sits beneath it.
             */
            let viewport = content;
            while (viewport.parentElement && viewport.parentElement !== container) {
                viewport = viewport.parentElement;
            }
            if (viewport.parentElement !== container) {
                throw new Error('CeriousScroll: the [data-cerious-scroll-content] element must live inside the host');
            }
            const originalContainerPosition = container.style.position;
            if (getComputedStyle(container).position === 'static') {
                container.style.position = 'relative';
            }
            const proxy = document.createElement('div');
            proxy.setAttribute('data-cerious-native-touch-proxy', '');
            proxy.style.cssText = `
      position: absolute;
      inset: 0;
      overflow-y: scroll;
      overflow-x: hidden;
      touch-action: auto;
      overflow-anchor: none;
      overscroll-behavior: contain;
      -webkit-overflow-scrolling: touch;
    `;
            const surface = document.createElement('div');
            surface.setAttribute('data-cerious-native-touch-surface', '');
            surface.style.cssText = `
      width: 1px;
      height: ${NativeTouchController.SURFACE_HEIGHT_PX}px;
      pointer-events: none;
    `;
            /**
             * Our own sticky layer, holding the host's element rather than restyling it.
             *
             * Making the host's element sticky is what an earlier version did, and it
             * silently broke any element that sized itself by being positioned — a grid
             * laid out with `position: absolute; inset: 0` collapsed to its header row
             * the moment `position` was overwritten. The engine has no business
             * rewriting layout properties on markup it did not author, so it brings its
             * own element and leaves the host's exactly as it found it.
             *
             * `position: sticky` also makes this the containing block for absolutely
             * positioned children, which is what lets an `inset: 0` child keep working.
             */
            const stickyViewport = document.createElement('div');
            stickyViewport.setAttribute('data-cerious-native-touch-viewport', '');
            stickyViewport.style.cssText =
                'position:sticky;top:0;z-index:1;width:100%;height:100%;' +
                    'touch-action:auto;overflow-anchor:none;';
            // The proxy takes the viewport's exact former slot. Moving it does not
            // invalidate references retained by framework wrappers.
            container.insertBefore(proxy, viewport);
            stickyViewport.appendChild(viewport);
            proxy.appendChild(stickyViewport);
            proxy.appendChild(surface);
            this.proxy = proxy;
            let lastScrollTop = 0;
            let ignoredScrollTop = null;
            let pendingDelta = 0;
            let rafId = null;
            let idleTimer = null;
            // Native scroll events do not identify their cause. Safari may adjust a
            // scroll container after a focused/changed descendant (scroll anchoring),
            // and forwarding that adjustment makes the changed card become a false
            // virtual boundary. Observe touch lifecycle passively so only an actual
            // pan and its subsequent momentum are allowed to drive the engine.
            let touchActive = false;
            let touchMovedScroll = false;
            let momentumActive = false;
            // Wheel has no touchstart/touchend to bracket it, so ownership is a window
            // opened by each wheel event and closed by idle or `scrollend`. Without it
            // a wheel-driven scroll looks exactly like the browser adjustments the
            // touch gate exists to reject.
            const acceptWheel = (driver === null || driver === void 0 ? void 0 : driver.acceptWheel) === true;
            let wheelActive = false;
            const viewportHeight = () => {
                const h = content.clientHeight;
                return h > 0 ? h : (container.clientHeight || container.offsetHeight);
            };
            const raf = (cb) => {
                if (typeof requestAnimationFrame === 'function')
                    return requestAnimationFrame(cb);
                return setTimeout(cb, 16);
            };
            const caf = (id) => {
                if (typeof cancelAnimationFrame === 'function')
                    cancelAnimationFrame(id);
                else
                    clearTimeout(id);
            };
            const emit = (result) => {
                this.eventDetail.percentage = this.deps.calculateScrollPercentage();
                this.eventDetail.currentElement = this.deps.getCurrentElement();
                this.eventDetail.scrollOffset = this.deps.getScrollOffset();
                this.eventDetail.result = result;
                container.dispatchEvent(new CustomEvent('cerious-viewport-change', {
                    detail: this.eventDetail,
                }));
                onScroll === null || onScroll === void 0 ? void 0 : onScroll(result);
            };
            const flush = () => {
                rafId = null;
                const delta = pendingDelta;
                pendingDelta = 0;
                if (delta === 0)
                    return;
                emit(this.deps.scroll(delta, viewportHeight()));
            };
            const writeProxyPosition = (next) => {
                const max = Math.max(0, proxy.scrollHeight - proxy.clientHeight);
                const clamped = Math.max(0, Math.min(max, next));
                if (Math.abs(proxy.scrollTop - clamped) <= 1) {
                    lastScrollTop = proxy.scrollTop;
                    return;
                }
                ignoredScrollTop = clamped;
                proxy.scrollTop = clamped;
                // Read back because browsers may round or clamp the assigned value.
                ignoredScrollTop = proxy.scrollTop;
                lastScrollTop = proxy.scrollTop;
            };
            const finishGesture = () => {
                var _a, _b;
                wheelActive = false;
                if (!this.driving)
                    return;
                if (rafId !== null) {
                    caf(rafId);
                    flush();
                }
                this.driving = false;
                momentumActive = false;
                this.syncPosition();
                (_b = (_a = this.deps).onSettle) === null || _b === void 0 ? void 0 : _b.call(_a);
            };
            const scheduleIdle = (ms = NativeTouchController.IDLE_MS) => {
                if (idleTimer !== null)
                    window.clearTimeout(idleTimer);
                idleTimer = window.setTimeout(() => {
                    idleTimer = null;
                    wheelActive = false;
                    finishGesture();
                }, ms);
            };
            const handleScroll = () => {
                // Safari exposes elastic overscroll through scrollTop: it can go below 0
                // at the top or above maxScroll at the bottom, then animate back into the
                // legal range. Forwarding that rebound would move the virtual camera in
                // the opposite direction (most visibly pulling the last rows back up just
                // after the user reached the bottom). Clamp observations to the native
                // range so both the outward stretch and its rebound are zero engine
                // movement once the physical boundary has been reached.
                const max = Math.max(0, proxy.scrollHeight - proxy.clientHeight);
                const current = Math.max(0, Math.min(max, proxy.scrollTop));
                if (ignoredScrollTop !== null &&
                    Math.abs(current - ignoredScrollTop) <= NativeTouchController.PROGRAMMATIC_TOLERANCE_PX) {
                    ignoredScrollTop = null;
                    lastScrollTop = current;
                    return;
                }
                ignoredScrollTop = null;
                const delta = current - lastScrollTop;
                lastScrollTop = current;
                if (delta === 0)
                    return;
                // A real touch pan or wheel gesture is the only owner of this local scroll
                // surface. Focus, scroll anchoring, scrollIntoView, and other browser
                // adjustments must be rebased back to the engine position rather than
                // interpreted as input.
                if (!touchActive && !momentumActive && !wheelActive) {
                    this.syncPosition();
                    return;
                }
                this.driving = true;
                if (touchActive)
                    touchMovedScroll = true;
                pendingDelta += delta;
                if (rafId === null)
                    rafId = raf(flush);
                scheduleIdle(wheelActive && !touchActive && !momentumActive
                    ? NativeTouchController.WHEEL_IDLE_MS
                    : NativeTouchController.IDLE_MS);
            };
            /**
             * Open the wheel ownership window.
             *
             * Passive on purpose: preventing the default here would take back the very
             * native scrolling this mode exists to use. The event is only a signal that
             * the scrolls about to arrive are the user's.
             */
            const handleWheel = () => {
                if (!acceptWheel)
                    return;
                wheelActive = true;
                scheduleIdle(NativeTouchController.WHEEL_IDLE_MS);
            };
            const handleTouchStart = () => {
                if (idleTimer !== null) {
                    window.clearTimeout(idleTimer);
                    idleTimer = null;
                }
                // A fresh finger stops any previous momentum. Preserve its final pending
                // pixels before transferring ownership to the new gesture.
                if (rafId !== null) {
                    caf(rafId);
                    flush();
                }
                this.driving = false;
                momentumActive = false;
                wheelActive = false;
                touchActive = true;
                touchMovedScroll = false;
                const max = Math.max(0, proxy.scrollHeight - proxy.clientHeight);
                lastScrollTop = Math.max(0, Math.min(max, proxy.scrollTop));
            };
            const handleTouchEnd = (event) => {
                if (event.touches.length > 0)
                    return;
                touchActive = false;
                if (touchMovedScroll) {
                    // Scroll events after touchend are browser-owned momentum. The normal
                    // scrollend/idle path closes this window.
                    momentumActive = true;
                    scheduleIdle();
                }
                else {
                    // It was a tap. Close ownership BEFORE the synthesized click mutates or
                    // focuses content, so any resulting anchoring scroll cannot move the
                    // virtual camera.
                    momentumActive = false;
                    this.driving = false;
                    this.syncPosition();
                }
            };
            const handleTouchCancel = () => {
                touchActive = false;
                momentumActive = false;
                if (rafId !== null) {
                    caf(rafId);
                    flush();
                }
                this.driving = false;
                this.syncPosition();
            };
            proxy.addEventListener('scroll', handleScroll, { passive: true });
            proxy.addEventListener('scrollend', finishGesture, { passive: true });
            if (acceptWheel)
                proxy.addEventListener('wheel', handleWheel, { passive: true });
            proxy.addEventListener('touchstart', handleTouchStart, { passive: true });
            proxy.addEventListener('touchend', handleTouchEnd, { passive: true });
            proxy.addEventListener('touchcancel', handleTouchCancel, { passive: true });
            this.syncProxyPosition = () => {
                if (this.driving || !this.proxy)
                    return;
                const percentage = this.deps.calculateScrollPercentage();
                const max = Math.max(0, proxy.scrollHeight - proxy.clientHeight);
                const middle = Math.round(max / 2);
                // calculateScrollPercentage() is already clamped and reports exact 0/100
                // at the dataset boundaries. Do not use a fuzzy percentage threshold
                // here: on a very large dataset even 0.01% can represent thousands of
                // pixels. Snapping that valid near-top position to physical scrollTop 0
                // leaves the next upward finger drag rubber-banding at a false boundary.
                writeProxyPosition(percentage <= 0 ? 0 : percentage >= 100 ? max : middle);
            };
            this.syncPosition();
            return () => {
                proxy.removeEventListener('scroll', handleScroll);
                proxy.removeEventListener('scrollend', finishGesture);
                if (acceptWheel)
                    proxy.removeEventListener('wheel', handleWheel);
                proxy.removeEventListener('touchstart', handleTouchStart);
                proxy.removeEventListener('touchend', handleTouchEnd);
                proxy.removeEventListener('touchcancel', handleTouchCancel);
                if (rafId !== null)
                    caf(rafId);
                if (idleTimer !== null)
                    window.clearTimeout(idleTimer);
                pendingDelta = 0;
                this.driving = false;
                this.syncProxyPosition = null;
                this.proxy = null;
                // Nothing to restore on the host's own element — it was never restyled.
                // Reinsert immediately before the proxy, which is precisely where the
                // viewport lived before attachment, then discard the private surface.
                container.insertBefore(viewport, proxy);
                proxy.remove();
                container.style.position = originalContainerPosition;
            };
        }
        /** Align the local surface after keyboard, scrollbar, or programmatic jumps. */
        syncPosition() {
            var _a;
            (_a = this.syncProxyPosition) === null || _a === void 0 ? void 0 : _a.call(this);
        }
    }
    NativeTouchController.SURFACE_HEIGHT_PX = 2000000;
    NativeTouchController.PROGRAMMATIC_TOLERANCE_PX = 2;
    NativeTouchController.IDLE_MS = 180;
    /**
     * Longer than {@link IDLE_MS}, because wheel input is intermittent where
     * momentum is continuous. A notch animation runs for a beat after the last
     * event, and closing the gesture underneath it re-centres the surface —
     * which cancels the browser's in-flight scroll and shows up as a stutter.
     */
    NativeTouchController.WHEEL_IDLE_MS = 400;
    NativeTouchController._stylesInjected = false;

    /** ResizeObserver on mounted rows; MutationObserver to attach/detach as the window moves. */
    class ContentObserverManager {
        constructor(deps) {
            this.deps = deps;
            // Track a single observation per container to prevent observer leaks if
            // observe() is called more than once on the same element. Refcounted so
            // multiple consumers can share a single underlying observer pair.
            this._activeObservations = new WeakMap();
        }
        /**
         * Watch mounted rows for in-place height changes.
         *
         * @param container Host whose subtree contains `[data-element-index]` rows.
         * @returns Detach function. Refcounted if `observe` is called again on the same node.
         */
        observe(container) {
            if (!container)
                return () => { };
            const existing = this._activeObservations.get(container);
            if (existing) {
                existing.refCount++;
                let released = false;
                return () => {
                    if (released)
                        return;
                    released = true;
                    existing.refCount--;
                    if (existing.refCount <= 0) {
                        existing.cleanup();
                        this._activeObservations.delete(container);
                    }
                };
            }
            if (typeof ResizeObserver === 'undefined') {
                return () => { };
            }
            const observedElements = new Set();
            const resizeObserver = new ResizeObserver((entries) => {
                var _a, _b;
                let needsInvalidation = false;
                for (const entry of entries) {
                    const element = entry.target;
                    const indexAttr = element.getAttribute('data-element-index');
                    if (indexAttr === null) {
                        continue;
                    }
                    const index = parseInt(indexAttr, 10);
                    if (Number.isNaN(index)) {
                        continue;
                    }
                    const cachedHeight = this.deps.getMeasuredHeight(index);
                    const newHeight = entry.contentRect.height;
                    // Defensive: ResizeObserver should always give a finite number, but
                    // guard against zero/negative which would corrupt the height cache.
                    if (!Number.isFinite(newHeight) || newHeight < 0)
                        continue;
                    if (cachedHeight !== undefined && Math.abs(cachedHeight - newHeight) > 0.5) {
                        this.deps.setMeasuredHeight(index, newHeight);
                        needsInvalidation = true;
                    }
                }
                if (needsInvalidation) {
                    this.deps.invalidateCache();
                    // Reposition + re-render now that a row's measured height changed.
                    (_b = (_a = this.deps).onResize) === null || _b === void 0 ? void 0 : _b.call(_a);
                }
            });
            const mutationObserver = new MutationObserver((mutations) => {
                for (const mutation of mutations) {
                    mutation.addedNodes.forEach((node) => {
                        if (node instanceof Element && node.hasAttribute('data-element-index') && !observedElements.has(node)) {
                            try {
                                resizeObserver.observe(node);
                                observedElements.add(node);
                            }
                            catch (_a) {
                                // Defensive: detached/invalid node. Ignore.
                            }
                        }
                    });
                    mutation.removedNodes.forEach((node) => {
                        if (node instanceof Element && observedElements.has(node)) {
                            try {
                                resizeObserver.unobserve(node);
                            }
                            catch (_a) {
                                // Already unobserved.
                            }
                            observedElements.delete(node);
                        }
                    });
                }
            });
            try {
                mutationObserver.observe(container, { childList: true, subtree: true });
            }
            catch (_a) {
                // Container is not a valid Node; observers are inert.
                resizeObserver.disconnect();
                return () => { };
            }
            let disposed = false;
            const cleanup = () => {
                if (disposed)
                    return;
                disposed = true;
                try {
                    mutationObserver.disconnect();
                }
                catch ( /* noop */_a) { /* noop */ }
                try {
                    resizeObserver.disconnect();
                }
                catch ( /* noop */_b) { /* noop */ }
                observedElements.clear();
            };
            const entry = { refCount: 1, cleanup };
            this._activeObservations.set(container, entry);
            let released = false;
            return () => {
                if (released)
                    return;
                released = true;
                entry.refCount--;
                if (entry.refCount <= 0) {
                    entry.cleanup();
                    this._activeObservations.delete(container);
                }
            };
        }
    }

    /** Arrow / page / home / end. */
    class KeyboardController {
        constructor(deps) {
            this.deps = deps;
            // Mutated in place and passed as CustomEvent.detail.
            this._eventDetail = {
                percentage: 0,
                currentElement: 0,
                scrollOffset: 0
            };
        }
        /**
         * @param container Host. Given `tabindex="0"` if missing so it can take focus.
         * @param keyboardOptions Optional overrides.
         * @param onViewportChange After a handled key.
         * @returns Detach function.
         */
        attach(container, keyboardOptions, onViewportChange) {
            const options = Object.assign({ enabled: true, arrowKeySpeed: 120, pageKeySpeed: 1.0 }, keyboardOptions);
            if (!options.enabled) {
                return () => { };
            }
            if (!container.hasAttribute('tabindex')) {
                container.setAttribute('tabindex', '0');
            }
            const handleKeyDown = (event) => {
                if (options.onKeyDown && options.onKeyDown(event, null)) {
                    return;
                }
                let handled = false;
                switch (event.key) {
                    case 'ArrowUp':
                        this.deps.scroll(-options.arrowKeySpeed, this.deps.getViewportHeight());
                        handled = true;
                        break;
                    case 'ArrowDown':
                        this.deps.scroll(options.arrowKeySpeed, this.deps.getViewportHeight());
                        handled = true;
                        break;
                    case 'PageUp':
                        this.deps.scroll(-this.deps.getViewportHeight() * options.pageKeySpeed, this.deps.getViewportHeight());
                        handled = true;
                        break;
                    case 'PageDown':
                        this.deps.scroll(this.deps.getViewportHeight() * options.pageKeySpeed, this.deps.getViewportHeight());
                        handled = true;
                        break;
                    case 'Home':
                        this.deps.jumpToElement(0);
                        handled = true;
                        break;
                    case 'End':
                        this.deps.jumpToElement(Number.MAX_SAFE_INTEGER);
                        handled = true;
                        break;
                }
                if (handled) {
                    event.preventDefault();
                    event.stopPropagation();
                    // Reuse _eventDetail; listeners must not retain it across events.
                    this._eventDetail.percentage = this.deps.getScrollPercentage();
                    this._eventDetail.currentElement = this.deps.getCurrentElement();
                    this._eventDetail.scrollOffset = this.deps.getScrollOffset();
                    if (onViewportChange) {
                        onViewportChange(this._eventDetail);
                    }
                    container.dispatchEvent(new CustomEvent('cerious-viewport-change', {
                        detail: this._eventDetail
                    }));
                }
            };
            container.addEventListener('keydown', handleKeyDown);
            return () => container.removeEventListener('keydown', handleKeyDown);
        }
    }

    /**
     * Host size: ResizeObserver on the container, plus window.resize for
     * environments without it and for zoom/orientation.
     */
    class ResizeController {
        constructor(onViewportChange) {
            this.onViewportChange = onViewportChange;
        }
        /**
         * @param container Host to observe.
         * @returns Detach function.
         */
        attach(container) {
            const cleanups = [];
            // Always listen to window.resize so existing behavior/tests keep working
            // and to handle environments without ResizeObserver.
            const windowHandler = () => this.onViewportChange(container);
            window.addEventListener('resize', windowHandler);
            cleanups.push(() => window.removeEventListener('resize', windowHandler));
            // Observe the container itself for size mutations that don't bubble up
            // as a window resize (CSS-driven, parent layout, programmatic sizing).
            if (typeof ResizeObserver !== 'undefined') {
                let lastWidth = container.clientWidth;
                let lastHeight = container.clientHeight;
                let firstObservation = true;
                const ro = new ResizeObserver(() => {
                    // ResizeObserver fires once on observe(); ignore that synthetic event
                    // so we don't double-trigger on attach.
                    if (firstObservation) {
                        firstObservation = false;
                        lastWidth = container.clientWidth;
                        lastHeight = container.clientHeight;
                        return;
                    }
                    const w = container.clientWidth;
                    const h = container.clientHeight;
                    if (w === lastWidth && h === lastHeight)
                        return;
                    lastWidth = w;
                    lastHeight = h;
                    this.onViewportChange(container);
                });
                try {
                    ro.observe(container);
                    cleanups.push(() => ro.disconnect());
                }
                catch (_a) {
                    // Defensive: if observe throws (detached node etc.), ignore.
                }
            }
            return () => {
                for (let i = 0; i < cleanups.length; i++) {
                    try {
                        cleanups[i]();
                    }
                    catch (_a) {
                        // Continue cleaning up remaining handles even if one throws.
                    }
                }
            };
        }
    }

    /**
     * Copyright (c) 2024-2026 Cerious DevTech LLC. All rights reserved.
     */
    /**
     * Virtual list: position is (element index, pixel offset into that element).
     * Only the visible window is in the DOM. Call `renderViewport` from `onScroll`.
     *
     * @example
     * ```ts
     * const scroller = new CeriousScroll(container, data.length, {
     *   onScroll: () => {
     *     scroller.renderViewport(container.clientHeight, container, (i, el) => {
     *       el.textContent = data[i].label;
     *     });
     *   },
     * });
     * scroller.renderViewport(container.clientHeight, container, (i, el) => {
     *   el.textContent = data[i].label;
     * });
     * ```
     */
    class CeriousScroll {
        /**
         * Measure the usable vertical rendering area inside `container`.
         *
         * Framework wrappers (Vue/React/Angular) create an inner
         * `[data-cerious-scroll-content]` element sized to `height: 100%` of the
         * container. When that inner element opts into horizontal scrolling
         * (e.g. `overflow-x: auto` for a wide spreadsheet), its own
         * `clientHeight` shrinks by the horizontal scrollbar's gutter, while the
         * container's stays unchanged. Reading from the inner element first means
         * the engine renders the right number of rows and the last row stays
         * clear of the scrollbar.
         */
        /**
         * Settle on a writing direction.
         *
         * `'auto'` asks the DOM rather than the option, because direction is almost
         * always inherited — from `<html dir>`, a locale wrapper, a CSS rule — and a
         * host that has to restate it in JavaScript will eventually disagree with the
         * page around it.
         */
        static resolveDirection(container, requested) {
            if (requested === 'ltr' || requested === 'rtl')
                return requested;
            try {
                return getComputedStyle(container).direction === 'rtl' ? 'rtl' : 'ltr';
            }
            catch (_a) {
                return 'ltr'; // no computed styles (SSR, bare jsdom)
            }
        }
        /** Writing direction the engine resolved for this host. */
        get direction() {
            return this.resolvedDirection;
        }
        static measureViewportHeight(container) {
            const inner = container.querySelector('[data-cerious-scroll-content]');
            if (inner) {
                const h = inner.clientHeight;
                if (h > 0)
                    return h;
            }
            return container.clientHeight || container.offsetHeight || 600;
        }
        /**
         * Measure the scrollable viewport height, less any top inset the placement
         * reserves (e.g. the `<thead>` in table mode). Subtracting the header keeps
         * the row count, scroll percentage, and true-bottom math correct so the last
         * row lands flush with the container bottom instead of behind the header.
         */
        measureViewport(container) {
            const raw = CeriousScroll.measureViewportHeight(container);
            const inset = this.placement.getTopInset ? this.placement.getTopInset() : 0;
            return Math.max(0, raw - inset);
        }
        /**
         * @param container Host element. Height is read from it, or from an inner
         *   `[data-cerious-scroll-content]` when present (framework wrappers).
         * @param totalElements Dataset length. Finite integer >= 1.
         * @param options Optional. Put `renderViewport` in `onScroll` so every
         *   input path (including native scrollbar) re-renders.
         */
        constructor(container, totalElements, options = {}) {
            var _a, _b, _c, _d, _e, _f, _g, _h;
            this.showDebug = false;
            /** Camera row index. */
            this.currentElement = 0;
            /** Pixels into {@link currentElement}. */
            this.scrollOffset = 0;
            /** `0`–`100` along the measured range. */
            this.scrollPercentage = 0;
            /** Virtual-track `top` in pixels (percentage mapped onto the track). */
            this.viewportTop = 0;
            /** First visible index (inclusive), from the last {@link updateDisplay}. */
            this.startElement = 0;
            /** Last visible index (inclusive), from the last {@link updateDisplay}. */
            this.endElement = 0;
            /** Non-null only in `layout: 'masonry'`. Owns the card DOM. */
            this.masonry = null;
            /**
             * A content element this engine created because the host had none, and the
             * host it was created for. Rows render into it instead of the host.
             */
            this.ownedContent = null;
            this.ownedContentHost = null;
            /** The host this engine is attached to, once it is known. */
            this.attachedContainer = null;
            this.serverRowsRelocated = false;
            /** Writing direction in force, resolved once the host is known. */
            this.resolvedDirection = 'ltr';
            /** The pinned header element and the index it is currently showing. */
            this.stickyElement = null;
            this.stickyIndex = null;
            /** Pinned header height, measured once per hand-off rather than per frame. */
            this.stickyHeight = 0;
            /** Edge already asked about, cleared when the window moves away from it. */
            this.infiniteArmed = null;
            this.infiniteBusy = false;
            /** Card count in masonry mode; `totalElements` holds the SEGMENT count. */
            this.totalItems = 0;
            if (!Number.isFinite(totalElements) || totalElements < 1) {
                throw new Error('CeriousScroll: totalElements must be >= 1 (finite integer required)');
            }
            if (!container) {
                throw new Error('CeriousScroll: container element is required for automatic viewport detection');
            }
            // Deep-clone + freeze caller-supplied options. Each nested object is
            // frozen separately so library code (and consumers) cannot accidentally
            // mutate live configuration.
            const frozenOptions = Object.assign(Object.assign({}, options), { keyboard: options.keyboard ? Object.freeze(Object.assign({}, options.keyboard)) : undefined, touch: options.touch ? Object.freeze(Object.assign({}, options.touch)) : undefined, wheel: options.wheel ? Object.freeze(Object.assign({}, options.wheel)) : undefined });
            this.options = Object.freeze(frozenOptions);
            this.totalElements = Math.floor(totalElements);
            this.placement = this.options.layout === 'table'
                ? new TableFlowPlacement(this.options.table)
                : new AbsolutePlacement();
            // Masonry scrolls over SEGMENTS, not cards. The constructor's
            // `totalElements` is a card count in that mode, so translate it here and
            // keep the rest of the engine unaware of the distinction.
            if (this.options.layout === 'masonry') {
                if (!this.options.masonry) {
                    throw new Error("CeriousScroll: layout 'masonry' requires the `masonry` option");
                }
                if (this.options.heightProvider) {
                    throw new Error("CeriousScroll: layout 'masonry' installs its own heightProvider; remove yours");
                }
                this.totalItems = this.totalElements;
                this.masonry = new MasonryRenderer(container, this.totalItems, this.options.masonry);
                this.totalElements = this.masonry.segmentCount;
            }
            this.viewportHeight = this.measureViewport(container);
            this.windowHeight = this.viewportHeight;
            const heightProvider = this.masonry
                ? this.masonry.heightProvider()
                : this.options.heightProvider;
            this.getElementHeight = heightProvider
                ? (index) => heightProvider.height(index)
                : (index) => {
                    // Do not cache the default. Writing it would make hasMeasuredHeight()
                    // true for a row that was never measured, so a later prune/reflow would
                    // skip offsetHeight and keep the fake 40px.
                    const measuredHeight = this.performanceCache.getMeasuredHeight(index);
                    return measuredHeight !== undefined ? measuredHeight : CeriousScroll.DEFAULT_ELEMENT_HEIGHT;
                };
            this.performanceCache = new PerformanceCache(this.getElementHeight, heightProvider);
            // Caps linear walks (findRowFromScrollPosition) so a bad scrollPixel
            // cannot iterate past the dataset.
            this.performanceCache.setTotalElements(this.totalElements);
            // Engine is constructed below; setScrollHandlers() wires it without a
            // `null as any` placeholder that could NPE if a scroll event fired first.
            this.nativeScrollbar = new NativeScrollbar(this.totalElements, () => this.calculateScrollPercentage(), this.getElementHeight, (element, offset) => {
                this.currentElement = element;
                this.scrollOffset = offset;
            }, null, // scrollHandlers - set after NavigationEngine construction
            () => this.viewportHeight, () => this.currentElement, () => this.scrollOffset, () => this.viewportRenderer.calculateTrueBottomPosition(this.viewportHeight), CeriousScroll.VIRTUAL_TRACK_HEIGHT, () => {
                var _a, _b, _c;
                // Scrollbar drags use jumpToPosition(..., skipScrollbarSync=true), so
                // they deliberately bypass NavigationEngine's normal sync callback.
                // Keep the independent native-touch surface aligned here; otherwise a
                // scrollbar jump away from the top leaves the proxy at physical
                // scrollTop 0 and the next touch can rubber-band in mid-dataset.
                (_a = this.nativeTouchController) === null || _a === void 0 ? void 0 : _a.syncPosition();
                (_c = (_b = this.options).onScroll) === null || _c === void 0 ? void 0 : _c.call(_b);
            });
            // With a computed height source, size the strip by CONTENT. Element-count
            // sizing assumes an element is roughly a row; when it is not, the track
            // loses resolution and the scroll position quantizes.
            if (heightProvider === null || heightProvider === void 0 ? void 0 : heightProvider.totalHeight) {
                this.nativeScrollbar.setContentHeightSource(() => this.performanceCache.getProvidedTotalHeight());
            }
            this.viewportRenderer = new ViewportRenderer(this.totalElements, () => this.currentElement, () => this.scrollOffset, () => this.calculateScrollPercentage(), (index, height) => this.performanceCache.setMeasuredHeight(index, height), (index) => this.performanceCache.hasMeasuredHeight(index), (index) => this.performanceCache.getMeasuredHeight(index), () => this.performanceCache.getUniformHeightHint(), this.placement);
            this.viewportRenderer.hydrate = ((_a = this.options.ssr) === null || _a === void 0 ? void 0 : _a.hydrate) === true;
            this.navigationEngine = new NavigationEngine({
                totalElements: this.totalElements,
                viewportHeight: this.viewportHeight,
                getCurrentElement: () => this.currentElement,
                getScrollOffset: () => this.scrollOffset,
                getElementHeight: (index) => this.getElementHeight(index),
                hasMeasuredHeight: (index) => this.performanceCache.hasMeasuredHeight(index),
                getLastRenderedElement: () => this.viewportRenderer.lastRenderedElement,
                getElementViewportPosition: (index) => this.getElementViewportPosition(index),
                getCalculateScrollPercentage: () => this.calculateScrollPercentage(),
                updateScrollPosition: (element, offset) => {
                    this.currentElement = element;
                    this.scrollOffset = offset;
                },
                requestDisplayUpdate: () => this.updateDisplay(),
                syncScrollbar: () => {
                    var _a;
                    if (this.nativeScrollbar.container && !this.nativeScrollbar.isSyncing) {
                        this.nativeScrollbar.syncNativeScrollbar();
                    }
                    (_a = this.nativeTouchController) === null || _a === void 0 ? void 0 : _a.syncPosition();
                },
                getTrueBottomPosition: () => this.viewportRenderer.calculateTrueBottomPosition(this.viewportHeight)
            });
            this.keyboardController = new KeyboardController({
                scroll: (deltaY, viewportHeight) => this.navigationEngine.scroll(deltaY, viewportHeight),
                jumpToElement: (index) => this.navigationEngine.jumpToElement(index),
                getViewportHeight: () => this.viewportHeight,
                getScrollPercentage: () => this.calculateScrollPercentage(),
                getCurrentElement: () => this.currentElement,
                getScrollOffset: () => this.scrollOffset
            });
            this.resizeController = new ResizeController((containerEl) => {
                this.handleViewportChange(containerEl);
            });
            this.viewportStateCalculator = new ViewportStateCalculator({
                totalElements: () => this.totalElements,
                getCurrentElement: () => this.currentElement,
                getScrollOffset: () => this.scrollOffset,
                getElementHeight: (index) => this.getElementHeight(index),
                getWindowHeight: () => this.windowHeight,
                calculateScrollPercentage: () => this.calculateScrollPercentage(),
                bufferSize: CeriousScroll.VIEWPORT_BUFFER_SIZE,
                nearEndThreshold: CeriousScroll.NEAR_END_THRESHOLD,
                virtualTrackHeight: CeriousScroll.VIRTUAL_TRACK_HEIGHT
            });
            this.wheelController = new WheelController({
                scroll: (deltaY, viewportHeight) => this.scroll(deltaY, viewportHeight),
                calculateScrollPercentage: () => this.calculateScrollPercentage(),
                getCurrentElement: () => this.currentElement,
                getScrollOffset: () => this.scrollOffset
            });
            this.touchController = new TouchController({
                scroll: (deltaY, viewportHeight) => this.scroll(deltaY, viewportHeight),
                calculateScrollPercentage: () => this.calculateScrollPercentage(),
                getCurrentElement: () => this.currentElement,
                getScrollOffset: () => this.scrollOffset
            });
            this.nativeTouchController = new NativeTouchController({
                scroll: (deltaY, viewportHeight) => this.scroll(deltaY, viewportHeight),
                calculateScrollPercentage: () => this.calculateScrollPercentage(),
                getCurrentElement: () => this.currentElement,
                getScrollOffset: () => this.scrollOffset,
                onSettle: () => this.snapToBoundary()
            });
            this.contentObserverManager = new ContentObserverManager({
                getMeasuredHeight: (index) => this.performanceCache.getMeasuredHeight(index),
                setMeasuredHeight: (index, height) => this.performanceCache.setMeasuredHeight(index, height),
                invalidateCache: () => this.invalidateCache(),
                // In-place height change (expand/collapse). Reflow so callers don't
                // have to remember recalculate() — same path for every framework.
                onResize: () => this.reflow()
            });
            this.nativeScrollbar.setScrollHandlers(this.navigationEngine);
            this.updateDisplay();
            // Playwright / field diagnostics. Gated on ?debugScroll= so production
            // stays inert. Registry is keyed by instance so a second scroller does
            // not overwrite the first hook.
            try {
                const params = new URLSearchParams((_c = (_b = globalThis.location) === null || _b === void 0 ? void 0 : _b.search) !== null && _c !== void 0 ? _c : '');
                const enabled = params.has('debugScroll') && params.get('debugScroll') !== '0' && params.get('debugScroll') !== 'false';
                if (enabled) {
                    const g = globalThis;
                    const registry = g.__ceriousScrollDebugRegistry instanceof Map
                        ? g.__ceriousScrollDebugRegistry
                        : (g.__ceriousScrollDebugRegistry = new Map());
                    const debugId = `cerious-scroll-${(g.__ceriousScrollDebugCounter = ((_d = g.__ceriousScrollDebugCounter) !== null && _d !== void 0 ? _d : 0) + 1)}`;
                    const snapshot = () => {
                        const trueBottom = this.viewportRenderer.calculateTrueBottomPosition(this.viewportHeight);
                        return {
                            version: 'cerious-scroll-debug-v1',
                            id: debugId,
                            totalElements: this.totalElements,
                            viewportHeight: this.viewportHeight,
                            currentElement: this.currentElement,
                            scrollOffset: this.scrollOffset,
                            scrollPercentage: this.calculateScrollPercentage(),
                            lastRenderedRange: this.viewportRenderer.lastRenderedRange,
                            renderedElementCount: this.viewportRenderer.renderedElementCount,
                            renderer: this.viewportRenderer.lifecycleStats,
                            trueBottom,
                        };
                    };
                    registry.set(debugId, snapshot);
                    g.__ceriousScrollDebug = (id) => {
                        var _a;
                        if (id)
                            return (_a = registry.get(id)) === null || _a === void 0 ? void 0 : _a();
                        return snapshot();
                    };
                    g.__ceriousScrollDebug.list = () => Array.from(registry.keys());
                    this.debugCleanup = () => {
                        registry.delete(debugId);
                        if (registry.size === 0) {
                            try {
                                delete g.__ceriousScrollDebug;
                            }
                            catch (_a) {
                                g.__ceriousScrollDebug = undefined;
                            }
                        }
                    };
                }
            }
            catch (_j) {
                // SSR / tests have no location
            }
            this.attachedContainer = container;
            this.resolvedDirection = CeriousScroll.resolveDirection(container, this.options.direction);
            if (this.masonry)
                this.masonry.rtl = this.resolvedDirection === 'rtl';
            this.installAria(container);
            if (this.options.attachScrollbar !== false) {
                // A right-to-left reader expects the bar on the left, the same way the
                // browser moves its own.
                this.nativeScrollbar.attachNativeScrollbar(container, this.resolvedDirection === 'rtl' ? 'left' : 'right');
            }
            if (((_e = this.options.keyboard) === null || _e === void 0 ? void 0 : _e.enabled) !== false) {
                this.keyboardCleanup = this.keyboardController.attach(container, this.options.keyboard, () => {
                    var _a, _b;
                    (_b = (_a = this.options).onScroll) === null || _b === void 0 ? void 0 : _b.call(_a);
                });
            }
            // Give the host a content element if it has none. The native surface needs
            // one element it can hold still while it scrolls beneath, and a host that
            // renders rows straight into itself offers nothing to hold. Creating it
            // here is what makes native scrolling the default for EVERY host rather
            // than only the ones whose markup happens to suit it — a plain
            // `new CeriousScroll(div, n)` used to fall back to the JavaScript path
            // silently, which is the worst way for a default to not apply.
            //
            // Masonry is exempt: its renderer builds and owns its own viewport.
            if (!this.masonry && !container.querySelector('[data-cerious-scroll-content]')) {
                const owned = document.createElement('div');
                owned.setAttribute('data-cerious-scroll-content', '');
                // Matches what the framework wrappers build, so the engine measures and
                // lays out identically however the element got there.
                owned.style.cssText = 'position:relative;width:100%;height:100%;overflow-y:clip;overflow-x:auto';
                container.appendChild(owned);
                this.ownedContent = owned;
                this.ownedContentHost = container;
            }
            const nativeContent = container.querySelector('[data-cerious-scroll-content], [data-cerious-masonry="content"]');
            // Native touch is the default for the dedicated content structure used
            // by the framework bindings, demo bootstrap, and Masonry. Legacy direct
            // hosts without that structure retain manual touch automatically; an
            // explicit native-proxy request still reaches attach() and its useful
            // validation error.
            // Depth does not matter: the surface wraps whichever host child contains
            // the content element, so a host may nest it (a horizontal-scroll wrapper
            // around a wide grid) and still get native scrolling.
            const canUseNativeProxy = !!nativeContent;
            const requestedTouchMode = (_f = this.options.touch) === null || _f === void 0 ? void 0 : _f.mode;
            const touchEnabled = ((_g = this.options.touch) === null || _g === void 0 ? void 0 : _g.enabled) !== false;
            const useNativeProxyTouch = touchEnabled && (requestedTouchMode === 'native-proxy' ||
                (requestedTouchMode !== 'manual' && canUseNativeProxy));
            // The wheel scrolls the native surface. Not a mode, not a preference: the
            // browser's own physics is the platform's, and reproducing it from raw
            // deltas was only ever an approximation of one platform at a time.
            //
            // `canUseNativeProxy` is effectively always true now — the engine builds the
            // element the surface needs when a host has none — but it is still checked,
            // because the alternative to a JavaScript fallback in some DOM nobody
            // anticipated is a list that does not scroll at all.
            const wheelEnabled = ((_h = this.options.wheel) === null || _h === void 0 ? void 0 : _h.enabled) !== false;
            const useNativeProxyWheel = wheelEnabled && canUseNativeProxy;
            if (wheelEnabled) {
                // Resolved HERE, not in the controller: only this scope knows whether the
                // surface can exist, and the controller is told rather than guessing.
                this.wheelCleanup = this.wheelController.attach(container, () => { var _a, _b; (_b = (_a = this.options).onScroll) === null || _b === void 0 ? void 0 : _b.call(_a); }, this.options.wheel, useNativeProxyWheel);
            }
            // One surface, either driver. Wheel needs it even when touch does not want
            // it (or is switched off entirely), so attachment is driven by the union.
            if (useNativeProxyTouch || useNativeProxyWheel) {
                this.touchCleanup = this.nativeTouchController.attach(container, () => {
                    var _a, _b;
                    (_b = (_a = this.options).onScroll) === null || _b === void 0 ? void 0 : _b.call(_a);
                }, this.options.touch, { acceptWheel: useNativeProxyWheel });
            }
            else if (touchEnabled) {
                this.touchCleanup = this.touchController.attach(container, () => {
                    var _a, _b;
                    (_b = (_a = this.options).onScroll) === null || _b === void 0 ? void 0 : _b.call(_a);
                }, this.options.touch);
            }
            if (this.masonry) {
                // Masonry owns its own resize: a width change invalidates the whole
                // layout, which needs a re-anchor and a sliced rebuild, not a re-measure.
                const onRender = () => { var _a, _b; (_b = (_a = this.options).onScroll) === null || _b === void 0 ? void 0 : _b.call(_a); };
                // Re-measure now that the scrollbar strip exists. The renderer's geometry
                // was computed in its constructor, before the strip was attached, so the
                // last column would otherwise be sized against space the strip occupies.
                // Waiting for a resize observation is not enough: when the host is reused
                // it already carries the strip's padding, so the content box never changes
                // size and no observation ever arrives.
                this.masonry.remeasure(this, onRender);
                this.resizeCleanup = this.masonry.observeResize(this, onRender);
                this.masonry.scheduleTailChain(this);
            }
            else if (this.options.autoResize !== false) {
                this.resizeCleanup = this.setupAutoResizeHandling(container);
            }
            if (this.options.observeContentChanges !== false) {
                this.contentObserverCleanup = this.contentObserverManager.observe(container);
            }
        }
        /** Last row from the dataset currently in the DOM, if any. */
        get lastRenderedElement() {
            return this.viewportRenderer.lastRenderedElement;
        }
        /**
         * Indices currently mounted in the viewport (visible + overscan).
         * @returns Sorted or insertion-order indices; do not mutate.
         */
        getRenderedIndices() {
            return this.viewportRenderer.getRenderedIndices();
        }
        /**
         * @param index Dataset index.
         * @returns The live row element, or `null` if that index is not mounted.
         */
        getRenderedElement(index) {
            return this.viewportRenderer.getRenderedElement(index);
        }
        /**
         * Re-invoke the renderer callback for every currently-rendered element and
         * re-measure each one's height. Use after in-place row mutations whose new
         * height the engine cannot otherwise observe — e.g. expand/collapse driven
         * by external state, an async image that finished loading and grew its row.
         *
         * Without this, a follow-up `renderViewport()` call would skip the renderer
         * for already-rendered indices and re-read the stale `offsetHeight`, so the
         * mutation would silently no-op.
         *
         * @param renderElement Same callback you pass to `renderViewport`.
         *
         * Typical usage:
         * ```
         * scroller.refreshVisible(renderCallback);
         * scroller.renderViewport(container.clientHeight, container, renderCallback);
         * ```
         */
        refreshVisible(renderElement) {
            if (typeof renderElement !== 'function') {
                throw new Error('CeriousScroll.refreshVisible: renderElement must be a function');
            }
            this.viewportRenderer.refreshVisible(renderElement);
        }
        /**
         * Record a measured row height.
         * @param index Dataset index in `[0, totalElements)`.
         * @param height Height in pixels (non-negative finite).
         */
        setMeasuredHeight(index, height) {
            if (!Number.isFinite(index) || index < 0 || index >= this.totalElements) {
                throw new Error(`CeriousScroll.setMeasuredHeight: index ${index} out of range (0..${this.totalElements - 1})`);
            }
            if (!Number.isFinite(height) || height < 0) {
                throw new Error(`CeriousScroll.setMeasuredHeight: height must be a non-negative finite number, got ${height}`);
            }
            this.performanceCache.setMeasuredHeight(index, height);
        }
        /**
         * Apply a pixel delta. Positive is down. `viewportHeight` should be the
         * host/content height; table header inset is subtracted here.
         *
         * @param deltaY Pixels to move (positive = down, negative = up).
         * @param viewportHeight Host or content `clientHeight` in pixels.
         * @returns Camera after the move: `{ element, offset }`.
         */
        scroll(deltaY, viewportHeight) {
            if (!Number.isFinite(deltaY) || !Number.isFinite(viewportHeight) || viewportHeight <= 0) {
                return { element: this.currentElement, offset: this.scrollOffset };
            }
            // Callers (wheel/touch controllers, consumers) pass the raw container/content
            // height. Subtract any placement top inset (e.g. the table header) so the
            // boundary guardian compares the last row against the true scrollable area —
            // otherwise it sees a phantom header-height overshoot at the bottom and
            // clamps one row short, clipping the final row. Mirrors renderViewport.
            const inset = this.placement.getTopInset ? this.placement.getTopInset() : 0;
            const effectiveViewportHeight = Math.max(1, viewportHeight - inset);
            return this.navigationEngine.scroll(deltaY, effectiveViewportHeight);
        }
        /**
         * Position of a row relative to the current viewport (not from dataset origin).
         *
         * @param elementIndex Dataset index.
         * @returns `top` / `bottom` in px from the viewport top (negative = above);
         *   `isVisible` if the row intersects the viewport.
         */
        getElementViewportPosition(elementIndex) {
            if (elementIndex < 0 || elementIndex >= this.totalElements) {
                throw new Error(`Element index ${elementIndex} is out of bounds (0-${this.totalElements - 1})`);
            }
            // Walk from the camera, not from row 0. Uniform rows are O(1).
            const uniform = this.performanceCache.getUniformHeightHint();
            let elementRelativeTop = -this.scrollOffset;
            if (elementIndex === this.currentElement) ;
            else if (uniform !== undefined && uniform > 0) {
                elementRelativeTop += (elementIndex - this.currentElement) * uniform;
            }
            else if (elementIndex >= this.currentElement) {
                for (let i = this.currentElement; i < elementIndex; i++) {
                    elementRelativeTop += this.getElementHeight(i);
                }
            }
            else {
                for (let i = this.currentElement - 1; i >= elementIndex; i--) {
                    elementRelativeTop -= this.getElementHeight(i);
                }
            }
            const elementHeight = this.getElementHeight(elementIndex);
            const elementRelativeBottom = elementRelativeTop + elementHeight;
            const isVisible = elementRelativeBottom > 0 && elementRelativeTop < this.viewportHeight;
            return {
                top: elementRelativeTop,
                bottom: elementRelativeBottom,
                isVisible
            };
        }
        /**
         * Jump to a percentage along the measured range.
         *
         * @param percentage `0` = top, `100` = true bottom. Clamped.
         * @returns Camera after the jump: `{ element, offset }`.
         */
        handleScrollPercentage(percentage) {
            if (!Number.isFinite(percentage)) {
                throw new Error(`CeriousScroll.handleScrollPercentage: percentage must be finite, got ${percentage}`);
            }
            return this.navigationEngine.handleScrollPercentage(percentage);
        }
        /**
         * Jump to a row at offset 0. Out-of-range indices are clamped.
         * `Number.MAX_SAFE_INTEGER` is the End-key sentinel (last row / true bottom).
         *
         * @param elementIndex Zero-based target index.
         * @returns Camera after the jump. Offset is 0 unless clamped to true bottom.
         */
        /**
         * Jump to an exact camera position.
         *
         * {@link jumpToElement} always lands at offset 0, which is enough when an
         * element is a row. It is not enough for re-anchoring after a relayout, where
         * the goal is to put a specific piece of content back at a specific screen
         * position — that needs a sub-element offset.
         *
         * @param elementIndex Target element.
         * @param offset Pixels into that element.
         * @param skipScrollbarSync Leave the strip alone (the caller will sync).
         * @returns Camera after the jump.
         */
        jumpToPosition(elementIndex, offset, skipScrollbarSync = false) {
            if (!Number.isFinite(elementIndex) || !Number.isFinite(offset)) {
                throw new Error(`CeriousScroll.jumpToPosition: elementIndex and offset must be finite, got ${elementIndex}, ${offset}`);
            }
            return this.navigationEngine.jumpToPosition(elementIndex, offset, skipScrollbarSync);
        }
        jumpToElement(elementIndex) {
            if (!Number.isFinite(elementIndex)) {
                throw new Error(`CeriousScroll.jumpToElement: elementIndex must be finite, got ${elementIndex}`);
            }
            return this.navigationEngine.jumpToElement(elementIndex);
        }
        /**
         * Grow or shrink the dataset without reconstructing the scroller.
         *
         * Recreating mid-drag tears down the strip the user is holding (thumb
         * freezes). A sliding window with a moving last index also makes the
         * bottom bounce. Growing in place keeps index 0 stable.
         *
         * Heights are keyed by index. A prepend that shifts every row needs
         * `clearAllCaches()` first. This call does not move the camera or render.
         *
         * @param totalElements New length. Finite integer >= 1.
         */
        updateTotalElements(totalElements) {
            if (!Number.isFinite(totalElements) || totalElements < 1) {
                throw new Error('CeriousScroll.updateTotalElements: totalElements must be >= 1 (finite integer required)');
            }
            const next = Math.floor(totalElements);
            if (next === this.totalElements)
                return;
            this.totalElements = next;
            // New rows arrived, so "I already asked about this edge" is stale. Without
            // this a viewer parked at the very bottom is stuck after one page: the
            // window never leaves the threshold, so the re-arm never fires and they
            // would have to scroll away and back to get the next one.
            this.infiniteArmed = null;
            this.syncAriaTotals();
            this.performanceCache.setTotalElements(next);
            this.navigationEngine.updateConfig(next, this.viewportHeight);
            this.viewportRenderer.updateTotalElements(next);
            this.nativeScrollbar.updateNativeScrollbarHeight(next);
            // Resizing a native scroll surface changes the meaning of its existing
            // scrollTop. Re-anchor both native input surfaces immediately to the
            // unchanged logical camera so an asynchronous browser scroll event cannot
            // reinterpret the old pixel position and move the viewport. Each surface
            // already defers its write while its own gesture is active.
            this.syncScrollbar();
        }
        /** Reset camera to element 0, offset 0. */
        reset() {
            this.navigationEngine.reset();
        }
        /**
         * Mount the visible window and measure rows. Call from `onScroll` (and once
         * after construct). The callback fills the element; the engine reads
         * `offsetHeight` — returning a height is ignored.
         *
         * @param windowHeight Viewport height in pixels (typically `container.clientHeight`).
         * @param container Host (or inner content) element rows are attached to.
         * @param renderElement `(index, element) => void` — populate `element` for `index`.
         * @returns Snapshot of the pass. `renderedElements` is reused; do not retain it.
         */
        renderViewport(windowHeight, container, renderElement) {
            var _a, _b;
            if (!Number.isFinite(windowHeight) || windowHeight <= 0) {
                throw new Error(`CeriousScroll.renderViewport: windowHeight must be a positive finite number, got ${windowHeight}`);
            }
            if (!container || typeof container.appendChild !== 'function') {
                throw new Error('CeriousScroll.renderViewport: container must be an HTMLElement');
            }
            if (typeof renderElement !== 'function') {
                throw new Error('CeriousScroll.renderViewport: renderElement must be a function');
            }
            // Subtract any placement top inset (e.g. the table header) from the area the
            // renderer fills, so rows stop at the container bottom rather than running
            // the header's height past it. Invalidate first so we don't reuse a stale
            // header height; the value measured after this pass is cached for scroll()
            // so wheel/touch don't force getBoundingClientRect every event.
            if (this.masonry) {
                // Masonry mounts CARDS, not one node per virtual element. `renderElement`
                // is ignored: cards are populated by `masonry.renderItem`, which runs once
                // per visible mount rather than once per frame. Dynamic mode may also use
                // it to populate the offscreen measurement probe.
                const usable = this.syncViewportHeight(windowHeight);
                this.masonry.render(usable, container, this);
                return this.masonryRange();
            }
            (_b = (_a = this.placement).invalidateTopInset) === null || _b === void 0 ? void 0 : _b.call(_a);
            const insetBefore = this.placement.getTopInset ? this.placement.getTopInset() : 0;
            const effectiveWindowHeight = Math.max(1, windowHeight - insetBefore);
            let target = this.renderTarget(container);
            const rowRenderer = renderElement;
            this.relocateServerRows(container, target);
            const range = this.viewportRenderer.renderViewport(effectiveWindowHeight, target, rowRenderer);
            // Re-sync the engine's viewport height to the area rows actually fill
            // (`windowHeight` minus the current inset). We compare against the live
            // viewportHeight, not just `insetBefore`, because the inset can change
            // *between* renders — e.g. a framework wrapper mounts the <thead> content
            // asynchronously after the engine first measured an empty header. Without
            // this, the true-bottom math is off by the header height and the last row
            // never quite renders.
            this.syncViewportHeight(windowHeight);
            this.updateDisplay();
            // Rows have just been measured, so this is the first moment the strip can know whether the
            // dataset actually overflows. The strip is built before any render, when no tail height is
            // known, and must assume it does — leaving a short list with a bar it never needed until some
            // later resize happened to correct it.
            this.nativeScrollbar.refreshScrollRange();
            this.syncSticky(this.renderTarget(container), range, renderElement);
            this.checkInfinite(range);
            return range;
        }
        /**
         * Re-sync the engine's cached viewport height to the host.
         *
         * The engine measures the host once at construction and normally re-syncs
         * here, from inside {@link renderViewport}. A consumer that drives its own DOM
         * — anything that does not call `renderViewport` — must call this instead, or
         * the engine keeps its construction-time height forever. True-bottom is
         * derived from that height, so a stale value silently clamps the scroll short
         * of the end by exactly the drift.
         *
         * @param observedHeight Host height in pixels, before any placement top inset.
         * @returns The usable height the engine now holds.
         */
        syncViewportHeight(observedHeight) {
            var _a, _b;
            if (!Number.isFinite(observedHeight) || observedHeight <= 0)
                return this.viewportHeight;
            (_b = (_a = this.placement).invalidateTopInset) === null || _b === void 0 ? void 0 : _b.call(_a);
            const inset = this.placement.getTopInset ? this.placement.getTopInset() : 0;
            const synced = Math.max(1, observedHeight - inset);
            if (synced !== this.viewportHeight) {
                this.viewportHeight = synced;
                this.windowHeight = synced;
                this.navigationEngine.updateConfig(this.totalElements, this.viewportHeight);
                this.viewportRenderer.invalidateTrueBottomCache();
            }
            return this.viewportHeight;
        }
        /**
         * @returns Scroll position from `0` (top) to `100` (measured true bottom).
         */
        calculateScrollPercentage() {
            const trueBottom = this.viewportRenderer.calculateTrueBottomPosition(this.viewportHeight);
            let currentPosition = this.currentElement;
            if (this.scrollOffset > 0 && this.currentElement < this.totalElements - 1) {
                const elementHeight = this.getElementHeight(this.currentElement);
                const offsetFraction = elementHeight > 0 ? this.scrollOffset / elementHeight : 0;
                currentPosition += offsetFraction;
            }
            if (trueBottom) {
                const trueBottomElementHeight = this.getElementHeight(trueBottom.element);
                const trueBottomPosition = trueBottom.element + (trueBottomElementHeight > 0 ? trueBottom.offset / trueBottomElementHeight : 0);
                if (trueBottomPosition <= 0)
                    return 0;
                if (currentPosition >= trueBottomPosition - 0.01) {
                    return 100;
                }
                const percentage = (currentPosition / trueBottomPosition) * 100;
                return Math.max(0, Math.min(100, percentage));
            }
            // Tail not measured yet (first frames).
            const totalPositions = this.totalElements - 1;
            if (totalPositions <= 0)
                return 0;
            const percentage = (currentPosition / totalPositions) * 100;
            return Math.max(0, Math.min(100, percentage));
        }
        /**
         * Sum of measured heights from row 0 up to, but not including, `row`.
         *
         * @param row Exclusive end index.
         * @returns Pixels. Unmeasured rows contribute a 1px placeholder.
         */
        getCumulativeHeight(row) {
            return this.performanceCache.getCumulativeHeight(row);
        }
        /**
         * Map an absolute pixel position onto `{ element, offset }`.
         *
         * @param scrollPixel Distance from the top of the dataset in pixels.
         * @returns Camera for that pixel. Unmeasured rows are treated as 1px.
         */
        findRowFromScrollPosition(scrollPixel) {
            return this.performanceCache.findRowFromScrollPosition(scrollPixel);
        }
        /** Drop derived caches (uniform-height hint, true-bottom, header inset). Measured heights stay. */
        invalidateCache() {
            var _a, _b;
            this.performanceCache.invalidateCache();
            this.viewportRenderer.invalidateTrueBottomCache();
            (_b = (_a = this.placement).invalidateTopInset) === null || _b === void 0 ? void 0 : _b.call(_a);
        }
        /**
         * Drop measured heights as well — use when the dataset itself changed
         * (rows inserted/removed/reordered), not merely resized.
         */
        clearAllCaches() {
            var _a, _b;
            this.performanceCache.clearAllCaches();
            this.viewportRenderer.invalidateTrueBottomCache();
            (_b = (_a = this.placement).invalidateTopInset) === null || _b === void 0 ? void 0 : _b.call(_a);
        }
        /**
         * Viewport snapshot for masonry mode. `startElement`/`endElement` are SEGMENT
         * indices, matching the engine's element space; card-level detail belongs to
         * the caller's own render callback.
         */
        /**
         * Move server-rendered rows into whatever the renderer actually fills.
         *
         * A server cannot know about the content element the engine builds for
         * itself — that element does not exist until the client runs — so its rows
         * land in the host. Left there they would be neither adopted nor recycled,
         * and the client would render a second copy of every one of them beside the
         * originals. Runs once, before the first frame.
         */
        relocateServerRows(container, target) {
            var _a;
            if (((_a = this.options.ssr) === null || _a === void 0 ? void 0 : _a.hydrate) !== true)
                return;
            if (this.serverRowsRelocated)
                return;
            this.serverRowsRelocated = true;
            if (target === container)
                return;
            const stray = container.querySelectorAll(':scope > [data-element-index]');
            for (let i = 0; i < stray.length; i++)
                target.appendChild(stray[i]);
        }
        /**
         * Keep a section header pinned above the recycled window.
         *
         * Mounted OUTSIDE the recycler on purpose. A pinned row has to stay on screen
         * while the rows it heads scroll past, and the recycler's whole job is to
         * unmount anything that leaves the window — so a sticky row drawn as a normal
         * row is guaranteed to vanish at exactly the wrong moment. It is a separate,
         * long-lived element that the engine re-renders only when the resolved index
         * changes.
         *
         * @param container Host rows were rendered into.
         * @param range What the frame actually drew.
         * @param renderElement The caller's row renderer, reused so a header looks
         *   like the row it is.
         */
        syncSticky(container, range, renderElement) {
            var _a;
            const sticky = this.options.sticky;
            if (!sticky || typeof sticky.resolve !== 'function')
                return;
            const index = sticky.resolve(range.startElement);
            if (index === null || index === undefined || !Number.isFinite(index) ||
                index < 0 || index >= this.totalElements) {
                (_a = this.stickyElement) === null || _a === void 0 ? void 0 : _a.remove();
                this.stickyElement = null;
                this.stickyIndex = null;
                this.stickyHeight = 0;
                return;
            }
            if (!this.stickyElement) {
                const el = document.createElement('div');
                el.setAttribute('data-cerious-sticky', '');
                // Above the rows, inert to the pointer so the row underneath stays
                // clickable at the edges, and out of the recycler's reach.
                // Logical inset, so the gutter the strip reserves is subtracted from
                // whichever side the strip is actually on.
                el.style.cssText =
                    'position:absolute;top:0;inset-inline-start:0;' +
                        'inset-inline-end:var(--cerious-gutter, 0px);z-index:2;';
                if (sticky.className)
                    el.className = sticky.className;
                container.appendChild(el);
                this.stickyElement = el;
                this.stickyIndex = null;
            }
            else if (this.stickyElement.parentElement !== container) {
                container.appendChild(this.stickyElement);
            }
            if (this.stickyIndex !== index) {
                this.stickyElement.textContent = '';
                renderElement(index, this.stickyElement);
                // Deliberately NOT `data-element-index`: the pinned header is a copy of a
                // row, not a member of the rendered window, and answering row queries
                // would make it look like one to the recycler, to consumers, and to any
                // test counting what is on screen.
                this.stickyElement.dataset.stickyIndex = String(index);
                this.stickyIndex = index;
                // Read once per HAND-OFF, not per frame. This is a write-then-read and so
                // forces a synchronous layout, which is only acceptable because a section
                // change is rare; doing it every frame is the mistake that cost the grid
                // its frame budget.
                this.stickyHeight = this.stickyElement.offsetHeight;
            }
            // The next section's header pushes this one out rather than sliding under
            // it. Without this the pinned header sits at `top: 0` with a higher
            // z-index, so the incoming header disappears behind it and the content
            // swaps abruptly the instant `resolve` flips.
            const push = this.stickyPush(range, sticky.resolve, index);
            this.stickyElement.style.transform = push ? `translateY(${push}px)` : '';
        }
        /**
         * How far to lift the pinned header so the incoming one displaces it.
         *
         * Returns a negative pixel offset while the next section's header is inside
         * the pinned header's band, and 0 otherwise. At the extreme the pinned
         * header's bottom edge lands exactly on the incoming header's top edge, so
         * the two never overlap and the hand-off reads as a push rather than a swap.
         *
         * Computed from the heights the renderer just reported and the camera's own
         * offset, NOT from the DOM: this runs on every frame of a scroll, and a
         * geometry read here would force a synchronous layout over everything just
         * mounted.
         */
        stickyPush(range, resolve, current) {
            const height = this.stickyHeight;
            if (height <= 0)
                return 0;
            const rows = range.renderedElements;
            // `renderedElements` is ascending and begins at the first visible row, so
            // the running total is that row's top edge once the camera offset is taken
            // off it.
            let top = -this.scrollOffset;
            for (let i = 0; i < rows.length; i++) {
                const row = rows[i];
                if (row.index > range.startElement) {
                    // Past the band: no boundary close enough to push anything.
                    if (top >= height)
                        return 0;
                    // A row belonging to a different section is that section's header.
                    if (resolve(row.index) !== current)
                        return top - height;
                }
                top += row.height;
            }
            return 0;
        }
        /**
         * Settle the camera onto a row boundary once scrolling has stopped.
         *
         * Nearly free in this engine: the camera is already `(element, offset)`, so a
         * snap is `offset -> 0` on one row or the next. CSS `scroll-snap-type` cannot
         * do this job — the surface the browser scrolls is a featureless spacer with
         * no snap targets — so it is applied here, on the settle signal the native
         * surface provides.
         *
         * A no-op unless `snap.enabled`, and skipped when the camera is already
         * within `tolerance` of a boundary, which keeps a scroll that had effectively
         * landed from visibly nudging itself afterwards.
         */
        snapToBoundary() {
            var _a, _b, _c, _d, _e;
            const snap = this.options.snap;
            if (!(snap === null || snap === void 0 ? void 0 : snap.enabled))
                return;
            if (this.masonry)
                return; // a card grid has no single row boundary to land on
            const offset = this.scrollOffset;
            const tolerance = Math.max(0, (_a = snap.tolerance) !== null && _a !== void 0 ? _a : 2);
            if (offset <= tolerance)
                return;
            const element = this.currentElement;
            const height = this.getElementHeight(element);
            if (!Number.isFinite(height) || height <= 0)
                return;
            if (offset >= height - tolerance) {
                // Already all but past this row: forward is the near boundary.
                this.jumpToElement(Math.min(element + 1, this.totalElements - 1));
                (_c = (_b = this.options).onScroll) === null || _c === void 0 ? void 0 : _c.call(_b);
                return;
            }
            const forward = snap.align === 'start' ? false : offset > height / 2;
            const target = forward ? Math.min(element + 1, this.totalElements - 1) : element;
            this.jumpToElement(target);
            (_e = (_d = this.options).onScroll) === null || _e === void 0 ? void 0 : _e.call(_d);
        }
        /**
         * Apply screen-reader semantics, if asked.
         *
         * The numbers are the point. A virtualized list mounts a window, so a reader
         * left to count the DOM says "3 of 12" for a dataset of a million;
         * `aria-setsize` and `aria-posinset` state the truth independently of what
         * happens to be rendered, and the engine is the only thing that knows both.
         *
         * Roles are layout-dependent and deliberately conservative: `table` layout
         * emits real `<tr>`/`<td>`, which already mean row and cell, so the engine
         * adds only the virtualization numbers and leaves the semantics alone.
         */
        installAria(container) {
            var _a, _b;
            const aria = this.options.aria;
            if (!(aria === null || aria === void 0 ? void 0 : aria.enabled))
                return;
            const isTable = this.options.layout === 'table';
            if (aria.label)
                container.setAttribute('aria-label', aria.label);
            if (aria.labelledBy)
                container.setAttribute('aria-labelledby', aria.labelledBy);
            const containerRole = (_a = aria.role) !== null && _a !== void 0 ? _a : (isTable ? undefined : 'list');
            if (containerRole)
                container.setAttribute('role', containerRole);
            if (isTable) {
                // The correct ARIA for a virtualized table: the real row count, so the
                // reader does not infer it from the mounted window.
                container.setAttribute('aria-rowcount', String(this.totalElements));
            }
            const itemRole = (_b = aria.itemRole) !== null && _b !== void 0 ? _b : (isTable ? undefined : 'listitem');
            this.viewportRenderer.decorateRow = (el, index) => {
                if (itemRole)
                    el.setAttribute('role', itemRole);
                if (isTable) {
                    // 1-based, and counting the header row, as a real table does.
                    el.setAttribute('aria-rowindex', String(index + 2));
                }
                else {
                    el.setAttribute('aria-setsize', String(this.totalElements));
                    el.setAttribute('aria-posinset', String(index + 1));
                }
            };
        }
        /** Keep `aria-rowcount` truthful when the dataset grows or shrinks. */
        syncAriaTotals() {
            var _a, _b;
            if (!((_a = this.options.aria) === null || _a === void 0 ? void 0 : _a.enabled))
                return;
            if (this.options.layout !== 'table')
                return;
            (_b = this.attachedContainer) === null || _b === void 0 ? void 0 : _b.setAttribute('aria-rowcount', String(this.totalElements));
        }
        /**
         * Ask for more rows when the rendered window nears an edge.
         *
         * Re-arms only when the window leaves the threshold, so a load that appends
         * nothing cannot spin; an in-flight promise also holds the gate, because the
         * common shape is an async fetch and the next frame would otherwise fire
         * again before the first returned.
         */
        checkInfinite(range) {
            var _a;
            const infinite = this.options.infinite;
            if (!infinite || typeof infinite.onLoadMore !== 'function')
                return;
            if (this.infiniteBusy)
                return;
            const threshold = Math.max(0, (_a = infinite.threshold) !== null && _a !== void 0 ? _a : 20);
            const total = this.totalElements;
            let direction = null;
            if (range.endElement >= total - 1 - threshold)
                direction = 'end';
            else if (infinite.edges === 'both' && range.startElement <= threshold)
                direction = 'start';
            if (direction === null) {
                // Out of range again: the next approach is a new one.
                this.infiniteArmed = null;
                return;
            }
            if (this.infiniteArmed === direction)
                return;
            this.infiniteArmed = direction;
            this.infiniteBusy = true;
            const release = () => { this.infiniteBusy = false; };
            try {
                const result = infinite.onLoadMore({
                    direction,
                    first: range.startElement,
                    last: range.endElement,
                    total
                });
                if (result && typeof result.then === 'function') {
                    result.then(release, release);
                }
                else {
                    release();
                }
            }
            catch (error) {
                release();
                throw error;
            }
        }
        /**
         * Where rows actually go.
         *
         * A caller that hands us the host is describing WHERE it wants rows, not
         * demanding a particular node. When this engine created the content element
         * the host lacked, that intent is served by the element inside — and it has
         * to be, because the native surface holds that element still and anything
         * left outside it would not move with the rows. A caller that names some
         * other element is being specific, and is left alone.
         */
        renderTarget(container) {
            if (this.ownedContent && container === this.ownedContentHost)
                return this.ownedContent;
            return container;
        }
        masonryRange() {
            this.updateDisplay();
            return {
                startElement: this.currentElement,
                endElement: this.currentElement,
                scrollPercentage: this.scrollPercentage,
                viewportElements: 1,
                renderedElements: [],
                totalRenderedHeight: this.viewportHeight
            };
        }
        /**
         * Scroll a specific CARD into view. Masonry mode only.
         *
         * {@link jumpToElement} takes a segment index in this mode, which is an
         * internal unit; this takes the card index the caller actually thinks in.
         *
         * @param index Card index.
         * @param screenOffset Pixels below the viewport top to place it. Default 0.
         */
        jumpToItem(index, screenOffset = 0) {
            if (!this.masonry) {
                throw new Error("CeriousScroll.jumpToItem: only available with layout 'masonry'");
            }
            const pos = this.masonry.cameraForItem(index, screenOffset);
            if (!pos)
                return;
            this.navigationEngine.jumpToPosition(pos.segment, pos.offset);
        }
        /** Cards in the dataset. Masonry mode only; otherwise equals `totalElements`. */
        get itemCount() {
            return this.masonry ? this.totalItems : this.totalElements;
        }
        /**
         * Current column width in pixels, or `null` outside masonry mode.
         *
         * Exposed because real cards need it: requesting a CDN image at the column's
         * actual width, choosing a `srcset` candidate, or deciding how much text to
         * render all depend on it, and it changes with the container.
         */
        get masonryColumnWidth() {
            return this.masonry ? this.masonry.columnWidth : null;
        }
        /** Current column count, or `null` outside masonry mode. */
        get masonryColumns() {
            return this.masonry ? this.masonry.columns : null;
        }
        /**
         * Determinism guarantee of the current masonry layout, or `null` outside
         * masonry mode. See {@link MasonryDeterminism}.
         *
         * Worth branching on rather than assuming. Under `'local'` a card's column
         * depends on how the viewer reached it, so a feature that treats a position as
         * shareable — a deep link to a card, a saved scroll coordinate, a
         * pixel-comparison test — is only sound under `'canonical'`.
         */
        get masonryDeterminism() {
            return this.masonry ? this.masonry.determinism : null;
        }
        /**
         * Re-size the scrollbar strip and re-sync it, after total content height
         * changed without the element count changing.
         *
         * {@link updateTotalElements} covers the usual case, but a computed layout can
         * change its total height while the element count is fixed — a relayout, or a
         * progressive height calculation settling from estimate to exact. Without this
         * the strip keeps its stale surface and the thumb misreports the range.
         */
        refreshScrollbarMetrics() {
            this.nativeScrollbar.updateNativeScrollbarHeight(this.totalElements);
            this.syncScrollbar();
        }
        /** Refresh `startElement`, `endElement`, `scrollPercentage`, `viewportTop`. */
        updateDisplay() {
            const snapshot = this.viewportStateCalculator.calculate();
            this.startElement = snapshot.startElement;
            this.endElement = snapshot.endElement;
            this.scrollPercentage = snapshot.scrollPercentage;
            this.viewportTop = snapshot.viewportTop;
        }
        /**
         * Re-sync the native scrollbar after geometry changed without a scroll
         * event — typically `updateTotalElements()` + a re-render. Growing the
         * track leaves a bottom thumb stranded until this runs. Call after rows
         * are re-measured. No-op while the user is dragging (see NativeScrollbar).
         */
        syncScrollbar() {
            var _a;
            if (this.nativeScrollbar.container && !this.nativeScrollbar.isSyncing) {
                this.nativeScrollbar.syncNativeScrollbar();
            }
            (_a = this.nativeTouchController) === null || _a === void 0 ? void 0 : _a.syncPosition();
        }
        /**
         * Host size changed. Re-measures viewport height, invalidates header inset,
         * then reflows (re-anchor, scrollbar sync, `onScroll`).
         *
         * @param container The same host passed to the constructor.
         */
        handleViewportChange(container) {
            var _a, _b;
            // Header height can change with the container; drop the cache so table
            // mode re-reads getBoundingClientRect once, not on every scroll.
            (_b = (_a = this.placement).invalidateTopInset) === null || _b === void 0 ? void 0 : _b.call(_a);
            this.viewportHeight = this.measureViewport(container);
            this.windowHeight = this.viewportHeight;
            this.navigationEngine.updateConfig(this.totalElements, this.viewportHeight);
            // Does not recreate the strip — recreating reset scrollTop to 0 and
            // stranded echo-accounting on the discarded node (dead zone).
            this.nativeScrollbar.handleViewportChange(container, this.viewportHeight);
            this.reflow();
        }
        /**
         * Resize or in-place row height change with no explicit scroll. Re-anchor
         * if empty space appeared under the last row, sync the thumb (programmatic
         * marker swallows the echo so we don't jump to top), then `onScroll` so
         * the host re-renders. The engine does not own the row callback.
         */
        reflow() {
            var _a, _b;
            this.navigationEngine.reanchorBottom(this.viewportHeight);
            if (this.nativeScrollbar.container && !this.nativeScrollbar.isSyncing) {
                this.nativeScrollbar.syncNativeScrollbar();
            }
            this.updateDisplay();
            (_b = (_a = this.options).onScroll) === null || _b === void 0 ? void 0 : _b.call(_a);
        }
        /**
         * Attach resize observers on `container` (and `window.resize`).
         *
         * @param container Host element.
         * @returns Detach function.
         */
        setupAutoResizeHandling(container) {
            return this.resizeController.attach(container);
        }
        /**
         * Remove the native scrollbar strip and restore padding.
         *
         * @param container Optional. Used to find an orphan strip if this instance
         *   is not tracking one.
         */
        detachScrollbar(container) {
            this.nativeScrollbar.detachScrollbar(container);
        }
        /**
         * Attach wheel handling. The constructor already does this when
         * `wheel.enabled` is not `false`.
         *
         * @param container Host element.
         * @param onScroll Invoked after each applied delta with `{ element, offset }`.
         * @param wheelOptions Overrides constructor `wheel` options.
         * @returns Detach function.
         *
         * @example
         * ```ts
         * const cleanup = scroller.setupWheelHandler(container, () => {
         *   scroller.renderViewport(container.clientHeight, container, renderCallback);
         * });
         * ```
         */
        setupWheelHandler(container, onScroll, wheelOptions) {
            // Standalone use cannot assume the native surface is mounted around this
            // container, so it gets the self-contained path.
            return this.wheelController.attach(container, onScroll, wheelOptions, false);
        }
        /**
         * Attach touch handling. The constructor already does this when
         * `touch.enabled` is not `false`.
         *
         * @param container Host element.
         * @param onScroll Invoked after each applied delta with `{ element, offset }`.
         * @param options Overrides constructor `touch` options.
         * @returns Detach function.
         *
         * @example
         * ```ts
         * const cleanup = scroller.setupTouchHandler(container, () => {
         *   scroller.renderViewport(container.clientHeight, container, renderCallback);
         * });
         * ```
         */
        setupTouchHandler(container, onScroll, options) {
            return this.touchController.attach(container, onScroll, options);
        }
        /** Detach listeners, observers, and the debug hook. Call when the host leaves the DOM. */
        dispose() {
            var _a, _b, _c, _d, _e, _f, _g, _h;
            (_a = this.masonry) === null || _a === void 0 ? void 0 : _a.dispose();
            (_b = this.keyboardCleanup) === null || _b === void 0 ? void 0 : _b.call(this);
            this.keyboardCleanup = undefined;
            (_c = this.wheelCleanup) === null || _c === void 0 ? void 0 : _c.call(this);
            this.wheelCleanup = undefined;
            (_d = this.touchCleanup) === null || _d === void 0 ? void 0 : _d.call(this);
            this.touchCleanup = undefined;
            (_e = this.resizeCleanup) === null || _e === void 0 ? void 0 : _e.call(this);
            this.resizeCleanup = undefined;
            (_f = this.contentObserverCleanup) === null || _f === void 0 ? void 0 : _f.call(this);
            this.contentObserverCleanup = undefined;
            if (this.debugCleanup) {
                try {
                    this.debugCleanup();
                }
                catch ( /* noop */_j) { /* noop */ }
                this.debugCleanup = undefined;
            }
            // After the controllers have detached — the surface puts the content element
            // back where it found it, and only then is this safe to remove.
            (_g = this.stickyElement) === null || _g === void 0 ? void 0 : _g.remove();
            this.stickyElement = null;
            this.stickyIndex = null;
            this.stickyHeight = 0;
            if ((_h = this.ownedContent) === null || _h === void 0 ? void 0 : _h.parentNode)
                this.ownedContent.parentNode.removeChild(this.ownedContent);
            this.ownedContent = null;
            this.ownedContentHost = null;
            this.clearAllCaches();
        }
    }
    CeriousScroll.VIRTUAL_TRACK_HEIGHT = 15000;
    CeriousScroll.DEFAULT_ELEMENT_HEIGHT = 40;
    CeriousScroll.VIEWPORT_BUFFER_SIZE = 50;
    CeriousScroll.NEAR_END_THRESHOLD = 100;

    exports.CeriousScroll = CeriousScroll;

    return exports;

})({});
