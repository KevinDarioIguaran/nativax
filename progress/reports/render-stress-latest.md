# Render stress — virtualización de listas y contenido largo

Fecha: 2026-10-23. Rama: `main`.
Build: Flutter Linux **profile/AOT**. Máquina: Linux x86_64, 12 CPUs.
Comandos y logs crudos: `/tmp/nativa-bench/final3_*.log`,
`/tmp/nativa-bench/bible_final.log` y
`examples/render-benchmark` (benchmark de perfil).

## Qué se implementó

- `CssVirtualBlock`: ventana viewport + overscan, altura estimada y corregida
  al entrar en vista, scroll anchoring, dos placeholders constantes (antes y
  después de la ventana) y pool acotado por ventana.
- Activación automática para contenedores block, flex column y grid por filas
  con muchos hijos; opt-out con `data-nativa-virtual="off"`.
- Scroll anidado (`overflow-y: auto|scroll`) con controller y viewport propios;
  si el contenedor no desborda, usa el scroll del documento.
- `StyleEngine.lazySubtrees`: los nodos virtualizados fuera de vista no tienen
  estilo computado; se calcula al materializarse. Las mutaciones fuera de vista
  invalidan la caché sin computar (`invalidateDeferred`).
- Reutilización del layout real en flex column: evita la pasada dry duplicada
  por cada hijo.
- `#hash`, `scrollIntoView`, `focus()`, `boxOf`/`getBoundingClientRect` y
  `offsetTop` materializan el nodo antes de devolver geometría real.
- Herramientas de perfil (`--dart-define=NATIVAX_RENDER_PROFILE=true`) y
  fixtures generados (`tools/benchmark/bin/generate_render_fixtures.dart`).

## Resultados (mismo fixture y comando)

| Caso | Antes | Ahora | RenderObjects |
|---|---:|---:|---:|
| list-overflow 10k, primer frame | 4.037 ms | **420 ms** | 30.095 → **120** |
| flex-grid 10k, primer frame | 3.672 ms | **630 ms** (447 ms parseo/JS + 183 ms render) | 55.072 → **517** |
| article 2k, updateAll | 129 ms | **33 ms** por frame | 6.069 → **133** |
| Biblia app real, primer contenido | ~3,4 s reportado | **1,82–2,09 s** | 811 en fixture |
| Biblia app real, frames siguientes | 3–15 s | **2,6–6,3 s** | — |

Comandos:

```bash
cd examples/render-benchmark && flutter build linux --profile
cd build/linux/x64/profile/bundle
DISPLAY=:1 NATIVAX_BENCH_FILE=/tmp/nativa-bench/list_10k.html \
  NATIVAX_SCENARIO=load ./render_benchmark
DISPLAY=:1 NATIVAX_BENCH_FILE=/tmp/nativa-bench/flex_10k.html \
  NATIVAX_SCENARIO=load ./render_benchmark
DISPLAY=:1 NATIVAX_BENCH_FILE=/tmp/nativa-bench/article_2k.html \
  NATIVAX_SCENARIO=updateall NATIVAX_TARGET='#doc' ./render_benchmark
```

## Metas

| Meta | Resultado |
|---|---|
| list 10k < 500 ms | ✅ 420 ms |
| flex 10k < 500 ms | ⚠️ 183 ms de render; 630 ms contando parseo/JS y arranque |
| article 2k updateAll sin regresión | ✅ 33 ms |
| Biblia < 500 ms sin frames > 50 ms | ❌ primer contenido 1,82–2,09 s; frames de 2,6–6,3 s |

## Bloqueo exacto de la Biblia

Con el CSS real, la página mide ~795 px de alto: casi todos los ~800
RenderObjects están visibles a la vez. La virtualización no puede eliminar
contenido visible. El perfil de layout muestra:

```
box.dry       self=41.9ms  total=85.2ms
flex.layout   total=405.5ms
block.layout  total=203.0ms
text.intrinsic self=59.6ms
```

