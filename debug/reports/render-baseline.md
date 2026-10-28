# NativaX Native — Render Baseline

**Date:** 2026-10-28
**Commit:** e269f95
**Command:** `./build/nativax_bench --w 320 --h 200 --cards 2 --text 12 --iters 2`

```json
{"bench":"render","w":320,"h":200,"iters":2,"cards":2,
 "build_ms":0.067,"clear_ms":0.040,"raster_ms":14.530,
 "frame_ms":14.570,"raster_mpix_s":4.4,
 "avg_verts":4128,"avg_indices":6480,"checksum":"e89099fa"}
```

Notes:
- `raster_ms` is the CPU rasterizer path, not the GPU path.
- Checksum is deterministic; any change indicates a rendering change.
