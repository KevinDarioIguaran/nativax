# Familia Nativa

Nativa es la familia. NativaX es la plataforma; el resto son componentes con
una responsabilidad concreta. La regla es no crear paquetes vacíos ni duplicar
fachadas: un nombre se convierte en paquete cuando tiene API pública, tests y
un ciclo de desarrollo propio.

## Mapa de proyectos

```
NATIVA
├── NativaX       Plataforma multiplataforma
├── NativaJS      Motor JavaScript
├── NativaWeb     HTML, CSS, DOM y APIs web
├── NativaRender  Layout y renderizado Flutter
├── NativaFlow    Workers, concurrencia y mensajería
├── NativaForge   Toolchain, tests y conformidad
├── NativaShield  Seguridad, permisos y límites
└── NativaBench   Benchmarks y rendimiento
```

| Proyecto | Estado | Ubicación actual | Responsabilidad |
|---|---|---|---|
| **NativaX** | Activo | `packages/nativax` | Runtime público, `NativaXView`, carga de documentos, ciclo de vida y workers |
| **NativaJS** | Activo | `packages/nativa_js` | QuickJS-ng, puente C/FFI, timers, WebAssembly (wasm3), límites y puente WebGL |
| **NativaWeb** | Activo, modular | `packages/nativa_html`, `nativa_dom`, `nativa_css`, `nativa_dom_bindings` | HTML, DOM, CSS y APIs de navegador expuestas a JavaScript |
| **NativaRender** | Activo | `packages/nativa_render` | Layout CSS, composición y widgets Flutter; consume el puente gráfico de NativaJS |
| **NativaFlow** | Embebido | `packages/nativax/lib/src/workers.dart`, `nativa_dom_bindings/lib/src/worker_runtime.dart` | Workers, mensajería y planificación de trabajo |
| **NativaForge** | Activo | `tools/` | Tests, conformidad, empaquetado y herramientas de desarrollo |
| **NativaShield** | Activo | `debug/engines/security`, `SECURITY_*` | Aislamiento, permisos, límites de recursos y auditoría |
| **NativaBench** | Activo | `benchmarks/`, `debug/engines/microbenchmarks`, `debug/engines/memory` | Benchmarks reproducibles de ejecución, FPS, latencia, memoria y conformidad |

## NativaWeb no es un paquete monolítico

NativaWeb es la familia de cuatro módulos independientes. Cada uno tiene su
propio `pubspec.yaml`, tests y límites:

| Paquete | Responsabilidad |
|---|---|
| `nativa_html` | Tokenizer y tree builder HTML |
| `nativa_dom` | Árbol DOM, eventos, selectores, mutaciones y serialización |
| `nativa_css` | Tokenizer, parser, cascada, media queries y estilos computados |
| `nativa_dom_bindings` | DOM y APIs de navegador expuestas al motor JavaScript |

No hay un paquete `nativa_web` de fachada: duplicaría dependencias sin aportar
una API propia. Las aplicaciones que necesiten la plataforma web completa
pueden depender de los módulos que usen, o de `nativax` para el runtime público.

## Nombres y convenciones

- La familia se llama **Nativa**.
- La plataforma principal conserva el nombre **NativaX** y el paquete Dart
  `nativax` para no romper la API pública.
- Los paquetes internos usan `snake_case` con prefijo `nativa_`:
  `nativa_js`, `nativa_html`, `nativa_dom`, `nativa_css`,
  `nativa_dom_bindings`, `nativa_render`.
- Los nombres de producto usan `CamelCase`: NativaJS, NativaWeb, NativaRender,
  NativaFlow, NativaForge, NativaShield, NativaBench.
- Los símbolos nativos heredados (`nativax_bridge`, `nativax_gl`, etc.) se
  conservan para no romper el ABI mientras dure la transición; no son nombres
  de producto.

## Migración aplicada

| Antes | Ahora |
|---|---|
| `packages/nativax_js` | `packages/nativa_js` |
| `packages/nativax_html` | `packages/nativa_html` |
| `packages/nativax_dom` | `packages/nativa_dom` |
| `packages/nativax_css` | `packages/nativa_css` |
| `packages/nativax_dom_bindings` | `packages/nativa_dom_bindings` |
| `packages/nativax_flutter` | `packages/nativa_render` |
| `packages/nativax` | `packages/nativax` (sin cambio) |

## Criterios para extraer un proyecto

Un nombre pasa a ser paquete independiente cuando cumple al menos tres de
estos puntos:

1. Tiene una API pública estable y documentada.
2. Tiene tests propios que no dependen del runtime completo.
3. Puede versionarse y publicarse por separado.
4. Su extracción reduce dependencias, no las multiplica.
5. Existe un consumidor claro fuera de NativaX.

NativaFlow, NativaForge, NativaShield y NativaBench conservan hoy su código en
las áreas existentes. Se extraerán cuando sus límites estén claros; mientras
tanto, sus nombres identifican responsabilidades, no paquetes ficticios.
