# Histórico

> Las entradas anteriores al 2026-10-21 usan la nomenclatura antigua
> `nativax_*`. La tabla de migración y los nombres actuales están en
> [`docs/nativa-family.md`](../docs/nativa-family.md).

## 2026-10-20 — Sesión 1: cimientos

- Monorepo con `nativax_js`, `nativax_dom`, `nativax_html`, `nativax_css`,
  `nativax_dom_bindings`.
- QuickJS-ng vendorizado, puente C/FFI, timers, límites.
- 159 tests unitarios en verde.
- `STATUS.md` con el plan del renderer.

## 2026-10-20 — Sesión 2: conformidad + renderer (fase 1)

### Infraestructura

- `tools/conformance` (paquete del workspace) con:
  - descarga pinneada de Test262, html5lib-tests y WPT (`.conformance/`),
  - runners Test262, html5lib tokenizer, WPT (adaptador testharness), WPT URL
    y WPT tree construction,
  - estados `PASS/FAIL/SKIP/ERROR`, motivos, JSONL, resumen JSON, Markdown,
    comparación con línea base,
  - `run_all.dart` y README.
- `.agents/` con contexto, arquitectura, estándares de calidad, conformidad,
  código, seguridad y rendimiento.
- `progress/` con estado, fases, conformidad y este log.

### Correcciones

- `nativax_flutter` no compilaba: faltaba `foundation.dart` para `listEquals`
  y `MediaQuery` era ambiguo con `nativax_css`. Corregido.
- `:empty` no se reevaluaba al cambiar `Text.data`; ahora `characterData`
  invalida el padre. Test nuevo en `nativax_css` (31 tests).
- El radio de borde porcentual se cacheaba entre tamaños; el renderer invalida
  decoración y painter al cambiar el tamaño.
- Tabla completa de entidades HTML5 (2.125 nombres + 106 legacy) generada en
  `nativax_html/lib/src/entities.dart`. html5lib pasó de 59,96 % a 96,95 %.
- Test262: se excluyen `*_FIXTURE.js`; los tests de módulos/import dinámico y
  TCO se reportan SKIP con motivo.

### Renderer fase 1

- `packages/nativax_flutter` con `pubspec.yaml` y entrypoint.
- `NativaXDocumentView`: escucha mutaciones, agrupa en microtask, recalcula
  estilos, aplica `MediaContext` desde `LayoutBuilder`, scroll raíz y color de
  canvas.
- `NativeXNodeView`: bloque, flex, texto inline, cajas, imágenes, input,
  textarea, checkbox/radio, select y botones; gestos → `Element.click()`;
  semántica básica.
- 6 widget tests + 1 test de integración JS→DOM→Flutter.
- `packages/nativax`: `NativaXRuntime` (parseo, `<style>`, scripts inline y
  externos vía `NativaXResourceLoader`, `DOMContentLoaded`/`load`, dispose),
  `NativaXView`, `FlutterHostEnvironment` y 3 tests, incluido un contador
  end-to-end con estado en JavaScript.

### Línea base de conformidad

| Suite | Tasa | PASS/FAIL/SKIP/ERROR |
|---|---:|---|
| Test262 (subconjunto) | 97,93 % | 19.577 / 413 / 1.108 / 0 |
| html5lib tokenizer | 96,95 % | 5.625 / 177 / 1.025 / 0 |
| WPT `dom/nodes` (límite 400) | 14,52 % | 36 / 210 / 79 / 2 |
| WPT `css/selectors` (límite 400) | 3,03 % | 5 / 160 / 235 / 0 |
| WPT URL | 0,00 % | 0 / 896 / 0 / 0 |
| WPT tree construction | 30,49 % | 361 / 821 / 789 / 2 |

### Verificación

```bash
(cd packages/nativax_js && dart test)                 # 31
(cd packages/nativax_dom && dart test)                # 34
(cd packages/nativax_html && dart test)               # 38
(cd packages/nativax_css && dart test)                # 31
(cd packages/nativax_dom_bindings && dart test)       # 26
(cd packages/nativax_flutter && flutter test)         # 7
flutter analyze packages/nativax_flutter              # limpio
dart analyze tools/conformance                        # limpio
(cd tools/conformance && dart run bin/run_all.dart)   # ver conformance.md
```

Total unitario/widget: **170 tests**.

## 2026-10-20 — Sesión 3: cierre de fase 2

- Fase 2 cerrada con el alcance 0.1: motor, contexto, puente DOM, eventos,
  reactividad, ejemplo interactivo y ciclo de vida.
