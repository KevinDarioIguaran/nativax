# JavaScript soportado por NativaX

NativaX ejecuta JavaScript real con **QuickJS-ng**, sin navegador y sin JIT.
Esta página define el contrato: lo que existe, lo que no, y cómo se comporta el
event loop. No es una promesa de compatibilidad total con el navegador.

## Lenguaje

QuickJS-ng implementa ECMAScript moderno: variables, funciones, clases,
módulos internos, promesas, `async`/`await`, generadores, `Proxy`, `Reflect`,
`BigInt`, `Symbol`, expresiones regulares, `Map`/`Set`, etc.

Medición actual con Test262 (subconjunto de `language/*`): **97,93 %**
(19.577 / 21.098; 413 fallos, 1.108 SKIP). Ver
[`progress/conformance.md`](../progress/conformance.md).

### Diferencias conocidas

- Algunos errores tempranos de modo estricto no se rechazan como en V8.
- Decoradores y algunas propuestas recientes no están implementadas.
- No hay optimización de llamadas en cola (TCO): los tests correspondientes se
  saltan para no agotar la pila nativa.

## APIs disponibles

### Consola

```js
console.log('texto', {a: 1});
console.warn('aviso');
console.error('error');
```

El host recibe `ConsoleMessage` mediante `NativaXRuntimeConfig.onConsole`.
Los valores se serializan a texto.

### Temporizadores y microtareas

```js
setTimeout(fn, 100);
clearTimeout(id);
setInterval(fn, 100);
clearInterval(id);
queueMicrotask(fn);
```

- Se implementan con `Timer` de Dart; no bloquean el hilo.
- `setInterval` se limita a un mínimo de 4 ms y 1.000 temporizadores activos
  por runtime.
- `queueMicrotask` usa la cola de promesas de QuickJS.

### DOM

- Nodos, `querySelector*`, `getElementBy*`, `closest`, `matches`,
  `create*`, inserción/eliminación (`append`, `before`, `replaceWith`, ...),
  `innerHTML`/`outerHTML` (lectura y escritura), `insertAdjacentHTML`,
  `textContent`, `innerText`, `attributes`, `classList`, `style`,
  `dataset`, `compareDocumentPosition`, `TreeWalker`, `NodeIterator`.
- Interfaces por etiqueta (`HTMLInputElement`, `HTMLDialogElement`,
  `SVGElement`, ...) para `instanceof`. La identidad de los wrappers se
  conserva mientras el nodo está conectado (las propiedades que guarda el
  script no se pierden).
- Eventos con captura, burbujeo, `once`, `signal`, `composedPath`, y las
  clases `MouseEvent`, `PointerEvent`, `KeyboardEvent`, `FocusEvent`,
  `InputEvent`, `SubmitEvent`, `DragEvent`, `ErrorEvent`, `MessageEvent`,
  `ProgressEvent`, `CloseEvent`, `HashChangeEvent`, `PopStateEvent`,
  `TransitionEvent`, `AnimationEvent`, ... Manejadores `on*` (propiedades y
  atributos HTML). Un error en un listener se reporta (evento `error` en
  `window`) y no detiene la página.
- Formularios: `form.elements` (con acceso por nombre y `RadioNodeList`),
  `FormData`, `validity`, `checkValidity`, `reportValidity`,
  `setCustomValidity`, `validationMessage`, `willValidate`,
  `requestSubmit`, `reset`, `valueAsNumber`, `valueAsDate`,
  `selectedOptions`, `labels`, `defaultValue`, ...
- `dialog` (`show`, `showModal`, `close`, `returnValue`), `details.open`,
  `customElements` (autónomos, con `observedAttributes` y callbacks de ciclo
  de vida), `DOMParser`, `XMLSerializer`, `Range`/`Selection` básicos.
- Geometría desde el renderer: `getBoundingClientRect`, `offset*`,
  `client*`, `scroll*`, `scrollIntoView`.
- `getComputedStyle` (también de pseudoelementos), `CSS.supports`,
  `CSS.escape`.
- Observadores: `MutationObserver` (real, en microtarea), `ResizeObserver` e
  `IntersectionObserver` (sondeo de layout por frame).

