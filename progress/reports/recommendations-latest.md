# NativaX — recomendaciones de calidad

Generado: 2026-10-25 19:24:21.

## Diagnóstico

| Área | Estado |
|---|---|
| Fidelidad visual | 10/300 medidas |
| Rendimiento | 270/270 medidos |
| App idle | 134.1 MB · 0.00 % CPU |
| Vídeo | 0 perfiles · playback no |
| Juegos | 0 perfiles medidos |

## Prioridades

- **P1:** 7
- **P2:** 3

## Recomendaciones automáticas

Motor de reglas con evidencia medida (no una caja negra). Cobertura actual: **10/300** páginas y **270/270** escenarios.

### P1 · DOM / layout — El coste dominante está en DOM y layout, no en JS puro

**Confianza:** alta

**Evidencia**

- matrix.grid-create-1200: 2336.05× (467.2 vs 0.2 ms)
- game3d.quality-640x360-c100: 1940.59× (582.2 vs 0.3 ms)
- layout.grid-create-1k: 1681.03× (504.3 vs 0.3 ms)
- 183 escenarios DOM están por encima del objetivo de 3×.

**Acción:** Agrupar mutaciones DOM, evitar recalcular layout por nodo y hacer style/layout incremental por subárbol.

**Criterio de aceptación:** Crear 1k filas ≤3× Chromium, 10k dentro del presupuesto y sin frame máximo >100 ms.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --only '^dom\.' --out .perf/dom
```

### P1 · JavaScript — El motor JS pierde en cargas que superan el presupuesto

**Confianza:** alta

**Evidencia**

- js.json-deep: 22.78×
- js.typed-arrays: 18.67×
- js.arraybuffer: 14.23×
- js.map-set: 8.26×

**Acción:** Separar coste del motor y del bridge; en escritorio evaluar V8/JavaScriptCore tras el mismo contrato. QuickJS sin JIT no puede igualar a V8 en bucles calientes.

**Criterio de aceptación:** Cada carga JS dentro del objetivo acordado o una decisión documentada de backend por plataforma.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --only '^js\.' --out .perf/js
```

### P1 · fidelidad visual — Hay contenido mal posicionado o fuera de su caja

**Confianza:** media

**Evidencia**

- 50projects50days/auto-text-effect: posición 0.8 %, tinta 99.2 %
- 50projects50days/custom-range-slider: posición 33.1 %, tinta 7.2 %
- 50projects50days/animated-navigation: posición 51.7 %, tinta 1.1 %
- 50projects50days/content-placeholder: posición 56.7 %, tinta 36.0 %

**Acción:** Revisar containing blocks, transforms, posición fija y stacking contexts; corregir el layout antes del color.

**Criterio de aceptación:** Posición ≥90 % y tinta <50 % en las páginas afectadas.

**Comando:**

```bash
dart run debug/engines/visual_comparison/bin/visual_check.dart --only 'pagina' --out .visual/latest
```

### P1 · juegos — Los perfiles de juego Canvas 2D quedan por encima del presupuesto

**Confianza:** alta

**Evidencia**

- game.quality-640x360-p2500: 60.97×
- game.quality-640x360-p5000: 52.86×
- game.quality-854x480-p1000: 43.27×
- game.quality-640x360-p1000: 42.65×

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

### P1 · renderer — DOM, layout y posición apuntan al mismo cuello de botella

**Confianza:** media

**Evidencia**

- Layout visual medio 80.9 % y posición 71.6 %.
- Los escenarios DOM superan el objetivo de trabajo.

**Acción:** Priorizar el motor de layout/posicionamiento compartido antes de microoptimizar páginas individuales.

**Criterio de aceptación:** Layout/posición ≥90 % en el catálogo medido y DOM create 1k ≤3× Chromium.

### P1 · scroll / frames — El scroll de listas largas pierde el presupuesto de frame

**Confianza:** alta

**Evidencia**

- scroll.rows-40k: p95 789.3 ms (objetivo 16.7 ms).
- scroll.rows-25k: p95 423.0 ms (objetivo 16.7 ms).
- scroll.rows-20k: p95 335.2 ms (objetivo 16.7 ms).
- scroll.rows-15k: p95 250.1 ms (objetivo 16.7 ms).

**Acción:** Virtualizar filas, limitar el área de paint y evitar layout global en cada paso de scroll.

**Criterio de aceptación:** p95 ≤16.7 ms y frame máximo ≤100 ms en los escenarios de scroll.

**Comando:**

```bash
dart run tools/perf/bin/perf.dart run --only '^scroll\.' --out .perf/scroll
```

### P2 · cobertura visual — Faltan 290 páginas visuales por medir

**Confianza:** alta

**Evidencia**

- 10/300 páginas con resultado medido.
- Sin esa muestra no se puede extrapolar la fidelidad al catálogo completo.

**Acción:** Ejecutar el catálogo visual completo y revisar las páginas nuevas.

**Criterio de aceptación:** 300/300 páginas medidas; overall y tinta reportados sin muestras pendientes.

**Comando:**