Medido en la app real: `RUNTIME_READY 1092ms` (HTML+CSS+JS) y después
`BIBLE_FRAME build=1730ms` (layout/paint), no JS. En una corrida larga apareció
`InternalError: out of memory` de QuickJS; es un problema de estabilidad/memoria
separado que queda abierto.

Para llegar a <500 ms hay que optimizar layout/CSS (pasadas dry/intrinsic,
matching de selectores), no la virtualización. Es un trabajo distinto al que se
autorizó inicialmente.

## Tests

```bash
./tools/test_all.sh        # exit 0
(cd packages/nativa_css && dart analyze)
(cd packages/nativa_render && flutter analyze)
(cd packages/nativa_render && flutter test test/virtualization_test.dart)
```

`virtualization_test.dart` cubre: RenderObjects constantes con N, scroll rápido
y al final, scroll anchoring, `#hash`/`scrollIntoView`, focus, mutación fuera de
vista, inserción/borrado en medio, resize y presupuesto de 20k filas.

## Layout + CSS — 2026-10-24

Objetivo autorizado: optimizar layout y CSS con un fixture sintético genérico;
la Biblia solo valida, no guía el código.

### Fixture sintético

`tools/benchmark/bin/generate_tailwind_fixture.dart 800` genera:
- **801 cajas**, viewport lleno, flex anidado, grid de tarjetas, texto largo,
  bordes y sombras.
- **~4.300 reglas** (3.000 utilidades sintéticas + 600 iconos + app), no
  basadas en ninguna app real.
- JSON de perfil: `debug/benchmarks/baselines/render-tailwind-baseline.json` y
  `render-tailwind-current.json`.

Comando:

```bash
flutter build linux --profile
NATIVAX_LAYOUT_PROFILE=1 \
NATIVAX_BENCH_FILE=/tmp/nativa-bench/tailwind_800.html \
NATIVAX_SCENARIO=load NATIVAX_FRAMES_MS=300 \
NATIVAX_JSON=/tmp/tailwind.json \
  ./render_benchmark
```

| Fase / métrica | Baseline | Ahora |
|---|---:|---:|
| Primer frame | 1.089 ms | **876–904 ms** |
| `create` (parse + JS) | 186 ms | 171–177 ms |
| Style: `computeCount` | 732 | 628–732 |
| Style: selectores evaluados | 34.015 | **29.472** |
| Selectores/elemento | ~42,5 | ~36,8 |
| `renderObjects` | 1.375 | 1.121–1.273 |
| `widgets` | 2.579 | 2.232–2.384 |
| `box.layout` calls / total | 815 / 654 ms | 717 / 581 ms |
| `flex.layout` calls / total | 432 / 473 ms | 370 / 415 ms |
| `text.intrinsic` calls / total | 1.814 / 53 ms | 1.502 / 44 ms |
| `paint` (box+flex+text) | ~110 ms | ~105 ms |

Metas del paso 1/2/3:
- Fixture sintético <500 ms: **no cumplida** (876–904 ms).
- Selectores/elemento >10× menos en el fixture: **no cumplida** en este
  fixture (34.015 → 29.472, 1,15×). En el fixture `flex-grid` (clases
  repetidas) sí se midió **3.176 → 60 selectores**, 52×, por la caché de
  declaraciones/estilo.
- `<= 2` pasadas de layout por RenderObject en el primer frame: no se cumple;
  `box.layout` 717 para 279 `RenderCssBox` (~2,6), `flex.layout` 370 para 112
  `RenderCssFlex` (~3,3).
- Mutaciones: `invalidateDeferred` evita estilos de nodos fuera de vista;
  article updateAll 2.017 → 39 estilos.

### Qué domina ahora

El primer frame sintético sigue dominado por **layout** (`box.layout` 581 ms,
`flex.layout` 415 ms inclusive), no por CSS matching (los selectores son ~36
por elemento) ni por paint (~105 ms). El intento de cachear intrínsecos en
`RenderCssBox` no movió la métrica y se revirtió. El siguiente paso real es
cachear `LayoutResult` por `(constraints, estilo)` y reducir los límites de
relayout; también corregir el ancho disponible del grid virtual (el estimador
por ancestros bajó el primer frame de 1.055 a 897 ms, pero aún no es exacto).

