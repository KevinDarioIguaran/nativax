/**
 * Demo bootstrap helper for the vanilla cerious-scroll demos.
 *
 * Mirrors what the Vue/React/Angular wrappers do internally:
 *   - inserts a [data-cerious-scroll-content] element inside the host
 *   - creates a `new CeriousScroll(host, total, opts)` instance
 *   - re-renders into the content element on every scroll/resize/data change
 *
 * Usage:
 *   const demo = mountDemo({
 *     host: document.querySelector('.demo-scroll'),
 *     total: 100_000,
 *     render: (index, container) => {
 *       const el = document.createElement('div');
 *       el.className = 'basic-row';
 *       el.textContent = 'Row #' + index;
 *       container.appendChild(el);
 *     },
 *     onViewport: (v) => { ... },
 *   });
 *
 *   // demo.scroller    → the CeriousScroll instance
 *   // demo.setTotal(n) → recreate the engine with a new dataset size
 *   // demo.render()    → request a manual re-render
 */
(function (root) {
  const CONTENT_ATTR = 'data-cerious-scroll-content';

  function ensureContentElement(container) {
    let el = container.querySelector('[' + CONTENT_ATTR + ']');
    if (el) return el;
    el = document.createElement('div');
    el.setAttribute(CONTENT_ATTR, '');
    el.style.position = 'relative';
    el.style.width = '100%';
    el.style.height = '100%';
    el.style.overflowY = 'clip';
    el.style.overflowX = 'auto';
    container.appendChild(el);
    return el;
  }

  function mountDemo(config) {
    const host = config.host;
    const userRender = config.render;
    if (!host) throw new Error('mountDemo: host element required');
    if (typeof userRender !== 'function') throw new Error('mountDemo: render() required');

    // Always hand the demo a CLEAN container. renderViewport() pools/clears new
    // rows for us, but refreshVisible() re-renders already-populated rows in
    // place — without clearing first, demos that append (the common pattern)
    // stack a fresh copy on every refresh (doubling on each data update/click).
    const renderFn = function (index, container) {
      container.textContent = '';
      return userRender(index, container);
    };

    const contentEl = ensureContentElement(host);

    let state = {
      total: Math.max(1, Math.floor(config.total || 1)),
      scroller: null,
    };

    function viewportHeight() {
      return contentEl.clientHeight || host.clientHeight || 0;
    }

    function render() {
      if (!state.scroller) return null;
      return state.scroller.renderViewport(viewportHeight(), contentEl, renderFn);
    }

    function emitViewport() {
      if (typeof config.onViewport !== 'function') return;
      const s = state.scroller;
      if (!s) return;
      config.onViewport({
        currentElement: s.currentElement,
        scrollOffset: s.scrollOffset,
        percentage: s.scrollPercentage,
        startElement: s.startElement,
        endElement: s.endElement,
        viewportHeight: viewportHeight(),
      });
    }

    function createScroller(initialPos) {
      const userOpts = config.options || {};
      const userOnScroll = userOpts.onScroll;
      const merged = Object.assign({}, userOpts, {
        onScroll: function () {
          if (typeof userOnScroll === 'function') userOnScroll();
          render();
          emitViewport();
        },
      });
      const Ctor = (typeof root.CeriousScroll === 'function')
        ? root.CeriousScroll
        : (root.CeriousScroll && root.CeriousScroll.CeriousScroll);
      if (typeof Ctor !== 'function') throw new Error('CeriousScroll constructor not found on window');
      const s = new Ctor(host, state.total, merged);
      if (initialPos) {
        s.currentElement = Math.min(initialPos.currentElement, state.total - 1);
        s.scrollOffset = initialPos.scrollOffset;
      }
      state.scroller = s;
    }

    function setTotal(n) {
      const next = Math.max(1, Math.floor(n));
      const old = state.scroller;
      const pos = old ? { currentElement: old.currentElement, scrollOffset: old.scrollOffset } : null;
      if (old) {
        try { old.detachScrollbar(host); } catch (e) {}
        try { old.dispose(); } catch (e) {}
      }
      contentEl.textContent = '';
      state.total = next;
      createScroller(pos && pos.currentElement < next ? pos : null);
      render();
      emitViewport();
    }

    function refresh() {
      if (!state.scroller) return;
      try {
        state.scroller.refreshVisible(renderFn);
      } catch (e) {
        render();
      }
    }

    // Initial mount
    createScroller(null);
    // First render on next frame so layout has settled
    requestAnimationFrame(function () {
      render();
      emitViewport();
    });

    // Re-render on resize
    const ro = new ResizeObserver(function () {
      render();
      emitViewport();
    });
    ro.observe(host);

    return {
      get scroller() { return state.scroller; },
      get total() { return state.total; },
      render: render,
      refresh: refresh,
      setTotal: setTotal,
      // Grow/shrink the dataset IN PLACE — no teardown, unlike setTotal(). Use
      // for a live append/prepend feed: setTotal() recreates the scroller (and
      // the scrollbar the user may be dragging), which freezes the drag.
      updateTotal: function (n) {
        if (!state.scroller) return;
        const next = Math.max(1, Math.floor(n));
        state.total = next;
        state.scroller.updateTotalElements(next);
      },
      jumpTo: function (index) {
        if (!state.scroller) return;
        state.scroller.jumpToElement(Math.max(0, Math.min(state.total - 1, index | 0)));
        // jumpToElement updates engine state but does not emit onScroll, so the
        // consumer must re-render and refresh stats after a programmatic move.
        render();
        emitViewport();
      },
      scrollToPercentage: function (pct) {
        if (!state.scroller) return;
        // The scroller exposes handleScrollPercentage (not scrollToPercentage);
        // it also doesn't emit onScroll, so render + emit here.
        state.scroller.handleScrollPercentage(pct);
        render();
        emitViewport();
      },
      destroy: function () {
        ro.disconnect();
        if (state.scroller) {
          try { state.scroller.detachScrollbar(host); } catch (e) {}
          try { state.scroller.dispose(); } catch (e) {}
        }
        state.scroller = null;
      },
    };
  }

  // Tiny deterministic PRNG so demo data is stable & re-renders agree.
  function hash(index, salt) {
    let h = (index * 374761393 + salt * 668265263) | 0;
    h = (h ^ (h >>> 13)) * 1274126177;
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  }
  function randInt(index, lo, hi, salt) { return lo + Math.floor(hash(index, salt || 1) * (hi - lo + 1)); }
  function pick(arr, index, salt) { return arr[Math.floor(hash(index, salt || 1) * arr.length)]; }

  root.mountDemo = mountDemo;
  root.demoUtils = { hash: hash, randInt: randInt, pick: pick };

  // ---- Analytics ----------------------------------------------------------
  // Every page in this site loads this file, so the tag lives here rather than
  // being pasted into each document. Nine of eighteen pages previously carried
  // no tag at all, the benchmark among them, which left half the site invisible
  // in reporting.
  const GA_ID = 'G-S1NK61TS72';

  /**
   * Classify the current page from its filename, so reports can separate the
   * benchmark from the demos without pattern-matching URLs in the GA console.
   */
  function pageIdentity() {
    const file = (root.location.pathname.split('/').pop() || 'index.html').toLowerCase();
    const name = file.replace(/\.html$/, '');
    if (!name || name === 'index') return { type: 'gallery', id: 'gallery' };
    if (name === 'benchmark') return { type: 'benchmark', id: 'benchmark' };
    // 'data-grid-demo' -> 'data-grid', 'comparison-demo' -> 'comparison'
    return { type: 'demo', id: name.replace(/-demo$/, '') };
  }

  function initAnalytics() {
    // Local development traffic never reaches reporting.
    const host = root.location.hostname;
    if (root.location.protocol === 'file:' ||
        !host || host === 'localhost' || host === '127.0.0.1' || host === '[::1]') {
      return;
    }
    // If a page still carries its own inline tag, let it win rather than
    // loading gtag twice and double-counting the page view.
    if (document.querySelector('script[src*="googletagmanager.com/gtag/js"]')) return;

    const script = document.createElement('script');
    script.async = true;
    script.src = 'https://www.googletagmanager.com/gtag/js?id=' + GA_ID;
    document.head.appendChild(script);

    root.dataLayer = root.dataLayer || [];
    function gtag() { root.dataLayer.push(arguments); }
    root.gtag = gtag;

    const page = pageIdentity();
    gtag('js', new Date());
    // These ride along on the automatic page_view. page_type and page_id are
    // custom parameters: they have to be registered as custom dimensions in the
    // GA4 admin before they appear in reports.
    gtag('config', GA_ID, {
      page_type: page.type,
      page_id: page.id,
      page_title: document.title,
      // Lets the vanilla site be compared against the React, Vue and Angular
      // demo apps inside a single GA property.
      wrapper: 'vanilla',
    });
  }

  /**
   * Send a one-off event. No-ops when analytics did not initialise, so callers
   * never have to check first.
   */
  function trackEvent(name, params) {
    if (typeof root.gtag !== 'function') return;
    root.gtag('event', name, params || {});
  }

  root.trackEvent = trackEvent;

  initAnalytics();

  // ---- Topbar + FPS meter -------------------------------------------------
  // Auto-renders the shared topbar (brand, FPS meter, "All demos", npm link)
  // into the first `<header class="topbar" data-auto-topbar>` element on the
  // page, mirroring the layout used by the Vue/React/Angular demo apps.
  const NPM_URL = 'https://www.npmjs.com/package/@ceriousdevtech/cerious-scroll';

  function renderTopbar() {
    const bar = document.querySelector('header.topbar[data-auto-topbar]');
    if (!bar) return;
    const onGallery = bar.hasAttribute('data-gallery');
    const onBenchmark = /benchmark\.html$/.test(location.pathname);
    bar.innerHTML =
      '<a class="topbar__brand" href="index.html">CeriousScroll <small>Vanilla JS demos</small></a>' +
      '<div class="topbar__spacer"></div>' +
      '<span class="fps-meter" id="fps-meter" title="Live frames per second">' +
        '<span class="fps-meter__value">0</span>' +
        '<span class="fps-meter__unit">FPS</span>' +
      '</span>' +
      (onGallery ? '' : '<a class="topbar__link" href="index.html">← All demos</a>') +
      // The benchmark is not one of the demos, so it gets its own way in from
      // every page rather than living in the gallery grid.
      (onBenchmark ? '' : '<a class="topbar__link topbar__link--accent" href="benchmark.html">Benchmark</a>') +
      '<a class="topbar__link" href="' + NPM_URL + '" target="_blank" rel="noreferrer">npm ↗</a>';
    startFpsMeter();
  }

  function startFpsMeter() {
    const el = document.getElementById('fps-meter');
    if (!el) return;
    const valueEl = el.querySelector('.fps-meter__value');
    let frames = 0;
    let last = performance.now();
    function loop(now) {
      frames++;
      const elapsed = now - last;
      if (elapsed >= 500) {
        const fps = Math.round((frames * 1000) / elapsed);
        valueEl.textContent = String(fps);
        el.classList.remove('fps-meter--good', 'fps-meter--ok', 'fps-meter--bad');
        el.classList.add('fps-meter--' + (fps >= 55 ? 'good' : fps >= 30 ? 'ok' : 'bad'));
        frames = 0;
        last = now;
      }
      requestAnimationFrame(loop);
    }
    requestAnimationFrame(loop);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', renderTopbar);
  } else {
    renderTopbar();
  }
})(window);
