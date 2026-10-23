# Plan: JIT para NativaJS (sin V8, <10 MB)

Fecha: 2026-10-21. Estado: **plan**, no implementado. Inspiración arquitectónica en V8
(Ignition/Maglev/TurboFan) y en `quickjs-jit` (Longbridge), pero **sin usar V8,
JavaScriptCore ni ningún motor externo**. El motor sigue siendo QuickJS-ng.

## 1. Objetivo y restricciones

- Añadir ejecución acelerada (JIT) a `nativa_js` (QuickJS-ng) para reducir el
  gap de 7,58× frente a V8 en steady-state (docs/performance-audit.md).
- **No usar V8, JSC ni un navegador.** Solo QuickJS-ng + código propio.
- Mantener `libnativax_quickjs.so` (stripped) **por debajo de 10 MB**.
  Línea base actual: **1,6 MB** stripped → presupuesto libre ≈ **8,4 MB**.
- Preservar compatibilidad iOS/entornos sin JIT: fallback a intérprete.
- No romper la frontera JS↔Dart (scripts solo reciben ids, escalares y JSON).
- Cada ganancia debe ser un commit medido (AGENTS.md).

## 2. Línea base actual

- Motor: QuickJS-ng 0.17.0, intérprete de bytecode, `DIRECT_DISPATCH=1`
  (computed goto), `-O3`, `NDEBUG`, `-fvisibility=hidden`.
- Binario stripped: 1,6 MB (incluye wasm3 + bridge + GL).
- Tests: 53 en `nativa_js`, Test262 97,93 %.
- Benchmarks steady: media geométrica 7,58× más lento que V8.

## 3. Estrategia: JIT por niveles (inspirada en V8, tamaño controlado)

V8 usa Ignition (baseline) + Maglev/TurboFan (optimizador). Para mantener
<10 MB se propone un enfoque incremental y reversible:

| Nivel | Nombre | Descripción | Coste tamaño estimado |
|---|---|---|---|
| L0 | Intérprete QuickJS (actual) | Sin cambios | 0 |
| L1 | **Baseline JIT (copy-and-patch / template)** | Compila bytecode a código nativo 1:1, sin optimización, con guards mínimos | +1,5–2,5 MB |
| L2 | **Feedback (type feedback + ICs)** | Inline caches de propiedades/llamadas en el intérprete y en L1 | +0,5–1 MB |
| L3 | **Optimizing JIT (opcional, tardío)** | Compilación especulativa con deoptimización; solo si L1+L2 no bastan | +3–5 MB |
| L4 | **W^X + deopt runtime** | Memoria ejecutable, metadatos de unwind, fallback seguro | +0,5 MB |

**Decisión clave:** no empezar por un optimizador (TurboFan-like). Empezar por
L1+L2 (estilo Maglev mínimo / V8 Sparkplug) que es donde está el mayor
retorno por byte. L3 solo si la medición lo exige.

## 4. Opciones de implementación evaluadas

### Opción A — Adoptar `quickjs-jit` (Rust + Cranelift)
- Pros: JIT real ya implementado, tiering, deopt, benchmarks publicados.
- Contras: Rust toolchain, +3,7 MB (1,7→5,4 MB), ABI interno de QuickJS
  versionado, iOS sin JIT, mantenimiento atado a Longbridge, reescribe el
  build hook y la frontera FFI.
- Veredicto: **descartada como base** por coste de mantenimiento y tamaño;
  puede servir de referencia de diseño.

### Opción B — JIT propio en C sobre QuickJS-ng (recomendada)
- Backend de codegen pequeño. Candidatos:
  - **copy-and-patch** (estilo V8 Sparkplug / LuaJIT? no): plantillas
    precompiladas por opcode, copiadas y parcheadas en runtime. Muy pequeño,
    rápido de implementar, buen ratio tamaño/velocidad.
  - **MIR** (C, ~? MB) como backend: más optimización, más tamaño.
  - **ensamblador propio** x86-64 + AArch64: máximo control y mínimo
    tamaño, mayor esfuerzo.
- Veredicto: **recomendada**. Empezar con copy-and-patch (L1), añadir
  feedback (L2), y evaluar MIR/optimizador solo si hace falta.

