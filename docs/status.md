# NativaX: estado de la sesión (2026-10-20)

> **Este archivo es histórico.** El estado vivo y actualizado está en
> [`progress/status.md`](progress/status.md) (sesión 19: 276 tests en los
> paquetes, WebGL/WebAssembly y juego real arrancando; B5 en curso).

> **Actualización de la sesión 2 (conformidad + fase 1).** El estado vivo está
> en [`progress/status.md`](progress/status.md); el histórico y los números en
> [`progress/`](progress/README.md); las normas de trabajo en
> [`.agents/`](.agents/README.md). Resumen: `nativa_render` ya compila y
> renderiza texto, cajas, bloque, flex, controles básicos y eventos
> JS→DOM→Flutter; el runtime público `NativaXView` ya carga documentos y un
> contador con estado en JS; las fases 2 y 3 están cerradas para el alcance 0.1
> (JS async/eventos/ciclo de vida y layout CSS con posición, listas,
> formularios, imágenes y responsive); hay 212 tests verdes y runners de conformidad para Test262,
> html5lib y WPT. La línea base es Test262 97,93 %, html5lib 96,95 %, WPT
> DOM/CSS todavía muy bajo y URL 0 % (API ausente). El texto de abajo es el
> resumen original de la sesión 1 y se conserva como referencia.

El prompt original completo está en
[`docs/idea.md`](idea.md). Este archivo resume lo que ya
existe, lo verificado y lo que falta, para retomar en otra sesión.

## Pedidos adicionales del usuario (durante la sesión)

1. Crear el proyecto en `~/Documents/nativax`, separado del repo Torah+ (`~/Documents/bible`).
2. Que el motor sea "tan rápido como C": QuickJS-ng compilado en C con `-O3`. Es un intérprete sin JIT (iOS no permite JIT). El costo principal está en el puente JS↔Dart (JSON por llamada). Hay que **medirlo con benchmarks y luego optimizarlo** (agrupar llamadas, cachés).
3. APIs "como si fuera un navegador", respaldadas por las capacidades nativas de Flutter: tema, idioma, etc. → **ya implementadas en la capa de bindings** (ver más abajo). Falta conectarlas a Flutter (`HostEnvironment`).

## Entorno verificado

- Flutter 3.47.0 / Dart 3.13.0, Linux desktop disponible (Debian 13, Wayland `:1`), clang/cmake/ninja/gtk3.
- Sin Android SDK ni iOS/macOS/Windows en esta máquina → esas plataformas aún **no verificadas**.
- Node v22 disponible (solo para `node --check` del preludio JS).

## Decisiones (pendiente escribirlas como ADR en docs/adr/)

- **Motor JS:** QuickJS-ng v0.17.0 (MIT), código vendorizado en `packages/nativa_js/third_party/quickjs` (solo las fuentes de la librería y su LICENSE), compilado por `hook/build.dart` con `native_toolchain_c` 0.19.5 (paquete *experimental* de labs.dart.dev, a documentar como riesgo). `flutter_js` y `flutter_qjs` se descartaron: `flutter_qjs` está abandonado (2022) y `flutter_js` usa motores distintos por plataforma.
- **Puente C propio** (`src/nativax_bridge.c/.h`): solo punteros, escalares y JSON. Evita el ABI de `JSValue`, que cambia entre 32 y 64 bits (NaN-boxing). Callback síncrono con `NativeCallable.isolateLocal`. Interrupción por presupuesto de tiempo, límite de memoria y de pila.
- **Monorepo:** pub workspaces (no melos). Raíz `pubspec.yaml` con `workspace:`.
- **Layout:** no hay paquete `nativax_layout` puro. La geometría vive en RenderObjects propios dentro de `nativa_render` (una sola fuente de verdad): `RenderCssBox`, `RenderCssBlock` y `RenderCssFlex`. El estilo calculado deja solo los `%` sin resolver, y el layout los resuelve contra el bloque contenedor que el padre escribe en `CssItemParentData`.
- **Parser HTML y CSS propios** (tokenizer + tree builder / CSS Syntax L3), sin regex sobre el markup.

