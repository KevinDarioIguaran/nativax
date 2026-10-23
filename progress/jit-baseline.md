# Baseline JIT — Fase 0

Fecha: 2026-10-21. Flag: `NATIVAX_JIT` (default off).

## Binario

- `libnativax_quickjs.so` stripped: **1,6 MB** (1 666 168 bytes) con flag off y on.
- Diferencia de tamaño por el scaffold: 0 bytes tras strip.

## Tests

- `nativa_js`: **54** tests en verde (53 previos + `jit_test.dart`).
- `./tools/test_all.sh`: **317** tests en verde, exit 0.
- `dart analyze`: sin issues.

## Disponibilidad

- `nativaJsJitAvailable`: `false` en builds por defecto; `true` solo con
  `NATIVAX_JIT=1`.
- `nativaJsJitInit()`: seguro, no-op cuando el backend no está compilado.
- `nativaJsJitCodeBytes`: 0 (sin backend todavía).

## Conformidad

- No se re-ejecutaron Test262/html5lib/URL/WPT en esta fase; el scaffold no
  toca el parser ni el intérprete, por lo que no se esperan cambios.
- Pendiente de medir en Fase 1/2.

## Siguiente paso

Fase 1 (optimización del intérprete) o Fase 2 (baseline JIT copy-and-patch),
según decisión de producto.