### Opción C — Solo optimizar el intérprete (Ruta A del audit)
- Superinstructions, PIC, inline caching, caché de bytecode. Sin JIT.
- Pros: mínimo riesgo, iOS compatible, sin memoria ejecutable.
- Contras: techo ~1× V8, no 7×.
- Veredicto: **prerrequisito** de cualquier JIT (los ICs se reutilizan).

## 5. Arquitectura propuesta

```
fuente JS
  → parser QuickJS (sin cambios)
  → bytecode QuickJS (sin cambios)
  → [NUEVO] Profiler de hotness (contador de llamadas/loops)
  → [NUEVO] L1 Baseline JIT: bytecode → código nativo (copy-and-patch)
  → [NUEVO] L2: type feedback + ICs compartidos con intérprete
  → ejecución nativa con guards → deopt al intérprete si falla
  → GC/refcount QuickJS sin cambios (el código nativo usa la ABI QuickJS)
```

Puntos de integración en QuickJS-ng (fork interno):
1. `JSFunction` / `JSFunctionBytecode`: añadir puntero `jit_code` y
   `jit_size` (como hace quickjs-jit).
2. `JS_CallInternal`: si `jit_code != NULL`, saltar a él; si no, intérprete.
3. Puntos de deoptimización: cada guard escribe el estado de vuelta al frame
   de QuickJS y retorna al intérprete.
4. Invalidación: al cambiar shapes/prototipos, marcar `jit_code = NULL`
   (o recompilar).

El código nativo generado **no gestiona memoria propia**: reutiliza `JSValue`,
refcount y GC de QuickJS. Esto mantiene el tamaño bajo y la semántica exacta.

## 6. Plataformas

- **Linux/Android/macOS/Windows (x86-64/ARM64):** JIT habilitado detrás de
  flag de build `NATIVAX_JIT=1`.
- **iOS:** JIT deshabilitado por política del OS; siempre intérprete.
- **Web/WASM:** fuera de alcance (NativaX no corre en web).

## 7. Seguridad (NativaShield)

- Memoria ejecutable solo W^X: `mmap(PROT_READ|PROT_WRITE)` → escribir →
  `mprotect(PROT_READ|PROT_EXEC)`. Nunca W+X simultáneo.
- Límite de tamaño de código compilado por función y global (evitar OOM).
- Timeout de compilación (no bloquear el hilo UI).
- El código compilado solo proviene del bytecode de QuickJS (no de entrada
  externa); no se acepta código nativo de scripts.
- Deoptimización segura: guard checks antes de cada operación especulativa.
- Auditoría: `tools/security` debe seguir 14 PASS / 0 FAIL.

## 8. Fases y entregables

### Fase 0 — Medición y scaffolding (completada 2026-10-21)

- [x] Integración de `jit_code` en `JSFunctionBytecode` (campo añadido, inicializado a
  NULL y liberado en `free_function_bytecode`).
- [x] Puntos de integración: `nx_jit_try_compile` se invoca al crear bytecode
  (compilador y lector de objetos). Resultado siempre NULL por ahora.
- [x] Exportación de `nx_jit_try_compile` / `nx_jit_free_code` en el scaffold.
- [x] Añadir flag de build `NATIVAX_JIT` (default off) en `hook/build.dart`.
- [x] Añadir `src/nativax_jit.{h,c}` (scaffold, no-op cuando el flag está off).
- [x] Medir tamaño base: 1.6 MB stripped con flag off y con flag on (sin diferencia).
- [x] Tests: 53/53 en `nativa_js` con flag off y con flag on.
- [ ] Crear `progress/jit-baseline.md` con binario size, Test262, benchmarks.
- Aceptación: build verde, 0 cambio de comportamiento. **Cumplida.**

### Fase 1 — Optimizar intérprete (Ruta A, sin JIT) (1–2 semanas)
- [ ] Superinstructions (`load_const`+`add`+`branch`, etc.).
- [ ] Inline caches de propiedades en bytecode (PIC mínimo).
- [ ] Caché de bytecode por fuente para `evaluate` repetido.
- Aceptación: ≥1,2× en `js_steady.function_calls` y `objects_properties`,
  Test262 sin regresión, tamaño sin cambio.