## Paquetes y estado

| Paquete | Qué contiene | Tests |
|---|---|---|
| `nativa_js` | QuickJS FFI, `JavaScriptEngine`/`QuickJsEngine`, host functions `__nx.host`, `TimerHost` (setTimeout/Interval, queueMicrotask), `installConsole`, límites (tiempo, memoria, pila, microtareas) | **31 ✅** |
| `nativa_dom` | Node/Element/Text/Comment/Document/Fragment, selectores (L3 + `:not`, nth-*, atributos, combinadores, especificidad), eventos (captura/target/burbujeo, once, dedup, `RemovalAwareListener`), mutaciones, límites de nodos y profundidad, formularios (value/checked/select/radio), `click()` con comportamiento de activación (checkbox, submit, links → `onNavigate`), serializador | **34 ✅** |
| `nativa_html` | Tokenizer (estados WHATWG simplificados), entidades, raw text (script/style) y RCDATA, tree builder con html/head/body implícitos, cierre implícito de p/li/dd/dt/option, recuperación, errores con línea:col, límites, `parseFragment` | **38 ✅** |
| `nativa_css` | Tokenizer, parser con recuperación y warnings, ~70 longhands + shorthands, colores (148 nombres, hex, rgb, hsl), unidades, media queries (width/height/orientation/prefers-color-scheme/reduced-motion/resolution), `StyleEngine` (índice de reglas, capas UA/autor/inline/!important, herencia, `inherit`/`initial`/`unset`, blockificación, invalidación incremental), hoja UA | **30 ✅** |
| `nativa_dom_bindings` | Preludio JS (`prelude.dart`: Node/Element/Document/Event/CustomEvent/classList/style Proxy/dataset/on* handlers; WeakRef + FinalizationRegistry para liberar wrappers), `DomBindings` (≈70 ops del host), `HostEnvironment` y `StaticEnvironment`, `MemoryStorage`, `InlineStyle`. APIs tipo navegador: `window`, `navigator.language(s)`, `innerWidth/innerHeight/devicePixelRatio`, `matchMedia` con eventos `change`, `localStorage` con cuota, `nativax.theme` (brightness/colors/`setMode`) con el evento `nativax:themechange`, `languagechange`, `resize`, `nativax.invoke` (JS→Dart) y `postMessage` (Dart→JS) | **26 ✅** |
| `nativa_render` | **Fase 1 (sesión 2): compila y renderiza.** Layout de caja/bloque/flex, `NativaXDocumentView`, texto inline, controles básicos, gestos y 7 tests. **Falta:** posicionamiento absoluto/z-index, listas, tablas, foco/teclado, scroll por contenedor y notificaciones por dueño | — |
| `nativax` | **Fase 1 (sesión 2):** `NativaXRuntime`, `NativaXView`, `FlutterHostEnvironment` y 3 tests; falta carga desde assets y ejemplo ejecutable | — |

Total verificado (sesión 1): **159 tests en verde**; tras la sesión 7 (fase 4A en curso): **190 tests** (ejecutar `dart test` dentro de cada paquete puro).

## Plan del renderizador (diseño ya decidido, falta implementarlo)

