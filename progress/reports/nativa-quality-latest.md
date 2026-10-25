# NativaX — informe de capacidad y evidencia

Fecha: 2026-10-24. Este documento consolida las dos herramientas nuevas:
`tools/visual` (fidelidad visual) y `tools/perf` (rendimiento, memoria y
respuesta). Todo se mide **sin WebView, sin Chromium embebido, sin CEF y sin
Electron**. Chromium solo se usa como referencia externa headless.

NativaX sigue siendo el runtime propio: HTML → DOM → CSS → `nativa_render` →
widgets Flutter, y JavaScript sobre QuickJS-ng.

---

## 1. Resumen ejecutivo

| Área | Resultado |
|---|---|
| Fidelidad visual, 51 páginas de 50projects50days | **6 PASS, 5 WARN, 40 FAIL, 0 INVALID**; overall medio 52,59 % |
| Rendimiento, 245 definidos (17 medidos) | **4–5 PASS, 2–4 WARN, 9–10 FAIL, 0 INVALID** (última pasada 5/2/10) |
| App Flutter Linux en reposo (blanco) | **105 MB RSS, 0,00 % CPU** → cumple 250 MB / 1 % |
| GPU | No expuesta por el kernel en esta máquina (`not exposed`) |
| JS puro (arrays/objetos/strings) | A la altura o por delante de Chromium (0,4×–2,9×) |
| Coste dominante | **DOM/layout/scroll**, no el motor JS |
| Autocalibración del juicio visual | Chromium vs Chromium = **100 % / PASS** |
| Tests | **14 perf + 119 visual + 78 CSS + 4 security + 10 leaks + 25 vídeo + 9 recomendaciones + 3 manifiesto de vídeo** en verde; el `test_all` completo mantiene un flake ajeno en `wasm_rapier_test` |

Respuesta corta a “¿rinde como debe?”: **en reposo y en CPU pura sí; en creación
de filas, actualización masiva y scroll largo todavía no**.

---

## 2. Qué puede hacer el sistema

### 2.1 Juicio visual headless (`tools/visual`)

Compara la misma página renderizada por Chromium headless y por NativaX
offscreen (`flutter test` + `RenderRepaintBoundary`) y emite un veredicto por
página:

- **Posición**: cajas de cada elemento con `getBoundingClientRect` en ambos
  motores; tolerancia 2 px con caída hasta 16 px.
- **Layout**: ancho/alto, IoU y altura del documento.
- **Color**: ΔE76 de media y paleta dominante por elemento (top 5 colores),
  midiendo la caja propia de cada motor para no confundir color con
  desplazamiento.
- **Diseño**: 27 propiedades computadas normalizadas (tipografía, colores,
  bordes, radios, sombra, display, posición, opacidad, overflow).
- **Entorno**: viewport, DPR, tamaño de captura, cobertura del documento,
  errores JS, recursos externos bloqueados.
- **Píxeles**: ΔE por píxel, cubos 2/5/10/20, filas, teselas 16×16,
  `ink_mismatch_pct` (tinta no coincidente), `diff.png` y CSV píxel a píxel
  opcional.

Salidas por página: `chrome.png`, `nativax.png`, `diff.png`, sondas JSON,
`elements.json`/`.csv`, `positions.csv`, `colors.csv`, `pixels.json` y
`pixels.csv` con `--pixel-csv`. Tabla global en `results.json` y
`summary.csv`.

Fixtures vendorizados: **51 páginas** de `bradtraversy/50projects50days`
(commit `c92b0bc3…`, MIT), más `examples/test-pages`.

```bash
dart run tools/visual/bin/visual_check.dart --suite 50projects50days
dart run tools/visual/bin/visual_check.dart --self-check --limit 1
dart run tools/visual/bin/visual_check.dart examples/test-pages/form.html
```

### 2.2 Suite de rendimiento (`tools/perf`)

Compara Chromium (vía CDP) contra NativaX offscreen y mide:

- Tiempo de escenario, tiempo de render/frame, nodos, heap (Chromium),
  layout/style (Chromium), RSS/CPU del árbol de procesos y GPU si existe.
