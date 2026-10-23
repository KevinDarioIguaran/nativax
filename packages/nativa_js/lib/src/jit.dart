import 'ffi/bindings.dart' as b;

/// Whether a JIT backend is compiled into this build of `nativa_js`.
///
/// Always `false` unless the library was built with `NATIVAX_JIT=1`. Even
/// when `true`, the JIT is strictly additive and falls back to the QuickJS
/// interpreter on any unsupported case.
bool get nativaJsJitAvailable => b.nx_jit_available() != 0;

/// Process-global JIT initialization. Safe to call repeatedly. No-op when the
/// JIT backend is not compiled in.
void nativaJsJitInit() => b.nx_jit_init();

/// Bytes of native code currently retained by the JIT (0 when unavailable).
int get nativaJsJitCodeBytes => b.nx_jit_code_bytes();
