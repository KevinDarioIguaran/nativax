# Low-end baseline before idle/load work

Branch: `perf/low-end-idle` (from `559cf07`)

Harness: Bible app profile build, `NATIVAX_AUTOSCROLL=1`,
`NATIVAX_BENCH=1`, 6 s steady scroll window; CPU from `/proc/<pid>/stat`,
RSS from `VmRSS`.

| Metric | Value |
|---|---:|
| Scroll build avg | 6–7 ms |
| Scroll build p50 | 3 ms |
| Scroll build p95 | 8–22 ms |
| Scroll raster | 1–2 ms |
| CPU while scrolling | 63–90 % |
| CPU idle | 59–78 % |
| RSS idle | 397–420 MB |
| RSS scrolling | 479–499 MB |
| QuickJS scrolling | 330 MB, ~7 frames / 6 s, CPU ~101 % |

Known open items: true per-subtree invalidation, idle CPU, initial loading
stall, QuickJS cost, RAM target 250 MB.
