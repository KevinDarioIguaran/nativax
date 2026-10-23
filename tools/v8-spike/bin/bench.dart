import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ParseC = Uint32 Function(Pointer<Utf8>);
typedef _ParseD = int Function(Pointer<Utf8>);
typedef _EvalC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _EvalD = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);

void main(List<String> args) {
  final libPath = args.isNotEmpty
      ? args[0]
      : '${Directory.current.path}/target/release/libnx_v8.so';
  final jsonPath = args.length > 1 ? args[1] : '/tmp/nativa-bench/dict_es.json';
  final lib = DynamicLibrary.open(libPath);
  final parse = lib.lookupFunction<_ParseC, _ParseD>('nv8_parse_json_file');
  final eval = lib.lookupFunction<_EvalC, _EvalD>('nv8_eval');
  final free = lib.lookupFunction<_FreeC, _FreeD>('nv8_free');

  final pathPtr = jsonPath.toNativeUtf8();
  final parseWatch = Stopwatch()..start();
  final length = parse(pathPtr);
  parseWatch.stop();
  calloc.free(pathPtr);

  final codePtr = 'JSON.stringify({ok: 1 + 1, len: "abc".length})'.toNativeUtf8();
  final evalWatch = Stopwatch()..start();
  final resultPtr = eval(codePtr);
  evalWatch.stop();
  final result = resultPtr.toDartString();
  free(resultPtr);
  calloc.free(codePtr);

  print('V8_JSON_PARSE file=$jsonPath length=$length '
      'ms=${parseWatch.elapsedMilliseconds} us=${parseWatch.elapsedMicroseconds}');
  print('V8_EVAL result=$result ms=${evalWatch.elapsedMilliseconds}');
}