- **App Linux real en reposo** con una página blanca (`idle-app`), que es la
  medida válida para el objetivo de 250 MB / 1 % CPU.
- Objetivos: frame p95 ≤ 16,7 ms, frame máximo ≤ 100 ms, trabajo ≤ 3×,
  nodos ±5 %, idle ≤ 250 MB / 1 %.
- Salidas: `results.json`, `results.csv`, `report.md`, `timeline.csv`,
  `app-idle.json`, `charts/*.svg`.

Escenarios internos: crear/actualizar/eliminar 1k y 10k filas, scroll de 10k,
scroll 2D de 900 teselas y cuatro cargas JS. Benchmarks externos integrados:
js-framework-benchmark vanilla keyed, Browser-Bench y Cerious-Scroll. uibench
se descarga aparte; million-rows queda como build npm opcional; PassMark 2D
HTML Scroll se reproduce con una escena equivalente porque su página no es
redistribuible.

```bash
dart run tools/perf/bin/perf.dart run --app-idle --out .perf/latest
dart run tools/perf/bin/perf.dart idle-app --seconds 5 --build
dart run tools/perf/bin/perf.dart fetch --source uibench
```

### 2.3 Panel Tkinter (`tools/perf/gui/perf_gui.py`)

Ventana de escritorio con barra lateral y el mismo lenguaje visual del
informe HTML:

- **Resumen**: fidelidad media, donuts de veredictos visuales y de rendimiento,
  estadísticas de píxeles/tinta, peores páginas y peores escenarios.
- **Rendimiento**: tabla de los **100** escenarios (pendientes incluidos),
  detalle por operación, barras de trabajo con escala logarítmica, RSS en el
  tiempo y motivos del veredicto.
- **Fidelidad visual**: 300 páginas (51 medidas y el resto pendientes), barras
  por categoría, gráficas de píxeles y color, peores causas de
  posición/color/diseño y miniaturas de Chromium, NativaX y la diferencia.
- **Conformidad**: Test262, html5lib, URL, WPT DOM/CSS/tree con botones para
  ejecutar cada suite y tabla PASS/FAIL/SKIP/ERROR.
- **Vídeo**: 25 perfiles, contrato sin playback real.
- **Videojuegos**: 25 perfiles Canvas 2D y 25 WebGL 3D.
- **Idle**: RSS/CPU reales frente a 250 MB / 1 %, más la línea temporal.
- **Informes**: **En vivo** por defecto, recalculado desde los JSON actuales
  y mostrado como captura del HTML real; durante una ejecución se actualiza
  como texto y al terminar se regenera la captura. Los históricos quedan como
  snapshots manuales.
- **Acciones por fila**: clic derecho o botón **Acciones ▾** para ver detalles
  o ejecutar un solo escenario/página; el resultado se fusiona en la tabla y
  se abre el detalle.
- **Informe con recomendaciones**: `tools/recommend.py` convierte los datos
  medidos en prioridades P0/P1/P2 con evidencia, acción, criterio de aceptación
  y comando; está en **Informes → Recomendaciones** y en **En vivo**;
  `quality_report.sh` lo regenera al final.
- Barra de acciones para ejecutar todo, solo visual, solo rendimiento, idle
  real, refrescar o detener; el registro se muestra en la ventana.
- La tabla, las tarjetas, los contadores y las gráficas se refrescan solos
  cada segundo cuando cambian `results.json`, `app-idle.json`, la matriz
  Docker o el catálogo. El estado muestra `n/total · ejecutando…`; también se
  actualiza si la ejecución se lanzó fuera del panel.


```bash
python3 tools/perf/gui/perf_gui.py
```

### 2.4 Todo junto

```bash
tools/quality_report.sh          # juicio visual + rendimiento + idle real
tools/quality_report.sh --gui    # lo anterior y abre el panel Tkinter
```

### 2.5 Comparación y regresión

- `tools/perf compare <baseline.json> <current.json>` compara el trabajo de
  cada escenario y marca `regression`/`improvement`/`noise`.
- El juicio visual deja `results.json` y `summary.csv` para comparar páginas y
  categorías.
- `--self-check` demuestra que el juez visual no está roto (Chromium contra
  Chromium = 100 %).