- `NativaXRuntime` ejecuta scripts inline y externos, `<style>`/`<link>`,
  dispara `DOMContentLoaded`/`load`, cancela timers al disponer.
- Documentación de APIs y event loop en `docs/javascript-supported.md`.
- Ejemplo `examples/counter` (HTML/CSS/JS) + test de widget.
- 7 tests nuevos de fase 2: async/await + timers, microtareas, eventos de
  carga, recursos externos, errores de script, consola y ciclo de vida.
- Total: **178 tests** (160 puros + 7 renderer + 10 runtime/JS + 1 ejemplo).

## 2026-10-20 — Sesión 4: cierre de fase 3

- Posicionamiento `relative`/`absolute` con `Stack`, offsets y orden por
  `z-index` (bloque contenedor = padre inmediato, documentado).
- Listas con marcadores (`disc`, `circle`, `square`, `decimal`, `ol[start]`,
  `li[value]`).
- Overflow `auto`/`scroll` por contenedor; se conserva el clip de
  `hidden`/`clip`.
- `label` activa su control (`for` o anidado).
- Corrección importante: los nodos de texto que solo contienen espacios entre
  bloques ya no generan párrafos anónimos de 23 px.
- Tests nuevos de posición, listas, labels, responsive (`@media` + `vw`),
  tipografía, `flex-wrap`, imágenes con resolver y overflow.
- Documentación `docs/css-supported.md` con el subconjunto y las limitaciones.
- Total: **187 tests** (160 puros + 16 renderer/layout + 10 runtime/JS +
  1 ejemplo).

## 2026-10-20 — Sesión 5: fase 4 (iteración 1)

- `URL` y `URLSearchParams` expuestos a scripts; WPT URL pasó de 0 % a
  **70,98 %** (636/896).
- `CharacterData.appendData/insertData/deleteData/replaceData/substringData`
  con conversión WebIDL de offsets y counts.
- `ChildNode.before/after/replaceWith` en `Node` (Text/Comment incluidos).
- `Node.isEqualNode/isSameNode/normalize/getRootNode`, `Document.importNode`,
  `createElementNS` básico, `hasAttributes`, `getAttributeNS`, etc.
- WPT `dom/nodes` subió de 14,52 % a **19,11 %** (47/246 ejecutados).
- WPT `css/selectors` medido completo: **4,37 %** (8/528; 345 reftests).
- Tests nuevos de URL y APIs DOM en `packages/nativax/test/phase4_test.dart`.
- Total: **189 tests**.

## 2026-10-20 — Sesión 6: hot reload + avance de fase 4

- `NativaXHotReloadView`: lee un archivo HTML, vigila el directorio, debounce
  de 80 ms, recarga el runtime con `NativaXRuntime` nuevo, control manual con
  `NativaXHotReloadController` y manejo de errores.
- Documentado en `docs/hot-reload.md`: es hot reload de documento (hot
  restart), no conserva estado JS.
- Test de hot reload con archivo temporal y recarga manual.
- URL 70,98 %; DOM 19,11 %; CSS 4,37 %; tree 30,49 %.
- Total: **190 tests**.

## 2026-10-20 — Sesión 7: fase 4A (tree construction)

- `DocumentType` en DOM, parser, serializador y bindings.
- Parseo de doctype con public/system; `Document.doctype`.
- `<?...>` comparable como comentario/PI.
- `<template>` en head y contenido dentro del template.
- WPT tree construction: 30,49 % → **38,53 %**; SKIP 789 → 99.
- Plan de fase 4 dividido en 4A (parser), 4B (CSS/CSSOM), 4C (DOM),
  4D (URL), y fases 5/6 por plataforma/estabilización.
- Total: 190 tests.

## 2026-10-20 — Sesión 8: 4A parser (adopción/tablas)

- Adoption agency simplificada: al cerrar un formato mal anidado se mueve el
  elemento al bloque actual y se deja un clon vacío en su posición.
- Inserción implícita de `tbody`/`tr` para `table`/`td`/`th`.
- `template` en head y contenido dentro del template.
- WPT tree construction: **39,75 %** (745/1.973; 99 SKIP).
- Documentación HTML pendiente de ampliar; plan de fases actualizado.

## 2026-10-20 — Sesión 9: suite de benchmarks

- Nuevo `tools/benchmark` (workspace) con:
  - JS puro: aritmética, funciones, objetos/prototipos, arrays, strings,
    recursión, JSON parse/stringify, churn de objetos.
  - Puente JS→C→Dart (`bridge.noop`).
  - DOM: crear, consultar, modificar, eliminar, eventos, `innerHTML` y
    `StyleEngine.recompute`.
  - Referencia nativa Dart separada por categoría.
