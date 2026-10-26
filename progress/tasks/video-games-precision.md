# Task: video and game precision

Goal: measure video and games with the same evidence standard as the visual
judge and performance suite: captures, per-profile metrics, limits, and
recommendations. NativeX does not promise video playback or full game-player
support until that measurement exists.

## Video

Current state: NativaX does not decode video. The renderer shows a `▶ video`
placeholder, the DOM reports `MEDIA_ERR_SRC_NOT_SUPPORTED`, `canPlayType`
returns `""`, and `play()` rejects with `NotSupportedError`.

### Task 1 — keep the video contract measurable

- 25 resolution profiles: 360p, 480p, 720p, 1080p, 1440p, 2160p, portrait,
  square, ultrawide, and CSS attributes.
- Verify placeholder, box, aspect ratio, `videoWidth/videoHeight = 0`,
  `readyState = 0`, `networkState = 3`, and `error.code = 4`.
- Command: `cd packages/nativa_render && flutter test test/video_quality_test.dart`.
- Acceptance: 25/25 PASS without claiming playback.

### Task 2 — add a media pipeline before measuring playback

- Decoder, audio, clock, seek, controls, and render surface.
- Measure frame drop, CPU, RSS, and synchronization at 360p, 720p, and 1080p.
- Acceptance: real playback with audio and seek; an explicit error for
  unsupported formats.

### Task 3 — add visual measurement for video

- Compare placeholder/layout with Chromium through the visual judge.
- Acceptance: position/layout/color/design measured, with `INVALID` when the
  comparison is not valid.

## Games

Current state: the performance registry defines 25 Canvas 2D and 25 WebGL 3D
scenarios. Historical task notes report all 50 measured with `WARN`; there is no
current full run in this checkout, so re-run before quoting that. The complete
`examples/game-player` Three.js bundle is not executed by that matrix.

### Task 4 — measure game profiles by quality

- 2D: 640×360, 854×480, 1280×720, 1920×1080, 2560×1440.
- 3D: the same resolutions with 100–5,000 cubes.
- Particles/cubes: 100, 500, 1,000, 2,500, 5,000.
- Metrics: frame p95, maximum frame, work, nodes, RSS, and CPU.
- Command:

  ```bash
  dart run debug/engines/performance/bin/perf.dart run \
    --only '^game' --out debug/artifacts/perf/game
  ```

- Acceptance: every profile has measured frame p95 and RSS; WARN is not hidden.

### Task 5 — measure the real game player

- Run `examples/game-player` with `NATIVAX_GAME_DPR=0.5/1.0/1.5/2.0`.
- Capture metrics and RSS for the app, not only the offscreen harness.
- Acceptance: every quality profile has measured frame p95, RSS, and CPU.

### Task 6 — add game visual regression

- Canvas captures at each quality level.
- Compare with Chromium where the comparison is valid.
- Acceptance: layout/paint differences are detected by the judge.

## Memory and native

### Task 7 — measure peak RSS under load

- Heavy pages, 1k/10k/50k rows, scroll, and repeated navigation.
- Acceptance: peak RSS ≤ 250 MB and no growing trend over 24 h.

### Task 8 — architecture guard

- Fail if a WebView, CEF, embedded Chromium, Electron, or presentation HTTP
  server appears.
- Acceptance: an automated gate. The repository has no CI workflow yet, so the
  guard runs through `tools/test_all.sh`/architecture tests until CI exists.

## Shared precision

Every measurement must include:

- viewport and DPR;
- capture or golden;
- frame metrics;
- RSS/CPU;
- nodes and resources;
- environment state;
- verdict reason;
- limits and what was not measured.

A placeholder, a WARN, or a skipped profile is not a playback or game-support
claim.
