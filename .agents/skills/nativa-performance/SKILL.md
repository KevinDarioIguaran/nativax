---
name: nativa-performance
description: Use before optimizing, benchmarking, measuring memory or leaks, or claiming speed, latency, frame-rate, or 7x improvements in Nativa.
---

# Nativa performance

Read `references/performance.md` before measuring or optimizing.

## Workflow

1. Define the workload and checksum. The work must be equivalent to the baseline.
2. Record engine and version, OS, architecture, mode (JIT/AOT), profile, date,
   and command.
3. Use warm-up, multiple rounds, median, MAD, percentiles, and environment
   metadata.
4. Separate pure JS, bridge, DOM, CSS/layout, and renderer.
5. For memory, use a baseline, batches, GC, positive and negative controls, and
   resource counters. One RSS sample is not a leak.
6. Compare against the stored baseline with both a threshold and measured noise.
7. Run final decisions in release/AOT. JIT results are useful for trends, not
   final claims.

## 7x requirement

Pure JavaScript will not become 7x faster while keeping QuickJS-ng. The valid
goal is 7x end-to-end on app workloads (WebAssembly physics, bridge, DOM/layout,
renderer). The admitted routes are WAMR AOT/JIT for WebAssembly with wasm3 as
fallback, and a V8/JavaScriptCore adapter on platforms that allow JIT. Do not
change the work, checksum, input size, or denominator to claim 7x.

## Output

Report the command, workload, baseline, result, dispersion, and limitations.
Never claim a speedup or leak without reproducible evidence.
