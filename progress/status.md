# Estado actual

Última actualización: 2026-10-24 (V8 + CSS, diagnóstico de UI).
Tests: **346** en total (`./tools/test_all.sh`, exit 0), incluidos 12 de
virtualización, 5 de caché de estilo y los fixtures de render.

## V8 integrado (rama `feat/v8-engine`) — 2026-10-24

- `V8Engine` real detrás de `JavaScriptEngine` (isolate persistente, host
  functions, buffers binarios y UTF-8 nativo). Se activa con
  `engineFactory: V8Engine.new`; QuickJS sigue por defecto.
- Biblia: `FIRST_VERSE` **5.411 → 3.306–4.100 ms**. RSS sube a 600–780 MB por
  el grafo del diccionario de 16 MB; con heap de 512 MB V8 aborta.
- Decodificar 16 MB con `TextDecoder` en JS costaba ~1,6 s; ahora lo hace V8
  nativo (`simdutf`).
- **No separa hilos todavía**: V8 corre en el isolate de UI. Los frames de
  **1,8–3,0 s** son `build` de Flutter (cascada 2–4,5 ms/elemento y layout de
  ~3.627 nodos al reconstruir `#verses`), no JS. Medido: hilo UI 97–100 %,
  hilos V8 de GC ~13 %, JS de la app 50–150 ms.
- Detalle: `progress/reports/v8-engine-latest.md`.

## V8 FFI spike — 2026-10-24

- `tools/v8-spike`: `cdylib` Rust con `v8`/`rusty_v8` 152.2.0 y FFI desde Dart.
- Medido sobre el mismo `/api/dict/ES` (14.380.093 bytes, 31.966 entradas):
  **V8 JSON.parse 87 ms**; Node 22 (parse+filter+sort) 76 ms; QuickJS en la
  app ~6.800 ms bloqueando la UI.
- `libnx_v8.so`: 62 MB. No integrado en `nativa_js`; no hay host functions,
  workers ni bridge DOM todavía.
- Conclusión: V8 sí enlaza desde Dart y elimina el coste del parser; falta el
  puente y la política de hilos. iOS sin JIT → QuickJS de fallback.
- `AGENTS.md` actualizado: QuickJS-ng sigue siendo el motor por defecto y el
  fallback, pero se permite un backend V8 o JavaScriptCore con JIT detrás de
  `JavaScriptEngine`.
- Detalle: `tools/v8-spike/README.md` y
  `progress/reports/v8-spike-latest.md`.

## CSS style cost — 2026-10-24

- Causa raíz: `pseudoStyleOf` evaluaba todas las reglas `::before/::after`
  para cada elemento (Font Awesome, 600 iconos). Se indexaron por sujeto con
  `_RuleBuckets`; `pseudoStyleOf` y la cascada pseudo solo miran candidatos.
- `NATIVAX_METRICS=1` añade métricas por elemento (µs propios, selectores,
  candidatos, hit/miss) restando el tiempo anidado.
- Se saltan `script/style/head/title/meta/link/noscript/template` antes de
  `styleOf`.
- Medido: fixture sintético **1.089 → 442 ms**; style **0,038 ms/elemento** y
  1,1 selectores/elemento. Biblia **1.842 → 314 ms** primer contenido; style
  **0,343 ms/elemento**, 17 selectores/elemento. list 10k **440 ms**, flex
  10k **611 ms** (426 parseo/JS), article updateAll **26 ms/frame**.
- Biblia sigue con frames de población de 242–429 ms; ahora domina layout.
- `./tools/test_all.sh` exit 0; analyze limpio. WPT css/selectors no medido:
  `.conformance/suites/wpt` ausente en este checkout. JSON en
  `benchmarks/results/style-*.json`; detalle en
  `progress/reports/render-stress-latest.md`.

## Layout + CSS — 2026-10-24

- Estabilización: invalidación de descendientes con estilo perezoso, walk de
  `position: fixed` con presupuesto suficiente, y evicción de `ComputedStyle`
  al salir de la ventana virtual (test de 120 ciclos; `cachedStyleCount < 300`).
- CSS: `MatchedPropertiesCache` + `ComputedStyle` compartido por firma
  (tag/id/clases/atributos/pseudo/estado), detección de selectores
  estructurales, y buckets de `:hover` para no crear `MouseRegion` en todos
  los nodos. Fixture `flex-grid`: **3.176 → 60 selectores** (52×).