- Runner con warmup, rondas, mediana/min/max/desviación/MAD, checksums,
  metadatos de motor/OS/arquitectura/reloj y JSON/Markdown.
- Comparador con umbral y ruido (MAD/mediana × multiplicador); no declara
  regresión dentro del ruido.
- 7 tests del runner, formato y comparación.
- Documentación `tools/benchmark/README.md` y `docs/benchmarks.md`.
- Total: **197 tests**.

## 2026-10-20 — Sesión 10: suite de fugas

- `tools/leaks`: 18 casos de JS, DOM, listeners, timers, bindings, CSS,
  runtime y controles positivo/negativo.
- Perfiles `quick/full/stress`, límites de tiempo, JSONL por lote, JSON, MD y
  comparación de revisiones.
- Analizador con `PASS/FAIL/SKIP/ERROR/INCONCLUSIVE`; exige tendencia y
  evidencia de recursos/heap, no una sola muestra de RSS.
- Bug real encontrado y corregido: `node.release` no liberaba listeners al
  soltar el wrapper JS; `dom.detached_listeners` lo detectó.
- 9 tests de análisis/informes/comparación.
- Total: **206 tests**.

## 2026-10-20 — Sesión 11: auditoría de seguridad

- `tools/security`: 15 casos de sandbox, bridge, XSS, límites, storage,
  lifecycle y hardening.
- Corregido: `click()`/`requestSubmit()` programáticos ya no son
  `isTrusted`; el renderer usa gestos confiables.
- Corregido: `NativaXRuntime` elimina `__nx` con `DomBindings.harden()` antes
  de ejecutar scripts; preludios conservan el host por closure.
- Corregido: `node.release` libera listeners (detectado por `tools/leaks`).
- Abierto: `__nx_dispatch`/`__nx_eventDone`/`__nx_releaseListener` siguen
  visibles en `globalThis` (severidad media; sin escape al host).
- Documentos: `SECURITY_THREAT_MODEL.md`, `SECURITY_AUDIT.md`,
  `SECURITY_TEST_PLAN.md`, `SECURITY_PLATFORM_MATRIX.md`.
- Resultado real: 13 PASS / 1 FAIL / 1 SKIP.
- Total: **209 tests**.

## 2026-10-20 — Sesión 12: seguridad + selectores

- Selectores nuevos: `:is`, `:where`, `:has`, `:dir`, `:lang`, `:heading`,
  `:focus-visible`, `:focus-within`, flag `s` y `:nth-child(... of S)`.
  WPT CSS 4,37 % → **4,92 %**.
- Auditoría de seguridad: 13 PASS / 1 FAIL / 1 SKIP.
- Corregido `click()`/`requestSubmit()` programáticos (`isTrusted=false`).
- `NativaXRuntime` elimina `__nx` con `DomBindings.harden()`.
- Corregido `node.release` para no borrar listeners de nodos conectados;
  los desconectados sí los liberan.
- Documentos `SECURITY_*` y `tools/security`.
- Total: **209 tests**.

## 2026-10-20 — Sesión 13: ejemplo del Web Challenge

- Añadido `examples/web-challenge` a partir del ZIP del reto web.
- El HTML/CSS/JS se cargan desde assets con un `NativaXResourceLoader`;
  no se añadió red ni WebView.
- `compat.js` aporta shims mínimos para diagnóstico (`performance`,
  `requestAnimationFrame`, `getComputedStyle`, `Intl`, `screen`) y la app
  marca como no soportadas las APIs ausentes.
- Adaptaciones de degradación en formularios, diálogo, canvas y HTTP.
- Tests: arranque sin errores de script y contador interactivo.
- Compilado en Linux:
  `build/linux/x64/release/bundle/nativax_web_challenge_example`.
- Total: **211 tests**.

## 2026-10-20 — Sesión 14: Web Challenge actualizado

- Reemplazados los assets por la segunda versión del ZIP: nueva cabecera con
  estadísticas, navegación por secciones, estilos renovados y panel de
  diagnóstico.
- Reaplicadas las adaptaciones de NativaX: `compat.js`, degradación de
  formularios/diálogo/canvas/HTTP y manejo seguro de arranque.
- Corregida la navegación de anchors sin `HTMLAnchorElement.hash`.
- Tests del ejemplo: **2/2**; build Linux reconstruido correctamente.

## 2026-10-20 — Sesión 15: variables CSS y carga real del ejemplo

- Implementadas custom properties CSS (`--x`) con herencia y
  `var(--x, fallback)`; antes se descartaban y casi todo el CSS del ejemplo
  quedaba sin color, borde ni fondo.
