# Spike: adaptar quickjs-jit (Longbridge) a NativaX

Fecha: 2026-10-22. Estado: **spike de viabilidad**, no integrado.

## Qué se probó

1. Toolchain Rust instalado de forma aislada en `/tmp/opencode` (rustc 1.99.1,
   cargo 1.99.1). No se añadió al proyecto.
2. Clon de `longbridge/rquickjs` (workspace `quickjs-jit` 0.12.11) y submódulo
   `quickjs-ng` `fd0a021`.
3. `cargo build -p quickjs-jit-sys --features jit-abi`: **OK**.
   Genera QuickJS-ng parcheado con la ABI JIT versionada (`quickjs-jit.h`).
4. `cargo build -p quickjs-jit-runtime --features compiler`: **OK**.
   Genera el runtime JIT Rust (Cranelift + tiering).

## Por qué no es drop-in

- El JIT no vive en la API C pública de QuickJS: es un runtime Rust
  (`quickjs-jit-runtime`) que implementa callbacks de la ABI `JSJit*`.
- Nuestro bridge (`src/nativax_bridge.c`) y `nativa_dom_bindings` usan la API C
  de QuickJS-ng directamente. Para usar el JIT hay que:
  1. Construir `quickjs-jit` como librería (Rust) y exponer una **API C**
     equivalente a `nx_*`, o reescribir el bridge con `rquickjs`.
  2. Inicializar el runtime JIT y enlazarlo con el `JSRuntime`/`JSContext`.
  3. Sustituir el QuickJS-ng vendorizado por el parcheado (misma versión de ABI).
  4. Mantener iOS sin JIT (fallback al intérprete).
- Tamaño esperado: +3.7 MB (1.7 → 5.4 MB), dentro del presupuesto de 10 MB.
- Riesgo: ABI interna versionada; mezclar versiones falla en runtime.

## Opciones de integración

### A. Bridge Rust con `rquickjs` (recomendada si se adopta)
- Reescribir `nx_eval`, `nx_call`, `nx_run_jobs`, `nx_memory_used`, etc. en Rust.
- Mantener la fachada C para Dart FFI (`NxRuntime`, callbacks de host).
- Ventaja: usa el JIT ya implementado y su gestión de runtime.
- Coste: reescritura del bridge y de las partes que tocan `JSValue`.

### B. QuickJS-ng parcheado + runtime JIT desde C
- Enlazar el runtime Rust y llamar a su inicialización desde C.
- Requiere una API C del runtime (no existe pública) o un wrapper Rust.
- Más frágil que A; no recomendada.

## Estimación honesta

- Spike técnico: hecho (compila sys + runtime).
- Integración real: **semanas** de trabajo, con pruebas de conformidad,
  rendimiento y leaks.
- No es una tarea de una sesión; no se debe declarar "JIT adaptado" hasta tener
  benchmarks y `test_all` en verde con el motor nuevo.

## Decisión pendiente

- ¿Se adopta `quickjs-jit` como motor alternativo (Linux/Android) con fallback
  QuickJS-ng en iOS?
- ¿O se continúa el JIT propio sobre QuickJS-ng, que ya funciona para casos
  triviales y no rompe la ABI actual?
