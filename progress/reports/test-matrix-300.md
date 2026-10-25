# Matriz de 300 casos nuevos — 2026-10-24

Este lote suma **300 casos de prueba nuevos** repartidos por riesgo. No es una
tasa de compatibilidad ni una promesa de reproducción multimedia.

| Área | Casos nuevos | Dónde | Resultado de esta pasada |
|---|---:|---|---|
| Rendimiento: tamaños, DOM, scroll, layout | 120 | `tools/perf/lib/src/scenarios.dart` | 14 tests de contrato; escenarios definidos, no todos ejecutados |
| Juegos Canvas 2D por resolución/partículas | 25 | `tools/perf` (`game.quality-*`) | smoke 640x360/100 partículas: WARN, 56,7 ms NativaX vs 2,0 ms Chromium |
| Vídeo por resolución y atributos | 25 | `packages/nativa_render/test/video_quality_test.dart` | 25/25 PASS; **es contrato de placeholder, no reproducción** |
| Juez visual (color/geometría) | 50 | `tools/visual/test/matrix_test.dart` | 50/50 PASS |
| Media/platform: DPR, orientación, resolución, color scheme | 20 | `packages/nativa_css/test/media_matrix_test.dart` | 20/20 PASS |
| Seguridad adversarial | 30 | `tools/security/lib/src/matrix_cases.dart` | 30/30 PASS (10 globals, 10 URLs, 10 innerHTML) |
| Memoria y lifecycle | 30 | `tools/leaks/lib/src/cases/matrix_cases.dart` | quick: 30 PASS, 0 FAIL, 0 ERROR |
| **Total** | **300** | | |

Además, `tools/test_recommend.py` añade 9 tests del motor de recomendaciones
y `tools/test_video_manifest.py` 3 del manifiesto de vídeo (fuera del recuento
de 300 casos de producto).

## Catálogo de rendimiento

El catálogo queda en **245 escenarios** (239 internos + 6 externos). Los 17
escenarios base siguen siendo la única línea base medida; los 145 nuevos
(120 de matriz + 25 de juego) están definidos y se ejecutan con
`Solo rendimiento` o `perf.dart run`.

## Vídeo: límite explícito

NativaX **no decodifica vídeo**. El renderer mantiene el tamaño del elemento y
muestra `▶ video`; el DOM reporta `MEDIA_ERR_SRC_NOT_SUPPORTED`. Los 25 tests
verifican que 360p–2160p, retrato, cuadrado, ultrawide, atributos y tamaños CSS
conservan su caja y que no se finge reproducción. Para reproducir vídeo real
hace falta un pipeline multimedia (decoder, audio, sincronización, controles),
que no forma parte de este lote.

## Juegos: alcance

Los 25 escenarios de juego usan Canvas 2D (resoluciones 640x360 a 2560x1440 y
100–5.000 partículas). El `examples/game-player` Three.js completo no se ejecuta
en esta matriz; hacerlo requiere su build, WebGL/workers y una medición aparte.

## Comandos

```bash
cd tools/perf && dart analyze && dart test
cd tools/visual && dart analyze && dart test
cd packages/nativa_css && dart analyze && dart test
cd packages/nativa_render && flutter analyze && flutter test test/video_quality_test.dart
cd tools/security && dart analyze && dart test
cd tools/leaks && dart analyze && dart test
cd tools/leaks && dart run bin/leaks.dart run --profile quick --only matrix
```

El `./tools/test_all.sh` completo sigue teniendo el flake ajeno de
`wasm_rapier_test`; no se usa como evidencia de esta matriz.