- Añadido shorthand `font` y fallback sólido para gradientes no soportados.
- Resuelto `env(safe-area-inset-*)` como `0px` (con fallback explícito).
- El ejemplo ya aplica fondo, color, tipografía y cabecera visibles; el test
  de arranque sigue sin errores de script.
- Total: **212 tests**.

## 2026-10-20 — Sesión 16: compatibilidad web (ejemplo original sin modificar)

Objetivo: que `examples/web-challenge` se vea y funcione como en Chrome con
su HTML/CSS/JS original. Se eliminó `compat.js` y el `app.js` adaptado.

- CSS: `display: grid` completo, `calc/min/max/clamp`, `::before/::after`
  con `content`, `:hover`/`:active`/`:target` y pseudoclases de formulario,
  `box-shadow`, gradientes reales, `transform`, `filter`,
  `backdrop-filter`, `text-shadow`, bordes `dashed/dotted/double`,
  `@keyframes`, `transition`/`animation`, `@supports`, `@layer`,
  `position: fixed/sticky`, `z-index` en flujo, `display: contents`,
  propiedades SVG, hoja UA ampliada.
- Renderer: grid, sticky, SVG en línea, canvas 2D, animaciones, capa de
  viewport (fixed y `dialog` modal), `details`, controles nativos (range,
  color, fecha/hora, archivo, select múltiple, radio), legend sobre el borde,
  arrastrar y soltar, teclado, `LayoutHost` (geometría y scroll).
- JS: ~3.800 líneas de plataforma web (eventos, HTML*Element, formularios,
  location/history, performance, rAF, crypto, Intl sin ICU, storage,
  IndexedDB, observers, fetch/XHR/WebSocket por política de red, Blob/File,
  Workers, BroadcastChannel, customElements, DOMParser, canvas 2D).
- HTML: foreign content (SVG/MathML).
- Corregido: cajas `display:none` que se pintaban; errores de listeners que
  tumbaban la página; wrappers JS de nodos conectados que se recolectaban.
- Seguridad: S-04 corregido (registro privado de callbacks en el puente C);
  activación de usuario para portapapeles y vibración.
- Conformidad: DOM 19,11 → 23,78 %; CSS 4,92 → 6,56 %; tree 39,75 → 39,97 %.
- Total: **264 tests**.

### Pendiente inmediato

- Paquete `nativax` (runtime + `NativaXView` + `FlutterHostEnvironment`).
- `createElementNS`, CSSOM, `DOMParser`, `URL`.
- Adoption agency, foster parenting, doctype, template y foreign content.
- CI, README, LICENSE y benchmarks.

## 2026-10-21 — Sesión 17: espejo con Chrome (bloque A) y módulos ES (B1)

Bloque A — fidelidad visual medida, no a ojo:

- Nueva herramienta `tools/mirror/` (`mirror.sh` + `measure.js` +
  `compare.dart`): renderiza la misma página en Chrome headless (solo como
  referencia) y en NativaX, y compara la caja de cada elemento. Formularios
  pasó de 28 % a 82,7 % de cajas idénticas (±2 px).
- Corregido: bordes ajustados a píxel de dispositivo (CSS Values 4), legend
  shrink-to-fit sin partirse, colapso de márgenes padre/hijo y cajas vacías,
  `letterSpacing`/altura de línea de Material filtrándose al texto de la
  página, iconos de select/fecha/hora pintados (la app real mostraba glifos
  rotos sin la fuente de iconos), filas de `select multiple` como Chrome,
  salto de línea final en `<pre>`, rects de elementos inline, filas grid
  estiradas hasta `min-height`, `position:absolute` relativo al padding box,
  transformaciones 3D reales con `perspective`/`transform-origin`,
  `getBoundingClientRect` con transformaciones, contenido de botones centrado,
  elementos reemplazados sin estirar en grid, `<fieldset>` con ancho fijo.
- Tests: `packages/nativax_flutter/test/fidelity_test.dart` (13).
- Pendiente medido: inline con fondo/padding partido por líneas, `dir=rtl`,
  ancho intrínseco de `<input>` (Chrome usa métricas OS/2 de la fuente),
  redondeo de alturas de línea de Flutter (0,2 px/línea).

B1 — módulos ES para `examples/threejs-multiplayer-starter` (copiado sin
modificar del repo upstream, commit en `.upstream-commit`):

- Puente C: cargador de módulos de QuickJS (`nx_eval_module`,
  `import.meta.url`, errores asíncronos de módulos) y traspaso de buffers
  nativos entre Dart y JS sin base64 (`nx_buffer_put/take`).
