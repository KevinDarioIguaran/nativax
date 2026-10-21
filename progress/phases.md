# Fases

## Fase 0 — Investigación técnica 🟢

- [x] Elegir motor JS (QuickJS-ng vendorizado, sin JIT).
- [x] Verificar Flutter/Dart/Linux, clang, cmake, ninja, GTK.
- [x] Evaluar `flutter_js`/`flutter_qjs` y descartarlos con motivo.
- [x] Definir el puente C (solo escalares/JSON).
- [x] Verificar native assets en `flutter build linux`.

## Fase 1 — Esqueleto funcional 🟡

- [x] Paquetes puros: js, dom, html, css, bindings.
- [x] `nativax_flutter` compila (pubspec + entrypoint).
- [x] Renderer de texto, cajas, bloque y flex.
- [x] Mutaciones DOM → reconstrucción de UI.
- [x] Click Flutter → `Element.click()` → listener JS.
- [x] Controles básicos: input texto, textarea, checkbox, select, img.
- [x] Tests de widget + integración JS.
- [x] Paquete público `nativax` (`NativaXRuntime`, `NativaXView`).
- [x] `FlutterHostEnvironment` (MediaQuery, Theme, locale).
- [x] Carga de documentos desde string (asset/archivo pendiente).
- [x] Ejemplo `counter` como test widget end-to-end (app ejecutable pendiente).
- [ ] Posicionamiento absoluto, z-index, listas.
- [ ] Foco/teclado y `document.onFocusRequest`.
- [ ] Renderer por “dueño” (notificadores granulares) en lugar de rebuild
  global.

## Fase 2 — JavaScript funcional ✅ (alcance 0.1)

- [x] QuickJS-ng + FFI + límites.
- [x] Timers, microtareas, consola.
- [x] DOM bindings, eventos, `nativax.invoke`.
- [x] APIs de navegador básicas (window, navigator, matchMedia, storage,
  theme).
- [x] Event loop documentado (`docs/javascript-supported.md`).
- [x] Pruebas de ciclo de vida, timers, async/await, microtareas, recursos
  externos, consola y errores de script.
- [x] Ejemplo interactivo (`examples/counter`) + test.
- [x] Conformidad Test262 (97,93 % del subconjunto).
- Fuera de alcance 0.1 (fase 4): módulos ES, `URL`/`URLSearchParams`,
  `fetch`, Web Workers, Canvas.

## Fase 3 — Layout y CSS ✅ (alcance 0.1)

- [x] Caja: padding, borde, fondo, radios, clip.
- [x] Bloque: flujo, auto-width, `margin:auto`, colapso entre hermanos.
- [x] Flex: grow/shrink, wrap, gap, justify, align, auto márgenes.
- [x] Texto inline: `TextSpan`, `white-space`, `text-transform`, enlaces.
- [x] Unidades y porcentajes con bloque contenedor.
- [x] `position: relative/absolute`, offsets y `z-index` básico.
- [x] Listas (`disc`, `circle`, `square`, `decimal`, `ol[start]`, `li[value]`).
- [x] Overflow `auto`/`scroll` por contenedor.
- [x] Labels que activan su control; tipografía y `text-transform`.
- [x] Imágenes con resolver, `alt` y `object-fit`.
- [x] Tests de responsive (`@media`, `vw`) y resize.
- [x] Conformidad html5lib tokenizer (96,95 %).
- Pendiente fuera de alcance: `align-content`, baseline, `order`, clamp de
  max-size, grid, `fixed`/`sticky`, tablas, `opacity`, `transform` CSS.
- [ ] Conformidad tree construction (30,49 %; gaps de parser).

## Fase 4 — APIs y robustez (ABIERTA)

Objetivo de salida: **70 % en Test262, html5lib, URL, WPT DOM/CSS y tree
construction**. Se divide en subfases para no mezclar parser, selectores y
DOM en un solo bloque.

### 4A — HTML tree construction (en curso)

Objetivo: 70 % en WPT tree construction.