```bash
dart run debug/engines/visual_comparison/bin/visual_check.dart --all --catalog .visual/catalog.json --out .visual/latest
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

- Idle real: 134.1 MB y 0.00 % CPU.
- No hay una serie de RSS pico de la app real con páginas pesadas; el RSS del arnés no sirve para ese presupuesto.

**Acción:** Medir RSS máximo con 1k/10k filas, scroll y navegación repetida.

**Criterio de aceptación:** RSS pico de la app ≤250 MB en la carga acordada, sin tendencia creciente tras liberar recursos.

## Detalle de rendimiento

| Escenario | Tipo | Veredicto | NativaX ms | Chromium ms | Ratio | p95 ms | max ms | Nodos N/C | RSS arnés MB | Siguiente acción |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| `idle.blank` | idle | WARN | 0.0 | 0.0 | — | 0.0 | 0.0 | 7/7 | 743 | Mantener la línea base y vigilar regresiones. |
| `dom.rows-create-1k` | dom | WARN | 362.0 | 69.8 | 5.19× | 97.3 | 97.3 | 1008/1008 | 729 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-10k` | dom | FAIL | 10038.0 | 198.0 | 50.70× | 178.9 | 178.9 | 10008/10008 | 737 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-10k` | dom | FAIL | 0.0 | 21.2 | 0.00× | 0.0 | 0.0 | 10008/10008 | 751 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-remove-10k` | dom | WARN | 120.6 | 6.3 | 19.02× | 73.7 | 73.7 | 8/8 | 735 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `scroll.rows-10k` | scroll | FAIL | 1366.4 | 1.3 | 1051.08× | 119.3 | 143.1 | 10008/10008 | 747 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.2d-tiles` | scroll | PASS | 144.0 | 0.6 | 240.06× | 7.1 | 44.5 | 908/908 | 716 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `js.arrays` | js | PASS | 89.8 | 33.7 | 2.67× | 4.0 | 4.0 | 8/8 | 705 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.objects` | js | PASS | 32.6 | 54.3 | 0.60× | 3.7 | 3.7 | 8/8 | 694 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.strings` | js | PASS | 18.8 | 43.3 | 0.43× | 4.1 | 4.1 | 8/8 | 704 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.json` | js | PASS | 107.3 | 63.0 | 1.70× | 3.8 | 3.8 | 8/8 | 703 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `dom.rows-create-100` | dom | WARN | 118.8 | 26.5 | 4.48× | 71.0 | 71.0 | 108/108 | 714 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-250` | dom | WARN | 168.5 | 45.9 | 3.67× | 78.9 | 78.9 | 258/258 | 713 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-500` | dom | WARN | 234.9 | 66.0 | 3.56× | 84.2 | 84.2 | 508/508 | 706 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-2k` | dom | FAIL | 797.4 | 48.4 | 16.49× | 140.0 | 140.0 | 2008/2008 | 724 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-5k` | dom | FAIL | 2903.8 | 167.4 | 17.35× | 183.9 | 183.9 | 5008/5008 | 727 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-20k` | dom | FAIL | 0.0 | 445.2 | 0.00× | 0.0 | 0.0 | 8/20008 | 738 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-create-50k` | dom | FAIL | 0.0 | 1051.6 | 0.00× | 0.0 | 0.0 | 8/50008 | 736 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-update-100` | dom | WARN | 99.4 | 0.5 | 206.71× | 80.6 | 80.6 | 108/108 | 710 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-1k` | dom | FAIL | 462.9 | 11.0 | 42.18× | 101.4 | 101.4 | 1008/1008 | 727 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-5k` | dom | FAIL | 8715.1 | 15.7 | 555.49× | 125.0 | 125.0 | 5008/5008 | 738 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-100` | dom | WARN | 24.3 | 0.5 | 51.46× | 19.8 | 19.8 | 8/8 | 712 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-1k` | dom | WARN | 59.0 | 1.4 | 43.30× | 40.2 | 40.2 | 8/8 | 715 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.cards-create-1k` | dom | FAIL | 238.8 | 0.5 | 477.64× | 236.0 | 236.0 | 5007/5007 | 730 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.cards-create-5k` | dom | FAIL | 122.7 | 0.3 | 408.99× | 121.1 | 121.1 | 25007/25007 | 793 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.table-create-1k` | dom | FAIL | 204.4 | 1.4 | 145.99× | 202.6 | 202.6 | 5009/5009 | 730 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.flex-create-1k` | dom | WARN | 40.4 | 0.3 | 134.50× | 37.0 | 37.0 | 1007/1007 | 755 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.flex-create-5k` | dom | FAIL | 125.5 | 0.4 | 313.84× | 120.4 | 120.4 | 5007/5007 | 930 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.grid-create-1k` | dom | FAIL | 537.0 | 0.6 | 895.03× | 535.0 | 535.0 | 1007/1007 | 749 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.grid-create-5k` | dom | FAIL | 540.7 | 0.4 | 1351.84× | 539.0 | 539.0 | 5007/5007 | 776 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.nested-create-1k` | dom | WARN | 80.2 | 0.3 | 267.30× | 78.0 | 78.0 | 6007/6007 | 1006 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `form.inputs-1k` | dom | FAIL | 2656.6 | 94.7 | 28.06× | 2584.8 | 2584.8 | 2007/2007 | 1326 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.text-create-5k` | dom | WARN | 34.9 | 0.4 | 87.20× | 33.4 | 33.4 | 5007/5007 | 731 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.position-create-1k` | dom | WARN | 61.6 | 0.3 | 205.21× | 59.9 | 59.9 | 1008/1008 | 722 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `scroll.rows-1k` | scroll | WARN | 701.9 | 0.6 | 1169.87× | 58.1 | 75.9 | 1008/1008 | 730 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-5k` | scroll | FAIL | 1288.8 | 3.1 | 415.74× | 102.1 | 108.3 | 5008/5008 | 743 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-20k` | scroll | FAIL | 4612.6 | 1.9 | 2427.68× | 335.2 | 367.0 | 20008/20008 | 792 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-50k` | scroll | WARN | 11.4 | 1.4 | 8.16× | 0.2 | 3.4 | 8/50008 | 785 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.2d-tiles-225` | scroll | PASS | 170.7 | 1.6 | 106.69× | 9.0 | 72.8 | 233/233 | 709 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.2d-tiles-400` | scroll | PASS | 145.3 | 1.1 | 132.08× | 10.0 | 48.3 | 408/408 | 720 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.2d-tiles-1600` | scroll | PASS | 115.6 | 8.4 | 13.77× | 5.4 | 40.1 | 1608/1608 | 719 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.2d-tiles-2500` | scroll | PASS | 121.7 | 16.9 | 7.20× | 6.1 | 44.2 | 2508/2508 | 724 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.horizontal-1k` | scroll | PASS | 43.1 | 5.5 | 7.84× | 0.1 | 34.7 | 1007/1007 | 768 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.horizontal-5k` | scroll | PASS | 82.5 | 3.7 | 22.30× | 0.1 | 75.8 | 5007/5007 | 993 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.table-1k` | scroll | FAIL | 1651.0 | 15.5 | 106.52× | 127.0 | 179.6 | 5009/5009 | 766 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.cards-2k` | scroll | WARN | 561.8 | 1.6 | 351.15× | 30.1 | 97.3 | 10007/10007 | 752 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.forms-1k` | scroll | FAIL | 1629.2 | 1.4 | 1163.71× | 118.7 | 189.7 | 2007/2007 | 1237 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.text-5k` | scroll | WARN | 349.7 | 2.0 | 174.87× | 24.1 | 33.1 | 5007/5007 | 731 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.nested-1k` | scroll | FAIL | 2797.5 | 1.7 | 1645.61× | 157.6 | 188.0 | 6007/6007 | 1016 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `js.arrays-10k` | js | PASS | 11.2 | 4.9 | 2.29× | 4.5 | 4.5 | 8/8 | 709 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.arrays-500k` | js | PASS | 509.8 | 282.4 | 1.81× | 3.9 | 3.9 | 8/8 | 728 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.objects-5k` | js | PASS | 6.6 | 9.1 | 0.72× | 3.9 | 3.9 | 8/8 | 703 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.objects-100k` | js | PASS | 72.9 | 62.2 | 1.17× | 3.8 | 3.8 | 8/8 | 708 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.strings-5k` | js | PASS | 4.6 | 7.8 | 0.60× | 3.6 | 3.6 | 8/8 | 702 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.strings-100k` | js | PASS | 30.4 | 46.9 | 0.65× | 3.8 | 3.8 | 8/8 | 701 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.json-5k` | js | WARN | 34.1 | 7.0 | 4.87× | 4.1 | 4.1 | 8/8 | 699 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.json-50k` | js | WARN | 294.2 | 55.5 | 5.30× | 4.8 | 4.8 | 8/8 | 730 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.typed-arrays` | js | WARN | 84.0 | 4.5 | 18.67× | 4.1 | 4.1 | 8/8 | 705 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.regex` | js | WARN | 13.9 | 4.4 | 3.17× | 4.6 | 4.6 | 8/8 | 707 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.map-set` | js | WARN | 281.7 | 34.1 | 8.26× | 3.8 | 3.8 | 8/8 | 716 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.sort-strings` | js | PASS | 30.8 | 15.5 | 1.99× | 4.0 | 4.0 | 8/8 | 706 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.fib` | js | WARN | 37.4 | 5.0 | 7.47× | 4.5 | 4.5 | 8/8 | 704 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.math` | js | PASS | 42.1 | 16.4 | 2.57× | 4.4 | 4.4 | 8/8 | 703 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.dates` | js | PASS | 8.2 | 3.4 | 2.42× | 4.2 | 4.2 | 8/8 | 710 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.prototypes` | js | WARN | 47.0 | 7.6 | 6.19× | 4.9 | 4.9 | 8/8 | 706 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.closures` | js | WARN | 59.5 | 14.1 | 4.22× | 4.7 | 4.7 | 8/8 | 699 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.generators` | js | WARN | 26.9 | 8.5 | 3.17× | 4.6 | 4.6 | 8/8 | 698 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.recursion-tree` | js | WARN | 7.9 | 1.0 | 7.93× | 4.1 | 4.1 | 8/8 | 699 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.json-deep` | js | WARN | 4.6 | 0.2 | 22.78× | 4.2 | 4.2 | 8/8 | 705 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `js.arraybuffer` | js | WARN | 125.2 | 8.8 | 14.23× | 5.9 | 5.9 | 8/8 | 710 | Perfilar motor vs bridge; evaluar V8/JSC en escritorio; QuickJS no iguala JIT. |
| `layout.flex-create-100` | dom | WARN | 16.6 | 0.3 | 55.30× | 12.5 | 12.5 | 107/107 | 713 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.flex-create-1k` | dom | WARN | 35.9 | 0.5 | 71.77× | 33.5 | 33.5 | 1007/1007 | 759 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.flex-create-5k` | dom | WARN | 83.5 | 0.4 | 208.85× | 81.2 | 81.2 | 5007/5007 | 943 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.grid-create-100` | dom | WARN | 15.4 | 0.4 | 38.44× | 13.6 | 13.6 | 107/107 | 726 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.grid-create-1k` | dom | FAIL | 504.3 | 0.3 | 1681.03× | 501.5 | 501.5 | 1007/1007 | 753 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.grid-create-5k` | dom | FAIL | 503.1 | 1.4 | 359.36× | 500.4 | 500.4 | 5007/5007 | 773 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.table-create-100` | dom | FAIL | 213.8 | 0.4 | 534.48× | 210.4 | 210.4 | 509/509 | 719 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.table-create-1k` | dom | FAIL | 142.1 | 1.5 | 94.72× | 139.9 | 139.9 | 5009/5009 | 736 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.mixed-create-1k` | dom | FAIL | 293.4 | 1.1 | 266.69× | 291.8 | 291.8 | 5007/5007 | 759 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `layout.text-create-1k` | dom | WARN | 54.4 | 1.7 | 31.98× | 51.1 | 51.1 | 1007/1007 | 723 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `form.selects-500` | dom | FAIL | 924.4 | 27.3 | 33.82× | 887.6 | 887.6 | 2507/2507 | 883 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `form.checkboxes-1k` | dom | FAIL | 1071.0 | 5.7 | 188.38× | 1008.6 | 1008.6 | 2007/2007 | 919 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `form.labels-1k` | dom | WARN | 33.8 | 1.6 | 21.10× | 31.5 | 31.5 | 3007/3007 | 837 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `form.validation-1k` | dom | PASS | 95.1 | 37.5 | 2.54× | 83.2 | 83.2 | 2007/2007 | 1224 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `form.inputs-5k` | dom | FAIL | 10677.5 | 220.6 | 48.41× | 9910.9 | 9910.9 | 10007/10007 | 3418 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.keyframes-100` | dom | WARN | 77.2 | 1.3 | 59.71× | 67.5 | 67.5 | 108/108 | 728 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.keyframes-1k` | dom | FAIL | 142.7 | 4.7 | 30.32× | 132.2 | 132.2 | 1008/1008 | 748 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.transitions-1k` | dom | FAIL | 726.3 | 35.7 | 20.35× | 560.1 | 560.1 | 1008/1008 | 788 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.transform-1k` | dom | FAIL | 740.9 | 36.9 | 20.07× | 567.7 | 567.7 | 1008/1008 | 764 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.opacity-1k` | dom | FAIL | 722.0 | 57.6 | 12.54× | 540.3 | 540.3 | 1008/1008 | 768 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.raf-100` | dom | WARN | 385.0 | 21.3 | 18.09× | 93.5 | 93.5 | 108/108 | 731 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.canvas-100` | dom | WARN | 36.2 | 2.1 | 17.25× | 11.9 | 11.9 | 8/8 | 713 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.canvas-1k` | dom | WARN | 86.0 | 3.7 | 23.25× | 12.1 | 12.1 | 8/8 | 714 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `animation.mixed-1k` | dom | FAIL | 910.3 | 41.9 | 21.70× | 699.1 | 699.1 | 1008/1008 | 779 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-10` | dom | FAIL | 128.1 | 63.7 | 2.01× | 111.2 | 111.2 | 18/18 | 709 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-20` | dom | FAIL | 133.5 | 6.3 | 21.27× | 102.2 | 102.2 | 28/28 | 713 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-30` | dom | FAIL | 135.1 | 6.3 | 21.55× | 106.1 | 106.1 | 38/38 | 715 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-40` | dom | FAIL | 137.5 | 6.0 | 22.79× | 103.0 | 103.0 | 48/48 | 722 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-60` | dom | FAIL | 144.2 | 6.9 | 21.01× | 101.1 | 101.1 | 68/68 | 724 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-80` | dom | FAIL | 186.1 | 9.1 | 20.55× | 118.9 | 118.9 | 88/88 | 723 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-120` | dom | WARN | 159.9 | 8.4 | 18.99× | 90.2 | 90.2 | 128/128 | 720 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-160` | dom | WARN | 172.1 | 9.1 | 18.83× | 90.4 | 90.4 | 168/168 | 722 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-200` | dom | FAIL | 233.2 | 9.8 | 23.85× | 128.6 | 128.6 | 208/208 | 721 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-300` | dom | FAIL | 219.9 | 20.7 | 10.61× | 113.3 | 113.3 | 308/308 | 714 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-400` | dom | WARN | 235.2 | 58.3 | 4.04× | 99.7 | 99.7 | 408/408 | 724 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-600` | dom | WARN | 254.6 | 15.8 | 16.16× | 85.8 | 85.8 | 608/608 | 750 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-800` | dom | FAIL | 348.3 | 23.0 | 15.16× | 103.5 | 103.5 | 808/808 | 728 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-1200` | dom | FAIL | 434.8 | 44.6 | 9.76× | 112.4 | 112.4 | 1208/1208 | 731 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-1500` | dom | FAIL | 536.1 | 37.6 | 14.25× | 111.2 | 111.2 | 1508/1508 | 734 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-2500` | dom | FAIL | 901.5 | 67.9 | 13.27× | 109.9 | 109.9 | 2508/2508 | 732 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-3k` | dom | FAIL | 1073.2 | 131.2 | 8.18× | 101.1 | 101.1 | 3008/3008 | 737 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-4k` | dom | FAIL | 1926.0 | 123.7 | 15.57× | 119.3 | 119.3 | 4008/4008 | 734 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-6k` | dom | FAIL | 2861.3 | 123.8 | 23.11× | 119.8 | 119.8 | 6008/6008 | 742 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-8k` | dom | FAIL | 5925.1 | 182.7 | 32.43× | 159.5 | 159.5 | 8008/8008 | 743 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-create-12k` | dom | FAIL | 0.0 | 258.8 | 0.00× | 0.0 | 0.0 | 8/12008 | 741 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-create-15k` | dom | FAIL | 0.0 | 427.8 | 0.00× | 0.0 | 0.0 | 8/15008 | 745 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-create-25k` | dom | FAIL | 0.0 | 575.0 | 0.00× | 0.0 | 0.0 | 8/25008 | 745 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-create-40k` | dom | FAIL | 0.0 | 919.0 | 0.00× | 0.0 | 0.0 | 8/40008 | 742 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-update-10` | dom | WARN | 31.2 | 0.4 | 71.10× | 24.8 | 24.8 | 18/18 | 719 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-20` | dom | WARN | 40.5 | 1.1 | 36.48× | 30.3 | 30.3 | 28/28 | 721 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-30` | dom | WARN | 46.5 | 0.6 | 73.57× | 41.1 | 41.1 | 38/38 | 726 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-40` | dom | WARN | 73.9 | 0.5 | 143.51× | 65.5 | 65.5 | 48/48 | 722 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-60` | dom | WARN | 74.3 | 0.4 | 200.25× | 65.9 | 65.9 | 68/68 | 715 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-80` | dom | WARN | 79.5 | 0.5 | 166.23× | 68.1 | 68.1 | 88/88 | 714 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-120` | dom | WARN | 105.8 | 0.7 | 156.49× | 83.8 | 83.8 | 128/128 | 724 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-160` | dom | WARN | 90.2 | 2.7 | 32.89× | 62.6 | 62.6 | 168/168 | 725 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-200` | dom | WARN | 135.5 | 0.7 | 197.18× | 97.7 | 97.7 | 208/208 | 723 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-300` | dom | WARN | 134.4 | 1.4 | 93.42× | 92.7 | 92.7 | 308/308 | 727 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-400` | dom | WARN | 138.3 | 5.4 | 25.76× | 75.7 | 75.7 | 408/408 | 723 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-600` | dom | WARN | 205.7 | 8.1 | 25.37× | 75.3 | 75.3 | 608/608 | 733 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-800` | dom | WARN | 256.8 | 9.2 | 27.79× | 70.2 | 70.2 | 808/808 | 731 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-1200` | dom | WARN | 435.9 | 3.1 | 141.76× | 66.2 | 66.2 | 1208/1208 | 729 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-1500` | dom | WARN | 626.7 | 17.0 | 36.98× | 69.4 | 69.4 | 1508/1508 | 730 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-2500` | dom | FAIL | 1624.2 | 6.2 | 262.22× | 101.6 | 101.6 | 2508/2508 | 735 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-3k` | dom | WARN | 2690.2 | 18.3 | 146.65× | 91.6 | 91.6 | 3008/3008 | 740 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-4k` | dom | WARN | 4667.9 | 10.6 | 440.57× | 95.5 | 95.5 | 4008/4008 | 744 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-6k` | dom | FAIL | 10170.7 | 14.3 | 712.39× | 109.1 | 109.1 | 6008/6008 | 755 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-update-8k` | dom | FAIL | 0.0 | 18.4 | 0.00× | 0.0 | 0.0 | 8008/8008 | 752 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-update-12k` | dom | FAIL | 0.0 | 31.5 | 0.00× | 0.0 | 0.0 | 12008/12008 | 763 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-update-15k` | dom | FAIL | 0.0 | 50.5 | 0.00× | 0.0 | 0.0 | 15008/15008 | 782 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-update-25k` | dom | FAIL | 0.0 | 49.5 | 0.00× | 0.0 | 0.0 | 25008/25008 | 823 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-update-40k` | dom | FAIL | 0.0 | 94.7 | 0.00× | 0.0 | 0.0 | 40008/40008 | 872 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `dom.rows-remove-10` | dom | WARN | 24.5 | 0.5 | 47.70× | 20.0 | 20.0 | 8/8 | 732 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-20` | dom | WARN | 21.5 | 0.5 | 44.33× | 16.5 | 16.5 | 8/8 | 715 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-30` | dom | WARN | 26.1 | 0.3 | 96.69× | 20.3 | 20.3 | 8/8 | 708 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-40` | dom | WARN | 24.7 | 0.6 | 39.54× | 19.8 | 19.8 | 8/8 | 714 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-60` | dom | WARN | 22.1 | 0.7 | 31.33× | 17.9 | 17.9 | 8/8 | 710 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-80` | dom | WARN | 22.9 | 0.7 | 33.21× | 18.2 | 18.2 | 8/8 | 717 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-120` | dom | WARN | 23.8 | 0.7 | 32.75× | 19.3 | 19.3 | 8/8 | 716 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-160` | dom | WARN | 27.2 | 1.0 | 27.30× | 21.3 | 21.3 | 8/8 | 717 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-200` | dom | WARN | 26.9 | 0.9 | 30.06× | 21.2 | 21.2 | 8/8 | 725 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-300` | dom | WARN | 29.1 | 0.4 | 66.97× | 22.7 | 22.7 | 8/8 | 712 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-400` | dom | WARN | 33.8 | 1.7 | 19.52× | 25.3 | 25.3 | 8/8 | 721 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-600` | dom | WARN | 33.3 | 0.5 | 62.16× | 24.8 | 24.8 | 8/8 | 744 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-800` | dom | WARN | 43.2 | 1.4 | 31.64× | 32.9 | 32.9 | 8/8 | 741 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-1200` | dom | WARN | 39.7 | 6.1 | 6.47× | 26.3 | 26.3 | 8/8 | 729 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-1500` | dom | WARN | 43.0 | 2.2 | 19.94× | 30.9 | 30.9 | 8/8 | 735 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-2500` | dom | WARN | 45.5 | 2.9 | 15.45× | 33.2 | 33.2 | 8/8 | 733 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-3k` | dom | WARN | 51.9 | 8.7 | 5.95× | 37.8 | 37.8 | 8/8 | 733 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-4k` | dom | WARN | 62.5 | 7.2 | 8.69× | 44.4 | 44.4 | 8/8 | 730 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-6k` | dom | WARN | 81.8 | 15.7 | 5.20× | 56.0 | 56.0 | 8/8 | 737 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-8k` | dom | WARN | 107.8 | 6.9 | 15.53× | 66.7 | 66.7 | 8/8 | 743 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-12k` | dom | FAIL | 157.0 | 7.1 | 21.99× | 100.6 | 100.6 | 8/8 | 759 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-15k` | dom | FAIL | 182.9 | 15.5 | 11.77× | 108.5 | 108.5 | 8/8 | 766 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-25k` | dom | FAIL | 283.6 | 24.1 | 11.78× | 162.0 | 162.0 | 8/8 | 799 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `dom.rows-remove-40k` | dom | FAIL | 392.0 | 20.9 | 18.72× | 232.9 | 232.9 | 8/8 | 844 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `scroll.rows-10` | scroll | PASS | 16.4 | 1.0 | 16.41× | 0.2 | 4.5 | 18/18 | 719 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.rows-20` | scroll | PASS | 13.2 | 0.4 | 33.12× | 0.1 | 4.9 | 28/28 | 706 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.rows-30` | scroll | PASS | 59.3 | 0.6 | 98.85× | 15.1 | 31.9 | 38/38 | 741 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.rows-40` | scroll | PASS | 72.3 | 0.6 | 120.49× | 10.1 | 50.1 | 48/48 | 717 | Reducir trabajo o mejorar el layout/renderer antes de optimizar microcasos. |
| `scroll.rows-60` | scroll | WARN | 145.7 | 2.1 | 69.40× | 44.1 | 77.2 | 68/68 | 724 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-80` | scroll | WARN | 183.1 | 0.8 | 228.86× | 63.2 | 68.9 | 88/88 | 752 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-120` | scroll | WARN | 281.5 | 0.7 | 402.18× | 62.3 | 62.4 | 128/128 | 742 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-160` | scroll | WARN | 376.0 | 0.5 | 752.05× | 56.7 | 60.0 | 168/168 | 729 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-200` | scroll | WARN | 489.9 | 0.4 | 1224.84× | 78.4 | 79.9 | 208/208 | 734 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-300` | scroll | WARN | 541.8 | 14.8 | 36.61× | 60.3 | 82.2 | 308/308 | 738 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-400` | scroll | WARN | 714.1 | 1.7 | 420.04× | 71.9 | 84.9 | 408/408 | 737 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-600` | scroll | WARN | 684.7 | 0.6 | 1141.11× | 57.7 | 59.3 | 608/608 | 747 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-800` | scroll | WARN | 723.9 | 3.0 | 241.32× | 63.6 | 86.1 | 808/808 | 737 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-1200` | scroll | WARN | 715.0 | 3.5 | 204.27× | 62.4 | 63.1 | 1208/1208 | 749 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-1500` | scroll | WARN | 898.1 | 3.7 | 242.72× | 67.3 | 76.6 | 1508/1508 | 738 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-2500` | scroll | FAIL | 1087.4 | 0.6 | 1812.31× | 82.5 | 113.3 | 2508/2508 | 744 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-3k` | scroll | FAIL | 989.8 | 0.9 | 1099.75× | 86.7 | 106.0 | 3008/3008 | 745 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-4k` | scroll | WARN | 1057.8 | 0.5 | 2115.57× | 88.2 | 92.1 | 4008/4008 | 746 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-6k` | scroll | FAIL | 1552.8 | 0.8 | 1941.01× | 113.6 | 137.5 | 6008/6008 | 757 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-8k` | scroll | FAIL | 1728.4 | 1.0 | 1728.39× | 130.5 | 153.7 | 8008/8008 | 757 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-12k` | scroll | FAIL | 2527.0 | 1.6 | 1579.35× | 199.6 | 208.7 | 12008/12008 | 770 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-15k` | scroll | FAIL | 3389.7 | 1.3 | 2607.47× | 250.1 | 281.6 | 15008/15008 | 790 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-25k` | scroll | FAIL | 5676.8 | 0.7 | 8109.68× | 423.0 | 475.5 | 25008/25008 | 834 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `scroll.rows-40k` | scroll | FAIL | 12096.5 | 0.7 | 17280.73× | 789.3 | 952.6 | 40008/40008 | 871 | Virtualizar filas, limitar paint y eliminar layout global por paso. |
| `matrix.flex-create-10` | dom | WARN | 7.6 | 0.5 | 15.27× | 5.1 | 5.1 | 17/17 | 719 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-20` | dom | WARN | 10.6 | 0.4 | 26.44× | 8.0 | 8.0 | 27/27 | 715 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-50` | dom | WARN | 12.0 | 1.0 | 12.01× | 8.5 | 8.5 | 57/57 | 720 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-200` | dom | WARN | 36.9 | 0.6 | 61.46× | 32.7 | 32.7 | 207/207 | 740 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-400` | dom | WARN | 22.9 | 0.5 | 45.88× | 19.9 | 19.9 | 407/407 | 750 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-800` | dom | WARN | 27.8 | 0.6 | 46.35× | 25.2 | 25.2 | 807/807 | 760 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-1200` | dom | WARN | 41.1 | 0.5 | 82.13× | 38.7 | 38.7 | 1207/1207 | 790 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-2k` | dom | WARN | 53.5 | 0.6 | 89.20× | 51.3 | 51.3 | 2007/2007 | 805 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-3k` | dom | WARN | 72.0 | 1.5 | 47.98× | 69.7 | 69.7 | 3007/3007 | 849 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-4k` | dom | FAIL | 111.4 | 1.4 | 79.60× | 108.7 | 108.7 | 4007/4007 | 889 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-8k` | dom | WARN | 91.8 | 0.7 | 131.08× | 89.6 | 89.6 | 8007/8007 | 1036 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.flex-create-12k` | dom | FAIL | 169.8 | 0.4 | 424.38× | 166.4 | 166.4 | 12007/12007 | 1194 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-10` | dom | WARN | 7.1 | 1.4 | 5.10× | 4.7 | 4.7 | 17/17 | 714 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-25` | dom | WARN | 8.4 | 0.4 | 20.92× | 6.8 | 6.8 | 32/32 | 717 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-50` | dom | WARN | 10.3 | 1.6 | 6.45× | 8.6 | 8.6 | 57/57 | 722 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-200` | dom | WARN | 14.9 | 0.3 | 49.59× | 12.9 | 12.9 | 207/207 | 732 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-500` | dom | FAIL | 240.4 | 0.3 | 801.24× | 237.7 | 237.7 | 507/507 | 748 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-1200` | dom | FAIL | 467.2 | 0.2 | 2336.05× | 465.0 | 465.0 | 1207/1207 | 769 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-2500` | dom | FAIL | 458.1 | 1.4 | 327.24× | 456.6 | 456.6 | 2507/2507 | 765 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-5k` | dom | FAIL | 488.6 | 1.3 | 375.82× | 486.8 | 486.8 | 5007/5007 | 776 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-8k` | dom | FAIL | 447.0 | 0.3 | 1489.88× | 445.3 | 445.3 | 8007/8007 | 777 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.grid-create-12k` | dom | FAIL | 444.2 | 0.4 | 1110.49× | 442.7 | 442.7 | 12007/12007 | 792 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.table-create-500` | dom | FAIL | 142.6 | 0.7 | 203.75× | 141.1 | 141.1 | 2509/2509 | 737 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `matrix.mixed-create-500` | dom | FAIL | 388.2 | 0.4 | 970.41× | 386.5 | 386.5 | 2507/2507 | 758 | Agrupar mutaciones, cachear style y hacer layout incremental por subárbol. |
| `game.quality-640x360-p100` | dom | WARN | 44.9 | 1.7 | 26.41× | 10.4 | 10.4 | 8/8 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-640x360-p500` | dom | WARN | 85.6 | 2.2 | 38.92× | 9.9 | 9.9 | 8/8 | 740 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-640x360-p1000` | dom | WARN | 140.8 | 3.3 | 42.65× | 9.2 | 9.2 | 8/8 | 714 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-640x360-p2500` | dom | WARN | 292.6 | 4.8 | 60.97× | 13.9 | 13.9 | 8/8 | 721 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-640x360-p5000` | dom | WARN | 380.6 | 7.2 | 52.86× | 12.0 | 12.0 | 8/8 | 742 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-854x480-p100` | dom | WARN | 39.1 | 1.5 | 26.09× | 9.6 | 9.6 | 8/8 | 717 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-854x480-p500` | dom | WARN | 92.2 | 2.4 | 38.43× | 9.4 | 9.4 | 8/8 | 716 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-854x480-p1000` | dom | WARN | 177.4 | 4.1 | 43.27× | 12.4 | 12.4 | 8/8 | 729 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-854x480-p2500` | dom | WARN | 256.4 | 7.6 | 33.74× | 12.7 | 12.7 | 8/8 | 714 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-854x480-p5000` | dom | WARN | 353.4 | 32.2 | 10.98× | 9.7 | 9.7 | 8/8 | 746 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1280x720-p100` | dom | WARN | 40.5 | 3.1 | 13.07× | 10.3 | 10.3 | 8/8 | 710 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1280x720-p500` | dom | WARN | 104.1 | 4.2 | 24.79× | 10.1 | 10.1 | 8/8 | 728 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1280x720-p1000` | dom | WARN | 144.7 | 9.4 | 15.39× | 9.9 | 9.9 | 8/8 | 723 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1280x720-p2500` | dom | WARN | 295.8 | 9.6 | 30.82× | 11.5 | 11.5 | 8/8 | 724 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1280x720-p5000` | dom | WARN | 414.7 | 35.9 | 11.55× | 10.1 | 10.1 | 8/8 | 740 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1920x1080-p100` | dom | WARN | 51.7 | 14.0 | 3.69× | 11.8 | 11.8 | 8/8 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1920x1080-p500` | dom | WARN | 141.2 | 5.4 | 26.14× | 16.9 | 16.9 | 8/8 | 721 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1920x1080-p1000` | dom | WARN | 145.1 | 6.5 | 22.32× | 12.3 | 12.3 | 8/8 | 717 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1920x1080-p2500` | dom | WARN | 266.7 | 31.0 | 8.60× | 14.4 | 14.4 | 8/8 | 727 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-1920x1080-p5000` | dom | WARN | 354.3 | 33.0 | 10.74× | 11.6 | 11.6 | 8/8 | 741 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-2560x1440-p100` | dom | WARN | 51.3 | 14.2 | 3.61× | 9.7 | 9.7 | 8/8 | 726 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-2560x1440-p500` | dom | WARN | 100.4 | 16.0 | 6.28× | 10.6 | 10.6 | 8/8 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-2560x1440-p1000` | dom | WARN | 174.2 | 5.1 | 34.16× | 10.2 | 10.2 | 8/8 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-2560x1440-p2500` | dom | WARN | 282.6 | 9.0 | 31.40× | 14.5 | 14.5 | 8/8 | 726 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game.quality-2560x1440-p5000` | dom | WARN | 368.1 | 10.8 | 34.08× | 9.5 | 9.5 | 8/8 | 742 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-640x360-c100` | dom | FAIL | 582.2 | 0.3 | 1940.59× | 123.4 | 123.4 | 8/8 | 755 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-640x360-c500` | dom | WARN | 25.4 | 0.2 | 127.16× | 12.6 | 12.6 | 8/8 | 758 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-640x360-c1000` | dom | PASS | 21.0 | 0.0 | — | 9.7 | 9.7 | 8/8 | 743 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-640x360-c2500` | dom | WARN | 52.2 | 0.5 | 104.31× | 8.7 | 8.7 | 8/8 | 749 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-640x360-c5000` | dom | WARN | 23.1 | 0.3 | 76.99× | 10.0 | 10.0 | 8/8 | 748 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-854x480-c100` | dom | WARN | 18.2 | 0.1 | 182.20× | 8.8 | 8.8 | 8/8 | 754 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-854x480-c500` | dom | WARN | 32.4 | 0.3 | 108.03× | 8.6 | 8.6 | 8/8 | 753 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-854x480-c1000` | dom | WARN | 21.8 | 0.1 | 217.65× | 9.3 | 9.3 | 8/8 | 758 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-854x480-c2500` | dom | WARN | 25.9 | 0.2 | 129.33× | 8.9 | 8.9 | 8/8 | 748 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-854x480-c5000` | dom | WARN | 23.8 | 0.4 | 59.41× | 9.4 | 9.4 | 8/8 | 744 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1280x720-c100` | dom | WARN | 26.8 | 0.2 | 134.08× | 12.6 | 12.6 | 8/8 | 754 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1280x720-c500` | dom | WARN | 28.6 | 0.1 | 286.26× | 9.9 | 9.9 | 8/8 | 736 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1280x720-c1000` | dom | WARN | 29.5 | 0.1 | 295.12× | 9.7 | 9.7 | 8/8 | 750 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1280x720-c2500` | dom | WARN | 32.1 | 1.2 | 26.76× | 10.4 | 10.4 | 8/8 | 748 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1280x720-c5000` | dom | WARN | 34.7 | 0.4 | 86.65× | 10.6 | 10.6 | 8/8 | 764 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1920x1080-c100` | dom | WARN | 36.9 | 0.3 | 123.01× | 12.1 | 12.1 | 8/8 | 753 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1920x1080-c500` | dom | WARN | 47.4 | 0.2 | 236.96× | 11.9 | 11.9 | 8/8 | 756 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1920x1080-c1000` | dom | WARN | 73.9 | 0.3 | 246.37× | 12.0 | 12.0 | 8/8 | 755 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1920x1080-c2500` | dom | WARN | 56.8 | 0.3 | 189.27× | 13.4 | 13.4 | 8/8 | 752 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-1920x1080-c5000` | dom | WARN | 87.6 | 0.5 | 175.28× | 19.3 | 19.3 | 8/8 | 751 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-2560x1440-c100` | dom | WARN | 60.0 | 0.4 | 150.03× | 16.1 | 16.1 | 8/8 | 751 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-2560x1440-c500` | dom | WARN | 98.0 | 0.2 | 490.07× | 17.3 | 17.3 | 8/8 | 783 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-2560x1440-c1000` | dom | WARN | 86.1 | 0.3 | 286.93× | 18.3 | 18.3 | 8/8 | 778 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-2560x1440-c2500` | dom | WARN | 96.0 | 0.1 | 959.64× | 23.7 | 23.7 | 8/8 | 759 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `game3d.quality-2560x1440-c5000` | dom | WARN | 82.9 | 0.2 | 414.69× | 15.6 | 15.6 | 8/8 | 757 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| `external.browserbench-quick` | external | FAIL | 60313.6 | 11204.7 | 5.38× | 3.1 | 1239.1 | 0/17517 | 889 | Investigar el error del motor antes de comparar rendimiento. |
| `external.jsfb-create-1k` | external | FAIL | 2730.0 | 790.3 | 3.45× | 215.1 | 215.1 | 8031/8031 | 749 | Reproducir el benchmark externo con la misma carga y revisar el cuello. |
| `external.jsfb-create-10k` | external | FAIL | 68603.0 | 1639.4 | 41.85× | 3.0 | 148.0 | 30/80031 | 781 | Investigar el error del motor antes de comparar rendimiento. |
| `external.jsfb-clear` | external | FAIL | 0.0 | 260.6 | 0.00× | 0.0 | 0.0 | 30/31 | 793 | Reducir el trabajo por operación o elevar el presupuesto con justificación; el timeout no es un PASS |
| `external.cerious-load-scroll` | external | FAIL | 146.0 | 0.5 | 312.01× | 37.7 | 42.4 | 416/763 | 774 | Reproducir el benchmark externo con la misma carga y revisar el cuello. |
| `external.uibench-load-scroll` | external | FAIL | 11.7 | 0.6 | 19.45× | 0.1 | 3.7 | 13/153 | 712 | Reproducir el benchmark externo con la misma carga y revisar el cuello. |

### Motivos por escenario

- `idle.blank` — idle-rss: 742.4 MB tail vs 250.0 MB target; idle-cpu: 3.82 % tail vs 1.0 % target; Offscreen harness baseline (includes flutter test + tester); not the desktop app process.
- `dom.rows-create-1k` — work-ratio: 5.19x vs 3.0x target (362.0 ms / 69.8 ms)
- `dom.rows-create-10k` — work-ratio: 50.70x vs 3.0x target (10038.0 ms / 198.0 ms); no-long-frame: 178.9 ms max vs 100.0 ms
- `dom.rows-update-10k` — NativaX failed: operation failed: TimeoutError: script exceeded its execution budget     at wrap (<nativax:dom>:64:11)     at item (<nativax:dom>:350:36)     at get (<nativax:dom>:
- `dom.rows-remove-10k` — work-ratio: 19.02x vs 3.0x target (120.6 ms / 6.3 ms)
- `scroll.rows-10k` — no-long-frame: 143.1 ms max vs 100.0 ms; frame-p95: 119.3 ms p95 vs 16.7 ms
- `dom.rows-create-100` — work-ratio: 4.48x vs 3.0x target (118.8 ms / 26.5 ms)
- `dom.rows-create-250` — work-ratio: 3.67x vs 3.0x target (168.5 ms / 45.9 ms)
- `dom.rows-create-500` — work-ratio: 3.56x vs 3.0x target (234.9 ms / 66.0 ms)
- `dom.rows-create-2k` — work-ratio: 16.49x vs 3.0x target (797.4 ms / 48.4 ms); no-long-frame: 140.0 ms max vs 100.0 ms
- `dom.rows-create-5k` — work-ratio: 17.35x vs 3.0x target (2903.8 ms / 167.4 ms); no-long-frame: 183.9 ms max vs 100.0 ms
- `dom.rows-create-20k` — NativaX failed: operation failed: TimeoutError: script exceeded its execution budget     at hasAttribute (<nativax:dom>:1125:62)     at appendChild (<nativax:dom>:479:48)     at cr
- `dom.rows-create-50k` — NativaX failed: operation failed: TimeoutError: script exceeded its execution budget     at host (<nativax:host>:35:47)     at hasAttribute (<nativax:dom>:1125:62)     at appendChi
- `dom.rows-update-100` — work-ratio: 206.71x vs 3.0x target (99.4 ms / 0.5 ms)
- `dom.rows-update-1k` — work-ratio: 42.18x vs 3.0x target (462.9 ms / 11.0 ms); no-long-frame: 101.4 ms max vs 100.0 ms
- `dom.rows-update-5k` — work-ratio: 555.49x vs 3.0x target (8715.1 ms / 15.7 ms); no-long-frame: 125.0 ms max vs 100.0 ms
- `dom.rows-remove-100` — work-ratio: 51.46x vs 3.0x target (24.3 ms / 0.5 ms)
- `dom.rows-remove-1k` — work-ratio: 43.30x vs 3.0x target (59.0 ms / 1.4 ms)
- `dom.cards-create-1k` — work-ratio: 477.64x vs 3.0x target (238.8 ms / 0.5 ms); no-long-frame: 236.0 ms max vs 100.0 ms
- `dom.cards-create-5k` — work-ratio: 408.99x vs 3.0x target (122.7 ms / 0.3 ms); no-long-frame: 121.1 ms max vs 100.0 ms
- … y 224 escenarios más; ver `results.json`.

## Detalle visual

| Página | Veredicto | Overall | Posición | Layout | Color | Diseño | Píxeles % | Tinta % | ΔE medio | Acción |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `50projects50days/3d-boxes-background` | FAIL | 97.9 | 94.4 | 98.5 | 100.0 | 100.0 | 2.20 | 21.75 | 1.24 | sin acción dominante |
| `50projects50days/animated-countdown` | FAIL | 86.0 | 100.0 | 87.8 | 58.7 | 100.0 | 0.26 | 93.11 | 0.15 | revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado |
| `50projects50days/animated-navigation` | FAIL | 69.7 | 51.7 | 66.2 | 77.9 | 99.3 | 0.68 | 1.10 | 0.17 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/auto-text-effect` | FAIL | 48.8 | 0.8 | 44.0 | 82.9 | 97.7 | 2.04 | 99.25 | 0.29 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; c |
| `50projects50days/background-slider` | FAIL | 72.9 | 80.0 | 84.5 | 35.3 | 98.4 | 50.29 | 99.95 | 6.08 | revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado |
| `50projects50days/blurry-loading` | WARN | 99.1 | 100.0 | 97.6 | 100.0 | 99.0 | 0.00 | 0.00 | 0.00 | sin acción dominante |
| `50projects50days/button-ripple-effect` | FAIL | 98.8 | 100.0 | 100.0 | 100.0 | 91.8 | 0.06 | 3.50 | 0.01 | sin acción dominante |
| `50projects50days/content-placeholder` | FAIL | 74.0 | 56.7 | 79.4 | 72.8 | 100.0 | 5.68 | 35.96 | 0.27 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco |
| `50projects50days/custom-range-slider` | FAIL | 50.5 | 33.1 | 51.6 | 44.5 | 93.0 | 1.39 | 7.18 | 0.89 | corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; r |
| `50projects50days/dad-jokes` | WARN | 99.1 | 99.6 | 99.9 | 96.9 | 100.0 | 3.06 | 6.22 | 0.48 | sin acción dominante |

