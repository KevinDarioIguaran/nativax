# Pending test tasks

These tasks cannot be closed with quick tests or on this machine. They remain
explicit gaps rather than implied coverage.

## Memory and lifecycle

- 24–72 h soak with RSS, heap, timers, listeners, wrappers, documents, and
  contexts measured.
- Peak RSS of the real app with heavy pages.
- Positive and negative controls on real platforms.
- Massive create/destroy and repeated navigation stress.

## Platform

- Build and test Android, iOS, Linux, Windows, and macOS.
- DPI, orientation, keyboard, accessibility, fonts, and touch input.
- Do not claim support without compile-and-run evidence.

## Visual

- Golden images per platform with explicit tolerances.
- HTML/CSS fuzzing with minimization and a fixed seed.
- Visual regression with thousands of nodes, long text, images, and updates.
- Animation and frame-stability checks.

## Video and games

- Real media pipeline (decoder, audio, seek, controls).
- Run the complete Three.js game player with `NATIVAX_GAME_DPR`.
- Golden canvas captures per quality profile.

## Architecture and security

- JS/DOM/CSS/HTML fuzzing with minimization.
- RAM/CPU/descriptor exhaustion tests.
- Load/destroy races and reentrancy.
- License and dependency validation.

## Conformance

- Run the complete suites and update rates without converting SKIP to PASS.
- Full WPT, not only `dom/nodes` and `css/selectors`.

## Rule

A test that only increments a counter does not establish maturity. Every pending
task needs a command, metric, limit, and reproducible evidence.