- `NATIVA_PERF_E2E=1 dart test test/cdp_e2e_test.dart` verifica el cliente CDP.

---

## 3. Resultados medidos

### 3.1 Fidelidad visual (51 páginas, 800×900)

| Métrica | Valor |
|---|---|
| Veredictos | 6 PASS · 5 WARN · 40 FAIL · 0 INVALID |
| Overall medio / mediana | 52,59 % / 48,54 % |
| Posición media | 36,20 % |
| Layout medio | 53,04 % |
| Color medio | 45,24 % |
| Diseño medio (estilos) | 96,72 % |
| Píxeles comparados | 36.720.000 |
| Píxeles con ΔE > 2 | 6.569.980 (17,89 % medio) |
| Tinta no coincidente media | 62,82 % |

Casos reales detectados: `animated-countdown` deja el contenido `fixed` +
`translate(-50%,-50%)` fuera de pantalla; `background-slider` desplaza el
contenedor centrado 120 px; `event-keycodes` conserva la geometría pero difiere
el 99,21 % de la tinta visible.

Detalle: `progress/reports/visual-50projects50days-latest.md`.

Recomendaciones automáticas: `progress/reports/recommendations-latest.md`.

### 3.2 Rendimiento (245 definidos, 17 medidos)

| Escenario | Veredicto | NativaX | Chromium | Nodos |
|---|---|---:|---:|---:|
| `dom.rows-create-1k` | WARN/FAIL | 356–512 ms | 31–76 ms | 1008/1008 |
| `dom.rows-create-10k` | FAIL | 6,6–8,2 s o timeout JS | 245 ms | 10008/10008 |
| `dom.rows-update-10k` | FAIL | presupuesto JS agotado | 35 ms | 10008/10008 |
| `dom.rows-remove-10k` | WARN | 139 ms | 6 ms | 8/8 |
| `scroll.rows-10k` | FAIL | p95 206 ms, máx 231 ms | — | 10008/10008 |
| `scroll.2d-tiles` | PASS | p95 8,4 ms, máx 65 ms | — | 908/908 |
| `js.arrays` | PASS | 102 ms | 40 ms | 8/8 |
| `js.objects` | PASS | 40 ms | 14 ms | 8/8 |
| `js.strings` | PASS | 22 ms | 14 ms | 8/8 |
| `js.json` | WARN | 169 ms | 29 ms | 8/8 |
| `external.jsfb-create-1k` | FAIL | 2.848 ms, frame 191 ms | 135 ms | 8031/8031 |
| `external.jsfb-create-10k` | FAIL | timeout | 1.327 ms | 30/80031 |
| `external.browserbench-quick` | FAIL | timeout 30 s | ~11 s, ~31.000 pts | 0/16.717 |
| `external.cerious-load-scroll` | FAIL | 416 nodos | 721 nodos | 416/721 |
| `external.uibench-load-scroll` | FAIL | 13 nodos | 153 nodos | 13/153 |

Rango de tres pasadas completas. Los veredictos de DOM/scroll se mantienen;
los ms absolutos varían.

### 3.3 Idle real de la app

| Métrica | Valor | Objetivo |
|---|---:|---:|
| RSS en reposo | **105,0 MB** | ≤ 250 MB ✅ |
| CPU en reposo | **0,00 %** | ≤ 1 % ✅ |
| RSS pico en la medición | 106,5 MB | — |
| CPU pico en la medición | 25,45 % | — |
| GPU | no expuesta | — |

El `idle.blank` del arnés (`flutter test`) se reporta aparte y no decide este
objetivo, porque incluye el test runner.

Detalle: `progress/reports/perf-latest.md`.

---

## 3.4 Catálogo visual de 300 páginas

`--all` ejecuta **300 páginas** con commit pinneado:

| Suite | Páginas | Licencia |
|---|---:|---|
| 50projects50days | 51 | MIT (vendorizado) |
| mdn-css-examples | 27 | CC0-1.0 |
| mdn-learning-area | 67 | CC0-1.0 |
| odin-css-exercises | 21 | MIT |
| mdn-dom-examples | 134 | CC0-1.0 |