### Fase 2 — L1 Baseline JIT (iniciada 2026-10-21)

- [x] Backend inicial (x86-64 Linux): memoria ejecutable W^X (mmap + mprotect)
  para constantes; entradas C portables para `return undefined` y `return local0`.
- [x] Punto de llamada en `JS_CallInternal` (usado solo cuando `jit_code != NULL`).
- [x] Correctitud verificada: `f(){}` → null, `f(){return 42}` → 42,
  `f(){return 7}` → 7, `f(){var x=5; return x;}` → 5.
- [ ] Ampliar cobertura: aritmética, llamadas, propiedades, control de flujo,
  retorno de arg0 (pendiente de guard de argc).
- [ ] Port AArch64 (actualmente fallback al intérprete).
- [ ] Deoptimización y invalidación por shape change.
- [ ] Fork mínimo de QuickJS-ng: añadir `jit_code` a `JSFunction`.
- [ ] Generador de plantillas por opcode (x86-64 primero).
- [ ] Runtime de compilación con W^X y límites.
- [ ] Deopt a intérprete en cualquier guard fallido.
- [ ] Flag `NATIVAX_JIT=1` para habilitar.
- Aceptación: ≥2× en `arithmetic` y `function_calls` con JIT on; Test262
  97,93 % sin regresión; binario stripped <4 MB.

### Fase 3 — L2 Feedback + AArch64 (2–3 semanas)
- [ ] Type feedback compartido intérprete/JIT.
- [ ] Port a AArch64 (Android/macOS).
- [ ] Invalidación por shape change.
- Aceptación: ≥3× en benchmarks numéricos; tamaño <6 MB.

### Fase 4 — Evaluación de L3 (optimizador) (decisión)
- [ ] Solo si L1+L2 no alcanzan el objetivo de producto.
- [ ] Prototipo con MIR o ensamblador propio en un branch aislado.
- [ ] Medir tamaño y ganancia antes de integrar.
- Aceptación: ganancia ≥1,5× adicional sobre L2 y tamaño <10 MB.

### Fase 5 — Documentación y cierre
- [ ] Actualizar `docs/javascript-supported.md`, `docs/benchmarks.md`,
  `progress/status.md`, `progress/conformance.md`.
- [ ] Reporte de leaks con JIT on.
- [ ] Seguridad: 14 PASS / 0 FAIL.

## 9. Criterios de aceptación globales

- `./tools/test_all.sh`: 316+ tests en verde con JIT off y con JIT on.
- Test262: ≥97,93 % (sin regresión).
- html5lib/URL/WPT: sin regresión.
- Binario stripped: <10 MB (objetivo <6 MB tras Fase 3).
- Benchmarks: reportar ratios reales vs V8, no claims sin evidencia.
- Leaks: sin retención nueva (tools/leaks).
- Seguridad: 14 PASS / 0 FAIL / 1 SKIP.
- iOS: build con JIT off, intérprete intacto.

## 10. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Complejidad de fork de QuickJS-ng | Mantener el fork mínimo (solo `jit_code` + dispatch); upstream merge periódico |
| Deoptimización incorrecta → crashes | Guards exhaustivos + tests de fuzz + Test262 |
| Tamaño >10 MB | Medir en cada fase; L3 solo si cabe |
| iOS sin JIT | Flag off por defecto en iOS; intérprete intacto |
| Seguridad de memoria ejecutable | W^X + límites + auditoría |
| Rendimiento no mejora lo esperado | Fase 1 (Ruta A) ya da ganancia sin JIT; honestidad en docs |

## 11. Lo que NO se hará

- No usar V8, JSC, SpiderMonkey ni ningún motor externo.
- No reemplazar QuickJS-ng por `quickjs-jit` (Rust) en esta fase.
- No añadir JIT a wasm3 (fuera de alcance).
- No degradar el intérprete (el JIT es aditivo y opcional).

## 12. Siguiente paso recomendado

Empezar por **Fase 0 + Fase 1**: medir, añadir el flag y optimizar el
intérprete (superinstructions + ICs). Es el cambio de menor riesgo y mayor
retorno por byte, y deja el terreno preparado para L1. La Fase 2 (baseline
JIT) solo se inicia tras validar Fase 1 con benchmarks reales.