- Layout: estimación del ancho disponible por ancestros para el grid virtual;
  primer frame sintético **1.089 → 876–904 ms**; `box.layout` 654 → 581 ms,
  `flex.layout` 473 → 415 ms, `renderObjects` 1.375 → 1.121.
- Fixture sintético nuevo (`tailwind-app`, 801 cajas, ~4.300 reglas) y JSON de
  perfil en `benchmarks/results/render-tailwind-*.json`.
- Metas: list 10k **397 ms** ✅; flex 10k **606 ms** (152 ms de render + 432 ms
  de parseo/JS) ⚠️; article 2k updateAll **24 ms/frame** ✅; fixture sintético
  **876–904 ms** ❌; Biblia **1.842 ms** primer contenido y **2.793 ms**
  siguiente ❌. Domina layout, no JS.
- `./tools/test_all.sh` exit 0; `dart analyze` en `nativa_css` y
  `flutter analyze` en `nativa_render`/benchmark limpios. Detalle:
  `progress/reports/render-stress-latest.md` y `docs/chromium-mapping.md`.

## Virtualización del renderer — 2026-10-23

- `CssVirtualBlock` materializa solo viewport + overscan; el resto no tiene
  `RenderObject` ni estilo computado. Placeholders constantes, altura estimada
  y corregida con scroll anchoring.
- Activa en block, flex column y grid por filas con muchos hijos; opt-out con
  `data-nativa-virtual="off"`.
- Scroll anidado y del documento; `#hash`, `scrollIntoView`, `focus()`,
  `boxOf`/`getBoundingClientRect` materializan el nodo antes de medir.
- `StyleEngine.lazySubtrees` + invalidación diferida para mutaciones fuera de
  vista; flex column reutiliza el layout real y evita una pasada dry.
- Medido en profile/AOT: list 10k **4.037 → 420 ms** (RenderObjects
  30.095 → 120), flex 10k **3.672 → 630 ms** (183 ms de render + 447 ms de
  parseo/JS; 55.072 → 517), article 2k updateAll **129 → 33 ms**
  (6.069 → 133). Biblia: **sigue sin cumplir** (primer contenido 1,82–2,09 s;
  frames 2,6–6,3 s). El bloqueo es layout/paint de ~800 nodos visibles con el
  CSS real; no es JS. Detalle y comandos: `progress/reports/render-stress-latest.md`.
- `./tools/test_all.sh` exit 0; `dart analyze` en `nativa_css` y
  `flutter analyze` en `nativa_render` limpios.

## Resumen

| Área | Estado | Evidencia |
|---|---|---|
| Núcleo JS (QuickJS-ng + FFI) | 🟢 estable | 53 tests; registro privado de callbacks en el puente C |
| WebAssembly (wasm3) | 🟢 B4 | 11 unitarios + 3 E2E; Rapier 0.19.3 y worker real (103 cuerpos ~45 Hz) |
| DOM | 🟢 estable | 38 tests; pseudoelementos, `:hover`/`:active`/`:target`, validación, dialog/details y `adoptNode` |
| HTML | 🟢 estable | 51 tests; foreign content (SVG/MathML), recuperación de errores y preprocesado de entrada |
| CSS | 🟢 estable | 39 tests; grid, `calc()`, `::before/::after`, keyframes, transiciones, `@supports` |
| Bindings JS↔DOM | 🟢 amplio | 51 tests; ~3.800 líneas de plataforma web (ver docs/javascript-supported.md) |
| Renderer Flutter | 🟢 amplio | 34 tests; grid, sticky, SVG, canvas 2D, animaciones, filtros, DnD |
| Runtime público (`nativax`) | 🟢 | 28 tests; red por política, servicios de plataforma, errores no fatales |
| Juego real (B5) | 🟢 jugable | bundle Vite sin modificar, 3 workers, Rapier, Start real, frames GL y captura no plana |
| Presentación WebGL | 🟡 línea base | 1280×720 DPR 1.0: shown 26,3–29,1 fps; present p95 67–74 ms; objetivo 45 fps no alcanzado |
| Rendimiento 7× | 🔴 registrado | Rapier 180 pasos: 328,5 ms (wasm3) vs 30,7 ms (V8); gap 10,7× |
| Ejemplo web-challenge | ✅ original | HTML/CSS/JS **sin modificar**: 46/52 comprobaciones propias en verde |
| Seguridad | 🟢 | `tools/security`: 14 PASS / 0 FAIL / 1 SKIP |
| Conformidad | 🟡 | Test262 97,93 %; html5lib 99,26 %; URL 74,22 %; DOM 59,36 %; CSS 50,28 %; tree 50,37 % |
| Plataformas | 🟡 solo Linux | build Linux verificado; resto sin probar |