Se ejecutó una muestra de 4 páginas nuevas para validar el pipeline (todas
FAIL, entre 39,7 % y 65,6 %); **la tasa completa de las 300 está pendiente**.
La línea base de 51 páginas de la sección 3.1 sigue siendo la medición
completa. Detalle: `progress/reports/visual-catalog-latest.md`.

## 3.5 Compatibilidad con suites oficiales

Últimas corridas disponibles en `.conformance/results/` (la compuerta puede
refrescarlas con `--compat fast` o `--compat full`):

| Suite | Tasa | PASS/FAIL/SKIP/ERROR | Fecha | Comando |
|---|---:|---:|---|---|
| Test262 | 97,93 % | 19577 / 413 / 1108 / 0 | 2026-10-23 | `run_test262` |
| html5lib tokenizer | 99,26 % | 5759 / 43 / 1025 / 0 | 2026-10-23 | `run_html5lib` |
| WPT URL | 74,22 % | 665 / 231 / 0 / 0 | 2026-10-23 | `run_url` |
| WPT tree construction | 71,18 % | 1334 / 537 / 99 / 3 | 2026-10-24 | `run_html_tree` |
| WPT DOM (dom/nodes) | 70,00 % | 196 / 84 / 47 / 0 (límite 2000) | 2026-10-24 | `run_wpt --dirs dom/nodes --limit 2000` |

No es una tasa de compatibilidad completa del navegador; es el estado medido de
NativaX contra las suites oficiales que puede ejecutar su adaptador.

## 3.6 Compuerta sin UI para la IA

```bash
# Reutiliza artefactos existentes y compara contra la base
python3 tools/quality_gate.py

# Corre todo (visual + rendimiento + compatibilidad rápida)
python3 tools/quality_gate.py --run

# JSON limpio para parsear
python3 tools/quality_gate.py --json

# Guardar una nueva base
python3 tools/quality_gate.py --run --save-baseline
```

Códigos de salida: `0` = igual/mejor o base creada, `2` = regresión,
`3` = faltan mediciones. Escribe `progress/reports/quality-gate-latest.json` y
`.md`.

## 3.7 Vista previa del informe (no código)

```bash
tools/preview_report.sh                 # informe consolidado
tools/preview_report.sh progress/reports/perf-latest.md
```

Abre HTML renderizado en el navegador por defecto. También existe el panel
Tkinter (`tools/perf/gui/run_gui.sh`).

## 3.8 Aislamiento con contenedores (CPU/RAM)

```bash
tools/perf/container/matrix.sh
tools/perf/container/run.sh --cpus 1 --memory 1g --name low --only 'js.arrays'
```

Chromium y `flutter test` corren **dentro del mismo contenedor**, con
`--network none`, `--cpus` y `--memory` de Docker. En el panel, la sección
**Contenedores** tiene controles para elegir CPU (0,25–4), RAM (512 MB–4 GB),
nombre y qué tests ejecutar, además del botón de matriz fija. La imagen
`nativa-perf:local` se construye una vez (Debian trixie + Chromium + build
tools); Flutter y el repositorio se montan en sus rutas reales.

| Configuración | `dom.rows-create-1k` | `scroll.2d-tiles` | `js.arrays` |
|---|---|---|---|
| 2 CPU · 2 GB | 395 ms, FAIL | 139 ms, PASS (p95 7,8 ms) | 91 ms, PASS |
| 1 CPU · 1 GB | 714 ms, FAIL | 221 ms, FAIL (p95 31,2 ms) | 107 ms, PASS |
| 0.5 CPU · 768 MB | 3.292 ms, FAIL | 999 ms, FAIL (p95 167,9 ms) | 680 ms, PASS |

Bajo 1 CPU el scroll 2D deja de cumplir el presupuesto de 16,7 ms; con 0,5 CPU
también se degrada `js.arrays` (74,9 ms de p95). El idle real (105 MB / 0 % CPU)
se mide aparte en la app Linux, no en este arnés.

**Límite:** son cuotas cgroup de CPU, no cambios reales de frecuencia. No hay
estresores concurrentes, soak tests largos ni comparación visual bajo carga.

## 4. Cómo se mide (y qué significa)

