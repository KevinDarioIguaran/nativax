# NativaX — recomendaciones de calidad

Generado: 2026-10-24 19:52:15.

## Diagnóstico

| Área | Estado |
|---|---|
| Fidelidad visual | 51/300 medidas |
| Rendimiento | 17/270 medidos |
| App idle | 105.0 MB · 0.00 % CPU |
| Vídeo | 25 perfiles · playback no |
| Juegos | 50 perfiles medidos |

## Prioridades

- **P0:** 1
- **P1:** 7
- **P2:** 4

## Recomendaciones automáticas

Motor de reglas con evidencia medida (no una caja negra). Cobertura actual: **51/300** páginas y **17/270** escenarios.

### P0 · renderer — DOM, layout y posición apuntan al mismo cuello de botella

**Confianza:** media

**Evidencia**

- Layout visual medio 52.1 % y posición 34.9 %.
- Los escenarios DOM superan el objetivo de trabajo.

**Acción:** Priorizar el motor de layout/posicionamiento compartido antes de microoptimizar páginas individuales.

**Criterio de aceptación:** Layout/posición ≥90 % en el catálogo medido y DOM create 1k ≤3× Chromium.

### P1 · DOM / layout — El coste dominante está en DOM y layout, no en JS puro

**Confianza:** media

**Evidencia**

- dom.rows-remove-10k: 23.96× (161.5 vs 6.7 ms)
- dom.rows-create-1k: 16.33× (512.0 vs 31.4 ms)
- 2 escenarios DOM están por encima del objetivo de 3×.

**Acción:** Agrupar mutaciones DOM, evitar recalcular layout por nodo y hacer style/layout incremental por subárbol.

**Criterio de aceptación:** Crear 1k filas ≤3× Chromium, 10k dentro del presupuesto y sin frame máximo >100 ms.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --only '^dom\.' --out .perf/dom
```

### P1 · JavaScript — El motor JS pierde en cargas que superan el presupuesto

**Confianza:** media

**Evidencia**

- js.json: 3.72×

**Acción:** Separar coste del motor y del bridge; en escritorio evaluar V8/JavaScriptCore tras el mismo contrato. QuickJS sin JIT no puede igualar a V8 en bucles calientes.

**Criterio de aceptación:** Cada carga JS dentro del objetivo acordado o una decisión documentada de backend por plataforma.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --only '^js\.' --out .perf/js
```

### P1 · color — El color computado se separa del render de referencia

**Confianza:** media

**Evidencia**

- Color medio 44.1 %.

**Acción:** Revisar herencia, currentColor, gradientes y filtros antes de tocar layout.

**Criterio de aceptación:** Color medio ≥90 % en las páginas medidas.

### P1 · fidelidad visual — Hay contenido mal posicionado o fuera de su caja

**Confianza:** media

**Evidencia**

- 50projects50days/animated-countdown: posición 0.0 %, tinta 100.0 %
- 50projects50days/auto-text-effect: posición 0.0 %, tinta 100.0 %
- 50projects50days/background-slider: posición 0.0 %, tinta 100.0 %
- 50projects50days/custom-range-slider: posición 0.0 %, tinta 14.4 %
- 50projects50days/feedback-ui-design: posición 0.0 %, tinta 95.7 %

**Acción:** Revisar containing blocks, transforms, posición fija y stacking contexts; corregir el layout antes del color.

**Criterio de aceptación:** Posición ≥90 % y tinta <50 % en las páginas afectadas.

**Comando:**

```bash
dart run tools/visual/bin/visual_check.dart --only 'pagina' --out .visual/latest
```

### P1 · juegos — Los perfiles de juego Canvas 2D quedan por encima del presupuesto

**Confianza:** media

**Evidencia**

- game3d.quality-2560x1440-c2500: 692.24×
- game3d.quality-1920x1080-c500: 681.69×
- game3d.quality-1920x1080-c1000: 648.99×
- game3d.quality-1920x1080-c2500: 511.50×

**Acción:** Reducir partículas/draw calls por frame o bajar la escala interna; medir cada perfil por separado, no mezclar calidades.

**Criterio de aceptación:** Cada perfil de calidad cumple su frame p95 y su presupuesto de trabajo.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --only '^game\.' --out .perf/game
```

### P1 · multimedia — No hay reproducción de vídeo real

**Confianza:** alta

**Evidencia**

- NativaX no decodifica vídeo: el renderer usa un placeholder y el DOM reporta MEDIA_ERR_SRC_NOT_SUPPORTED.
- Los 25 tests de vídeo son de contrato/layout, no de playback.

**Acción:** Implementar pipeline multimedia (demux/decode, audio, reloj, seek, pista de vídeo y superficie de render) antes de afirmar soporte de vídeo.

**Criterio de aceptación:** Reproducir 360p, 720p y 1080p con audio y seek sin bloquear el frame; error de formato no soportado sigue siendo explícito.

### P1 · scroll / frames — El scroll de listas largas pierde el presupuesto de frame

**Confianza:** media

**Evidencia**

- scroll.rows-10k: p95 199.0 ms (objetivo 16.7 ms).

**Acción:** Virtualizar filas, limitar el área de paint y evitar layout global en cada paso de scroll.

**Criterio de aceptación:** p95 ≤16.7 ms y frame máximo ≤100 ms en los escenarios de scroll.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --only '^scroll\.' --out .perf/scroll
```