### Causas raíz por página (peores 10)

#### `50projects50days/auto-text-effect` — FAIL · overall 48.8 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; comprobar contenido fuera de pantalla/recortado
- `html:1>body:1>div:1`: pos Δ 326.3 px; tamaño Δ 9.7 px; ΔE 0.5
- `html:1>body:1>div:1>label:1`: pos Δ 321.3 px; tamaño Δ 4.0 px; ΔE 3.0
- `#speed`: pos Δ 316.6 px; tamaño Δ 6.0 px; ΔE 0.8; estilo: border-top-left-radi 0px→2px, border-top-right-rad 0px→2px, border-bottom-left-r 0px→2px
- `#text`: pos Δ 15.5 px; tamaño Δ 31.2 px; ΔE 2.3
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/auto-text-effect`

#### `50projects50days/custom-range-slider` — FAIL · overall 50.5 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco; revisar color, background, gradientes y filtros
- `#range`: pos Δ 7.0 px; tamaño Δ 14.0 px; ΔE 78.9; estilo: color rgb(157, 150, 142)→rgb(0, 0, 0), background-color rgb(255, 255, 255)→rgba(0, 0, 0, 0), border-top-color rgb(157, 150, 142)→rgb(0, 0, 0)
- `html:1>body:1>h2:1`: pos Δ 278.6 px; tamaño Δ 0.0 px; ΔE 5.8
- `html:1>body:1>div:1`: pos Δ 11.0 px; tamaño Δ 22.0 px; ΔE 9.2
- `html:1>body:1>div:1>label:1`: pos Δ 11.0 px; tamaño Δ 0.0 px; ΔE 2.1
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/custom-range-slider`

#### `50projects50days/animated-navigation` — FAIL · overall 69.7 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco
- `#nav>ul:1>li:3>a:1`: pos Δ 50.0 px; tamaño Δ 1.4 px; ΔE 9.8
- `#nav>ul:1>li:4>a:1`: pos Δ 70.0 px; tamaño Δ 1.4 px; ΔE 4.0
- `#nav>ul:1>li:4`: pos Δ 60.0 px; tamaño Δ 20.0 px; ΔE 1.1
- `#nav>ul:1>li:3`: pos Δ 40.0 px; tamaño Δ 20.0 px; ΔE 3.6
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/animated-navigation`

#### `50projects50days/background-slider` — FAIL · overall 72.9 %

- Acción sugerida: revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado
- `#left`: pos Δ 17.0 px; tamaño Δ 34.0 px; ΔE 7.5; estilo: border-top-left-radi 0px→2px, border-top-right-rad 0px→2px, border-bottom-left-r 0px→2px
- `#right`: pos Δ 17.0 px; tamaño Δ 34.0 px; ΔE 0.7; estilo: border-top-left-radi 0px→2px, border-top-right-rad 0px→2px, border-bottom-left-r 0px→2px
- `html:1>body:1>div:1`: pos Δ 0.0 px; tamaño Δ 0.0 px; ΔE 10.6
- `#left>i:1`: pos Δ — px; tamaño Δ — px; ΔE —; sobrante
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/background-slider`

#### `50projects50days/content-placeholder` — FAIL · overall 74.0 %

- Acción sugerida: corregir posición/containing block/transform; revisar width/height, flex/grid y tamaño intrínseco
- `#title`: pos Δ 16.3 px; tamaño Δ 0.0 px; ΔE 0.6
- `html:1>body:1>div:1`: pos Δ 5.5 px; tamaño Δ 11.0 px; ΔE 0.4
- `html:1>body:1>div:1>div:2`: pos Δ 5.5 px; tamaño Δ 11.0 px; ΔE 0.0
- `#excerpt>span:1`: pos Δ 12.3 px; tamaño Δ 0.0 px; ΔE 0.6
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/content-placeholder`

#### `50projects50days/animated-countdown` — FAIL · overall 86.0 %

- Acción sugerida: revisar color, background, gradientes y filtros; comprobar contenido fuera de pantalla/recortado
- `html:1>body:1>div:1>h4:1`: pos Δ 0.5 px; tamaño Δ 123.3 px; ΔE 12.3
- `html:1>body:1>div:1>div:1>span:2`: pos Δ 0.1 px; tamaño Δ 0.8 px; ΔE 7.9
- `html:1>body:1>div:1>div:1>span:3`: pos Δ 0.1 px; tamaño Δ 0.8 px; ΔE 7.9
- `html:1>body:1>div:1>div:1>span:4`: pos Δ 0.1 px; tamaño Δ 0.8 px; ΔE 7.9
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/animated-countdown`