No hay Shadow DOM, CSSOM (`document.styleSheets`, `insertRule`) ni
`createElementNS` con namespaces completos.

### Ventana y navegador

- `location` (incluida navegación por `#fragmento` con `hashchange`,
  `:target` y scroll), `history` (`pushState`, `replaceState`, `back`,
  `popstate`).
- `performance` (`now`, `mark`, `measure`, entradas de navegación),
  `requestAnimationFrame`, `requestIdleCallback`.
- `crypto.getRandomValues`, `crypto.randomUUID`, `TextEncoder`,
  `TextDecoder`, `atob`, `btoa`, `structuredClone`.
- `localStorage` (memoria por defecto, o el `KeyValueStorage` del host),
  `sessionStorage`, `indexedDB` (en memoria: almacenes, índices, rangos,
  cursores y transacciones).
- `BroadcastChannel`, `MessageChannel`, `window.postMessage`.
- `Worker` dedicados: contexto QuickJS en su propio isolate (hilo) por
  defecto, con `SharedArrayBuffer`/`Atomics` y `MessagePort`; puede compartir
  un `<canvas>` vía `transferControlToOffscreen()`. `threadedWorkers: false`
  los ejecuta en el hilo de UI para depurar.
- `WebAssembly` 1.0/2.0 sobre wasm3 (intérprete C): `Module`, `Instance`,
  `Memory` exportada, `compile`, `instantiate`, `instantiateStreaming`,
  `validate`, módulos reutilizables, imports `(module, name)`, `i64` con
  `BigInt`, memoria lineal viva (detach al crecer) y presupuesto de gas por
  llamada. `Table` y `Global` existen como constructores, pero las
  exportaciones/importaciones de tabla y global todavía se rechazan (ver
  limitaciones). Rapier 0.19.3 corre en el worker de física real del juego;
  con 3 cuerpos mantiene ~57 Hz y con 103 cuerpos ~45 Hz en este equipo.
- `Intl` (`DateTimeFormat`, `NumberFormat`, `RelativeTimeFormat`,
  `PluralRules`, `ListFormat`, `Collator`, `Segmenter`) para es, en, pt, fr,
  de, it, y `toLocale*String`. QuickJS-ng no trae ICU: es una
  implementación propia de los casos comunes.
- `navigator`: `userAgent`, `platform`, `language(s)`, `onLine`,
  `hardwareConcurrency`, `permissions.query`, `storage.estimate`,
  `clipboard` y `vibrate` (si el host los ofrece; la vista Flutter los
  conecta al portapapeles y a la háptica).
- `screen`, `visualViewport`, `scrollX/Y`, `scrollTo`, `alert` (snackbar,
  no bloquea), `confirm`/`prompt` (devuelven `false`/`null`).
- Canvas 2D: rectángulos, caminos (`arc`, `ellipse`, curvas, `roundRect`,
  `Path2D`), `fill`/`stroke`/`clip`, gradientes, sombras, `globalAlpha`,
  modos de composición, transformaciones, `save`/`restore`, `setLineDash`,
  texto (`fillText`, `measureText`). Sin `drawImage` de `<img>`,
  `getImageData` (devuelve píxeles vacíos), `putImageData` ni `toDataURL`.

### Red

`fetch` (`Request`, `Response`, `Headers`, `AbortController`, cuerpos de
texto, JSON, `FormData`, `Blob`, `URLSearchParams`), `XMLHttpRequest`
(asíncrono) y `WebSocket` pasan por la política `NativaXNetwork` del host:
por defecto **todo se deniega** (como sin conexión). `IoNetwork(allow: ...)`
habilita peticiones reales con una lista blanca. Las URL `data:` y `blob:`
funcionan siempre. `Blob`, `File`, `FileReader` y `URL.createObjectURL`
están en el propio motor.

### Multimedia

`video`/`audio` no reproducen: `play()` se rechaza y se emite `error`
(`MEDIA_ERR_SRC_NOT_SUPPORTED`), como un navegador sin códecs.

### Módulos

`<script type="module">` se ejecuta después de los scripts clásicos, con un
grafo de imports precargado por `DocumentModules`; `import.meta.url` está
disponible. Los especificadores "bare" se rechazan como en Chrome.
`dynamic import`, `import attributes` y source-phase imports quedan fuera de
alcance de 0.1.