### P2 · cobertura de rendimiento — Faltan 253 escenarios de rendimiento

**Confianza:** alta

**Evidencia**

- 17/270 escenarios medidos.
- La tabla muestra pendientes; no se puede declarar una tasa global ni comparar todos los tipos de carga.

**Acción:** Ejecutar primero el lote base y luego los escenarios de matriz; no mezclar una pasada corta con una afirmación global.

**Criterio de aceptación:** 270/270 escenarios ejecutados, al menos 3 rondas en release/AOT para la decisión final.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --out .perf/latest
```

### P2 · cobertura visual — Faltan 249 páginas visuales por medir

**Confianza:** alta

**Evidencia**

- 51/300 páginas con resultado medido.
- Sin esa muestra no se puede extrapolar la fidelidad al catálogo completo.

**Acción:** Ejecutar el catálogo visual completo y revisar las páginas nuevas.

**Criterio de aceptación:** 300/300 páginas medidas; overall y tinta reportados sin muestras pendientes.

**Comando:**

```bash
dart run tools/visual/bin/visual_check.dart --all --catalog .visual/catalog.json --out .visual/latest
```

### P2 · juegos — Falta medir el game-player Three.js completo

**Confianza:** alta

**Evidencia**

- La matriz de juego usa Canvas 2D y perfiles de resolución; no ejecuta el bundle Three.js de examples/game-player.

**Acción:** Construir el game-player y medir NATIVAX_GAME_DPR 0.5/1/1.5/2 con las mismas rondas y contadores.

**Criterio de aceptación:** Cada perfil de calidad tiene frame p95, RSS y CPU medidos.

### P2 · memoria — El idle cumple; falta el pico bajo carga

**Confianza:** media

**Evidencia**

- Idle real: 105.0 MB y 0.00 % CPU.
- No hay una serie de RSS pico de la app real con páginas pesadas; el RSS del arnés no sirve para ese presupuesto.

**Acción:** Medir RSS máximo con 1k/10k filas, scroll y navegación repetida.

**Criterio de aceptación:** RSS pico de la app ≤250 MB en la carga acordada, sin tendencia creciente tras liberar recursos.

## Detalle de rendimiento

| Escenario | Tipo | Veredicto | NativaX ms | Chromium ms | Ratio | p95 ms | max ms | Nodos N/C | RSS arnés MB | Siguiente acción |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| `idle.blank` | idle | PASS | 0.0 | 0.0 | — | 0.0 | 0.0 | 7/7 | 731 | Mantener la línea base y vigilar regresiones. |
| `dom.rows-create-1k` | dom | FAIL | 512.0 | 31.4 | 16.33× | 130.6 | 130.6 | 1008/1008 | 734 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-10k` | dom | FAIL | 0.0 | 263.1 | 0.00× | 0.0 | 0.0 | 8/10008 | 729 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-update-10k` | dom | FAIL | 0.0 | 29.0 | 0.00× | 0.0 | 0.0 | 10008/10008 | 760 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-remove-10k` | dom | WARN | 161.5 | 6.7 | 23.96× | 98.7 | 98.7 | 8/8 | 745 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `scroll.rows-10k` | scroll | FAIL | 2357.5 | 1.2 | 1964.60× | 199.0 | 234.0 | 10008/10008 | 766 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.2d-tiles` | scroll | PASS | 192.8 | 1.2 | 160.69× | 8.5 | 74.1 | 908/908 | 730 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `js.arrays` | js | PASS | 108.1 | 45.7 | 2.37× | 4.6 | 4.6 | 8/8 | 714 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.objects` | js | PASS | 46.3 | 16.3 | 2.84× | 5.2 | 5.2 | 8/8 | 706 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.strings` | js | PASS | 20.3 | 13.8 | 1.47× | 5.1 | 5.1 | 8/8 | 714 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.json` | js | WARN | 133.9 | 36.0 | 3.72× | 4.9 | 4.9 | 8/8 | 716 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `external.browserbench-quick` | external | FAIL | 14780.1 | 11281.4 | 1.31× | 1330.0 | 1330.0 | 0/16917 | 878 | Reproducir el benchmark externo con la misma carga y revisar el cuello. |
| `external.jsfb-create-1k` | external | FAIL | 3723.4 | 118.0 | 31.55× | 272.6 | 272.6 | 8031/8031 | 739 | Reproducir el benchmark externo con la misma carga y revisar el cuello. |
| `external.jsfb-create-10k` | external | FAIL | 68847.5 | 1313.2 | 52.43× | 3.0 | 87.2 | 30/80031 | 767 | Investigar el error del motor antes de comparar rendimiento. |
| `external.jsfb-clear` | external | FAIL | 0.0 | 250.1 | 0.00× | 0.0 | 0.0 | 30/31 | 783 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `external.cerious-load-scroll` | external | FAIL | 149.7 | 0.2 | 748.62× | 27.9 | 49.9 | 416/721 | 753 | Reproducir el benchmark externo con la misma carga y revisar el cuello. |
| `external.uibench-load-scroll` | external | FAIL | 11.4 | 0.5 | 22.75× | 0.2 | 4.1 | 13/153 | 705 | Reproducir el benchmark externo con la misma carga y revisar el cuello. |

