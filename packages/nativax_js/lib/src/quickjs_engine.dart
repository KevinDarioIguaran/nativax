import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'exceptions.dart';
import 'ffi/bindings.dart' as b;
import 'javascript_engine.dart';

/// Installed once per context. Captures the raw `__nx_host` C function,
/// removes it from the global object and exposes the frozen `__nx.host`
/// wrapper that turns host error envelopes into real script exceptions.
const String _hostPrelude = r'''
(() => {
  const raw = globalThis.__nx_host;
  delete globalThis.__nx_host;
  const ctors = { Error, TypeError, RangeError, SyntaxError };
  const stringify = JSON.stringify;
  const hasOwn = Object.prototype.hasOwnProperty;
  const host = (name, ...args) => {
    const r = raw(stringify([name, args]));
    if (r === undefined || r === null) return undefined;
    if (hasOwn.call(r, 'error')) {
      const C = ctors[r.error.type];
      const e = C ? new C(r.error.message) : new Error(r.error.message);
      if (!C) e.name = r.error.type;
      throw e;
    }
    return r.ok;
  };
  Object.defineProperty(globalThis, '__nx', {
    value: Object.freeze({ host }),
    enumerable: false, writable: false, configurable: false,
  });
})();
''';

/// [JavaScriptEngine] backed by QuickJS-ng, compiled from source by this
/// package's build hook.
///
/// One instance owns one QuickJS runtime and one context; instances share no
/// script state. Instances must be used from the isolate that created them.
final class QuickJsEngine implements JavaScriptEngine {
  QuickJsEngine([this.config = const JavaScriptEngineConfig()]) {
    _callback = NativeCallable<b.NxHostCallbackNative>.isolateLocal(_onHost);
    _rt = b.nx_runtime_new(
      _nextId++,
      config.memoryLimitBytes,
      config.maxStackBytes,
      _callback.nativeFunction,
    );
    if (_rt == nullptr) {
      _callback.close();
      throw JavaScriptEngineStateException('QuickJS runtime creation failed');
    }
    evaluate(_hostPrelude, filename: '<nativax:host>');
  }

  static int _nextId = 1;

  final JavaScriptEngineConfig config;
  late final NativeCallable<b.NxHostCallbackNative> _callback;
  late Pointer<b.NxRuntime> _rt;
  final Map<String, HostFunction> _hostFunctions = {};
  int _depth = 0;
  bool _disposed = false;

  /// Receives unexpected Dart exceptions thrown by host functions. They are
  /// reported to script code only as a generic `Error`.
  void Function(Object error, StackTrace stack)? onHostError;

  @override
  bool get isDisposed => _disposed;

  @override
  void registerHostFunction(String name, HostFunction function) {
    _checkAlive();
    _hostFunctions[name] = function;
  }

  @override
  Object? evaluate(String source, {String filename = '<nativax>'}) {
    _checkAlive();
    return _enter(() {
      final src = _toNative(source);
      final file = _toNative(filename);
      try {
        return _invoke(
          (out, outLen) =>
              b.nx_eval(_rt, src.ptr, src.length, file.ptr, out, outLen),
        );
      } finally {
        src.free();
        file.free();
      }
    });
  }

  @override
  Object? callGlobal(String functionName, [Object? argument]) {
    _checkAlive();
    return _enter(() {
      final name = _toNative(functionName);
      final arg = _toNative(argument == null ? '' : jsonEncode(argument));
      try {
        return _invoke(
          (out, outLen) =>
              b.nx_call(_rt, name.ptr, arg.ptr, arg.length, out, outLen),
        );
      } finally {
        name.free();
        arg.free();
      }
    });
  }

  @override
  int drainMicrotasks() {
    _checkAlive();
    return _enter(_drain);
  }

  @override
  bool get hasPendingMicrotasks {
    _checkAlive();
    return b.nx_has_pending_jobs(_rt) != 0;
  }

  @override
  int get memoryUsed {
    _checkAlive();
    return b.nx_memory_used(_rt);
  }

