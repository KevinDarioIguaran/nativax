# Security platform matrix

NativaX may claim a platform as verified only after the security suite runs on
that real environment. Passing on Linux is not evidence for mobile or desktop
targets with different sandbox, FFI, threading, and native-asset behavior.

| Platform | Build | Security suite | OS isolation | Status |
|---|---|---|---|---|
| Linux x86_64 | Yes | **Yes: 44 PASS / 0 FAIL / 1 SKIP** | No | **Partial** |
| Android | Not verified here | No | No | **Unknown** |
| iOS | Not verified here | No | No | **Unknown** |
| Windows | Not verified here | No | No | **Unknown** |
| macOS | Not verified here | No | No | **Unknown** |

The Linux run is `debug/benchmarks/security/20261026T024956Z-f47240e/`
(2026-10-25). It uses QuickJS-ng 0.17.0. V8 is not exercised by the suite and
does not enforce the execution/job/stack limits described for QuickJS. A Linux
desktop build can choose V8, so the security status of the default desktop
page-engine path is **not covered by this matrix**.

## Why each platform needs its own run

- native library loading and path resolution;
- app sandbox, manifest/entitlements, and file permissions;
- TLS roots, certificate storage, and secure storage;
- isolates/threads, native stack size, and FFI ABI;
- touch, keyboard, focus, IME, and accessibility input;
- suspend/resume, orientation, memory pressure, and process death;
- QuickJS native assets and V8 cdylib packaging (MSVC atomics on Windows,
  no JIT on iOS, Android page size and ABI splits).

## Rule

Do not turn “not tested” into PASS. The only verified row is Linux x86_64, and
even that row has no OS sandbox and one Flutter-only SKIP. Everything else is
unknown for security purposes.

## Related

- [`audit.md`](audit.md)
- [`test-plan.md`](test-plan.md)
- [`../architecture/platform-support.md`](../architecture/platform-support.md)