#### `50projects50days/3d-boxes-background` — FAIL · overall 97.9 %

- Acción sugerida: sin acción dominante
- `#btn`: pos Δ 343.0 px; tamaño Δ 0.0 px; ΔE 0.0
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/3d-boxes-background`

#### `50projects50days/button-ripple-effect` — FAIL · overall 98.8 %

- Acción sugerida: sin acción dominante
- Sin detalle de elementos; revisar artefactos.
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/button-ripple-effect`

#### `50projects50days/dad-jokes` — WARN · overall 99.1 %

- Acción sugerida: sin acción dominante
- `#jokeBtn`: pos Δ 2.2 px; tamaño Δ 0.0 px; ΔE 1.3
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/dad-jokes`

#### `50projects50days/blurry-loading` — WARN · overall 99.1 %

- Acción sugerida: sin acción dominante
- Sin detalle de elementos; revisar artefactos.
- Artefactos: `/home/k3vin/Documents/nativax/.visual/runs/50projects50days/pages/50projects50days/blurry-loading`

## Detalle de juegos

| Tipo | Escenario | Resolución | Carga | Veredicto | NativaX ms | Chromium ms | Ratio | p95 ms | RSS arnés MB | Acción |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|---|
| 2D | `game.quality-1280x720-p100` | 1280x720 | 100 | WARN | 40.5 | 3.1 | 13.07× | 10.3 | 710 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p1000` | 1280x720 | 1000 | WARN | 144.7 | 9.4 | 15.39× | 9.9 | 723 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p2500` | 1280x720 | 2500 | WARN | 295.8 | 9.6 | 30.82× | 11.5 | 724 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p500` | 1280x720 | 500 | WARN | 104.1 | 4.2 | 24.79× | 10.1 | 728 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1280x720-p5000` | 1280x720 | 5000 | WARN | 414.7 | 35.9 | 11.55× | 10.1 | 740 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p100` | 1920x1080 | 100 | WARN | 51.7 | 14.0 | 3.69× | 11.8 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p1000` | 1920x1080 | 1000 | WARN | 145.1 | 6.5 | 22.32× | 12.3 | 717 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p2500` | 1920x1080 | 2500 | WARN | 266.7 | 31.0 | 8.60× | 14.4 | 727 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p500` | 1920x1080 | 500 | WARN | 141.2 | 5.4 | 26.14× | 16.9 | 721 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-1920x1080-p5000` | 1920x1080 | 5000 | WARN | 354.3 | 33.0 | 10.74× | 11.6 | 741 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p100` | 2560x1440 | 100 | WARN | 51.3 | 14.2 | 3.61× | 9.7 | 726 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p1000` | 2560x1440 | 1000 | WARN | 174.2 | 5.1 | 34.16× | 10.2 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p2500` | 2560x1440 | 2500 | WARN | 282.6 | 9.0 | 31.40× | 14.5 | 726 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p500` | 2560x1440 | 500 | WARN | 100.4 | 16.0 | 6.28× | 10.6 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-2560x1440-p5000` | 2560x1440 | 5000 | WARN | 368.1 | 10.8 | 34.08× | 9.5 | 742 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p100` | 640x360 | 100 | WARN | 44.9 | 1.7 | 26.41× | 10.4 | 713 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p1000` | 640x360 | 1000 | WARN | 140.8 | 3.3 | 42.65× | 9.2 | 714 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p2500` | 640x360 | 2500 | WARN | 292.6 | 4.8 | 60.97× | 13.9 | 721 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p500` | 640x360 | 500 | WARN | 85.6 | 2.2 | 38.92× | 9.9 | 740 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-640x360-p5000` | 640x360 | 5000 | WARN | 380.6 | 7.2 | 52.86× | 12.0 | 742 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p100` | 854x480 | 100 | WARN | 39.1 | 1.5 | 26.09× | 9.6 | 717 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p1000` | 854x480 | 1000 | WARN | 177.4 | 4.1 | 43.27× | 12.4 | 729 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p2500` | 854x480 | 2500 | WARN | 256.4 | 7.6 | 33.74× | 12.7 | 714 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p500` | 854x480 | 500 | WARN | 92.2 | 2.4 | 38.43× | 9.4 | 716 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 2D | `game.quality-854x480-p5000` | 854x480 | 5000 | WARN | 353.4 | 32.2 | 10.98× | 9.7 | 746 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c100` | 1280x720 | 100 | WARN | 26.8 | 0.2 | 134.08× | 12.6 | 754 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c1000` | 1280x720 | 1000 | WARN | 29.5 | 0.1 | 295.12× | 9.7 | 750 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c2500` | 1280x720 | 2500 | WARN | 32.1 | 1.2 | 26.76× | 10.4 | 748 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c500` | 1280x720 | 500 | WARN | 28.6 | 0.1 | 286.26× | 9.9 | 736 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1280x720-c5000` | 1280x720 | 5000 | WARN | 34.7 | 0.4 | 86.65× | 10.6 | 764 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c100` | 1920x1080 | 100 | WARN | 36.9 | 0.3 | 123.01× | 12.1 | 753 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c1000` | 1920x1080 | 1000 | WARN | 73.9 | 0.3 | 246.37× | 12.0 | 755 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c2500` | 1920x1080 | 2500 | WARN | 56.8 | 0.3 | 189.27× | 13.4 | 752 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c500` | 1920x1080 | 500 | WARN | 47.4 | 0.2 | 236.96× | 11.9 | 756 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-1920x1080-c5000` | 1920x1080 | 5000 | WARN | 87.6 | 0.5 | 175.28× | 19.3 | 751 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c100` | 2560x1440 | 100 | WARN | 60.0 | 0.4 | 150.03× | 16.1 | 751 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c1000` | 2560x1440 | 1000 | WARN | 86.1 | 0.3 | 286.93× | 18.3 | 778 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c2500` | 2560x1440 | 2500 | WARN | 96.0 | 0.1 | 959.64× | 23.7 | 759 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c500` | 2560x1440 | 500 | WARN | 98.0 | 0.2 | 490.07× | 17.3 | 783 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-2560x1440-c5000` | 2560x1440 | 5000 | WARN | 82.9 | 0.2 | 414.69× | 15.6 | 757 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c100` | 640x360 | 100 | FAIL | 582.2 | 0.3 | 1940.59× | 123.4 | 755 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c1000` | 640x360 | 1000 | PASS | 21.0 | 0.0 | — | 9.7 | 743 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c2500` | 640x360 | 2500 | WARN | 52.2 | 0.5 | 104.31× | 8.7 | 749 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c500` | 640x360 | 500 | WARN | 25.4 | 0.2 | 127.16× | 12.6 | 758 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-640x360-c5000` | 640x360 | 5000 | WARN | 23.1 | 0.3 | 76.99× | 10.0 | 748 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c100` | 854x480 | 100 | WARN | 18.2 | 0.1 | 182.20× | 8.8 | 754 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c1000` | 854x480 | 1000 | WARN | 21.8 | 0.1 | 217.65× | 9.3 | 758 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c2500` | 854x480 | 2500 | WARN | 25.9 | 0.2 | 129.33× | 8.9 | 748 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c500` | 854x480 | 500 | WARN | 32.4 | 0.3 | 108.03× | 8.6 | 753 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |
| 3D | `game3d.quality-854x480-c5000` | 854x480 | 5000 | WARN | 23.8 | 0.4 | 59.41× | 9.4 | 744 | Bajar partículas/cubos, draw calls o DPR interno; medir cada calidad por separado. |