- Runtime: `<script type="module">` diferidos en orden, grafo de imports
  precargado (`DocumentModules`), especificadores "bare" rechazados como en
  Chrome, `fetch()` de recursos propios servido por el loader
  (`LocalResourceNetwork`), `ReadableStream` con lector real.
- API: `NativaXResourceLoader.loadBytes`, `NativaXAssetLoader`,
  `NativaXDirectoryLoader`.
- Tests al cierre de B1: 246 en paquetes (`nativax_js` 38, `nativax` 20).

B2 — workers en hilos reales:

- Cada `new Worker()` corre en su propio isolate (hilo) con su propio
  QuickJS (`IsolateWorkerLauncher`); opción `threadedWorkers: false` para
  ejecutarlos en el hilo de UI (`InProcessWorkerLauncher`).
- Ámbito global de worker real (`WorkerRuntime`): reutiliza toda la
  plataforma web de la prelude, sin `window`/`document`, con `self`,
  `DedicatedWorkerGlobalScope`, `WorkerLocation`, `name`, `close()`.
- Structured clone serializable entre runtimes (Map/Set/Date/RegExp/
  typed arrays/DataView/Blob/File/Error/BigInt/ciclos/transfer con
  detach) y `MessagePort` con ids globales enrutados por `PortRouter`
  (transferibles entre hilos, estilo Comlink).
- `SharedArrayBuffer` con contador de referencias atómico en C, compartido
  entre runtimes; `Atomics.wait` bloquea en workers y lanza en el hilo de UI;
  `crossOriginIsolated` es `true`.
- `fetch()` desde workers servido por la política de red de la página.
- `requestAnimationFrame` a 60 Hz sobre rejilla fija (sin deriva).
- Tests: 256 en paquetes + 2 del ejemplo + 19 de herramientas = 277.
- Pendiente: `importScripts` síncrono desde URL, WebSocket en workers,
  interrupción nativa de workers ocupados (hoy: kill del isolate).

B3 — WebGL 2 nativo:

- `packages/nativax_js/src/nativax_gl.c`: WebGL 1/2 sobre OpenGL ES 3.0
  vía EGL (cargado con `dlopen`, sin dependencia de enlace; display
  surfaceless de Mesa cuando existe). Cada llamada WebGL va de JS a C
  directamente (sin Dart ni JSON); typed arrays sin copia. Framebuffer por
  contexto con MSAA 4x, `preserveDrawingBuffer`, alpha/premultiplied.
- Presentación: al terminar la tarea que dibujó, `glReadPixels` a un triple
  buffer nativo ("surface", compartido entre hilos); Flutter muestra el último
  frame (`GlSurfaceView`, sondeo por vsync). El hilo que renderiza nunca
  espera a la UI. El contexto GL se restaura tras cada entrada al script
  (los isolates cambian de hilo; el contexto de Flutter no se pisa).
- JS: `WebGL2RenderingContext`/`WebGLRenderingContext` completos (objetos,
  `getParameter` tipado, extensiones mapeadas a GLES), `OffscreenCanvas`
  (transferible a workers), `transferControlToOffscreen`, `ImageBitmap`
  (memoria nativa, transferible sin copia), `createImageBitmap` con
  decodificación JPEG/PNG/GIF/BMP en C (stb_image v2.30, MIT).
- Prueba real: three.js r182 (la versión del juego) renderiza una escena con
  luces, sombras PCF y MSAA; coincide con Chrome (ANGLE/SwiftShader) con una
  diferencia media de 0,03/255 por canal (`packages/nativax/test/three_test.dart`).
- Solo Linux/Android por ahora (EGL); iOS/macOS/Windows compilan un stub
  que informa WebGL no disponible.
- Tests: 261 en paquetes + 2 + 19 = 282.

B4 — WebAssembly con wasm3:

- Motor elegido: wasm3 `28ecb9a` (MIT, 29-sep-2026), intérprete C sin JIT.
  Vendorizado en `packages/nativax_js/third_party/wasm3` y compilado por el
  hook con `d_m3MaxNativeStack=393216`. Rapier usa bulk memory, conversiones
  float→int y sign-extension, todas soportadas; SIMD no.
- Puente propio `src/nativax_wasm.c/.h`: un `WebAssembly.Module` valida y
  guarda una copia de los bytes; cada `Instance` reparsea para permitir
  múltiples instancias. Los imports se enlazan después de `m3_LoadModule`
  con `m3_LinkRawFunctionEx` y un descriptor por `(module, name)`.
  Las excepciones JS de un import se aparcan y se relanzan al salir del
  wasm, sin que wasm3 vea `JSValue`.
