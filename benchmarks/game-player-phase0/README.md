# Game player — Fase 0 (2026-10-21)

Datos crudos de la instrumentación de presentación WebGL. Ver el informe
completo en `progress/phase0-presentation.md`.

## Archivos

- `baseline_fixed_1280x720.jsonl`: 50 ventanas de 2 s con ventana fija de
  1280×720 y DPR 1.0. Se descartaron las 2 primeras ventanas y se resumieron
  las últimas 15 (30 s).
- `summary_baseline.txt`: salida de `tools/summarize_metrics.py` con
  `--skip 2 --last 15 --buffer 1280x720`.
- `exploratory_no_backdrop.jsonl`: corrida exploratoria con
  `NATIVAX_NO_BACKDROP=1`. **No es un A/B válido**: la ventana cambió a
  1280×702 y 1366×720 durante la prueba, así que no hay muestras comparables a
  1280×720.

## Línea base seleccionada

| Métrica | Valor |
|---|---:|
| render | 34,7 fps |
| shown | 26,3 fps |
| UI | 32,0 fps |
| present p50/p95/p99 | 34,5 / 74,0 / 85,5 ms |
| decode p50/p95 | 4,0 / 37,2 ms |
| build p95 | 2,9 ms |
| raster p95 | 15,1 ms |
| UI total p50/p95 | 27,8 / 44,0 ms |
| jank > 50 ms | 1,2 % |

El objetivo de 45 fps mostrados / p95 ≤ 25 ms **no se alcanza**. No se
implementó la textura nativa; el reproductor queda en el camino estable
`GlSurfaceView` + `RawImage` a DPR 1.0.

## Reproducir

```bash
cd examples/game-player
flutter build linux --release
cd ../..
tools/bench_game_player.sh base_r1 36
python3 tools/summarize_metrics.py \
  /tmp/opencode/nativax-metrics/base_r1.jsonl \
  --skip 2 --last 15 --buffer 1280x720
```
