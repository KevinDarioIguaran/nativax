// Hand-written FFI declarations for src/nativax_bridge.h. The surface is small
// and pointer/scalar-only, so code generation would add a dependency without
// reducing risk. Keep in sync with the header.
@DefaultAsset('package:nativa_js/src/ffi/bindings.dart')
library;

import 'dart:ffi';

final class NxRuntime extends Opaque {}

typedef NxHostCallbackNative = Void Function(
  Int64 runtimeId,
  Pointer<Char> request,
  Int64 requestLen,
  Pointer<Pointer<Char>> response,
  Pointer<Int64> responseLen,
);

const int nxOk = 0;
const int nxException = 1;

@Native<
    Pointer<NxRuntime> Function(
        Int64, Int64, Int64, Pointer<NativeFunction<NxHostCallbackNative>>)>()
external Pointer<NxRuntime> nx_runtime_new(
  int runtimeId,
  int memoryLimit,
  int stackSize,
  Pointer<NativeFunction<NxHostCallbackNative>> host,
);

@Native<Void Function(Pointer<NxRuntime>)>()
external void nx_runtime_free(Pointer<NxRuntime> rt);

@Native<Void Function(Pointer<NxRuntime>, Int64)>()
external void nx_set_budget_ms(Pointer<NxRuntime> rt, int budgetMs);

@Native<
    Int32 Function(Pointer<NxRuntime>, Pointer<Char>, Int64, Pointer<Char>,
        Pointer<Pointer<Char>>, Pointer<Int64>)>()
external int nx_eval(
  Pointer<NxRuntime> rt,
  Pointer<Char> source,
  int len,
  Pointer<Char> filename,
  Pointer<Pointer<Char>> out,
  Pointer<Int64> outLen,
);

@Native<
    Int32 Function(Pointer<NxRuntime>, Pointer<Char>, Int64, Pointer<Char>,
        Pointer<Pointer<Char>>, Pointer<Int64>)>()
external int nx_eval_module(
  Pointer<NxRuntime> rt,
  Pointer<Char> source,
  int len,
  Pointer<Char> url,
  Pointer<Pointer<Char>> out,
  Pointer<Int64> outLen,
);

@Native<
    Int32 Function(Pointer<NxRuntime>, Pointer<Char>, Pointer<Char>, Int64,
        Pointer<Pointer<Char>>, Pointer<Int64>)>()
external int nx_call(
  Pointer<NxRuntime> rt,
  Pointer<Char> functionName,
  Pointer<Char> jsonArg,
  int len,
  Pointer<Pointer<Char>> out,
  Pointer<Int64> outLen,
);

@Native<
    Int32 Function(
        Pointer<NxRuntime>, Int32, Pointer<Pointer<Char>>, Pointer<Int64>)>()
external int nx_run_jobs(
  Pointer<NxRuntime> rt,
  int maxJobs,
  Pointer<Pointer<Char>> out,
  Pointer<Int64> outLen,
);

@Native<Int32 Function(Pointer<NxRuntime>)>()
external int nx_has_pending_jobs(Pointer<NxRuntime> rt);

@Native<Void Function(Pointer<NxRuntime>)>()
external void nx_run_gc(Pointer<NxRuntime> rt);

@Native<Int64 Function(Pointer<NxRuntime>)>()
external int nx_memory_used(Pointer<NxRuntime> rt);

@Native<Pointer<Void> Function(Int64)>()
external Pointer<Void> nx_alloc(int size);

@Native<Void Function(Pointer<Void>)>()
external void nx_free(Pointer<Void> ptr);

@Native<Int64 Function(Pointer<Void>, Int64)>()
external int nx_buffer_put(Pointer<Void> data, int len);

@Native<Pointer<Void> Function(Int64, Pointer<Int64>)>()
external Pointer<Void> nx_buffer_take(int id, Pointer<Int64> len);

@Native<Void Function(Pointer<NxRuntime>, Int32)>()
external void nx_set_can_block(Pointer<NxRuntime> rt, int canBlock);

@Native<Void Function()>()
external void nx_gl_release_current();

@Native<Int32 Function()>()
external int nx_gl_available();

@Native<Int64 Function()>()
external int nx_surface_create();

@Native<Void Function(Int64)>()
external void nx_surface_retain(int id);

// Optional JIT (nativax_jit.c). Always available as symbols; return 0/false
// when the backend is not compiled in (NATIVAX_JIT != 1).
@Native<Int32 Function()>()
external int nx_jit_available();

@Native<Void Function()>()
external void nx_jit_init();

@Native<Int64 Function()>()
external int nx_jit_code_bytes();

@Native<Void Function(Int64)>()
external void nx_surface_release(int id);

@Native<Pointer<Uint8> Function(Int64, Pointer<Int32>, Pointer<Int32>, Pointer<Int64>)>()
external Pointer<Uint8> nx_surface_acquire(int id, Pointer<Int32> width, Pointer<Int32> height, Pointer<Int64> frame);

@Native<Int64 Function(Int64)>()
external int nx_surface_frame(int id);