- [x] Nodos `DocumentType` en DOM, parser, serializador y bindings.
- [x] Parseo de `DOCTYPE` con public/system id (básico).
- [x] Tratamiento de `<?...>` como comentario/PI equivalente.
- [x] `<template>` en head y contenido dentro del template.
- [ ] `DocumentType` canónico y quirks mode.
- [ ] Adoption agency (formato mal anidado).
- [ ] Foster parenting y tablas (`tbody` implícito).
- [ ] `<template>` como content fragment real.
- [ ] Foreign content (SVG/MathML).
- [ ] Resultado: 38,53 % actual; objetivo 70 %.

### 4B — CSS selectors y CSSOM

Objetivo: 70 % en WPT `css/selectors`.

- [x] `:is()`, `:where()` básicos; `:scope` solo raíz.
- [ ] `:scope` con contexto de consulta.
- [x] `:has()` con argumentos relativos básicos.
- [x] `:dir()`, `:lang()`, `:heading()` básicos.
- [x] `:focus`, `:focus-visible`, `:focus-within` (aproximación por activeElement).
- [x] `:nth-child(An+B of S)` básico; [ ] namespaces en selectores.
- [x] CSSOM básico: `document.styleSheets`, `insertRule`/`deleteRule`,
  `cssRules`, `selectorText`, `rule.style` y reparse de `<style>`.
- [ ] CSSOM completo: `@media`, `@import`, hojas enlazadas y normalización.
- [ ] `getComputedStyle`.
- [ ] Shadow DOM, `customElements`, `::part`.
- [ ] Resultado: 4,37 % actual; objetivo 70 %.

### 4C — DOM APIs

Objetivo: 70 % en WPT `dom/nodes`.

- [x] `CharacterData`, `ChildNode`, `Node.isEqualNode/normalize`.
- [x] `createElementNS` básico y atributos con namespace básico.
- [ ] Namespaces completos (`namespaceURI`, `prefix`, `localName`).
- [ ] `DocumentType`, `Attr`, `ProcessingInstruction` completos.
- [ ] `DOMParser`.
- [ ] `MutationObserver`.
- [ ] `compareDocumentPosition`, `Range`, `TreeWalker`.
- [ ] Constructores `new Document()`, `new Text()` completos.
- [ ] Resultado: 19,11 % actual; objetivo 70 %.

### 4D — URL hardening

Objetivo: mantener ≥70 % y acercarse a 85 %.

- [x] `URL`/`URLSearchParams`, esquemas especiales, puertos, IPv4.
- [ ] IDN/punycode.
- [ ] IPv6 canónico.
- [ ] File URLs y normalización fina.
- [ ] Resultado: 70,98 % actual.

### 4E — WebAssembly ✅ (B4)

Objetivo de B4: ejecutar el WebAssembly real del juego (Rapier) dentro de
NativaX.

- [x] wasm3 vendorizado (commit `28ecb9a`, MIT) y compilado por el hook.
- [x] `WebAssembly.Module/Instance/Memory`, `compile`, `instantiate`,
  `instantiateStreaming`, `validate`.
- [x] Imports `(module, name)`, incluidas 32 funciones de wasm-bindgen.
- [x] `i64` ↔ `BigInt`, múltiples resultados y memoria lineal viva.
- [x] `memory.grow` con detach del ArrayBuffer y refresco de vistas.
- [x] Presupuesto de gas por llamada (500 M) y límite de memoria (512 MB).
- [x] Rapier 0.19.3: mundo, cuerpos, colliders, 180 pasos y raycast,
  en UI y en worker con su propio runtime.
- [x] Worker real del juego (bundle Vite + Comlink + SAB): 103 cuerpos a
  ~45 Hz, jugador con raycast y flags `GROUNDED`.
- [ ] Memoria/tabla/global importadas y exportaciones de tabla/global.
- [ ] SIMD, hilos/atomics dentro de wasm.

### B5 — Juego real completo (en curso)

Objetivo: cargar `examples/threejs-multiplayer-starter/dist` sin modificarlo y
poder jugar.

- [x] Arranque del bundle de producción (Vite), CSS, assets y 3 workers.
- [x] `Shadow DOM` mínimo (fachada sobre light DOM) para loading-screen y UI.
- [x] `AudioContext` silencioso: three.js construye su grafo; decodificación
  de audio aún no disponible.