## Event loop

NativaX ejecuta el documento principal en el isolate de UI que creó el
runtime. Los `Worker` dedicados corren, por defecto, en su propio isolate
(hilo); `threadedWorkers: false` los trae al hilo de UI para depurar.

1. Una entrada de Dart (`evaluate`, un timer, un callback de evento, un
   mensaje del host) ejecuta el script de forma síncrona.
2. Al terminar la entrada, se drenan las microtareas (promesas,
   `queueMicrotask`).
3. Los `setTimeout`/`setInterval` vuelven al event loop de Dart y se ejecutan
   como una nueva entrada, con su propio presupuesto.
4. Una tarea (incluidas sus microtareas) que tarde más de 10 s se interrumpe
   con `JavaScriptTimeoutException`, como el aviso de "script lento" de un
   navegador; el presupuesto es configurable.

Consecuencias:

- Un bucle largo bloquea la UI (igual que en un navegador de un solo hilo).
- El orden entre temporizadores con el mismo deadline sigue el orden de Dart;
  no se garantiza el orden exacto del navegador.
- `requestAnimationFrame` corre a ~60 Hz sobre los temporizadores.
- No hay `setImmediate` ni `process.nextTick`.

## Errores y ciclo de vida

- Las excepciones de un script o de un listener se entregan a
  `NativaXRuntimeConfig.onScriptError`; un script que falla no cancela los
  siguientes, igual que en un navegador.
- Un error inesperado del host se convierte en un `Error` genérico para el
  script; no se filtran stacks ni rutas de Dart.
- `NativaXRuntime.dispose()` cancela timers, listeners y libera QuickJS y el
  DOM. No se puede usar el runtime después.
- El motor debe usarse desde el isolate que lo creó.

## Límites por defecto

| Límite | Valor |
|---|---|
| Memoria QuickJS | 64 MB |
| Pila | 256 KB |
| Presupuesto por tarea (runtime) | 10 s |
| Microtareas por drenado (runtime) | 1.000.000 |
| Workers simultáneos | 16 |
| Temporizadores activos | 1.000 |
| Nodos DOM | 100.000 |
| Profundidad DOM | 256 |
| `localStorage` | 5 MB de caracteres |
| Gas WebAssembly por llamada | 1.000 M unidades (el heightfield del juego usa ~542 M) |

### Límites de WebAssembly

- Faltan `memory`/`table`/`global` **importadas** y las exportaciones de tabla
  y global. Los módulos que las usan fallan con `LinkError` explícito.
- `Shadow DOM` es una fachada sobre light DOM: no hay scoping de CSS ni
  `slot`/`part`. Sirve para librerías que sólo usan `attachShadow` para
  aislar estilos y consultar su propio subárbol.
- `AudioContext` existe como grafo silencioso; `decodeAudioData` no decodifica
  MP3/OGG todavía. El juego usa audio opcional y sigue funcionando sin sonido.
- Sin SIMD (wasm3 lo parsea pero no ejecuta opcodes `v128`) ni hilos/atomics
  dentro de wasm. Los módulos que sólo declaran locales `v128` sí cargan.
- La validación de un módulo que importa memoria falla en `compile` porque
  wasm3 necesita un módulo proveedor; los módulos autocontenidos (Rapier,
  Emscripten `-s STANDALONE_WASM` sin imports de memoria) funcionan.
- El intérprete no usa JIT, por lo que es compatible con iOS; el coste es
  mayor que V8/WAMR con JIT. Rapier 0.19.3 ejecuta 180 pasos de física en
  ~1 s en este equipo (incluido el arranque de QuickJS y el glue).

## Mapa de conformidad

- **Test262**: lenguaje. Los módulos y APIs de host se saltan; las brechas
  reales se reportan como `FAIL`.
- **WPT**: DOM, selectores, HTML. El adaptador es “lite”: no ejecuta
  reftests, testdriver, workers ni el `testharness.js` completo.
- **html5lib-tests**: tokenizer.
- **WPT URL**: 70,98 %; el fixture se ejecuta contra el `URL` real de los
  bindings.
