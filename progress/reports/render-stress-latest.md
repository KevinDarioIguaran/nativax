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