- [x] `location.origin` correcto para `app://local` en workers.
- [x] `MutationObserver` conserva nodos eliminados hasta entregar el record.
- [x] Rapier real: heightfield, 103 cuerpos ~45 Hz, jugador con raycast.
- [x] El juego llega a "Ready!" y muestra `button.start-button.visible`.
- [x] Canvas `#webgl` con `position: fixed` a pantalla completa: constraints correctos.
- [x] Tap real en Start, frame presentado en la superficie y captura jugable.
- [ ] Input de juego (WASD/space/click), audio real y prueba visual final.

## Fase 5 — Juego real completo (B5)

Objetivo: cargar `examples/threejs-multiplayer-starter/dist` sin modificarlo y
poder jugar en Linux.

- [x] Arranque del bundle de producción (Vite), CSS, assets y 3 workers.
- [x] `Shadow DOM` mínimo (fachada sobre light DOM) para loading-screen y UI.
- [x] `AudioContext` silencioso; decodificación real pendiente.
- [x] `location.origin` correcto para `app://local` en workers.
- [x] `MutationObserver` conserva nodos eliminados hasta entregar el record.
- [x] Rapier real: heightfield, 103 cuerpos ~45 Hz, jugador con raycast.
- [x] El juego llega a "Ready!" y muestra `button.start-button.visible`.
- [x] Canvas `#webgl` con `position: fixed` full-screen: constraints correctos.
- [x] Tap real en Start, frame en la superficie y captura jugable.
- [ ] Input WASD/space/click, audio real y prueba visual final.

## Fase 6 — Rendimiento medible

Objetivo: presupuestos reproducibles y un objetivo 7× sobre la línea base de
NativaX. **No** se promete 7× sobre V8 en JavaScript general: eso exige otro
motor con JIT y, aun así, V8 no se supera 7× con JS equivalente.

- [x] Línea base QuickJS-ng vs V8 (9 microbenchmarks, mediana ~7×).
- [x] Línea base Rapier: 180 pasos, V8 30,74 ms vs wasm3 328,54 ms (10,7×).
- [ ] Perfilar arranque, bridge, DOM, estilos, layout y frames del juego.
- [ ] Gate P1: **7× menos tiempo que la línea base NativaX** en cargas del
  juego (física, bridge y frame), no en un microbenchmark aislado.
- [ ] Gate P2: JS puro dentro de 1,2× de V8 en desktop/Android con adaptador
  V8; QuickJS sigue siendo el fallback iOS.
- [ ] Gate P3: operaciones nativas seleccionadas 7× más rápidas que su
  equivalente JS/V8 (no aplica a JS general).
- [ ] Benchmarks release/AOT, no sólo JIT de Dart.

## Fase 7 — WebAssembly de alto rendimiento

- [ ] Vendorizar WAMR (AOT + intérprete; JIT sólo donde esté permitido).
- [ ] Mantener wasm3 como fallback iOS sin JIT.
- [ ] Misma escena Rapier: ≤46,9 ms para 180 pasos (7× sobre wasm3).
- [ ] Comparar WAMR AOT/JIT contra V8 en la misma escena.
- [ ] Memoria/tabla/global importadas y exportaciones completas.
- [ ] SIMD y hilos/atomics de wasm donde la plataforma lo permita.

## Fase 8 — Estrategia de motores JavaScript

- [ ] Interfaz de motor estable con QuickJS-ng como implementación base.
- [ ] Adaptador V8 en Linux/Windows/Android (JIT permitido).
- [ ] Evaluar JavaScriptCore/LLInt en Apple sin JIT.
- [ ] Selección por plataforma y por política de la app.
- [ ] Criterio explícito: 7× sobre V8 sólo para cargas nativas/paralelas
  concretas; en JS general el objetivo es paridad práctica, no 7×.

## Fase 9 — Puente, memoria y cero copias

