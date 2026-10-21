# NativaX security audit

Fecha: 2026-10-20. Alcance: Linux x86_64, Dart JIT, QuickJS-ng 0.17.0, paquetes
`nativax_js`, `nativax_dom`, `nativax_dom_bindings`, `nativax_html`,
`nativax_css` y runtime público.

Este informe **no** declara que NativaX sea “100 % seguro” ni “a prueba de
exploits”. Recoge lo comprobado y lo que queda abierto.

## Resultado de la suite

Comando:

```bash
cd tools/security
dart run bin/security.dart run
```

Resultado real: **14 PASS, 0 FAIL, 1 SKIP, 0 ERROR** (15 casos).

- `internal.callback_globals` pasó a `PASS` al corregir S-04.
- `SKIP`: `platform.flutter_resource_policy` (requiere harness Flutter).
- JSON/Markdown en `benchmarks/security/` (ignorado por git).

## Hallazgos

### S-01 — Click y submit programáticos se marcaban como `isTrusted` (corregido)

- **Severidad:** alta (si la app usa `isTrusted` para exigir gesto real).
- **Causa:** `Element.click()` y `requestSubmit()` ponían `isTrusted = true`
  siempre.
- **Reproducción:** listener de click comprobaba `event.isTrusted` tras
  `button.click()`; era `true`.
- **Corrección:** `click({bool trusted = false})` y
  `requestSubmit({bool trusted = false})`. El renderer pasa `trusted: true`
  solo desde gestos reales. `el.click` del puente JS usa `trusted: false`.
- **Regresión:** `events.programmatic_click_not_trusted` y
  `events.programmatic_submit_not_trusted`.

### S-02 — El puente `__nx.host` quedaba accesible a scripts (corregido en runtime)

- **Severidad:** media.
- **Causa:** el preludio usaba `__nx.host` y lo dejaba en `globalThis`.
- **Impacto:** un script podía invocar operaciones internas por nombre
  (`node.release`, `style.*`, `app.invoke`, etc.). No otorgaba acceso a OS,
  pero ampliaba la superficie y permitía autodaño/DoS.
- **Corrección:** `DomBindings.harden()` elimina `__nx` después de instalar
  timers/console/DOM. Los preludios conservan la referencia en su closure.
  `NativaXRuntime` lo llama antes de ejecutar scripts.
- **Límite:** usuarios que usan `DomBindings` directamente deben llamar a
  `harden()` manualmente. Está documentado.
- **Regresión:** `bridge.raw_host_hardened`.

### S-03 — Listeners retenidos al liberar un wrapper (corregido)

- **Severidad:** media (retención/DoS).
- **Causa:** `node.release` eliminaba el target del mapa pero no sus listeners.
- **Corrección:** al liberar el wrapper se llama `removeAllEventListeners()`.
- **Regresión:** `dom.detached_listeners` de `tools/leaks`.

### S-04 — Callbacks internos `__nx_*` visibles en `globalThis` (corregido)

- **Severidad:** media.
- **Evidencia original:** tras `harden()`, `Object.getOwnPropertyNames(globalThis)`
  contenía `__nx_dispatch`, `__nx_eventDone`, `__nx_releaseListener`.
- **Impacto original:** un script podía forjar callbacks de evento, liberar
  listeners por id, disparar timers antes de tiempo y, con las APIs nuevas,
  falsificar respuestas de red o mensajes de WebSocket/Worker.
- **Corrección:** el puente C (`nativax_bridge.c`) guarda un registro privado
  de callbacks en `NxRuntime` (`__nx_register`, capturado y borrado por el
  preludio del host). `callGlobal` consulta primero ese registro. Los
  preludios registran ahí sus callbacks (`__nx_dispatch`, `__nx_fireTimer`,
  `__nx_async`, `__nx_ws`, `__nx_worker`, `__nx_mo`, `__nx_conn`, ...) y
  `harden()` elimina `__nx.register` junto con `__nx.host`.
- **Regresión:** `internal.callback_globals` (ahora verifica que no haya
  globals `__nx_*` y que no se puedan invocar).

