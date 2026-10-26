# Game player — phase 0 (2026-10-21)

Raw data from the WebGL presentation instrumentation. The complete original
report is archived at
[`../../../progress/history/phase0-presentation-2026-10-21-es.md`](../../../progress/history/phase0-presentation-2026-10-21-es.md).

## Files

- `baseline_fixed_1280x720.jsonl`: 50 two-second windows with a fixed
  1280×720 window and DPR 1.0. The first 2 windows were dropped and the last 15
  (30 s) were summarized.
- `summary_baseline.txt`: output of
  `debug/engines/performance/game_player/summarize_metrics.py` with
  `--skip 2 --last 15 --buffer 1280x720`.
- `exploratory_no_backdrop.jsonl`: exploratory run with
  `NATIVAX_NO_BACKDROP=1`. **This is not a valid A/B**: the window changed to
  1280×702 and 1366×720 during the test, so it has no comparable samples at
  1280×720.

## Selected baseline

| Metric | Value |
|---|---:|
| render | 34.7 fps |
| shown | 26.3 fps |
| UI | 32.0 fps |
| present p50/p95/p99 | 34.5 / 74.0 / 85.5 ms |
| decode p50/p95 | 4.0 / 37.2 ms |
| build p95 | 2.9 ms |
| raster p95 | 15.1 ms |
| UI total p50/p95 | 27.8 / 44.0 ms |
| jank > 50 ms | 1.2 % |

The target of 45 shown fps / p95 ≤ 25 ms **was not reached**. The native
texture path was not implemented; the player remains on the stable
`GlSurfaceView` + `RawImage` path at DPR 1.0. These numbers are a historical
phase-0 measurement, not a current performance claim.

## Reproduce

```bash
cd examples/game-player
flutter build linux --release
cd ../..
debug/engines/performance/game_player/bench_game_player.sh base_r1 36
python3 debug/engines/performance/game_player/summarize_metrics.py \
  /tmp/opencode/nativax-metrics/base_r1.jsonl \
  --skip 2 --last 15 --buffer 1280x720
```