- [ ] Protocolo binario para operaciones calientes; JSON sólo en APIs frías.
- [ ] Lotes de mutaciones DOM y buffers reutilizados.
- [ ] Transferencia de typed arrays/ImageBitmap/OffscreenCanvas sin copia.
- [ ] Medir y reducir el coste por llamada JS↔Dart.
- [ ] Presupuesto: bridge trivial <5 µs y cargas grandes sin picos de GC.

## Fase 10 — DOM, CSS y layout de conformidad

- [ ] Cerrar Fase 4: Test262, html5lib, URL, WPT DOM, CSS selectors y tree
  construction ≥70 %, sin SKIP.
- [ ] Adoption agency, foster parenting, tablas y template real.
- [ ] CSSOM, `getComputedStyle` completo, Shadow DOM real y `createElementNS`.
- [ ] Layout: tablas, float, columnas, writing-mode, grid/subgrid y márgenes.
- [ ] Invalidación incremental y no reconstrucción global por mutación.

## Fase 11 — Renderer y compositing

- [ ] Renderer por “dueño” con notificadores granulares.
- [ ] Capas fixed/sticky/absolute, z-index y top layer completos.
- [ ] Texto: selección, fuentes web, RTL y shaping.
- [ ] Animaciones/transiciones sin recalcular todo el árbol.
- [ ] Frame budget de 16 ms con el juego real.

## Fase 12 — Canvas, WebGL y GPU

- [ ] WebGL 2 completo en Linux/Android; backend propio en Apple/Windows.
- [ ] Canvas 2D: `drawImage`, `getImageData`, `putImageData`, `toDataURL`.
- [ ] WebGPU o adaptador equivalente donde exista.
- [ ] Sincronización de superficies y worker rendering sin bloqueos.

## Fase 13 — Multimedia y audio

- [ ] Decodificación real de audio (MP3/OGG/WAV) y Web Audio con nodos.
- [ ] Vídeo por plataforma; sin pipeline en Linux como limitación declarada.
- [ ] `decodeAudioData`, `AudioBuffer`, `MediaElement` y sincronía A/V.

## Fase 14 — Workers, hilos y paralelismo

- [ ] `importScripts` síncrono, WebSocket en workers y módulos dinámicos.
- [ ] Interrupción nativa de workers ocupados.
- [ ] Transferencia de puertos, SAB y buffers entre isolates.
- [ ] Colas de trabajo para no bloquear la UI.

## Fase 15 — Seguridad y robustez

- [ ] Fuzzing de parser HTML/CSS/JS y wasm.
- [ ] Sandbox de red, filesystem y APIs nativas por política.
- [ ] Límites de memoria, gas, tiempo, nodos y workers auditados.
- [ ] Pruebas de leaks y cargas hostiles en CI.

## Fase 16 — Android

- [ ] Gradle/NDK, QuickJS, wasm3/WAMR y EGL.
- [ ] Empaquetado, tamaños, permisos, ciclo de vida y background.
- [ ] Tests en dispositivo/emulador.

## Fase 17 — iOS

- [ ] Sin JIT: QuickJS + WAMR AOT, pila y FFI seguras.
- [ ] EGL/Metal o backend gráfico propio.
- [ ] App Store, memoria, background y ciclo de vida.

## Fase 18 — Windows, macOS y Linux release

- [ ] MSVC `/experimental:c11atomics`, clang/macOS y packaging.
- [ ] Native assets reproducibles y matrices CI.
- [ ] Build release firmado y actualizaciones.

## Fase 19 — Herramientas y accesibilidad

- [ ] DevTools, inspector DOM, consola, red y perfiles.
- [ ] Hot reload estable y depuración de workers.
- [ ] Accesibilidad: roles, foco, teclado, lectores de pantalla.
- [ ] i18n, RTL, temas y fuentes del sistema.

## Fase 20 — Release 1.0

- [ ] Conformidad declarada y reproducible en todas las suites.
- [ ] Gates de rendimiento P1/P2/P3 aprobados o excepciones documentadas.
- [ ] Matriz real de plataformas y límites por plataforma.
- [ ] API congelada, versionado, LICENSE, terceros y migración.
- [ ] Release 1.0 sólo con evidencia; sin números inventados.