## Spike quickjs-jit — 2026-10-22

- `quickjs-jit-sys` (con `jit-abi`) y `quickjs-jit-runtime` (con `compiler`)
  compilan con Rust 1.99.1 en `/tmp/opencode`.
- No integrado: el JIT es un runtime Rust con ABI propia; adaptarlo exige
  reescribir el bridge o exponer una API C equivalente. Detalle y estimación en
  `docs/nativa-js-jit-quickjs-jit-spike.md`.
- El JIT propio sobre QuickJS-ng sigue siendo el que está activo.

## JIT en NativaJS — 2026-10-21

- Backend inicial funcional en x86-64 Linux: W^X (mmap) para constantes y
  entradas C portables para `return undefined` y `return local0`. Correctitud
  verificada (`f(){}` → null, `f(){return 42}` → 42, `f(){var x=5;return x}` → 5).
  Punto de llamada en `JS_CallInternal` activo. Resto cae al intérprete.
- Plan completo: `docs/nativa-js-jit-plan.md`. Baseline: `progress/jit-baseline.md`.

## Plan JIT para NativaJS — 2026-10-21

- Plan documentado en `docs/nativa-js-jit-plan.md`: JIT por niveles inspirado en
  V8 (baseline copy-and-patch + feedback), sin V8/JSC, con presupuesto <10 MB
  (línea base 1,6 MB stripped). Fase 0+1 (flag + optimización del intérprete)
  recomendada como primer paso; L1/L2/L3 posteriores y opcionales.

## Reorganización Nativa y skills — 2026-10-21

- Paquetes internos renombrados a `nativa_js`, `nativa_html`, `nativa_dom`,
  `nativa_css`, `nativa_dom_bindings` y `nativa_render`; `nativax` conserva su
  nombre y API pública. Los paquetes de herramientas pasan a
  `nativa_conformance`, `nativa_benchmark`, `nativa_leaks` y
  `nativa_security`.
- NativaWeb queda documentado como familia modular de cuatro paquetes; no se
  creó un paquete fachada `nativa_web`.
- `.agents` se convirtió en una biblioteca de skills con `SKILL.md` y
  `references/`: OpenCode las descubre en `.agents/skills` y Claude Code usa
  enlaces en `.claude/skills`. La entrada común es `AGENTS.md`; `CLAUDE.md`
  importa esas instrucciones.
- `./tools/test_all.sh`: **316 tests en verde** con el juego cerrado.
- `flutter analyze`: **sin issues**; se eliminó un flag de entrega sin uso en
  `nativa_dom_bindings`.
- No se reanudó el trabajo de conformidad; el siguiente incremento sigue
  pendiente de petición explícita.
- Reportes de conformidad: se eliminaron 420 archivos con timestamp de
  `progress/reports/`; solo quedan `*-latest.md` por suite. Las corridas con
  fecha pasan a `.conformance/results/` (ignorado por git).

## Incremento de conformidad URL — 2026-10-21

- URL: **70,98 % → 72,21 %** (+1,23 puntos; 636 → 647 PASS;
  260 → 249 FAIL; 896 casos, 0 SKIP, 0 ERROR).
- Causa real: el parser de `data:` delegaba en `Uri.parse`, que rechaza las
  URLs `data:` por su MIME type. Se añadió una rama específica para `data:`
  usando un pseudo-URI `http:` y normalizando scheme, puerto, host y href.
- Comando: `dart run bin/run_url.dart` (commit de la suite `e7d77cd`).
- Tests: `nativa_dom_bindings` 51 en verde; `./tools/test_all.sh` 316 en verde;
  `flutter analyze` limpio.

## Incremento de conformidad URL — 2026-10-21 (2)

- URL: **72,21 % → 74,22 %** (+2,01 puntos; 647 → 665 PASS;
  249 → 231 FAIL; 896 casos, 0 SKIP, 0 ERROR).
- Causa real: un esquema especial sin `//` (`http:example.com`,
  `http:/example.com`, `http:a:b@host`, etc.) no se normalizaba a autoridad
  cuando no había base.