### Motivos por escenario

- `dom.rows-create-1k` — work-ratio: 16.33x vs 3.0x target (512.0 ms / 31.4 ms); no-long-frame: 130.6 ms max vs 100.0 ms
- `dom.rows-create-10k` — NativaX failed: operation failed: TimeoutError: script exceeded its execution budget     at host (<nativax:host>:35:15)     at createElement (<nativax:dom>:1249:57)     at create (
- `dom.rows-update-10k` — NativaX failed: operation failed: TimeoutError: script exceeded its execution budget     at wrap (<nativax:dom>:64:11)     at item (<nativax:dom>:350:36)     at get (<nativax:dom>:
- `dom.rows-remove-10k` — work-ratio: 23.96x vs 3.0x target (161.5 ms / 6.7 ms)
- `scroll.rows-10k` — no-long-frame: 234.0 ms max vs 100.0 ms; frame-p95: 199.0 ms p95 vs 16.7 ms
- `js.json` — work-ratio: 3.72x vs 3.0x target (133.9 ms / 36.0 ms)
- `external.browserbench-quick` — no-long-frame: 1330.0 ms max vs 100.0 ms
- `external.jsfb-create-1k` — work-ratio: 31.55x vs 3.0x target (3723.4 ms / 118.0 ms); no-long-frame: 272.6 ms max vs 100.0 ms
- `external.jsfb-create-10k` — NativaX failed: timed out waiting for the page benchmark to finish
- `external.jsfb-clear` — NativaX failed: setup failed: TimeoutError: script exceeded its execution budget     at host (<nativax:host>:36:21)     at <anonymous> (<nativax:dom>:27:26)
- `external.cerious-load-scroll` — nodes: 416 vs 721 (42.3 % diff); work-ratio: 748.62x vs 3.0x target (149.7 ms / 0.2 ms)
- `external.uibench-load-scroll` — nodes: 13 vs 153 (91.5 % diff); work-ratio: 22.75x vs 3.0x target (11.4 ms / 0.5 ms)

## Detalle visual

| Página | Veredicto | Overall | Posición | Layout | Color | Diseño | Píxeles % | Tinta % | ΔE medio | Acción |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `50projects50days/3d-boxes-background` | FAIL | 71.6 | 27.8 | 85.1 | 90.8 | 100.0 | 9.97 | 100.00 | 6.46 | corregir posición/containing block/transform; comprobar contenido fuera de pantalla/recortado |
| `50projects50days/animated-countdown` | FAIL | 52.6 | 0.0 | 42.2 | 99.6 | 100.0 | 0.16 | 100.00 | 0.09 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; c |
| `50projects50days/animated-navigation` | FAIL | 39.0 | 28.5 | 47.2 | 6.3 | 98.2 | 1.13 | 1.96 | 0.67 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/auto-text-effect` | FAIL | 48.5 | 0.0 | 41.2 | 87.3 | 95.8 | 2.11 | 100.00 | 0.34 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; c |
| `50projects50days/background-slider` | FAIL | 37.3 | 0.0 | 76.0 | 0.0 | 96.8 | 100.00 | 100.00 | 51.81 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/blurry-loading` | WARN | 70.7 | 50.0 | 52.8 | 100.0 | 99.0 | 0.00 | 0.00 | 0.00 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/button-ripple-effect` | PASS | 95.0 | 100.0 | 91.3 | 100.0 | 83.7 | 0.19 | 15.03 | 0.10 | sin acción dominante |
| `50projects50days/content-placeholder` | FAIL | 56.8 | 10.5 | 68.5 | 72.4 | 100.0 | 6.91 | 39.30 | 0.33 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/custom-range-slider` | FAIL | 23.1 | 0.0 | 29.0 | 3.1 | 90.9 | 2.87 | 14.37 | 1.98 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/dad-jokes` | PASS | 93.0 | 94.6 | 89.0 | 93.0 | 98.0 | 3.75 | 9.30 | 1.24 | sin acción dominante |
| `50projects50days/double-click-heart` | FAIL | 67.8 | 85.0 | 90.9 | 0.0 | 100.0 | 23.85 | 99.66 | 8.79 | revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado |
| `50projects50days/double-vertical-slider` | FAIL | 24.2 | 16.0 | 15.0 | 0.0 | 99.1 | 34.55 | 100.00 | 19.85 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/drag-n-drop` | PASS | 98.8 | 100.0 | 100.0 | 100.0 | 91.8 | 0.00 | 0.00 | 0.00 | sin acción dominante |
| `50projects50days/drawing-app` | PASS | 92.2 | 100.0 | 94.4 | 81.1 | 90.6 | 2.22 | 21.58 | 1.12 | sin acción dominante |
| `50projects50days/drink-water` | FAIL | 58.0 | 53.1 | 77.6 | 15.3 | 100.0 | 6.83 | 41.61 | 4.40 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/event-keycodes` | FAIL | 91.9 | 100.0 | 86.1 | 89.2 | 91.8 | 0.27 | 99.21 | 0.13 | comprobar contenido fuera de pantalla/recortado |
| `50projects50days/expanding-cards` | WARN | 77.2 | 62.3 | 62.1 | 100.0 | 99.3 | 0.00 | 0.00 | 0.00 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/faq-collapse` | FAIL | 24.2 | 2.9 | 20.5 | 10.0 | 97.6 | 24.88 | 80.30 | 14.53 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/feedback-ui-design` | FAIL | 26.4 | 0.0 | 17.9 | 25.0 | 98.4 | 40.81 | 95.66 | 4.38 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/form-input-wave` | FAIL | 33.7 | 0.0 | 38.1 | 30.9 | 97.3 | 31.39 | 63.06 | 9.49 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/github-profiles` | WARN | 70.9 | 92.9 | 79.6 | 17.3 | 99.0 | 2.59 | 37.34 | 0.63 | revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros |
| `50projects50days/good-cheap-fast` | FAIL | 71.2 | 31.5 | 77.6 | 94.4 | 99.0 | 1.72 | 79.80 | 0.65 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/hidden-search` | PASS | 96.1 | 98.6 | 94.0 | 100.0 | 88.4 | 0.04 | 0.16 | 0.13 | sin acción dominante |
| `50projects50days/hoverboard` | INVALID | — | — | — | — | — | — | — | — | sin acción dominante |
| `50projects50days/image-carousel` | FAIL | 58.7 | 66.7 | 58.5 | 27.3 | 95.5 | 35.67 | 94.61 | 9.58 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/incrementing-counter` | FAIL | 47.4 | 39.3 | 36.9 | 38.0 | 100.0 | 1.48 | 79.80 | 0.82 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/insect-catch-game` | FAIL | 39.1 | 17.0 | 35.9 | 34.6 | 97.5 | 2.61 | 81.53 | 2.36 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/kinetic-loader` | WARN | 79.8 | 100.0 | 100.0 | 24.0 | 91.8 | 0.35 | 50.49 | 0.26 | revisar color, background, gradientes y filtros |
| `50projects50days/live-user-filter` | WARN | 81.1 | 73.5 | 72.5 | 90.1 | 98.5 | 2.66 | 32.37 | 0.97 | revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/mobile-tab-navigation` | FAIL | 28.5 | 29.4 | 15.8 | 0.0 | 99.4 | 99.24 | 99.24 | 33.91 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/movie-app` | FAIL | 56.1 | 35.9 | 49.2 | 62.7 | 99.3 | 1.08 | 12.90 | 0.16 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/netflix-mobile-navigation` | FAIL | 21.1 | 5.1 | 15.6 | 0.0 | 99.6 | 0.70 | 96.20 | 0.63 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/notes-app` | FAIL | 26.1 | 0.0 | 24.4 | 20.0 | 91.8 | 0.45 | 64.64 | 0.26 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/password-generator` | FAIL | 26.1 | 4.5 | 22.0 | 15.0 | 96.3 | 15.00 | 61.33 | 7.12 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/password-strength-background` | FAIL | 43.7 | 10.4 | 28.6 | 76.4 | 86.2 | 2.40 | 98.30 | 1.26 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; c |
| `50projects50days/pokedex` | FAIL | 22.6 | 0.0 | 25.3 | 0.0 | 100.0 | 92.72 | 94.87 | 16.90 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/progress-steps` | FAIL | 57.5 | 57.3 | 64.9 | 23.5 | 100.0 | 1.11 | 66.35 | 0.58 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/quiz-app` | FAIL | 55.1 | 49.6 | 64.7 | 24.3 | 98.1 | 5.39 | 7.66 | 4.11 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/random-choice-picker` | FAIL | 37.1 | 0.0 | 48.5 | 32.2 | 96.6 | 7.12 | 59.14 | 4.87 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/random-image-generator` | FAIL | 88.3 | 67.2 | 94.8 | 100.0 | 98.2 | 1.77 | 97.07 | 0.77 | corregir posición/containing block/transform; comprobar contenido fuera de pantalla/recortado |
| `50projects50days/rotating-nav-animation` | FAIL | 40.4 | 36.7 | 27.8 | 25.0 | 98.6 | 38.11 | 95.08 | 26.98 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/scroll-animation` | FAIL | 54.9 | 10.6 | 45.9 | 91.7 | 100.0 | 15.12 | 32.49 | 8.03 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/simple-timer` | FAIL | 50.6 | 0.0 | 41.5 | 98.5 | 90.5 | 0.65 | 100.00 | 0.28 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; c |
| `50projects50days/sound-board` | FAIL | 19.5 | 0.0 | 10.0 | 5.8 | 100.0 | 20.48 | 100.00 | 5.94 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/split-landing-page` | FAIL | 31.7 | 28.6 | 27.1 | 0.0 | 100.0 | 99.29 | 99.29 | 79.09 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/sticky-navigation` | FAIL | 32.7 | 30.6 | 22.2 | 7.8 | 99.7 | 93.10 | 93.10 | 44.28 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/testimonial-box-switcher` | FAIL | 30.8 | 0.0 | 38.7 | 16.8 | 99.7 | 34.85 | 58.35 | 27.29 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/theme-clock` | FAIL | 36.5 | 0.0 | 33.3 | 46.8 | 99.0 | 4.40 | 95.36 | 3.92 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/toast-notification` | FAIL | 22.4 | 0.0 | 24.7 | 0.0 | 100.0 | 0.91 | 60.39 | 0.74 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/todo-list` | FAIL | 31.0 | 2.1 | 37.0 | 19.8 | 95.4 | 19.30 | 86.55 | 4.31 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/verify-account-ui` | FAIL | 43.3 | 28.1 | 61.4 | 9.1 | 94.4 | 16.38 | 87.97 | 9.91 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |

### Causas raíz por página (peores 10)

#### `50projects50days/hoverboard` — INVALID · overall — %

- Acción sugerida: sin acción dominante
- Sin detalle de elementos; revisar artefactos.
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/hoverboard`

#### `50projects50days/sound-board` — FAIL · overall 19.5 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado
- `#buttons>button:6`: pos Δ 237.0 px; tamaño Δ 43.6 px; ΔE 17.7
- `#buttons>button:5`: pos Δ 237.0 px; tamaño Δ 78.9 px; ΔE 7.0
- `#buttons>button:4`: pos Δ 202.0 px; tamaño Δ 39.4 px; ΔE 17.0
- `#buttons`: pos Δ 186.0 px; tamaño Δ 70.0 px; ΔE 11.9
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/sound-board`

#### `50projects50days/netflix-mobile-navigation` — FAIL · overall 21.1 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado
- `html:1>body:1>div:1>div:1>div:1>ul:1>li:1>a:1`: pos Δ 1009.2 px; tamaño Δ 884.0 px; ΔE —
- `html:1>body:1>div:1>div:1>div:1>ul:1>li:2>a:1`: pos Δ 1009.2 px; tamaño Δ 884.0 px; ΔE —
- `html:1>body:1>div:1>div:1>div:1>ul:1>li:3>a:1`: pos Δ 1009.2 px; tamaño Δ 884.0 px; ΔE —
- `html:1>body:1>div:1>div:1>div:1>img:1`: pos Δ 1009.2 px; tamaño Δ 882.0 px; ΔE —; estilo: display inline→inline-block, overflow-x clip→visible, overflow-y clip→visible
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/netflix-mobile-navigation`

#### `50projects50days/toast-notification` — FAIL · overall 22.4 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros
- `#button`: pos Δ 57.0 px; tamaño Δ 114.1 px; ΔE 15.8
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/toast-notification`

#### `50projects50days/pokedex` — FAIL · overall 22.6 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado
- `html:1>body:1>h1:1`: pos Δ 46.2 px; tamaño Δ 92.4 px; ΔE 66.1
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/pokedex`

#### `50projects50days/custom-range-slider` — FAIL · overall 23.1 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros
- `html:1>body:1>h2:1`: pos Δ 278.6 px; tamaño Δ 213.3 px; ΔE 50.9
- `#range`: pos Δ 234.0 px; tamaño Δ 14.0 px; ΔE 79.3; estilo: font-family arial→lato, sans-serif, color rgb(157, 150, 142)→rgb(0, 0, 0), background-color rgb(255, 255, 255)→rgba(0, 0, 0, 0)
- `html:1>body:1>div:1>label:1`: pos Δ 250.0 px; tamaño Δ 2.0 px; ΔE 17.4
- `html:1>body:1>div:1`: pos Δ 250.0 px; tamaño Δ 22.0 px; ΔE 7.7
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/custom-range-slider`

#### `50projects50days/faq-collapse` — FAIL · overall 24.2 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado
- `html:1>body:1>div:1>div:4>h3:1`: pos Δ 185.0 px; tamaño Δ 16.0 px; ΔE 59.5
- `html:1>body:1>div:1>div:5>h3:1`: pos Δ 247.0 px; tamaño Δ 3.0 px; ΔE 35.7
- `html:1>body:1>div:1>div:5>button:1`: pos Δ 247.0 px; tamaño Δ 0.0 px; ΔE 21.8; estilo: font-family arial→muli, sans-serif, background-color rgba(0, 0, 0, 0)→rgb(159, 164, 168)
- `html:1>body:1>div:1>div:4`: pos Δ 185.0 px; tamaño Δ 62.0 px; ΔE 17.8
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/faq-collapse`

#### `50projects50days/double-vertical-slider` — FAIL · overall 24.2 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado
- `html:1>body:1>div:1>div:1>div:4`: pos Δ 2586.0 px; tamaño Δ 864.0 px; ΔE —
- `html:1>body:1>div:1>div:1>div:4>h1:1`: pos Δ 3014.5 px; tamaño Δ 248.8 px; ΔE —
- `html:1>body:1>div:1>div:1>div:4>p:1`: pos Δ 3019.5 px; tamaño Δ 117.3 px; ΔE —
- `html:1>body:1>div:1>div:1>div:3`: pos Δ 1722.0 px; tamaño Δ 864.0 px; ΔE —
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/double-vertical-slider`

#### `50projects50days/notes-app` — FAIL · overall 26.1 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros
- `#add`: pos Δ 79.9 px; tamaño Δ 79.9 px; ΔE 6.0; estilo: font-family arial→poppins, sans-serif
- `#add>i:1`: pos Δ 59.9 px; tamaño Δ 1.7 px; ΔE —; estilo: font-family arial→poppins, sans-serif
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/notes-app`

#### `50projects50days/password-generator` — FAIL · overall 26.1 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros
- `html:1>body:1>div:1>div:2>div:5>label:1`: pos Δ 48.0 px; tamaño Δ 125.3 px; ΔE 60.2
- `html:1>body:1>div:1>div:2>div:4>label:1`: pos Δ 29.0 px; tamaño Δ 121.7 px; ΔE 59.4
- `html:1>body:1>div:1>h2:1`: pos Δ 70.5 px; tamaño Δ 20.0 px; ΔE 46.4
- `html:1>body:1>div:1>div:2>div:1>label:1`: pos Δ 52.0 px; tamaño Δ 33.7 px; ΔE 47.2
- Artefactos: `/home/k3vin/Documents/nativax/.visual/latest/pages/50projects50days/password-generator`

## Detalle de juegos

| Tipo | Escenario | Resolución | Carga | Veredicto | NativaX ms | Chromium ms | Ratio | p95 ms | RSS arnés MB | Acción |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|---|
| 2D | `game.quality-1280x720-p100` | 1280x720 | 100 | WARN | 36.0 | 3.7 | 9.73× | 9.3 | 716 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p1000` | 1280x720 | 1000 | WARN | 123.5 | 20.2 | 6.12× | 11.3 | 718 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p2500` | 1280x720 | 2500 | WARN | 218.0 | 18.0 | 12.11× | 10.7 | 709 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p500` | 1280x720 | 500 | WARN | 80.5 | 15.5 | 5.19× | 8.6 | 708 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p5000` | 1280x720 | 5000 | WARN | 313.4 | 32.5 | 9.64× | 9.0 | 718 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p100` | 1920x1080 | 100 | WARN | 36.3 | 8.0 | 4.54× | 9.2 | 700 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p1000` | 1920x1080 | 1000 | WARN | 127.2 | 14.4 | 8.83× | 10.5 | 722 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p2500` | 1920x1080 | 2500 | WARN | 284.2 | 26.8 | 10.61× | 17.9 | 722 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p500` | 1920x1080 | 500 | WARN | 83.6 | 5.0 | 16.71× | 9.1 | 714 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p5000` | 1920x1080 | 5000 | WARN | 400.2 | 8.8 | 45.47× | 9.7 | 740 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p100` | 2560x1440 | 100 | WARN | 37.0 | 4.2 | 8.80× | 8.9 | 702 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p1000` | 2560x1440 | 1000 | WARN | 144.6 | 5.3 | 27.29× | 15.0 | 702 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p2500` | 2560x1440 | 2500 | WARN | 301.9 | 25.6 | 11.79× | 11.4 | 711 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p500` | 2560x1440 | 500 | WARN | 111.7 | 15.7 | 7.11× | 9.3 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p5000` | 2560x1440 | 5000 | WARN | 365.4 | 49.9 | 7.32× | 12.0 | 741 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p100` | 640x360 | 100 | WARN | 34.0 | 2.8 | 12.13× | 8.6 | 708 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p1000` | 640x360 | 1000 | WARN | 121.1 | 7.4 | 16.36× | 9.1 | 715 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p2500` | 640x360 | 2500 | WARN | 214.3 | 11.4 | 18.80× | 10.7 | 709 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p500` | 640x360 | 500 | WARN | 98.4 | 1.9 | 51.79× | 10.9 | 710 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p5000` | 640x360 | 5000 | WARN | 332.3 | 32.6 | 10.19× | 9.8 | 738 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p100` | 854x480 | 100 | WARN | 35.1 | 7.1 | 4.94× | 9.2 | 715 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p1000` | 854x480 | 1000 | WARN | 153.1 | 7.5 | 20.41× | 9.0 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p2500` | 854x480 | 2500 | WARN | 236.6 | 9.9 | 23.89× | 11.7 | 709 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p500` | 854x480 | 500 | WARN | 78.1 | 10.6 | 7.37× | 8.8 | 711 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p5000` | 854x480 | 5000 | WARN | 332.6 | 26.0 | 12.79× | 9.1 | 742 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c100` | 1280x720 | 100 | WARN | 24.7 | 0.1 | 246.86× | 9.5 | 729 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c1000` | 1280x720 | 1000 | WARN | 29.7 | 0.3 | 99.14× | 10.0 | 726 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c2500` | 1280x720 | 2500 | WARN | 29.6 | 0.1 | 295.90× | 9.2 | 737 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c500` | 1280x720 | 500 | WARN | 38.3 | 0.2 | 191.29× | 14.3 | 735 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c5000` | 1280x720 | 5000 | WARN | 32.0 | 0.1 | 320.04× | 9.7 | 727 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c100` | 1920x1080 | 100 | PASS | 46.3 | 0.0 | — | 14.5 | 726 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c1000` | 1920x1080 | 1000 | WARN | 64.9 | 0.1 | 648.99× | 30.1 | 723 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c2500` | 1920x1080 | 2500 | WARN | 51.2 | 0.1 | 511.50× | 12.2 | 723 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c500` | 1920x1080 | 500 | WARN | 68.2 | 0.1 | 681.69× | 15.7 | 731 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c5000` | 1920x1080 | 5000 | WARN | 53.6 | 0.3 | 178.62× | 11.8 | 722 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c100` | 2560x1440 | 100 | WARN | 40.8 | 0.3 | 136.13× | 10.4 | 731 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c1000` | 2560x1440 | 1000 | WARN | 78.5 | 0.2 | 392.45× | 14.6 | 729 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c2500` | 2560x1440 | 2500 | WARN | 69.2 | 0.1 | 692.24× | 16.1 | 734 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c500` | 2560x1440 | 500 | WARN | 59.4 | 0.4 | 148.58× | 13.3 | 729 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c5000` | 2560x1440 | 5000 | WARN | 79.1 | 0.3 | 263.73× | 15.2 | 722 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c100` | 640x360 | 100 | WARN | 31.2 | 0.1 | 312.33× | 15.8 | 734 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c1000` | 640x360 | 1000 | WARN | 18.3 | 0.2 | 91.41× | 8.2 | 729 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c2500` | 640x360 | 2500 | WARN | 49.8 | 0.3 | 165.94× | 23.2 | 736 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c500` | 640x360 | 500 | WARN | 19.4 | 0.3 | 64.79× | 9.2 | 722 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c5000` | 640x360 | 5000 | WARN | 26.4 | 0.1 | 263.98× | 11.2 | 737 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c100` | 854x480 | 100 | WARN | 17.5 | 0.1 | 175.21× | 8.1 | 729 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c1000` | 854x480 | 1000 | WARN | 37.9 | 0.3 | 126.42× | 12.5 | 725 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c2500` | 854x480 | 2500 | WARN | 24.0 | 0.2 | 119.78× | 10.5 | 743 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c500` | 854x480 | 500 | WARN | 20.6 | 0.4 | 51.55× | 8.6 | 728 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c5000` | 854x480 | 5000 | WARN | 23.4 | 0.1 | 234.50× | 8.8 | 722 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |

## Detalle de vídeo

- Reproducción real: **no**.
- Decoder: none.
- Contrato: MEDIA_ERR_SRC_NOT_SUPPORTED.
- Última corrida: PASS (2026-10-24T19:36:18).

| Perfil | Caja | Atributos | Contrato | Test |
|---|---|---|---|---|
| 360p | 640x360 | width="640" height="360" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| 480p | 768x432 | width="854" height="480" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| 720p | 768x432 | width="1280" height="720" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| 1080p | 768x432 | width="1920" height="1080" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| 1440p | 768x432 | width="2560" height="1440" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| 2160p | 768x432 | width="3840" height="2160" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| portrait | 720x1280 | width="720" height="1280" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| square | 768x768 | width="1080" height="1080" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| ultrawide | 768x324 | width="2560" height="1080" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| controls | 640x360 | width="640" height="360" controls | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| autoplay-muted | 640x360 | width="640" height="360" autoplay muted | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| loop | 640x360 | width="640" height="360" loop | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| preload-none | 640x360 | width="640" height="360" preload="none" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| poster | 640x360 | width="640" height="360" poster="poster.png" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| playsinline | 640x360 | width="640" height="360" playsinline | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| crossorigin | 640x360 | width="640" height="360" crossorigin="anonymous" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| source-child | 640x360 | width="640" height="360" + <source> | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| css-size | 320x180 | style width:320px;height:180px | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| css-half-width | 384x180 | style width:50%;height:180px | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| width-only | 640x320 | width="640" | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| muted-controls-720p | 768x432 | width="1280" height="720" controls muted | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| autoplay-loop-1080p | 768x432 | width="1920" height="1080" autoplay loop muted | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| css-object-fit | 320x180 | style width:320px;height:180px;object-fit:cover | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| css-max-width | 640x360 | width="1920" height="1080" style=max-width:640px | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |
| default | 300x150 | (sin atributos; caja UA 300x150) | placeholder + MEDIA_ERR_SRC_NOT_SUPPORTED | CONTRATO |

## Cobertura pendiente

| Suite | Pendientes | Primeras páginas |
|---|---:|---|
| mdn-css-examples | 27 | mdn-css-examples/alt-style-sheets, mdn-css-examples/animation-frames-timing-function, mdn-css-examples/backdrop, mdn-css-examples/counter-st |
| mdn-dom-examples | 134 | mdn-dom-examples/abort-api, mdn-dom-examples/audiocontext-setsinkid, mdn-dom-examples/auxclick, mdn-dom-examples/canvas/chroma-keying, mdn-d |
| mdn-learning-area | 67 | mdn-learning-area/accessibility/aria, mdn-learning-area/accessibility/assessment-finished, mdn-learning-area/accessibility/assessment-start, |
| odin-css-exercises | 21 | odin-css-exercises/advanced-html-css/animation/01-button-hover, odin-css-exercises/advanced-html-css/animation/02-pop-up, odin-css-exercises |

Total pendiente: **249** páginas. Lista completa en `.visual/catalog.json`.

| Grupo de escenarios | Pendientes |
|---|---:|
| animation | 9 |
| dom | 94 |
| form | 6 |
| game | 25 |
| game3d | 25 |
| js | 21 |
| layout | 10 |
| matrix | 24 |
| scroll | 39 |

Total pendiente: **253** escenarios. Lista completa en `tools/perf/scenarios.json`.

## Memoria y fugas

| Caso | Estado | Motivo |
|---|---|---|
| `dom.detached_listeners` | pass | resource counters returned to baseline after release |

## Seguridad

| Caso | Categoría | Severidad | Estado | Observado |
|---|---|---|---|---|
| `engine.host_globals` | sandbox | critical | pass | none exposed |
| `bridge.raw_host_hardened` | bridge | high | pass | undefined |
| `events.programmatic_click_not_trusted` | events | high | pass | script=false host=true |
| `events.programmatic_submit_not_trusted` | events | high | pass | script=false host=true |
| `xss.inner_html_does_not_execute` | xss | critical | pass | pwned=0 text=safe |
| `xss.javascript_url_not_executed` | xss | high | pass | pwned=0; navigate=javascript:globalThis.pwned=1 |
| `bridge.malformed_ids_are_contained` | bridge | high | pass | caught=true text=alive |
| `sandbox.engine_isolation` | isolation | critical | pass | undefined |
| `limits.infinite_loop_interrupted` | dos | high | pass | TimeoutError in 51 ms |
| `limits.microtask_limit` | dos | high | pass | MicrotaskLimitError: more than 100 microtasks in one drain; remaining jobs stay queued |
| `limits.parser_input_limit` | dos | medium | pass | input of 1000 characters exceeds 64 |
| `storage.quota` | storage | medium | pass | QuotaExceededError |
| `lifecycle.disposed_engine_rejects_calls` | lifecycle | high | pass | engine has been disposed |
| `internal.callback_globals` | hardening | medium | pass | none |
| `platform.flutter_resource_policy` | resources | high | skip | not runnable from the pure Dart CLI |

## Entorno y procedencia

- Visual: 51/300 páginas; referencia Google Chrome 152.0.7977.82.
- Rendimiento: 17/270 escenarios; referencia Google Chrome 152.0.7977.82.
- App idle: 105.0 MB · 0.00 % CPU.
- Los valores de vídeo son de contrato/placeholder; no hay decoder.
- Los escenarios de juego de esta matriz son Canvas 2D.

## Límites de esta conclusión

- Los tests de vídeo son de contrato/placeholder: NativaX no decodifica vídeo todavía; no se afirma reproducción.
- Los escenarios de juego de esta matriz son Canvas 2D; el `examples/game-player` Three.js completo requiere una medición aparte.
- El RSS del arnés (`flutter test`) no es el RSS de la app; el idle real se mide aparte.
- Las recomendaciones no prometen porcentajes de mejora; usan los cocientes y umbrales medidos.

## Cómo usar este informe

El panel puede mostrar este contenido desde **Informes → Recomendaciones** o desde el informe **En vivo**. Para regenerarlo:

```bash
python3 tools/recommend.py --out progress/reports/recommendations-latest.md
```