- **Chromium**: headless con CDP; viewport exacto; red bloqueada; animaciones
  congeladas. Métricas de layout/style/heap del propio navegador.
- **NativaX**: offscreen con `flutter test`; `tester.pump()` mide coste de
  frame (build/layout/paint en CPU). No es rasterización GPU ni FPS de pantalla.
- **Visual**: capturas del mismo viewport y fuentes del sistema; el desfase de
  ventana de Chromium se calibra para que medición y captura compartan layout.
- **Idle app**: proceso Flutter Linux real con `NATIVAX_PERF_PAGE` apuntando a
  una página blanca; PSS/CPU vía `/proc`; 3 s de calentamiento + 5 s de reposo.
- **Comparaciones**: en scroll, el cociente de trabajo es informativo (el
  compositor de Chromium puede tardar <1 ms); mandan p95 y frame máximo.

---

## 5. Mapa de archivos

```
tools/visual/                 juez visual (Dart, fixtures 50projects50days)
tools/perf/                   suite de rendimiento (Dart + CDP)
tools/perf/gui/perf_gui.py    panel Tkinter
tools/perf/fixtures/          js-framework-benchmark, Browser-Bench, Cerious
docs/visual-fidelity.md       contrato visual en español
docs/performance-suite.md     contrato de rendimiento en español
progress/reports/visual-50projects50days-latest.md
progress/reports/perf-latest.md
.visual/latest/               salidas visuales (ignorado por git)
.perf/latest/                 salidas de rendimiento (ignorado por git)
```

---

## 6. Verificación

- `tools/visual`: **66 tests** en verde (1 skip e2e), analyze limpio.
- `tools/perf`: **12 tests** en verde (1 skip e2e), analyze limpio.
- `examples/web-challenge`: `flutter analyze` limpio; tests en verde.
- En esta pasada: **14 perf + 119 visual + 78 CSS + 4 security + 10 leaks + 25 vídeo + 9 recomendaciones + 3 manifiesto de vídeo** en verde. El `test_all` completo mantiene un flake ajeno en `wasm_rapier_test`.
- `./tools/test_all.sh` no terminó en 0 en dos intentos por el test flaky
  `wasm_rapier_test` de `packages/nativax`; ese paquete solo pasa **30/30** y
  el resto de secciones se verificó por separado con éxito.
- Calibración: `--self-check` visual = 100 % / PASS; test CDP e2e = PASS.

---

## 7. Lo que todavía NO puede hacer

- **Aislamiento por contenedor**: sí, con cuotas de CPU y RAM de Docker. No
  hay estresores de CPU concurrentes, soak tests largos ni concurrencia, y la
  comparación visual sigue haciéndose en reposo con animaciones congeladas.
- **GPU/FPS reales**: mide trabajo de frame en CPU y RSS/CPU; la GPU no está
  expuesta en esta máquina. No hay FPS de pantalla ni rasterización GPU.
- **Vídeo, audio, canvas animado, WebGL**: no se juzgan.
- **Red real**: se bloquea en ambos motores para que la comparación sea
  reproducible.
- **PassMark 2D HTML Scroll**: propietario; se usa una escena equivalente.
- **million-rows**: necesita build npm y no tiene licencia upstream; queda como
  integración opcional, no en la línea base.
- Una sola pasada tiene varianza; para decisiones hay que repetir y usar los
  cocientes. No se presenta como FPS.
- `INVALID` no es compatibilidad; significa que la medición no es fiable.

---

## 8. Siguiente paso recomendado

1. **Crear/actualizar filas**: reducir el coste de DOM y de invalidación de
   estilo. Es el mayor multiplicador (1k ya es 4,4×; 10k, 33× o timeout).
2. **Virtualización y scroll**: bajar p95 de 108–206 ms a ≤16,7 ms en listas
   de 10k; el caso 2D ya demuestra que el pipeline puede ir a 6,8–8,4 ms.
3. **Presupuesto JS por operación**: permitir actualizar/limpiar 10k sin
   agotar QuickJS en una sola llamada.
4. Repetir ambos suites y comparar contra esta línea base antes de declarar
   cualquier mejora.
