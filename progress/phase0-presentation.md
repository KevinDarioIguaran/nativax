# Fase 0 — métricas de presentación WebGL

Fecha: 2026-10-21. Estado: **checkpoint estable**, Fase 0 instrumentada y
medida de forma preliminar. La Fase 1 (textura nativa) **no se inició**: a
petición del usuario se dejó una versión estable y se guardó el progreso.

## Entorno

- Flutter 3.47.0, Linux x64, Wayland/KDE.
- Backend de render: Impeller OpenGL ES (`OpenGLESSDF`).
- GPU: Intel UHD 630 (memoria compartida).
- Ventana fija de benchmark: 1280×720 de contenido, DPR nativo 1.0.
- Juego: bundle Vite de producción sin modificar; no se tocó
  `examples/game-player/assets/game/**`.

## Cambios de esta fase

- `examples/game-player/lib/metrics_overlay.dart`: overlay opt-in con
  percentiles por ventana de 2 s y salida JSONL.
- `packages/nativa_js/lib/src/quickjs_engine.dart`: `GlSurfaces` conserva
  intervalos de presentación y latencias de decode; expone p50/p95/p99.
- `tools/summarize_metrics.py`: agrupa por corrida y condición, con filtros
  `--skip`, `--last` y `--buffer`; no usa el promedio de FPS como veredicto.
- `tools/bench_game_player.sh`: corrida reproducible con ventana fija, metrics
  y autostart.
- `examples/game-player/linux/runner/my_application.cc`: flag de medición
  `NATIVAX_FIXED_WINDOW=1`; no cambia el comportamiento normal.
- `tools/test_all.sh`: omite ejemplos sin directorio `test/` en vez de fallar.

Las métricas están apagadas por defecto. Se activan con `NATIVAX_METRICS=1` o
con `NATIVAX_METRICS_FILE`. El juego normal mantiene DPR 1.0, backdrop-filter
activo y el camino `GlSurfaceView`/`RawImage` como fallback.

## Protocolo ejecutado

No se encontraron los archivos `metrics_overlay.dart` y
`summarize_metrics.py` indicados en el encargo, así que se implementaron de
nuevo respetando el contrato. Se hizo una corrida fija de 50 ventanas (100 s)
con:

```bash
NATIVAX_METRICS=1 \
NATIVAX_METRICS_FILE=/tmp/opencode/phase0_fixed.jsonl \
NATIVAX_METRICS_LABEL=probe_fixed \
NATIVAX_AUTOSTART=1 \
NATIVAX_FIXED_WINDOW=1 \
  ./nativax_game_player
```

Para el resumen se descartaron las 2 primeras ventanas (arranque) y se usaron
las últimas 15 ventanas (30 s) con buffer exactamente 1280×720.

## Resultado medido

Ventana estable de 30 s (15 ventanas de 2 s, 929 frames):

| Métrica | Valor |
|---|---:|
| render producido | 34,7 fps |
| frames mostrados | 26,3 fps |
| frames de UI | 32,0 fps |
| present p50 / p95 / p99 | 34,5 / 74,0 / 85,5 ms |
| decode p50 / p95 | 4,0 / 37,2 ms |
| build p95 | 2,9 ms |
| raster p95 | 15,1 ms |
| UI total p50 / p95 | 27,8 / 44,0 ms |
| jank > 50 ms | 11 / 929 = 1,2 % |

En la corrida completa (49 ventanas válidas, sin seleccionar los últimos 30 s)
la mediana fue: render 42,6, shown 29,1, UI 34,0, present p95 66,8 ms y decode
p95 34,9 ms. La variación entre tramos es alta y **no hay tres repeticiones**,
así que estos números son una línea base, no un veredicto estadístico.

## Lectura

- Build y raster no dominan: p95 de 2,9 ms y 15,1 ms.
- El coste está en el puente de presentación: intervalos `present` de 34,5 ms
  en p50, decode con p95 de 37 ms y `totalSpan` de UI de 27,8/44,0 ms.
- El render producido ya está por debajo del objetivo en esta corrida; no se
  puede atribuir toda la pérdida a Flutter sin las tres repeticiones.
- La hipótesis de que el límite es el puente (`glReadPixels` síncrono,
  `decodeImageFromPixels`, `RawImage`/`setState`) sigue siendo la más
  consistente con los datos, pero **no se declara éxito ni se implementó la
  textura nativa**.
- Criterio de éxito 1280×720: shown ≥ 45 fps, present p95 ≤ 25 ms, jank < 2 %,
  UI ≥ 50 fps. Resultado: **no alcanzado** (solo jank < 2 %).

## A/B de backdrop-filter

No hay conclusión válida. La corrida exploratoria con
`NATIVAX_NO_BACKDROP=1` cambió de tamaño de ventana durante la prueba
(1280×702 y 1366×720), por lo que el filtro `--buffer 1280x720` no conserva
muestras comparables. El archivo se guarda como evidencia exploratoria, no como
A/B. El backdrop sigue activo por defecto y el flag es solo de medición.

## Qué queda si se retoma

1. Repetir 3×30 s base y 3×30 s sin backdrop con ventana fija y carga estable.
2. Implementar la textura nativa Linux (`FlPixelBufferTexture` +
   `FlTextureRegistrar`) detrás de la interfaz `GlSurfacePresenter`.
3. Verificar si Impeller OpenGLES acepta texturas externas; si no, reportar y
   volver al fallback sin cambiar la app.
4. Solo entonces decidir readback asíncrono (PBO/fence) o EGLImage/dmabuf.

## Reproducción

```bash
# En examples/game-player
flutter build linux --release

# Una corrida de 36 s; el script fija ventana y activa metrics
tools/bench_game_player.sh base_r1 36

# Resumen de la ventana estable
python3 tools/summarize_metrics.py \
  /tmp/opencode/nativax-metrics/base_r1.jsonl \
  --skip 2 --last 15 --buffer 1280x720
```