- API JS (`lib/src/wasm_prelude.dart`): `Module`/`Instance`/`Memory`,
  `compile`, `instantiate`, `instantiateStreaming`, `validate`,
  `Module.imports/exports`, `CompileError`/`LinkError`/`RuntimeError`,
  `i64` con `BigInt`, múltiples resultados, memoria viva y `grow`.
  `Table` y `Global` existen pero sus imports/exports aún se rechazan.
- Memoria: `JS_NewArrayBuffer` externo sobre la memoria de wasm3. Al crecer,
  el buffer anterior se detacha y se crea otro; las vistas cacheadas de
  wasm-bindgen se refrescan igual que en Chrome.
- Límites: 512 MB de memoria lineal y 500 M de gas por llamada (el peor
  `world.step` medido de Rapier usa 7,8 M; 180 pasos usan 1,18 B en total).
- Prueba real: Rapier 0.19.3 (`@dimforge/rapier3d-compat`, wasm de 1,57 MB)
  crea un mundo, suelo, bola dinámica, 180 pasos, masa, sleep y raycast.
  Corre en el hilo de UI, en un worker real con su propio runtime y en el
  bundle de producción del worker de física del juego (`src/workers/physics.worker.ts`
  compilado por Vite), incluyendo Comlink, SharedArrayBuffer y Atomics.
  `packages/nativax/test/wasm_rapier_test.dart`.
- Rendimiento medido: el worker real con 3 cuerpos mantiene ~57 Hz; con
  103 esferas + suelo + jugador baja a ~45 Hz (~10-11 ms por `world.step`).
- Arreglo colateral: `NativaXRuntime` instala `console` aunque no haya
  `onConsole` (wasm-bindgen emite un `console.warn` recuperable al probar
  `instantiateStreaming`).
- Tests: `nativax_js` 52 (11 nuevos de wasm) y `nativax` 26 (3 de Rapier).
  Total: **275 en paquetes + 2 + 19 = 296**.
- Pendiente: memoria/tabla/global importadas, exports de tabla/global, SIMD
  y wasm con hilos/atomics.

## 2026-10-21 — Sesión 19: juego real (B5 en curso)

- Se arranca el bundle de producción de `threejs-multiplayer-starter/dist`
  sin modificarlo: HTML, CSS, main thread, render worker y physics worker.
- Web platform añadida para que el bundle llegue a "Ready!":
  - Shadow DOM mínimo como fachada sobre light DOM (`attachShadow`,
    `shadowRoot`, `innerHTML`, queries y eventos delegados al host).
  - `AudioContext`/nodos Web Audio silenciosos; `decodeAudioData` rechaza
    limpiamente (three.js sigue construyendo su grafo y el juego no se cae).
  - `location.origin`/`WorkerLocation.origin` devuelven `app://local` en vez
    de `null`, para que las texturas y el GLTF se resuelvan desde el worker.
  - `MutationObserver` guarda referencias a los nodos y materializa los
    records en `takeRecords()`, evitando wrappers ya liberados.
  - Los errores de `console.error(Error)` vuelven a mostrar sólo
    `name: message` (el stack se probó y rompía el contrato de la consola).
- wasm3: gas por llamada subido a 1.000 M. El heightfield 256×256 usa ~542 M;
  los pasos de Rapier del juego usan 14–100 M. El límite de 500 M bloqueaba
  la creación del terreno.
- Canvas: se probaron varias estrategias de constraints para el canvas
  full-screen; la definitiva está pendiente. `CanvasView` ya no usa
  `SizedBox.expand` con constraints infinitos para canvas 2D y el GL se
  dimensiona al viewport.
- Pruebas: `nativax_js` 52, `nativax` 27 (más un probe visual saltado).
  Total: **276 en paquetes + 2 + 7 + 9 + 3 = 297**.
- Estado: el juego arranca y muestra "Ready!" + botón Start. El bloqueo
  restante es el layout del canvas `position: fixed` al pulsar Start; no hay
  todavía captura jugable.

### Requisito de rendimiento 7×

- Registrado en `.agents/performance.md` con la línea base QuickJS-ng vs V8
  (mediana de gap ~7×; rango 2,6×–49× según el caso).
- Se distingue explícitamente:
  - 7× en JS puro **no** se puede conseguir con QuickJS-ng; requiere V8/JSC
    con JIT en plataformas que lo permitan.
  - 7× end-to-end sí es objetivo medible para física wasm, bridge, DOM/layout
    y renderer.
- Ruta propuesta: WAMR AOT/JIT para WebAssembly con wasm3 como fallback sin
  JIT, y adaptador V8/JSC opcional para JS en desktop/Android.