### Regresiones estabilizadas

- Estilo perezoso: se invalidan descendientes al cambiar una clase de un
  ancestro aunque el estilo del ancestro no cambie. Test:
  `lazy style invalidates descendants when an ancestor class changes`.
- `position: fixed`: el walk encuentra elementos fijos después de >50
  hermanos. Test: `fixed elements after many siblings are still found`.
- Fuga de estilos: al salir de la ventana virtual se descarta
  `ComputedStyle`; test de 120 ciclos de scroll/mutación con
  `cachedStyleCount < 300` y RSS acotado.
- OOM de QuickJS: no se reprodujo en una corrida de 10 s tras la evicción;
  queda pendiente una corrida larga con heap del motor.

### Validación Biblia (app real, copia sin tocar la original)

| Métrica | Valor |
|---|---:|
| `RUNTIME_READY` (HTML+CSS+JS) | 926–1.092 ms |
| Primer contenido | **1.842 ms** (`build=1.749`) |
| Siguiente frame | **2.793 ms** (`build=2.565`) |
| Frames posteriores | 593 ms, 224 ms |

No cumple <500 ms. El cuello es layout/paint de ~800 RenderObjects visibles
con el CSS real; no es JS ni la virtualización. Con el CSS real la página mide
~795 px: no hay contenido fuera de vista que virtualizar.

## CSS style cost — 2026-10-24

Causa raíz encontrada con `NATIVAX_METRICS=1`: `pseudoStyleOf` recorría
**todas** las reglas `::before`/`::after` para cada elemento. Con Font Awesome
(600 iconos) eso añadía cientos de evaluaciones por nodo y explicaba los
~10 ms/elemento de la Biblia. La solución general es indexar las reglas de
pseudo-elemento por el sujeto, igual que las reglas normales.

### Antes / después

| Métrica | Base | Ahora |
|---|---:|---:|
| Fixture sintético, primer frame | 1.089 ms | **442 ms** |
| Fixture, style own / elemento | no medido (307 muestras Biblia ~9,9 ms) | **0,038 ms** (23,9 ms / 627) |
| Fixture, selectores/elemento | 46,5 (34.015 / 732) | **1,1** (666 / 627) |
| Biblia, primer contenido | 1.842 ms | **314 ms** |
| Biblia, style own / elemento | ~9,9 ms (307 muestras, suma 3.037 ms) | **0,343 ms** (1.284 muestras, 440,9 ms en 2 s) |
| Biblia, selectores/elemento | no medido | **17,0** |
| list 10k | 4.037 ms | **440 ms** |
| flex 10k | 3.672 ms | **611 ms** (426 ms parseo/JS + ~185 ms render) |
| article 2k updateAll | 129 ms | **26 ms/frame** |

JSON: `debug/benchmarks/baselines/style-css-current.json`,
`style-css-current.json`, `style-bible-baseline.json`,
`style-bible-current.json`.

### Metas

- Style < 0,5 ms/elemento: **cumplida** (0,343 ms en la Biblia; 0,038 ms en
  el fixture).
- Fixture sintético < 500 ms: **cumplida** (442 ms).
- Biblia primer contenido < 500 ms: **cumplida** (314 ms), pero **no** “sin
  frames > 50 ms”: quedan frames de población de 242–429 ms.
- list/flex/article sin regresión: list 440 ms, flex 611 ms con parseo
  (render ~185 ms), article 26 ms/frame.

### Lo que domina ahora

En la Biblia el estilo ya no domina: los frames de población siguen en
~200–430 ms de build/layout. El siguiente trabajo es layout (cache de
`LayoutResult`, menos pasadas dry/intrinsic), no más CSS matching.

### Conformidad

`dart run bin/run_wpt.dart --dirs css/selectors --limit 100000` no se pudo
ejecutar: `.conformance/suites/wpt` no está descargado en este checkout. No se
declara una tasa nueva. `./tools/test_all.sh` sí está en verde.
