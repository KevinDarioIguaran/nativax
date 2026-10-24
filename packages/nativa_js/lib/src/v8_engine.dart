import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'javascript_engine.dart';
import 'quickjs_engine.dart' show NativeBuffers, nativaxHostPrelude;

typedef _HostNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CreateNative = Pointer<Void> Function(UintPtr, UintPtr);
typedef _CreateDart = Pointer<Void> Function(int, int);
typedef _SetHostNative = Void Function(Pointer<NativeFunction<_HostNative>>);
typedef _SetHostDart = void Function(Pointer<NativeFunction<_HostNative>>);
typedef _EvalNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _EvalDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CallNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CallDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _VoidNative = Void Function();
typedef _U32Native = Uint32 Function();
typedef _U32Dart = int Function();
typedef _VoidDart = void Function();
typedef _U64Native = Uint64 Function();
typedef _U64Dart = int Function();
typedef _TakeBufferNative = Pointer<Uint8> Function(Uint32, Pointer<Uint64>);
typedef _PutBufferNative = Uint32 Function(Pointer<Uint8>, UintPtr);
const int _zeroUint32 = 0;

typedef _SetBuffersNative =
    Void Function(
      Pointer<NativeFunction<_TakeBufferNative>>,
      Pointer<NativeFunction<_PutBufferNative>>,
    );
typedef _SetBuffersDart =
    void Function(
      Pointer<NativeFunction<_TakeBufferNative>>,
      Pointer<NativeFunction<_PutBufferNative>>,
    );

/// V8 backend prototype. It implements the same [JavaScriptEngine] contract as
/// [QuickJsEngine] and talks to the Rust `v8` cdylib through `dart:ffi`.
///
/// The native library is loaded from `NATIVAX_V8_LIB` (or the platform loader
/// path). It is not yet the default engine.
final class V8Engine implements JavaScriptEngine {
  V8Engine([this.config = const JavaScriptEngineConfig()]) {
    _lib = DynamicLibrary.open(
      Platform.environment['NATIVAX_V8_LIB'] ?? 'libnx_v8.so',
    );
    _create = _lib.lookupFunction<_CreateNative, _CreateDart>('nv8_create');
    _setHost = _lib.lookupFunction<_SetHostNative, _SetHostDart>(
      'nv8_set_host_callback',
    );
    _eval = _lib.lookupFunction<_EvalNative, _EvalDart>('nv8_eval');
    _call = _lib.lookupFunction<_CallNative, _CallDart>('nv8_call_global');
    _free = _lib.lookupFunction<_FreeNative, _FreeDart>('nv8_free');
    _disposeNative = _lib.lookupFunction<_VoidNative, _VoidDart>('nv8_dispose');
    _memory = _lib.lookupFunction<_U64Native, _U64Dart>('nv8_memory_used');
    _gc = _lib.lookupFunction<_VoidNative, _VoidDart>('nv8_gc');
    _drain = _lib.lookupFunction<_U32Native, _U32Dart>('nv8_drain_microtasks');
    _setBuffers = _lib.lookupFunction<_SetBuffersNative, _SetBuffersDart>(
      'nv8_set_buffer_callbacks',
    );
    _callback = NativeCallable<_HostNative>.isolateLocal(_onHost);
    _takeBufferCallback = NativeCallable<_TakeBufferNative>.isolateLocal(
      _takeBuffer,
    );
    _putBufferCallback = NativeCallable<_PutBufferNative>.isolateLocal(
      _putBuffer,
      exceptionalReturn: _zeroUint32,
    );
    // V8's object graph for the Bible dictionary needs more room than the
    // QuickJS default; keep a floor for the prototype.
    const floor = 1024 * 1024 * 1024;
    final heapLimit = config.memoryLimitBytes < floor
        ? floor
        : config.memoryLimitBytes;
    _runtime = _create(heapLimit, config.maxStackBytes);
    if (_runtime == nullptr) {
      _callback.close();
      throw JavaScriptEngineStateException('V8 runtime creation failed');
    }
    _setHost(_callback.nativeFunction);
    _setBuffers(
      _takeBufferCallback.nativeFunction,
      _putBufferCallback.nativeFunction,
    );
    evaluate(nativaxHostPrelude, filename: '<nativax:host>');
  }

