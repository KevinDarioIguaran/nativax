// Hand-written FFI declarations for src/nativax_bridge.h and the surface
// functions. The surface is small and pointer/scalar-only, so code generation
// would add a dependency without reducing risk. Keep in sync with the C side.
@DefaultAsset('package:nativa_js/src/ffi/bindings.dart')
library;

import 'dart:ffi';

@Native<Pointer<Void> Function(Int64)>()
external Pointer<Void> nx_alloc(int size);

@Native<Void Function(Pointer<Void>)>()
external void nx_free(Pointer<Void> ptr);

@Native<Int64 Function(Pointer<Void>, Int64)>()
external int nx_buffer_put(Pointer<Void> data, int len);

@Native<Pointer<Void> Function(Int64, Pointer<Int64>)>()
external Pointer<Void> nx_buffer_take(int id, Pointer<Int64> len);

@Native<Void Function()>()
external void nx_gl_release_current();

@Native<Int32 Function()>()
external int nx_gl_available();

@Native<Int64 Function()>()
external int nx_surface_create();

@Native<Void Function(Int64)>()
external void nx_surface_retain(int id);

@Native<Void Function(Int64)>()
external void nx_surface_release(int id);

@Native<Pointer<Uint8> Function(Int64, Pointer<Int32>, Pointer<Int32>, Pointer<Int64>)>()
external Pointer<Uint8> nx_surface_acquire(int id, Pointer<Int32> width, Pointer<Int32> height, Pointer<Int64> frame);

@Native<Int64 Function(Int64)>()
external int nx_surface_frame(int id);

@Native<Pointer<Void> Function(Int64)>()
external Pointer<Void> nx_sab_alloc(int len);

@Native<Int32 Function(Pointer<Void>)>()
external int nx_sab_is_block(Pointer<Void> data);

@Native<Int64 Function(Pointer<Void>)>()
external int nx_sab_length(Pointer<Void> data);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>()
external void nx_sab_release(Pointer<Void> data, Pointer<Void> context);

@Native<Int64 Function(Pointer<Void>)>()
external int nx_sab_share(Pointer<Void> data);

@Native<Pointer<Void> Function(Int64)>()
external Pointer<Void> nx_sab_open(int id);

@Native<Int32 Function(Pointer<Void>, Int32, Double)>()
external int nx_sab_wait(Pointer<Void> addr, int expected, double timeoutMs);

@Native<Int32 Function(Pointer<Void>, Int32)>()
external int nx_sab_notify(Pointer<Void> addr, int count);
