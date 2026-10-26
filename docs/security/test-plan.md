# Security test plan

## Objetivo

Comprobar empíricamente las fronteras de confianza de NativaX con límites
seguros y resultados reproducibles. No sustituye a una auditoría externa ni a
un sandbox del sistema operativo.

## Ejecución

```bash
cd debug/engines/security
dart run bin/security.dart run
dart run bin/security.dart run --only <caso>
dart run bin/security.dart run --list
```

Resultados: `benchmarks/security/*.json` y `*.md` (ignorados por git).

## Casos actuales

| ID | Categoría | Severidad | Qué prueba |
|---|---|---|---|
| `engine.host_globals` | sandbox | crítica | No hay globals de OS/FS/red/Dart |
| `bridge.raw_host_hardened` | bridge | alta | `__nx` eliminado en runtime |
| `events.programmatic_click_not_trusted` | eventos | alta | `click()` no es gesto |
| `events.programmatic_submit_not_trusted` | eventos | alta | `requestSubmit()` no es gesto |
| `xss.inner_html_does_not_execute` | XSS | crítica | `<script>`/`onerror` no ejecutan |
| `xss.javascript_url_not_executed` | XSS | alta | `javascript:` no ejecuta |
| `bridge.malformed_ids_are_contained` | bridge | alta | IDs falsos no corrompen |
| `sandbox.engine_isolation` | aislamiento | crítica | Engines separados |
| `limits.infinite_loop_interrupted` | DoS | alta | Timeout real |
| `limits.microtask_limit` | DoS | alta | Límite de microtareas |
| `limits.parser_input_limit` | DoS | media | Límite de entrada HTML |
| `storage.quota` | storage | media | Cuota de localStorage |
| `lifecycle.disposed_engine_rejects_calls` | lifecycle | alta | Uso tras dispose |
| `internal.callback_globals` | hardening | media | Globals internos (abierto) |
| `platform.flutter_resource_policy` | recursos | alta | Denegación en Flutter (SKIP CLI) |

## Límites aplicados

- Bucle infinito: presupuesto de 50 ms; se mide que termina.
- Microtareas: 100 jobs por drain.
- Parser HTML: 64 caracteres en la prueba de límite.
- Storage: 8 caracteres de cuota en la prueba.
- Timeout global de cada caso: la propia suite no ejecuta cargas sin límite.
- Los ataques destructivos de RAM/CPU no se ejecutan en CI.

## Cobertura pendiente

- Fuzzing de HTML/CSS/JS y del puente con semilla reproducible.
- Minimización automática de fallos.
- Pruebas de red local: redirecciones, loopback, DNS, TLS, MIME, tamaño.
- Pruebas de archivos/recursos externos y cancelación.
- Aislamiento entre documentos con IDs/handles cruzados a gran escala.
- Reentrancia host→JS→host y dispose durante callback.
- Pruebas de agotamiento de memoria y pila con procesos aislados.
- Android, iOS, Windows y macOS.
- SAST/SCA/licencias/secretos en CI.
- Pruebas de accesibilidad/entrada hostil.
- Pruebas de ciclo de vida del renderer Flutter (montaje/desmontaje).

## Criterio de PASS

Un `PASS` significa que **el ataque concreto ejecutado** no produjo el efecto no
autorizado. No significa que la categoría completa esté libre de
vulnerabilidades. Un `SKIP` no es una protección; un `FAIL` es un hallazgo.

## Integración CI

- `ci-fast`: suite de seguridad actual (15 casos) + tests.
- `ci-full`: fuzzing corto con semilla y comparación con baseline.
- `stress`/nightly: agotamiento controlado en proceso aislado.
- Un `FAIL`/`ERROR` de seguridad bloquea la publicación; un `SKIP` se revisa y
  se documenta.