  final JavaScriptEngineConfig config;
  late final DynamicLibrary _lib;
  late final _CreateDart _create;
  late final _SetHostDart _setHost;
  late final _EvalDart _eval;
  late final _CallDart _call;
  late final _FreeDart _free;
  late final _VoidDart _disposeNative;
  late final _U64Dart _memory;
  late final _VoidDart _gc;
  late final _U32Dart _drain;
  late final _SetBuffersDart _setBuffers;
  late final NativeCallable<_HostNative> _callback;
  late final NativeCallable<_TakeBufferNative> _takeBufferCallback;
  late final NativeCallable<_PutBufferNative> _putBufferCallback;
  late final Pointer<Void> _runtime;
  final Map<String, HostFunction> _hostFunctions = {};
  @override
  ModuleHost? moduleHost;
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  void registerHostFunction(String name, HostFunction function) {
    _checkAlive();
    _hostFunctions[name] = function;
  }

  Pointer<Utf8> _onHost(Pointer<Utf8> requestPtr) {
    final raw = requestPtr.toDartString();
    String response;
    try {
      final request = jsonDecode(raw) as List;
      final name = '${request[0]}';
      final args = (request.length > 1 && request[1] is List)
          ? (request[1] as List).cast<Object?>()
          : <Object?>[];
      final function = _hostFunctions[name];
      if (function == null) {
        throw JavaScriptHostError('TypeError', 'no host function "$name"');
      }
      response = jsonEncode({'ok': function(args)});
    } on JavaScriptHostError catch (e) {
      response = jsonEncode({
        'error': {'type': e.type, 'message': e.message},
      });
    } catch (e, st) {
      stderr.writeln('V8 host dispatch failed: $e\nrequest=$raw\n$st');
      response = jsonEncode({
        'error': {'type': 'Error', 'message': 'host failure: $e'},
      });
    }
    return response.toNativeUtf8();
  }

  Pointer<Uint8> _takeBuffer(int id, Pointer<Uint64> lengthOut) {
    final bytes = NativeBuffers.take(id);
    if (bytes == null) {
      lengthOut.value = 0xFFFFFFFFFFFFFFFF;
      return nullptr;
    }
    final out = malloc.allocate<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) out.asTypedList(bytes.length).setAll(0, bytes);
    lengthOut.value = bytes.length;
    return out;
  }

  int _putBuffer(Pointer<Uint8> data, int length) {
    final bytes = Uint8List.fromList(data.asTypedList(length));
    return NativeBuffers.put(bytes);
  }

  String _invoke(String source, {String label = 'eval'}) {
    final watch = Stopwatch()..start();
    final ptr = source.toNativeUtf8();
    try {
      final out = _eval(ptr);
      if (out == nullptr) return 'null';
      final text = out.toDartString();
      _free(out);
      if (watch.elapsedMilliseconds >= 50 &&
          Platform.environment['NATIVAX_TRACE_JS'] == '1') {
        stderr.writeln(
          'JS $label ${watch.elapsedMilliseconds}ms '
          'source=${source.length} result=${text.length}',
        );
      }
      return text;
    } finally {
      calloc.free(ptr);
    }
  }

  Object? _decode(String text) {
    if (text == 'undefined') return null;
    if (text.contains('"__nativax_error"')) {
      throw JavaScriptException(name: 'Error', message: text);
    }
    return jsonDecode(text);
  }

  void _checkAlive() {
    if (_disposed) {
      throw JavaScriptEngineStateException('V8 engine already disposed');
    }
  }

  @override
  Object? evaluate(String source, {String filename = '<nativax>'}) {
    _checkAlive();
    return _decode(_invoke(source, label: 'evaluate'));
  }

  @override
  void evaluateModule(String source, {required String url}) {
    _checkAlive();
    throw JavaScriptEngineStateException('V8 modules are not implemented yet');
  }

  @override
  Object? callGlobal(String functionName, [Object? argument]) {
    _checkAlive();
    final watch = Stopwatch()..start();
    final name = functionName.toNativeUtf8();
    final arg = jsonEncode(argument).toNativeUtf8();
    try {
      final out = _call(name, arg);
      if (out == nullptr) return null;
      final text = out.toDartString();
      _free(out);
      if (Platform.environment['NATIVAX_TRACE_JS'] == '1') {
        stderr.writeln(
          'JS callGlobal $functionName '
          '${watch.elapsedMilliseconds}ms result=${text.length}',
        );
      }
      return _decode(text);
    } finally {
      calloc.free(name);
      calloc.free(arg);
    }
  }

  @override
  int drainMicrotasks() => _disposed ? 0 : _drain();

  @override
  bool get hasPendingMicrotasks => false;

  @override
  int get memoryUsed => _disposed ? 0 : _memory();

  @override
  void collectGarbage() {
    if (!_disposed) _gc();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposeNative();
    _callback.close();
    _takeBufferCallback.close();
    _putBufferCallback.close();
  }
}