- Comando: `dart run bin/run_url.dart` (commit de la suite `e7d77cd`).
- Tests: `nativa_dom_bindings` 51 en verde; `./tools/test_all.sh` 316 en verde;
  `flutter analyze` limpio.

## Incremento de conformidad HTML tree — 2026-10-21

- Tree construction: **48,72 % → 50,37 %** (+1,65 puntos; 913 → 944 PASS;
  961 → 930 FAIL; 1973 casos, 99 SKIP, 0 ERROR).
- Causa real: el adoption agency simplificado dejaba el elemento de formato
  como ancestro y clonaba en el sitio equivocado.
- Fix: implementación del algoritmo de adoption agency (WHATWG) con clonación
  y reparentado del bloque más lejano.
- Comando: `dart run bin/run_html_tree.dart` (commit de la suite `e7d77cd`).
- Tests: `nativa_html` 51 en verde; `./tools/test_all.sh` 316 en verde.

## Incremento de conformidad CSS selectors — 2026-10-21

- CSS selectors: **17,68 % → 18,78 %** (+1,10 puntos; 32 → 34 PASS;
  149 → 147 FAIL; 528 archivos, 347 SKIP, 0 ERROR).
- Causa real: `.foo-*` (class prefix selector) no se soportaba y `:dir()`
  aceptaba cadenas entre comillas aunque la gramática exige un ident.
- Fix: soporte de class prefix selectors y validación de argumento de `:dir()`.
- Comando: `dart run bin/run_wpt.dart --dirs css/selectors --limit 100000`
  (commit de la suite `e7d77cd`).
- Tests: `nativa_dom` 38 en verde; `./tools/test_all.sh` 316 en verde;
  `flutter analyze` limpio.

## Incremento de conformidad CSS selectors — 2026-10-21 (2)

- CSS selectors: **39,78 % → 41,99 %** (+2,21 puntos; 72 → 76 PASS;
  109 → 105 FAIL; 528 archivos, 347 SKIP, 0 ERROR).
- Causa real: `getAttribute('lang')` coincidía con el atributo `xml:lang`
  por nombre local, y los selectores de atributo no trataban `lang` como
  insensible a mayúsculas.
- Fix: `getAttribute` solo coincide por nombre completo; los selectores de
  atributo tratan `lang` como case-insensitive.
- Comando: `dart run bin/run_wpt.dart --dirs css/selectors --limit 100000`
  (commit de la suite `e7d77cd`).
- Tests: `nativa_dom` 38 en verde; `./tools/test_all.sh` 316 en verde;
  `flutter analyze` limpio.

## Incremento de conformidad CSS selectors — 2026-10-21 (3)

- CSS selectors: **41,99 % → 50,28 %** (+8,29 puntos; 76 → 91 PASS;
  105 → 90 FAIL; 528 archivos, 347 SKIP, 0 ERROR).
- Causa real: el StyleEngine no se invalidaba en mutaciones de atributos,
  estructura o texto, por lo que la invalidación dinámica fallaba.
- Fix: `refreshStyles` ahora marca dirty el elemento afectado en cualquier
  mutación.
- Comando: `dart run bin/run_wpt.dart --dirs css/selectors --limit 100000`
  (commit de la suite `e7d77cd`).
- Tests: `nativa_dom` 38 en verde; `./tools/test_all.sh` 316 en verde;
  `flutter analyze` limpio.

## Checkpoint estable — Fase 0 de presentación

- **Versión por defecto:** DPR nativo 1.0, `backdrop-filter` activo y
  `GlSurfaceView`/`RawImage` como camino de presentación. No se bajó resolución
  y no se cambió el juego.
- **Métricas opt-in:** el HUD y el JSONL solo se activan con
  `NATIVAX_METRICS=1` o `NATIVAX_METRICS_FILE`. `NATIVAX_GAME_DPR`,
  `NATIVAX_NO_BACKDROP`, `NATIVAX_AUTOSTART` y `NATIVAX_FIXED_WINDOW` son flags
  de medición.
- **Medición preliminar a 1280×720:** render 34,7–42,6 fps, shown 26,3–29,1,
  UI 32–34, present p95 67–74 ms, decode p95 35–37 ms, build p95 2,9 ms,
  raster p95 15,1 ms, jank 1,2 %. El criterio de 45 fps/p95 ≤ 25 ms **no se
  alcanza**. Datos y advertencias en `progress/phase0-presentation.md` y
  `benchmarks/game-player-phase0/`.
