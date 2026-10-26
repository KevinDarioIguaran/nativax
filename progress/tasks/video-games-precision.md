# Tarea: precisión de vídeo y juegos

Objetivo: medir vídeo y juegos con el mismo nivel de evidencia que el juicio
visual y el suite de rendimiento: capturas, métricas por perfil, límites y
recomendaciones. No se promete reproducción de vídeo ni soporte del game-player
completo hasta que la medición exista.

## Vídeo

Estado actual: NativaX no decodifica vídeo. El renderer muestra un placeholder
`▶ video`, el DOM reporta `MEDIA_ERR_SRC_NOT_SUPPORTED`, `canPlayType` devuelve
`""` y `play()` rechaza con `NotSupportedError`.

Tarea 1. Mantener el contrato de vídeo medible:
- 25 perfiles de resolución: 360p, 480p, 720p, 1080p, 1440p, 2160p, retrato,
  cuadrado, ultrawide y atributos CSS.
- Verificar placeholder, caja, aspect ratio, `videoWidth/videoHeight = 0`,
  `readyState = 0`, `networkState = 3`, `error.code = 4`.
- Comando: `cd packages/nativa_render && flutter test test/video_quality_test.dart`
- Aceptación: 25/25 PASS sin afirmar playback.

Tarea 2. Añadir un pipeline multimedia antes de medir reproducción real:
- Decoder, audio, reloj, seek, controles y superficie de render.
- Medir frame drop, CPU, RSS y sincronización a 360p, 720p y 1080p.
- Aceptación: playback real con audio y seek; error explícito para formatos no
  soportados.

Tarea 3. Añadir medición visual de vídeo:
- Comparar el placeholder/layout contra Chromium con el juez visual.
- Aceptación: posición/layout/color/diseño medidos, con `INVALID` si la
  comparación no es válida.

## Juegos

Estado actual: 25 escenarios Canvas 2D y 25 WebGL 3D definidos; los 50 están
medidos y dan WARN. El `examples/game-player` Three.js completo no se ejecuta
en esta matriz.

Tarea 4. Medir perfiles de juego por calidad:
- 2D: 640x360, 854x480, 1280x720, 1920x1080, 2560x1440.
- 3D: las mismas resoluciones con 100–5.000 cubos.
- Partículas/cubos: 100, 500, 1.000, 2.500 y 5.000.
- Métricas: frame p95, frame máximo, trabajo, nodos, RSS y CPU.
- Comando: `dart run debug/engines/performance/bin/perf.dart run --only '^game' --out .perf/game`
- Aceptación: cada perfil tiene frame p95 y RSS medidos; no se ocultan WARN.

Tarea 5. Medir el game-player real:
- Ejecutar `examples/game-player` con `NATIVAX_GAME_DPR=0.5/1.0/1.5/2.0`.
- Capturar métricas y RSS de la app, no solo el arnés.
- Aceptación: cada perfil de calidad tiene frame p95, RSS y CPU medidos.

Tarea 6. Añadir regresión visual de juegos:
- Capturas del canvas a cada calidad.
- Comparar contra Chromium cuando sea válido.
- Aceptación: diferencias de layout/pintura detectadas por el juez.

## Memoria y nativo

Tarea 7. Medir RSS pico de la app real bajo carga:
- Páginas pesadas, 1k/10k/50k filas, scroll y navegación repetida.
- Aceptación: RSS pico ≤250 MB y sin tendencia creciente en 24 h.

Tarea 8. Guardia de arquitectura:
- Fallar si aparece WebView, CEF, Chromium embebido, Electron o servidor HTTP
  de presentación.
- Aceptación: test automático en CI.

## Precisión compartida

Para que vídeo y juegos tengan la misma precisión que el juicio visual, cada
medición debe incluir:
- viewport y DPR,
- captura o golden,
- métricas de frame,
- RSS/CPU,
- nodos y recursos,
- estado del entorno,
- motivo del veredicto,
- límites y lo que no se midió.

No se debe convertir un placeholder en compatibilidad ni un SKIP en éxito.
