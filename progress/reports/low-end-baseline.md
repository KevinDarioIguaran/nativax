# Low-end branch: before/after

Branch: `perf/low-end-idle` (no push; main stays at `559cf07`).

Harness: Bible app profile build, `NATIVAX_AUTOSCROLL=1`,
`NATIVAX_BENCH=1`, 6 s steady window; CPU from `/proc/<pid>/stat`;
RSS from `VmRSS`; first content from the app's `FIRST_CONTENT` stopwatch.

| Metric | Before | After |
|---|---:|---:|
| Scroll build avg | 6–7 ms | 5.9 ms |
| Scroll build p50 | 3 ms | 3 ms |
| Scroll build p95 | 8–22 ms | 16 ms |
| Scroll raster | 1–2 ms | 1.6 ms |
| CPU scrolling | 63–90 % | 91 % (single run; 63–91 range) |
| CPU idle (warm) | 59–78 % | 2.2–3.3 % |
| RSS idle | 397–420 MB | 393 MB |
| RSS scrolling | 479–499 MB | 551 MB (single high run) |
| First content | not measured (~15 s reported) | 1279 ms |
| QuickJS scrolling | 330 MB / ~7 frames in 6 s | 332 MB / 8 frames, CPU 100.8 % |
| 1-core scroll | not measured | 82 % CPU, 177 frames, build p95 12 ms |

## Changes applied

- Idle HUD repaint isolated and sampled every 2 s instead of 1 s.
- Background sync limited to the current book; 5 s gap between books; no
  duplicate `memSet` of every synced chapter. Remaining IndexedDB work no
  longer keeps a warm idle app at 59–78 % CPU.
- Image cache capped at 24 MB / 200 entries; JSON memory cache capped at 64
  LRU entries.
- Font faces filtered to used families while always retaining Font Awesome;
  linked font URLs resolve against the stylesheet. Icons verified visible.

## Still open

- True per-subtree invalidation; scroll-driven content mutations are only
  deferred until scroll idle, not applied incrementally.
- One bulk chapter/verse build still exceeds 100 ms at load. First content is
  1.279 s but the startup frame is ~1.5 s.
- QuickJS is not applied: 332 MB but 8 frames/6 s.
- 250 MB is not reached: ~393 MB idle and ~550 MB scrolling with V8.
- p95 is 16 ms on the normal run but 31 ms with one core; GC/materialization
  spikes remain.