- **A/B de backdrop:** no concluyente; la corrida exploratoria cambió de tamaño
  de ventana. Pendiente repetir 3×30 s con ventana fija.
- **Fase 1 (textura nativa):** no iniciada. Se dejó el checkpoint estable a
  petición del usuario; el siguiente paso documentado es
  `FlPixelBufferTexture`/`FlTextureRegistrar` detrás de una interfaz genérica,
  verificando antes el soporte de texturas externas en Impeller Linux.
- **Tests:** `./tools/test_all.sh` en verde con el juego cerrado; se añadió
  `gl_stats_test.dart` y se omiten ejemplos sin directorio `test/`.

## Incremento de conformidad HTML — 2026-10-21

- WPT tree construction: **39,97 % → 46,74 %** (876 PASS, 998 FAIL,
  99 SKIP, 0 ERROR). Total: **+6,77 puntos**, sin regresiones.
- **+5,07 puntos** son corrección del adaptador de fixtures: comentarios con
  un espacio delimitador y las dos formas de serializar processing
  instructions (`<?x ?>` y `<?x?>`). No cambian el DOM del parser; corrigen la
  comparación contra los `.dat`.
- **+1,70 puntos (35 tests) son mejoras reales del parser:** `center`,
  `dialog`, `dir`, `hgroup`, `listing`, `summary`, `search` y `plaintext`
  cierran `<p>`; un `<a>` anidado cierra el anterior; `</form>` deja abiertos
  sus descendientes; `<frame>` se ignora en body; un `</p>` antes de body no
  crea un párrafo en head; y un `</script` sin `>` al EOF sigue siendo texto.
- `./tools/test_all.sh`: **305 tests en verde** (43 en `nativa_html`).
- Siguen pendientes: adoption agency, foster parenting, template contents,
  tablas y foreign content.

## Segundo incremento de conformidad DOM — 2026-10-21

- WPT `dom/nodes`: **58,30 % → 59,36 %** (168 PASS, 115 FAIL, 44 SKIP,
  0 ERROR). **+1,06 puntos**, 3 archivos corregidos y **0 regresiones**.
- `Document.adoptNode` real: desengancha el nodo de su padre, actualiza
  `ownerDocument` en todo el subárbol y lanza `NotSupportedError` para
  documentos.
- Atributos: `Attr.ownerDocument` sigue al elemento, se conserva la identidad
  del wrapper y la adopción implícita al insertar en otro documento.
- Los wrappers de documento se mantienen vivos para no perder `contentType`;
  así `tagName` cambia entre HTML y XML. `Element-tagName-adopt.html` pasa.
- `./tools/test_all.sh`: **308 tests en verde**.
- Sigue fallando `Element-tagName.html` por el `DOMParser` simulado (devuelve
  un documento HTML) y por metadatos de prefijo cuando se recolecta el wrapper
  del elemento. También quedan MutationObserver y `createElement` con
  namespace como siguientes objetivos.

## Tercer incremento de conformidad — 2026-10-21

- html5lib tokenizer: **96,95 % → 99,26 %** (+2,31). 5759 PASS, 43 FAIL,
  1025 SKIP, 0 ERROR; **134 tests corregidos y 0 regresiones**.
- WPT tree construction: **46,74 % → 48,72 %** (+1,98). 913 PASS, 961 FAIL,
  99 SKIP, 0 ERROR; **37 tests corregidos y 0 regresiones**.
- Causas comunes corregidas en el tokenizer:
  - preprocesado de CR/CRLF a LF;
  - `<!...>` ya no incluye el `!` en comentarios bogus y acepta `--!>`;
  - NUL se sustituye por U+FFFD en comentarios, nombres y valores;
  - referencias numéricas 0x80–0x9F usan el mapa Windows-1252;
  - referencias numéricas con ceros a la izquierda y `</>` vacío.
- WPT `dom/nodes`: **59,36 %**, sin cambios ni regresiones.
- `./tools/test_all.sh`: **316 tests en verde** (51 en `nativa_html`).
- Quedan 43 fallos de tokenizer, concentrados en comentarios sin cerrar y en
  instrucciones de procesamiento (extensiones de html5lib).

## Comparación con Chrome (web-challenge)

