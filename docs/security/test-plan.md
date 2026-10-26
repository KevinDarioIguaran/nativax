# Security test plan

## Objective

Empirically probe NativaX's trust boundaries with bounded, reproducible cases.
This does not replace an external audit or an OS sandbox.

## Run

```bash
cd debug/engines/security
dart run bin/security.dart run
dart run bin/security.dart run --list
dart run bin/security.dart run --only <case-id>
```

Results go to `debug/benchmarks/security/<run_id>/` as JSON, Markdown, and
`manifest.json`. The directory is gitignored; copy the run ID and counts into
the audit/status when citing it. The current suite is QuickJS-only.

## Core cases

| ID | Category | Severity | What it proves |
|---|---|---|---|
| `engine.host_globals` | sandbox | critical | No OS/FS/network/Dart globals |
| `bridge.raw_host_hardened` | bridge | high | `__nx.host` removed in the runtime |
| `events.programmatic_click_not_trusted` | events | high | `click()` is not a user gesture |
| `events.programmatic_submit_not_trusted` | events | high | `requestSubmit()` is not a gesture |
| `xss.inner_html_does_not_execute` | XSS | critical | Inserted `<script>`/handlers do not run |
| `xss.javascript_url_not_executed` | XSS | high | `javascript:` does not execute |
| `bridge.malformed_ids_are_contained` | bridge | high | Forged ids do not corrupt the runtime |
| `sandbox.engine_isolation` | isolation | critical | Separate engines have separate globals |
| `limits.infinite_loop_interrupted` | DoS | high | QuickJS execution budget interrupts a loop |
| `limits.microtask_limit` | DoS | high | Self-rescheduling microtasks hit a limit |
| `limits.parser_input_limit` | DoS | medium | Oversized HTML is rejected before tokenizing |
| `storage.quota` | storage | medium | `localStorage` enforces its quota |
| `lifecycle.disposed_engine_rejects_calls` | lifecycle | high | Evaluation after dispose throws |
| `internal.callback_globals` | hardening | medium | No reachable `__nx_*` internal callbacks |
| `platform.flutter_resource_policy` | resources | high | Flutter default-deny/cancellation (SKIP in CLI) |

## Generated matrices

The suite also generates cases from small matrices:

- global names (`process`, `require`, `fetch`, `XMLHttpRequest`, `WebSocket`,
  `Deno`, `Bun`, `dart`, `File`, `Directory`) must be undefined;
- navigation URL payloads (ten `matrix.url.*` cases) must not execute or kill
  the runtime;
- ten `innerHTML` payloads must not execute scripts/handlers or leave a payload
  behind.

Generated cases are still concrete attacks, not evidence that every encoding
or browser parser edge case was tried.

## Limits applied inside cases

- Infinite loop: a 50 ms test budget proves interruption; the production page
  default is 10 s.
- Microtasks: test limit of 100 jobs in one drain.
- Parser input: test limit of 64 chars; production default is 4 MiB.
- Storage: test quota of 8 chars; production default is 5 MB.
- Each case has its own suite timeout.
- Destructive RAM/CPU exhaustion is not run in CI or the quick suite.

These test limits are intentionally smaller than production so the suite stays
fast. Do not quote them as the runtime defaults.

## PASS semantics

A `PASS` means **the specific attack executed** did not produce the
unauthorized effect. A `SKIP` is not a protection; a `FAIL` is a finding; an
`ERROR` is not a pass.

## Coverage gaps

- No security fuzzing/minimization with a reproducible seed.
- No local-network tests for redirects, loopback, DNS, TLS, MIME sniffing, or
  response size.
- No external-resource cancellation test in this CLI (Flutter SKIP).
- No cross-document handle/id stress.
- No host→JS→host reentrancy or dispose-during-callback test.
- No memory/stack exhaustion in a separate process.
- No Android, iOS, Windows, or macOS run.
- No V8 security run; V8 time/job/stack limits are not enforced.
- No SAST/SCA/license/secret scan.
- No accessibility or hostile-input timing tests.
- No Flutter renderer mount/unmount security test.
- No OS sandbox or privilege-separation test.

## Intended gates

These are proposed, not a working CI workflow (the repository has no
`.github/workflows`):

- **fast:** current 45-case suite + focused unit tests; any FAIL/ERROR blocks a
  release claim.
- **full:** short seeded fuzzing plus a baseline diff.
- **stress/nightly:** bounded exhaustion in an isolated process.

A SKIP must be reviewed and documented; it must not silently count as success.

## Related

- [`audit.md`](audit.md)
- [`threat-model.md`](threat-model.md)
- [`platform-matrix.md`](platform-matrix.md)
- [`../internals/limits-and-memory.md`](../internals/limits-and-memory.md)
