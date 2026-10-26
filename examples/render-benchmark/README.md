# Render benchmark

A Flutter profile/AOT benchmark for large NativaX documents. It measures
renderer build/layout/paint behavior; it is not a GPU FPS test and not part of
the public runtime API.

## Build and run

```bash
cd examples/render-benchmark
flutter build linux --profile

NATIVAX_BENCH_FILE=/tmp/list_10k.html \
  build/linux/x64/profile/bundle/render_benchmark
```

Run a scenario on the built bundle:

```bash
NATIVAX_BENCH_HTML=/path/to/page.html \
NATIVAX_SCENARIO=scroll \
  build/linux/x64/profile/bundle/render_benchmark
```

## Controls

| Variable | Meaning |
|---|---|
| `NATIVAX_BENCH_FILE` | Load a page from a file |
| `NATIVAX_BENCH_HTML` | Load a page from a Flutter asset |
| `NATIVAX_SCENARIO` | `load` (default), `mutate`, `updateall`, `scroll`, `resize` |
| `NATIVAX_TARGET` | CSS selector for the operation target (default `#doc`) |
| `NATIVAX_BENCH_ROOT` | Override the asset root |
| `NATIVAX_SCROLL_STEPS` | Scroll steps (default 40) |
| `NATIVAX_FRAMES_MS` | Frame/settle time (default 1200 ms) |
| `NATIVAX_NO_STYLE_CACHE=1` | Disable style caches for comparison |
| `NATIVAX_METRICS=1` | Enable runtime metrics |
| `NATIVAX_LAYOUT_PROFILE=1` | Enable layout profiling |
| `NATIVAX_JSON` | Write JSON results to this path |

These are harness controls, not stable configuration for applications.

## Scenarios

- `load`: build the initial document;
- `mutate`: change a small part of the tree;
- `updateall`: update all target children;
- `scroll`: scroll the target;
- `resize`: force a viewport resize.

## Limits

- Offscreen/profile CPU build/layout/paint, not GPU rasterization.
- No network; assets must be local.
- A single run has variance; compare medians and scenario, not one frame.
- Results depend on the document, host machine, Flutter mode, and caches.
- A profile build is a developer measurement, not a release guarantee.

For the registered performance suite and baseline, see
[`../../docs/performance-suite.md`](../../docs/performance-suite.md).