- `NativaXDocumentView(document, styleEngine, imageResolver, onDiagnostic)`: escucha mutaciones → `styleEngine.handleMutation` + nodos sucios → en lote (microtask) `recompute()` → señal (`ValueNotifier`) por "dueño" del nodo (el ancestro que se dibuja como widget propio; los inline van como spans dentro del párrafo del bloque). En cambios de estilo también se señala al dueño del padre y, si cambia `position`, al bloque contenedor.
- `_NodeView(element, mode)` con modo `block | flex | inline | positioned | root`. El modo decide el wrapper: `CssItem` (márgenes y flex) para bloque/flex, `Padding` para inline (WidgetSpan).
- Contenido: flex → `CssFlexLayout`. Bloque → si todos los hijos son inline, un `Text.rich`; si hay mezcla, `CssBlockFlow` con párrafos anónimos. `list-item` → marcador fuera del contenido (SizedBox de ancho 0 + OverflowBox). Caja → `CssBox(boxSpecFor(style))`.
- Inline: TextSpan anidados con colapso de espacios entre runs (`processWhiteSpace`), `<br>` → `\n`. Átomos (img, input, button, inline-block) → WidgetSpan. Links o inline con listeners → `TapGestureRecognizer` (se desechan en cada rebuild).
- Eventos: `GestureDetector(onTap: el.click())` en cada caja (gana el más interno y el DOM burbujea), con `excludeFromSemantics` en lo no interactivo. `Focus` → `document.setFocusedElement`, keydown/keyup con `detail.key`. `document.onFocusRequest` → `FocusNode` por elemento.
- Controles: TextField (`InputDecoration.collapsed`, controller por elemento, input/change/submit), Checkbox, radio pintado a mano (para evitar la API RadioGroup), DropdownButton para select, img con `ImageResolver` y `alt` en semantics. Requiere MaterialApp; si faltan MaterialLocalizations se inyectan las default.
- `position:absolute` → Stack del ancestro posicionado más cercano. `relative` → Transform.translate. z-index ordena los hijos del Stack.
- Raíz: LayoutBuilder (viewport → MediaContext para vw/vh y @media), SingleChildScrollView, color del canvas desde el fondo de html o de body.
- Accesibilidad: headers h1–h6, button, link, label de img, `aria-label`.

## Siguientes pasos priorizados

1. `nativa_render`: pubspec (flutter sdk + nativa_dom + nativa_css), renderizador, `flutter analyze` y widget tests (texto, cajas, flex, botón → evento, actualización reactiva, resize/@media, semantics).
2. ✅ (parcial, sesión 2) `nativax`: `NativaXRuntime` (carga desde string/asset/archivo con `ResourcePolicy`, ejecución de `<script>` inline en orden, `<style>` → authorSheets, `fireLoadEvents`, TimerHost + console + logger, dispose), `NativaXView(source:)`, `FlutterHostEnvironment` (MediaQuery, Theme, locales, plataforma) y `environmentChanged()` en cambios.
3. Ejemplos (`examples/counter`, hello, todo, forms) + `integration_test` en Linux (`flutter test -d linux`), y verificar que funciona `flutter build linux` con native assets.
4. Benchmarks (`debug/engines/microbenchmarks`): parsing, estilos, layout, costo por llamada del puente JS↔Dart → optimizar el puente.
5. Docs: README, architecture, compatibility (matriz real: solo Linux verificable aquí), html/css/javascript-supported, security-model, api-reference, troubleshooting, ADRs, CHANGELOG, LICENSE y licencias de terceros.
6. Fuera de esta máquina: Android/iOS/Windows/macOS (MSVC: QuickJS-ng necesita `/experimental:c11atomics`, ya está en el hook pero sin probar).

## Limitaciones conocidas a documentar

Sin colapso de márgenes padre/hijo, sin `align-content`, `baseline` → flex-start, sin clamp de max-size en items flex, el min automático en columnas es 0, `flex-basis` px se trata como border-box, los bordes dashed/dotted se dibujan sólidos (con diagnóstico), radio + colores de borde distintos → color uniforme, `position:absolute` relativo al content box, el contenido desbordado no recibe hit-test, sin `fixed`/`sticky`/grid/transform/animaciones/`calc`/`var`, los scripts de `innerHTML` no se ejecutan, eventos `:hover` no soportados, el JS corre en el hilo de UI (limitado por presupuesto).