## Detalle de vídeo

- Reproducción real: **no**.
- Decoder: —.
- Contrato: —.
- Última corrida: — (—).

## Cobertura pendiente

| Suite | Pendientes | Primeras páginas |
|---|---:|---|
| 50projects50days | 41 | 50projects50days/double-click-heart, 50projects50days/double-vertical-slider, 50projects50days/drag-n-drop, 50projects50days/drawing-app, 50 |
| mdn-css-examples | 27 | mdn-css-examples/alt-style-sheets, mdn-css-examples/animation-frames-timing-function, mdn-css-examples/backdrop, mdn-css-examples/counter-st |
| mdn-dom-examples | 134 | mdn-dom-examples/abort-api, mdn-dom-examples/audiocontext-setsinkid, mdn-dom-examples/auxclick, mdn-dom-examples/canvas/chroma-keying, mdn-d |
| mdn-learning-area | 67 | mdn-learning-area/accessibility/aria, mdn-learning-area/accessibility/assessment-finished, mdn-learning-area/accessibility/assessment-start, |
| odin-css-exercises | 21 | odin-css-exercises/advanced-html-css/animation/01-button-hover, odin-css-exercises/advanced-html-css/animation/02-pop-up, odin-css-exercises |

Total pendiente: **290** páginas. Lista completa en `.visual/catalog.json`.

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

- Visual: 10/300 páginas; referencia Google Chrome 152.0.7977.82.
- Rendimiento: 270/270 escenarios; referencia Google Chrome 152.0.7977.82.
- App idle: 134.1 MB · 0.00 % CPU.
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
python3 debug/engines/recommendations/recommend.py --out progress/reports/recommendations-latest.md
```