- Estado: registrado y no alcanzado; siguiente medición es `world.step` de
  Rapier con 103 cuerpos y el frame del juego real.

- Línea base WebAssembly: misma escena de 100 esferas, 180 pasos:
  V8 + Rapier 30,74 ms; NativaX + wasm3 328,54 ms (10,7× más lento).
  Para el 7× el objetivo es ≤46,9 ms; WAMR AOT es la siguiente evaluación.


### Inicio de Fase 4 (conformidad)

- Re-ejecutados WPT DOM y CSS: DOM **24,48 %** (70/214/41/2) y CSS selectors
  **7,10 %** (13/170/345), todavía lejos del 70 %.
- Implementado el reparse de `<style>` cuando scripts o UI los insertan/editan
  (`NativaXRuntime._refreshStyleSheets`). Es prerrequisito de CSSOM y de las
  hojas que inyectan los frameworks; los tests actuales siguen en verde.
- La Fase 4 **no está terminada**. Siguiente orden: CSSOM (`styleSheets`,
  `insertRule`, `cssRules`, `selectorText`), adoption agency/foster parenting
  y APIs DOM que bloquean `dom/nodes`.


### Fase 4: CSSOM básico

- Nuevo `web_prelude_cssom.dart`: `document.styleSheets`, `CSSStyleSheet`,
  `insertRule`, `deleteRule`, `replaceSync`, `CSSRule`, `CSSStyleRule`,
  `CSSMediaRule`, `selectorText`, `rule.style` y edición del texto de la hoja.
- `NativaXRuntime` reparsea `<style>` cuando se inserta o edita; el runner de
  WPT también conecta ahora `StyleEngine` y reparsea las hojas (antes corría
  sin estilos, lo que hundía artificialmente WPT CSS).
- WPT `css/selectors`: 7,10 % → **10,38 %** (19 PASS / 164 FAIL / 345 SKIP).
- WPT `dom/nodes`: 24,48 % (sin cambio).
- Tests: `nativax_dom_bindings` 49; total **277 en paquetes + 2 + 7 + 9 + 3 = 298**.


- Añadido `getElementById` a `DocumentFragment`/`Element` y constructor de
  `DocumentFragment`. WPT `dom/nodes`: 24,48 % → **25,17 %**
  (72 PASS / 212 FAIL / 41 SKIP / 2 ERROR).


- Corregido `:lang()` y `[lang|=...]`: la comparación usaba literalmente
  `$wanted-`/`$v-` en vez de interpolar el valor, por lo que nunca casaban los
  subtags. Añadidos tests de regresión en `nativax_dom`.
- Hallazgo de conformidad: los FAIL de `css/selectors` dependen sobre todo de
  `offsetWidth`/`getBoundingClientRect`; el runner no tiene layout, así que el
  70 % de CSS exige integrar el renderer, no sólo el selector.

- Corrección de selectores: `:lang()` y `[lang|=...]` usaban el literal
  `$wanted-`/`$v-`; ahora interpolan el valor. Tests de regresión añadidos en
  `nativax_dom`.
- Atributos expuestos por `Element.attributes` y `createAttribute` reciben
  `ownerDocument`/`baseURI` (el WPT `Node-baseURI` sigue fallando porque
  faltan `createAttribute`/`getAttributeNode` reales).
- Estado de conformidad sin cambio adicional: DOM 25,17 %, CSS 10,38 %.


## Sesión 17 — DOM real, no fachadas

- WPT `dom/nodes`: 25,17 % → **31,82 %** (91 PASS / 193 FAIL / 41 SKIP / 2 ERROR).
- `Attr` real y `NamedNodeMap`; `createAttribute`/`getAttributeNode`/
  `setAttributeNode`; `Node-baseURI` pasa al 100 %.
- `DOMImplementation` por documento, `new Document()`, `XMLDocument`,
  `createDocument`, `createDocumentType`, `createHTMLDocument`;
  `Document-implementation` y `Node-cloneNode-XMLDocument` al 100 %.
- Adopción automática entre documentos y `Document.cloneNode`; `Document-doctype`
  al 100 % (comentarios de nivel superior conservados por el parser).
- Errores de host convertidos a `DOMException` reales con `name`, `code` y
  `constructor`; esto desbloquea `assert_throws_dom` en toda la suite.
- `classList` completo: `Element-classlist` pasa de 170 a 0 fallos (100 %).
- `CharacterData-appendChild`, `-insertData`, `-substringData`: 100 %.
- `createAttribute`, `createProcessingInstruction`: 100 %.
- `ChildNode-after`, `ChildNode-replaceWith`, `ParentNode-append`,
  `ParentNode-prepend`: 100 %.
