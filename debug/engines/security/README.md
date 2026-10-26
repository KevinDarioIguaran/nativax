# Security suite

Probes the host/JS trust boundaries with bounded attack cases. It is not an OS
sandbox and does not prove the runtime “secure”.

```bash
cd debug/engines/security
dart run bin/security.dart run
dart run bin/security.dart run --list
dart run bin/security.dart run --only bridge
```

Outputs (gitignored): `debug/benchmarks/security/<run_id>/` with JSON,
Markdown, and `manifest.json`.

## Latest recorded result

`debug/benchmarks/security/20261026T024956Z-f47240e/`:

| PASS | FAIL | SKIP | ERROR | Total |
|---:|---:|---:|---:|---:|
| 44 | 0 | 1 | 0 | 45 |

The SKIP is `platform.flutter_resource_policy` (Flutter-only). The suite runs
QuickJS, not V8.

Coverage includes host globals, raw bridge hardening, trusted events,
`innerHTML`/`javascript:` XSS, forged ids, engine isolation, execution and
microtask limits, parser input, storage quota, disposal, and generated
global/URL/`innerHTML` matrices.

A PASS means the specific attack did not produce the unauthorized effect. A
SKIP is not protection. V8 time/job/stack limits are not enforced, so these
QuickJS limit results do not transfer to V8.

See:

- [`../../../docs/security/audit.md`](../../../docs/security/audit.md)
- [`../../../docs/security/threat-model.md`](../../../docs/security/threat-model.md)
- [`../../../docs/security/test-plan.md`](../../../docs/security/test-plan.md)
- [`../../../docs/security/platform-matrix.md`](../../../docs/security/platform-matrix.md)

## Tests

```bash
cd debug/engines/security
dart test
dart analyze
```