  @override
  void collectGarbage() {
    _checkAlive();
    b.nx_run_gc(_rt);
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_depth > 0) {
      throw JavaScriptEngineStateException(
        'dispose() called while script code is running',
      );
    }
    _disposed = true;
    _hostFunctions.clear();
    b.nx_runtime_free(_rt);
    _rt = nullptr;
    _callback.close();
  }

  void _checkAlive() {
    if (_disposed) {
      throw JavaScriptEngineStateException('engine has been disposed');
    }
  }

  /// Wraps an entry into script code. Only the outermost entry arms the time
  /// budget and drains microtasks; nested entries (script -> host -> script)
  /// run within the outer budget.
  T _enter<T>(T Function() body) {
    final outermost = _depth == 0;
    if (outermost) {
      b.nx_set_budget_ms(_rt, config.executionBudget.inMilliseconds);
    }
    _depth++;
    try {
      final result = body();
      if (outermost) _drain();
      return result;
    } finally {
      _depth--;
      if (outermost && !_disposed) b.nx_set_budget_ms(_rt, 0);
    }
  }

  int _drain() {
    return _withOut((out, outLen) {
      final n = b.nx_run_jobs(_rt, config.maxJobsPerDrain, out, outLen);
      if (n < 0) throw _decodeError(_readOut(out, outLen));
      if (n >= config.maxJobsPerDrain && b.nx_has_pending_jobs(_rt) != 0) {
        throw JavaScriptException(
          name: 'MicrotaskLimitError',
          message: 'more than ${config.maxJobsPerDrain} microtasks in one '
              'drain; remaining jobs stay queued',
        );
      }
      return n;
    });
  }

  Object? _invoke(
    int Function(Pointer<Pointer<Char>>, Pointer<Int64>) call,
  ) {
    return _withOut((out, outLen) {
      final status = call(out, outLen);
      final text = _readOut(out, outLen);
      if (status != b.nxOk) throw _decodeError(text);
      return text.isEmpty ? null : jsonDecode(text);
    });
  }

  T _withOut<T>(T Function(Pointer<Pointer<Char>>, Pointer<Int64>) body) {
    final out = b.nx_alloc(sizeOf<Pointer<Char>>()).cast<Pointer<Char>>();
    final outLen = b.nx_alloc(sizeOf<Int64>()).cast<Int64>();
    out.value = nullptr;
    outLen.value = 0;
    try {
      return body(out, outLen);
    } finally {
      if (out.value != nullptr) b.nx_free(out.value.cast());
      b.nx_free(out.cast());
      b.nx_free(outLen.cast());
    }
  }

  static String _readOut(Pointer<Pointer<Char>> out, Pointer<Int64> outLen) {
    if (out.value == nullptr || outLen.value == 0) return '';
    final bytes = out.value.cast<Uint8>().asTypedList(outLen.value);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static JavaScriptException _decodeError(String text) {
    final Map<String, Object?> desc = text.isEmpty
        ? const {}
        : (jsonDecode(text) as Map).cast<String, Object?>();
    final name = desc['name'] as String? ?? 'Error';
    final message = desc['message'] as String? ?? '';
    final stack = desc['stack'] as String?;
    if (desc['uncatchable'] == true && message == 'interrupted') {
      return JavaScriptTimeoutException(
        message: 'script exceeded its execution budget',
        stack: stack,
      );
    }
    return JavaScriptException(name: name, message: message, stack: stack);
  }

  void _onHost(
    int runtimeId,
    Pointer<Char> request,
    int requestLen,
    Pointer<Pointer<Char>> response,
    Pointer<Int64> responseLen,
  ) {
    String reply;
    try {
      reply = _dispatchHost(
        utf8.decode(request.cast<Uint8>().asTypedList(requestLen)),
      );
    } catch (error, stack) {
      onHostError?.call(error, stack);
      reply = '{"error":{"type":"Error","message":"internal host error"}}';
    }
    final bytes = utf8.encode(reply);
    // QuickJS' JSON parser requires a NUL-terminated buffer.
    final buf = b.nx_alloc(bytes.length + 1).cast<Uint8>();
    final view = buf.asTypedList(bytes.length + 1);
    view.setAll(0, bytes);
    view[bytes.length] = 0;
    response.value = buf.cast();
    responseLen.value = bytes.length;
  }

  String _dispatchHost(String request) {
    final decoded = jsonDecode(request) as List;
    final name = decoded[0] as String;
    final args = (decoded[1] as List).cast<Object?>();
    final fn = _hostFunctions[name];
    if (fn == null) {
      return jsonEncode({
        'error': {'type': 'TypeError', 'message': 'unknown host function'},
      });
    }
    try {
      final result = fn(args);
      return jsonEncode({'ok': result});
    } on JavaScriptHostError catch (e) {
      return jsonEncode({
        'error': {'type': e.type, 'message': e.message},
      });
    } on JavaScriptException catch (e) {
      // A nested entry (host -> script) threw. A timeout needs no special
      // case: the deadline has passed, so the outer frame is interrupted too.
      return jsonEncode({
        'error': {'type': e.name, 'message': e.message},
      });
    }
  }
}

final class _NativeString {
  _NativeString(this.ptr, this.length);
  final Pointer<Char> ptr;
  final int length;
  void free() => b.nx_free(ptr.cast());
}

_NativeString _toNative(String value) {
  final Uint8List bytes = utf8.encode(value);
  final buf = b.nx_alloc(bytes.length + 1).cast<Uint8>();
  final view = buf.asTypedList(bytes.length + 1);
  view.setAll(0, bytes);
  view[bytes.length] = 0;
  return _NativeString(buf.cast(), bytes.length);
}
