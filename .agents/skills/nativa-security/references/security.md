# Security

## Threat model

NativaX executes HTML, CSS, and JavaScript that may be hostile. The runtime
trusts none of them.

| Asset | Risk | Mitigation |
|---|---|---|
| Process / UI | Infinite script or microtask loop | 10 s runtime budget per entry, 1,000,000 jobs per drain (engine config defaults: 1 s / 10,000) |
| Memory | Unbounded heap | 64 MiB QuickJS allocator limit by default; V8 terminates near its limit |
| Stack | Deep recursion | 256 KiB QuickJS stack limit by default; V8 does not enforce it |
| DOM | Huge tree | 100k nodes, depth 256 |
| HTML parser | Malformed input / infinite nodes | Node limits and error recovery |
| Storage | Unlimited quota | 5 MB of characters |
| Host | Internal details leaked to JS | Generic error responses |
| Events | Orphaned listeners | `RemovalAwareListener`, cleanup on unmount |

## JS ↔ Dart boundary

- Scripts see only numeric ids; never Dart objects.
- Arguments and results are validated and decoded from JSON.
- An unexpected host error is reported as `internal host error`, without a Dart
  stack or message.
- `app.invoke` is a sensitive surface: the app decides which handlers to
  register and must treat arguments as untrusted.

## What is not implemented (and therefore cannot be assumed)

- No OS-level sandbox: the engine runs in the app process.
- Logical isolation only: one engine runtime per document, all inside the same OS process.
- No CSP or origin policy.
- No guarantee that destructive workloads are safe without the configured
  limits. The QuickJS budget interrupts bytecode, not synchronous Dart host
  work. The current V8 path does not enforce the time/job/stack limits.
- External resources are policy-gated and denied by default; this is not a
  network sandbox.

## Current audit

The executable suite lives in `debug/engines/security`. The live Linux status is in
`progress/status.md`; the latest QuickJS-only audit reports 45 cases: 44 PASS,
0 FAIL, and 1 SKIP. It does not certify V8.
See `../../../docs/security/audit.md`, `../../../docs/security/threat-model.md`,
`../../../docs/security/test-plan.md`, and
`../../../docs/security/platform-matrix.md`.

## Contribution rules

1. Every new API exposed to JS needs type validation and limits.
2. Do not add APIs that can read host paths, environment variables, or memory.
3. `JavaScriptHostError` messages must be stable and contain no sensitive data.
4. Every new limit needs a security/abuse test.
