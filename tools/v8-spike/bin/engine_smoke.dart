import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _CreateC = Pointer<Void> Function(UintPtr, UintPtr);
typedef _CreateD = Pointer<Void> Function(int, int);
typedef _SetHostC = Void Function(Pointer<NativeFunction<_HostNative>>);
typedef _SetHostD = void Function(Pointer<NativeFunction<_HostNative>>);
typedef _HostNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _HostDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _EvalC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _EvalD = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CallC = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CallD = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);
typedef _VoidC = Void Function();
typedef _VoidD = void Function();

void main() {
  final lib = DynamicLibrary.open('/home/k3vin/Documents/nativax/tools/v8-spike/target/release/libnx_v8.so');
  final create = lib.lookupFunction<_CreateC, _CreateD>('nv8_create');
  final setHost = lib.lookupFunction<_SetHostC, _SetHostD>('nv8_set_host_callback');
  final eval = lib.lookupFunction<_EvalC, _EvalD>('nv8_eval');
  final call = lib.lookupFunction<_CallC, _CallD>('nv8_call_global');
  final free = lib.lookupFunction<_FreeC, _FreeD>('nv8_free');
  final dispose = lib.lookupFunction<_VoidC, _VoidD>('nv8_dispose');

  final host = NativeCallable<_HostNative>.isolateLocal((Pointer<Utf8> req) {
    final list = jsonDecode(req.toDartString()) as List;
    if (list[0] == 'ping') {
      return jsonEncode({'ok': 'pong'}).toNativeUtf8();
    }
    return jsonEncode({'error': {'type': 'TypeError', 'message': 'unknown host'}}).toNativeUtf8();
  });

  create(512 * 1024 * 1024, 256 * 1024);
  setHost(host.nativeFunction);

  String run(String code) {
    final ptr = code.toNativeUtf8();
    final out = eval(ptr);
    calloc.free(ptr);
    final s = out.toDartString();
    free(out);
    return s;
  }

  print('EVAL ${run('1 + 1')}');
  print('HOST ${run('__nx_host(JSON.stringify(["ping", []]))')}');
  print('REG ${run('__nx_register("foo", (x) => x + 1); __nx_call("foo", 41)')}');
  final name = 'foo'.toNativeUtf8();
  final arg = '41'.toNativeUtf8();
  final out = call(name, arg);
  print('CALL ${out.toDartString()}');
  free(out);
  calloc.free(name);
  calloc.free(arg);
  dispose();
  host.close();
}