`examples/web-challenge/test/screenshot_test.dart` renderiza la página con
fuentes del sistema; con `NATIVAX_SHOT_DIR` carga los archivos originales.
Formularios, UI, Media (canvas, SVG), CSS & render y Diagnóstico coinciden
visualmente con Chrome salvo:

- vídeo/audio (sin pipeline multimedia: se reportan bloqueados);
- emojis en capturas de test (en la app real las pone la fuente del sistema).

"Run all" con el `app.js` original: **46 ok, 4 blocked, 2 unsupported**.
Bloqueados: vídeo y audio (multimedia) y fetch/WebSocket cuando la red está
denegada (el ejemplo real habilita sus hosts con `IoNetwork`). No
soportados: `share` y `geolocation`.

## Fase 4 — en curso

- [x] Test262 (97,93 %), html5lib (99,26 %) y URL (70,98 %) por encima del 70 %.
- [ ] WPT `dom/nodes`: **59,36 %** (objetivo 70 %).
- [ ] WPT `css/selectors`: **10,38 %** (objetivo 70 %).
- [ ] WPT tree construction: **48,72 %** (objetivo 70 %).
- [x] Reparse de `<style>` al insertar/editar hojas (prerrequisito de CSSOM y
  de la UI de frameworks).
- [x] CSSOM básico: `document.styleSheets`, `insertRule`, `deleteRule`,
  `cssRules`, `selectorText`, `rule.style` y reparse dinámico.
- [ ] CSSOM completo: `@media` anidado, reglas huérfanas, enlaces externos y
  `getComputedStyle` con todos los longhands.
- [ ] Adoption agency/foster parenting/tabla/template/foreign content.
- [x] `Attr`, `createAttribute`, `DOMImplementation`, `Document` multi-documento y `classList` vivo.
- [ ] Namespaces completos en selectores/atributos, `Range`, `DOMParser` e iframes.

## Estado del juego real (B5)

- El HTML/CSS/JS de producción de `examples/threejs-multiplayer-starter/dist`
  se carga sin modificarlo.
- Arrancan el hilo principal, el render worker y el physics worker.
- Se cargan texturas, cubemap y GLTF con `fetch` + `createImageBitmap`.
- Rapier crea el heightfield, el jugador y 100 esferas; el worker mantiene
  ~45 Hz con 103 cuerpos.
- La pantalla de carga llega a "Ready!" y el botón de inicio queda visible.
- **Resuelto:** `RenderCssBox` aplicaba `constraints.enforce(wanted)` en el
  sentido contrario; ahora `wanted.enforce(constraints)`. El canvas fijo
  full-screen respeta el viewport.
- `packages/nativax/test/game_play_test.dart` ya no está saltado: pulsa Start
  con un tap real, espera a que desaparezca el loading-screen, comprueba que
  el render worker presenta frames y valida que la captura no es un color
  plano (fox, terreno y UI).

## Lo que falta para un navegador "completo"

1. Multimedia (`video`/`audio`) y Web Audio real: hoy `AudioContext` es un
   grafo silencioso y `decodeAudioData` rechaza; requiere un plugin por
   plataforma (no existe uno oficial para Linux).
2. Canvas: `drawImage` de `<img>`, `getImageData`/`putImageData`,
   `toDataURL`.
3. Shadow DOM completo (hoy es una fachada sobre light DOM), CSSOM
   (`document.styleSheets`), `createElementNS` completo.
4. WebAssembly: memoria/tabla/global importadas, exportaciones de tabla/global,
   SIMD y hilos/atomics.
5. Layout: tablas reales, `float`, columnas, `writing-mode`, colapso de
   márgenes padre/hijo, `align-content` en flex, subgrid.
6. Fuentes web (`@font-face`), selección de texto, `contenteditable`.
7. Workers: `importScripts` síncrono desde URL, WebSocket en workers e
   interrupción nativa de un worker ocupado; `dynamic import`/módulos ES
   completos.
8. Parser HTML: adoption agency completa, foster parenting, quirks.
9. Plataformas: Android/iOS/Windows/macOS sin compilar.

## Comandos de verificación

```bash
./tools/test_all.sh
(cd tools/security && dart run bin/security.dart run)
(cd tools/conformance && dart run bin/run_wpt.dart --dirs dom/nodes --limit 100000)
(cd examples/web-challenge && NATIVAX_SHOT=/tmp/shot.png NATIVAX_SHOT_DIR=<dir> flutter test test/screenshot_test.dart)
```
