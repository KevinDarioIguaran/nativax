# Fugas, retención y ciclo de vida

Suite para detectar crecimiento sostenido de memoria, listeners huérfanos,
timers pendientes, wrappers retenidos y ciclos de vida incompletos.

## Ejecutar

```bash
cd tools/leaks
dart run bin/leaks.dart run --profile quick
```

Perfiles:

| Perfil | Lotes | Iteraciones | Uso |
|---|---:|---:|---|
| `quick` | 5 | 2.000 | CI / smoke |
| `full` | 20 | 10.000 | revisión |
| `stress` | 60 | 50.000 | máquina dedicada |

```bash
# Un caso concreto
dart run bin/leaks.dart run --only dom.listener_churn

# Listar
dart run bin/leaks.dart run --list

# Comparar dos revisiones
dart run bin/leaks.dart compare \
  --baseline ../../benchmarks/leaks/baseline.json \
  --current ../../benchmarks/leaks/current.json
```

Salidas:

- `benchmarks/leaks/*.json`
- `benchmarks/leaks/*.jsonl` (una muestra por lote)
- `benchmarks/leaks/*.md`

## Protocolo

Cada caso:

1. Registra línea base (`batch 0`).
2. Ejecuta lotes de trabajo.
3. Libera referencias y solicita GC cuando el runtime lo permite.
4. Registra RSS, `maxRss`, heap QuickJS y contadores de recursos.
5. Compara tendencia, no una sola muestra.
6. Distingue `PASS`, `FAIL`, `SKIP`, `ERROR`, `INCONCLUSIVE`.

Controles:

- `control.release`: crea y destruye runtimes; debe liberar.
- `control.retained`: retiene runtimes a propósito; el detector debe verlo.
- `css.style_churn`: árbol estable con recálculo; debe hacer meseta.
- `dom.detached_listeners`: nodos desconectados con listeners; verifica que
  los wrappers/listeners no queden retenidos.

## Reglas

- Una subida de RSS **no** demuestra una fuga; puede ser allocator/GC.
- `FAIL` exige tendencia sostenida **y** evidencia de recursos o heap del
  motor. Si no, `INCONCLUSIVE`.
- `ProcessInfo.currentRss` incluye Dart, QuickJS, Flutter y allocator; no es
  “heap vivo”.
- El `FAIL` de `dom.detached_listeners` llevó a corregir `node.release` para
  liberar listeners al soltar el wrapper JS.
- Los escenarios peligrosos tienen límites; el perfil `stress` no es CI.

## Limitaciones

- No hay API pública para inspeccionar todos los mapas internos de Dart o
  Flutter; se usan contadores y RSS.
- El GC de Dart puede retener memoria aunque los objetos sean inalcanzables.
- Las pruebas de vistas Flutter requieren un harness de widgets; esta CLI mide
  DOM/JS/runtime, no frames.
- La memoria del renderer y los recursos de imagen se validan por separado en
  tests de widgets (pendiente de ampliar).