- El juego real sigue arrancando (`game_boot_test` en verde) y los **298 tests**
  pasan.
- CSS sigue en 10,38 %: sus FAIL necesitan `offsetWidth`/layout, no más API DOM.


## Sesión 18 — MutationObserver, colecciones y atributos con namespace

- WPT `dom/nodes`: 31,82 % → **44,88 %** (127 PASS / 154 FAIL / 44 SKIP / 2 ERROR).
- Los diez archivos `MutationObserver-*.html` pasan al 100 %: entrega en
  microtask QuickJS (no Dart), opciones `attributeOldValue`/
  `characterDataOldValue`, registros múltiples, `takeRecords`, childList
  fragmentado, `textContent`, `innerHTML`/`outerHTML` y callbacks.
- `HTMLCollection` independiente de `NodeList`, con índices, propiedades
  nombradas y `item()` WebIDL; `NodeList` usa `Array.prototype` para iterar.
- Atributos con namespace/prefix: `attributeEntries`, `getAttributeNS`,
  `setAttributeNS`, `removeAttributeNS`, `Attr.prefix` y mutaciones con
  `attributeNamespace`.
- `Document.importNode` adopta el clon al documento destino; constantes de
  `Node`; `isEqualNode`/`isSameNode`; `outerHTML`; `createTreeWalker`;
  `createDocumentType` y `DOMImplementation.createHTMLDocument`.
- Corregido el testharness del runner: `async_test(name)`, `add_cleanup`,
  `step_func`, `step_func_done` y `unreached_func`.
- `iframe.contentDocument`/`contentWindow` y `window.frames` básicos, con
  `load` y detección de tipo por URL.
- Suite completa: **298 tests en verde**; el juego real sigue arrancando.


## Sesión 20 — juego real jugable

- Corregido el bug de constraints de `RenderCssBox`: `constraints.enforce(wanted)`
  clampaba en la dirección equivocada y devolvía 800×800 bajo un máximo de 60.
  Ahora es `wanted.enforce(constraints)`.
- `game_play_test` ya no está skipped: pulsa Start con tap real, espera
  `loading-screen` fuera, comprueba frames GL y valida una captura con más de
  6 bandas de luminancia.
- `./tools/test_all.sh`: **299 tests**, todos en verde.
- WPT `dom/nodes`: **58,30 %** (165 PASS / 118 FAIL / 44 SKIP).
- Rendimiento JS: pausado en fase 19; baseline steady-state 7,58× más lento que
  V8 y auditoría en `docs/performance-audit.md`.

## Sesión 21 — checkpoint estable y métricas de presentación (Fase 0)

- Se añadió `MetricsOverlay` (`examples/game-player/lib/metrics_overlay.dart`)
  con percentiles p50/p95/p99 de build/raster/total, intervalos de presentación
  y decode, jank > 50 ms y salida JSONL cada 2 s. Es **opt-in** con
  `NATIVAX_METRICS=1` o `NATIVAX_METRICS_FILE`; el juego normal queda limpio.
- `GlSurfaces` conserva una ventana móvil de 240 intervalos y latencias de
  decode y expone los percentiles. Test nuevo:
  `packages/nativax_js/test/gl_stats_test.dart`.
- `tools/summarize_metrics.py` agrupa por corrida/condición y soporta
  `--skip`, `--last` y `--buffer`; no usa el promedio de FPS como criterio.
- `tools/bench_game_player.sh` lanza una corrida release con ventana fija,
  autostart y metrics.
- `NATIVAX_FIXED_WINDOW=1` (solo benchmark) fija la ventana a 1280×720; sin el
  flag el reproductor sigue siendo redimensionable.
- `./tools/test_all.sh` ahora omite ejemplos sin `test/` en lugar de fallar por
  “Test directory not found”.
- Línea base preliminar a 1280×720/DPR 1.0: render 34,7–42,6 fps, shown
  26,3–29,1 fps, UI 32–34 fps, present p95 67–74 ms, decode p95 35–37 ms,
  build p95 2,9 ms, raster p95 15,1 ms, jank ~1,2 %. **No se alcanza** el
  objetivo de 45 fps/p95 ≤ 25 ms.
- El A/B de `backdrop-filter` no es válido: la ventana cambió durante la
  corrida exploratoria. Se guarda como evidencia, no como comparación.
- **No se implementó la Fase 1** (textura nativa). Se dejó el camino estable
  actual y se guardó el progreso por indicación del usuario.
- `./tools/test_all.sh`: **301 tests**, todos en verde (juego cerrado).
