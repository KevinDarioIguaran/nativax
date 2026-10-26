# Suite de seguridad

```bash
cd debug/engines/security
dart run bin/security.dart run
dart run bin/security.dart run --list
dart run bin/security.dart run --only bridge
```

Salidas en `benchmarks/security/` (JSON + Markdown, ignoradas por git).

## Estado real (Linux)

13 PASS, 1 FAIL, 1 SKIP.

- FAIL abierto: `internal.callback_globals` (`__nx_dispatch`,
  `__nx_eventDone`, `__nx_releaseListener` visibles en `globalThis`).
- SKIP: política de recursos Flutter, no ejecutable desde CLI pura.

Ver `../../docs/security/audit.md`, `../../docs/security/threat-model.md`,
`../../docs/security/test-plan.md` y `../../docs/security/platform-matrix.md`.

No se declara NativaX “100 % seguro”; un PASS solo cubre el ataque probado.