### S-09 — APIs de plataforma añadidas (red, portapapeles, workers)

- **Red:** `fetch`, `XMLHttpRequest` y `WebSocket` pasan por
  `NativaXNetwork`; el valor por defecto (`DeniedNetwork`) lo deniega todo.
  `IoNetwork` exige una función `allow(Uri)` del host (lista blanca) y limita
  las respuestas a 32 MB.
- **Portapapeles y vibración:** requieren activación transitoria del usuario
  (gesto confiable en los últimos 5 s), como en los navegadores.
- **Workers:** cada uno es un motor QuickJS separado con presupuesto propio;
  máximo 16 por documento; solo URLs `blob:`/`data:` (sin red).
- **Presupuesto JS:** el runtime usa 10 s por tarea (antes 1 s) para no
  cortar páginas reales; una tarea larga sigue bloqueando la UI (ver S-06).
- **Identidad de wrappers:** los nodos conectados retienen su wrapper
  (antes podía recolectarse y perder estado); se liberan al desconectarse.

### S-05 — `javascript:` en navegación (abierto, bajo)

- **Severidad:** baja.
- **Evidencia:** `xss.javascript_url_not_executed` confirma que el código no se
  ejecuta; el `href` llega a `Document.onNavigate`.
- **Riesgo:** si la app usa ese href para abrir un navegador, WebView o
  ejecutar acciones, puede introducir XSS fuera de NativaX.
- **Remediación:** el host debe validar esquemas y destinos en `onNavigate`.
  Añadir una política de URL por defecto en una fase posterior.

### S-06 — Presupuesto JS no interrumpe trabajo Dart del host (residual)

- **Severidad:** media (DoS).
- **Causa:** el timeout de QuickJS interrumpe bytecode, no una llamada síncrona
  a un host function que esté ejecutando trabajo Dart pesado (por ejemplo
  `innerHTML` enorme o `app.invoke`).
- **Mitigación actual:** límites de entrada/nodos y responsabilidad del host.
- **Pendiente:** límites de tiempo para operaciones host, o ejecución en
  isolate/proceso aislado.

### S-07 — Sin sandbox del sistema operativo (arquitectura)

- NativaX ejecuta JS en el proceso de la app. Un fallo de QuickJS, FFI o del
  host puede afectar al proceso completo.
- **No se declara aislamiento OS.** Para contenido no confiable de terceros se
  requiere un proceso separado y permisos del sistema operativo.

### S-08 — Carga de recursos (no verificada en Flutter)

- `NativaXRuntime` usa `NativaXDenyAllResources` por defecto.
- La política real depende del `NativaXResourceLoader` que inyecte la app:
  validación de esquema, redirecciones, red privada, tamaño, TLS, etc.
- La prueba Flutter de denegación/cancelación queda **SKIP** en esta CLI.

## Controles verificados

- Sin `process`, `require`, `File`, `Platform`, `fetch`, `XMLHttpRequest`,
  `WebSocket`, `Deno`, `Bun`, `dart` ni `__nx_host` en scripts.
- `innerHTML`/`insertAdjacentHTML` no ejecutan scripts.
- IDs falsos producen excepción y el runtime sigue funcionando.
- Dos engines no comparten globals.
- Bucle infinito interrumpido (~51 ms con presupuesto de 50 ms).
- Límite de microtareas (`MicrotaskLimitError`).
- Límite de entrada del parser HTML.
- Cuota de `localStorage`.
- Engine dispuesto rechaza evaluación.
- Click/submit programáticos no son confiables; gestos del host sí.

## Riesgo residual

- S-05, S-06 y S-07 permanecen.
- No se ha probado Android, iOS, Windows ni macOS.
- No hay fuzzing de seguridad ni pruebas de red locales en esta iteración.
- No se ha auditado la cadena de suministro con SAST/SCA.

## Cómo reproducir

```bash
cd tools/security
dart run bin/security.dart run
dart run bin/security.dart run --only internal.callback_globals
```


Las correcciones tienen tests de regresión en la suite y en
`packages/nativax_dom/test`, `packages/nativax_dom_bindings/test` y
`tools/leaks`.
