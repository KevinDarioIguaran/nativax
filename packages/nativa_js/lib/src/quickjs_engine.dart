import 'dart:collection';
import 'dart:io' show Platform, stderr;
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'exceptions.dart';
import 'ffi/bindings.dart' as b;
import 'javascript_engine.dart';
import 'wasm_prelude.dart';

/// Installed once per context. Captures the raw `__nx_host` C function,
/// removes it from the global object and exposes the frozen `__nx.host`
/// wrapper that turns host error envelopes into real script exceptions.
const String nativaxHostPrelude = r'''
(() => {
  const raw = globalThis.__nx_host;
  const rawRegister = globalThis.__nx_register;
  const takeBuffer = globalThis.__nx_buffer_take;
  const putBuffer = globalThis.__nx_buffer_put;
  const shareSab = globalThis.__nx_sab_share;
  const openSab = globalThis.__nx_sab_open;
  const gl = globalThis.__nx_gl_native || null;
  const decodeUtf8 = globalThis.__nx_decode_utf8 || null;
  delete globalThis.__nx_decode_utf8;
  delete globalThis.__nx_sab_share;
  delete globalThis.__nx_sab_open;
  delete globalThis.__nx_gl_native;
  delete globalThis.__nx_host;
  delete globalThis.__nx_register;
  delete globalThis.__nx_buffer_take;
  delete globalThis.__nx_buffer_put;
  // Callbacks for Engine.callGlobal live in a registry scripts cannot reach.
  const register = (name, fn) => rawRegister(String(name), fn);
  const ctors = { Error, TypeError, RangeError, SyntaxError };
  const domNames = new Set([
    'IndexSizeError', 'HierarchyRequestError', 'WrongDocumentError', 'InvalidCharacterError',
    'NoModificationAllowedError', 'NotFoundError', 'NotSupportedError', 'InUseAttributeError',
    'InvalidStateError', 'SyntaxError', 'InvalidModificationError', 'NamespaceError',
    'InvalidAccessError', 'TypeMismatchError', 'SecurityError', 'NetworkError', 'AbortError',
    'URLMismatchError', 'QuotaExceededError', 'TimeoutError', 'InvalidNodeTypeError',
    'DataCloneError', 'EncodingError', 'NotReadableError', 'UnknownError', 'ConstraintError',
    'DataError', 'TransactionInactiveError', 'ReadOnlyError', 'VersionError', 'OperationError',
    'NotAllowedError', 'OptOutError',
  ]);
  const stringify = JSON.stringify;
  const hasOwn = Object.prototype.hasOwnProperty;
  const host = (name, ...args) => {
    const r = raw(stringify([name, args]));
    if (r === undefined || r === null) return undefined;
    if (hasOwn.call(r, 'error')) {
      const type = r.error.type;
      if (globalThis.DOMException && domNames.has(type)) {
        throw new globalThis.DOMException(r.error.message, type);
      }
      const C = ctors[type];
      const e = C ? new C(r.error.message) : new Error(r.error.message);
      if (!C) e.name = type;
      throw e;
    }
    return r.ok;
  };
  // Rejected module evaluations (top-level await, failed imports).
  rawRegister('__nx_module_error', (e) => {
    try {
      raw(stringify(['__module_error', [{
        name: e && e.name ? String(e.name) : 'Error',
        message: e && e.message !== undefined ? String(e.message) : String(e),
        stack: e && e.stack ? String(e.stack) : '',
      }]]));
    } catch (_) {}
  });
  Object.defineProperty(globalThis, '__nx', {
    value: Object.freeze({ host, register, takeBuffer, putBuffer, shareSab, openSab, gl, decodeUtf8 }),
    enumerable: false, writable: false, configurable: true,
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
    b.nx_jit_init();
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
    _hostFunctions['__module'] = _moduleRequest;
    _hostFunctions['__module_error'] = (args) {
      final e = (args[0] as Map).cast<String, Object?>();
      moduleHost?.onError(
        JavaScriptException(
          name: e['name'] as String? ?? 'Error',
          message: e['message'] as String? ?? '',
          stack: e['stack'] as String?,
        ),
      );
      return null;
    };
    evaluate(nativaxHostPrelude, filename: '<nativax:host>');
    evaluate(wasmPrelude, filename: '<nativax:wasm>');
  }

  @override
  ModuleHost? moduleHost;

  /// Lets `Atomics.wait` block the calling thread. Enable it only on worker
  /// isolates; the UI thread must never block (browsers throw there too).
  set canBlock(bool value) {
    _checkAlive();
    b.nx_set_can_block(_rt, value ? 1 : 0);
  }

  Object? _moduleRequest(List<Object?> args) {
    final op = args[0] as String;
    final host = moduleHost;
    if (host == null)
      throw JavaScriptHostError('TypeError', 'modules are not enabled');
    switch (op) {
      case 'resolve':
        return host.resolve(args[1] as String, args[2] as String);
      case 'source':
        return host.source(args[1] as String);
    }
    throw JavaScriptHostError('TypeError', 'unknown module request');
  }

  @override
  void evaluateModule(String source, {required String url}) {
    _checkAlive();
    _enter(() {
      final src = _toNative(source);
      final file = _toNative(url);
      try {
        return _invoke(
          (out, outLen) =>
              b.nx_eval_module(_rt, src.ptr, src.length, file.ptr, out, outLen),
          label: 'module:$url',
        );
      } finally {
        src.free();
        file.free();
      }
    });
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
          label: 'eval:$filename',
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
          label: 'call:$functionName',
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
      if (outermost) {
        if (!_disposed) b.nx_set_budget_ms(_rt, 0);
        // A WebGL context made current by this task must not stay current:
        // the next task of this isolate may run on another thread, and the
        // UI thread's own GL context (Flutter's) must be restored.
        b.nx_gl_release_current();
      }
    }
  }

  int _drain() {
    return _withOut((out, outLen) {
      final n = b.nx_run_jobs(_rt, config.maxJobsPerDrain, out, outLen);
      if (n < 0) throw _decodeError(_readOut(out, outLen));
      if (n >= config.maxJobsPerDrain && b.nx_has_pending_jobs(_rt) != 0) {
        throw JavaScriptException(
          name: 'MicrotaskLimitError',
          message:
              'more than ${config.maxJobsPerDrain} microtasks in one '
              'drain; remaining jobs stay queued',
        );
      }
      return n;
    });
  }

  Object? _invoke(
    int Function(Pointer<Pointer<Char>>, Pointer<Int64>) call, {
    String label = 'js',
  }) {
    final watch = _traceJs ? (Stopwatch()..start()) : null;
    try {
      return _withOut((out, outLen) {
        final status = call(out, outLen);
        final text = _readOut(out, outLen);
        if (status != b.nxOk) throw _decodeError(text);
        return text.isEmpty ? null : jsonDecode(text);
      });
    } finally {
      if (watch != null) {
        watch.stop();
        _jsTotalUs += watch.elapsedMicroseconds;
        _jsCalls++;
        if (_jsCalls % 100 == 0) {
          stderr.writeln(
            'QJS_JS_TOTAL calls=$_jsCalls '
            'totalMs=${(_jsTotalUs / 1000).toStringAsFixed(1)}',
          );
        }
        if (watch.elapsedMilliseconds >= 20) {
          stderr.writeln('QJS_JS $label ${watch.elapsedMilliseconds}ms');
        }
      }
    }
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

  final bool _traceHost = Platform.environment['NATIVAX_TRACE_HOST'] == '1';
  int _hostTotal = 0;
  final Map<String, int> _hostCounts = {};
  final Map<String, int> _hostMicros = {};
  final Map<String, int> _hostMaxUs = {};
  final Map<String, int> _hostBytes = {};
  int _lastRequestBytes = 0;
  String? _lastHostName;
  final bool _traceJs = Platform.environment['NATIVAX_TRACE_JS'] == '1';
  int _jsTotalUs = 0;
  int _jsCalls = 0;

  void _onHost(
    int runtimeId,
    Pointer<Char> request,
    int requestLen,
    Pointer<Pointer<Char>> response,
    Pointer<Int64> responseLen,
  ) {
    String reply;
    _lastRequestBytes = requestLen;
    final watch = _traceHost ? (Stopwatch()..start()) : null;
    try {
      reply = _dispatchHost(
        utf8.decode(request.cast<Uint8>().asTypedList(requestLen)),
      );
    } catch (error, stack) {
      onHostError?.call(error, stack);
      reply = '{"error":{"type":"Error","message":"internal host error"}}';
    }
    if (watch != null) {
      watch.stop();
      final us = watch.elapsedMicroseconds;
      final name = _lastHostName ?? '?';
      _hostTotal++;
      _hostCounts[name] = (_hostCounts[name] ?? 0) + 1;
      _hostMicros[name] = (_hostMicros[name] ?? 0) + us;
      if (us > (_hostMaxUs[name] ?? 0)) _hostMaxUs[name] = us;
      _hostBytes[name] =
          (_hostBytes[name] ?? 0) + _lastRequestBytes + reply.length;
      if (_hostTotal % 1000 == 0 || us >= 20000) {
        final names = _hostCounts.keys.toList()
          ..sort(
            (a, b) => (_hostMicros[b] ?? 0).compareTo(_hostMicros[a] ?? 0),
          );
        final byMax = _hostCounts.keys.toList()
          ..sort((a, b) {
            final ma = _hostMaxUs[a] ?? 0;
            final mb = _hostMaxUs[b] ?? 0;
            return mb.compareTo(ma);
          });
        String row(String n) =>
            '$n calls=${_hostCounts[n]} '
            'totalMs=${((_hostMicros[n] ?? 0) / 1000).toStringAsFixed(1)} '
            'maxMs=${((_hostMaxUs[n] ?? 0) / 1000).toStringAsFixed(1)} '
            'bytes=${_hostBytes[n]}';
        stderr.writeln(
          'QJS_HOST total=$_hostTotal last=${us}us '
          'top=${names.take(10).map(row).join(' | ')}',
        );
        stderr.writeln('QJS_HOST_MAX ${byMax.take(10).map(row).join(' | ')}');
      }
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
    _lastHostName = name;
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

/// Moves byte buffers between Dart and script code without JSON: Dart parks
/// bytes under an id, and script code adopts them as an `ArrayBuffer` with
/// `__nx.takeBuffer(id)` (and the reverse with `__nx.putBuffer(view)`). Ids
/// are process-wide, so they also cross isolates.
abstract final class NativeBuffers {
  /// Copies [bytes] into native memory and returns its id.
  static int put(Uint8List bytes) {
    final ptr = b.nx_alloc(bytes.isEmpty ? 1 : bytes.length).cast<Uint8>();
    if (bytes.isNotEmpty) ptr.asTypedList(bytes.length).setAll(0, bytes);
    return b.nx_buffer_put(ptr.cast(), bytes.length);
  }

  /// Removes the buffer [id] and returns a copy of its bytes, or null if no
  /// such buffer is parked.
  static Uint8List? take(int id) {
    final len = b.nx_alloc(sizeOf<Int64>()).cast<Int64>();
    try {
      final ptr = b.nx_buffer_take(id, len);
      if (len.value < 0) return null;
      final out = Uint8List.fromList(ptr.cast<Uint8>().asTypedList(len.value));
      b.nx_free(ptr);
      return out;
    } finally {
      b.nx_free(len.cast());
    }
  }
}

/// Canvas backing stores shared between script runtimes (any thread) and the
/// UI: WebGL contexts publish frames into a surface; the renderer shows the
/// latest one.
class _SurfacePresentation {
  int frames = 0;
  int width = 0;
  int height = 0;
  int decodeMicros = 0;
  int lastShownMicros = 0;
  final ListQueue<int> intervals = ListQueue<int>();
  final ListQueue<int> decodes = ListQueue<int>();

  void addInterval(int micros) {
    if (micros <= 0) return;
    intervals.add(micros);
    while (intervals.length > 240) {
      intervals.removeFirst();
    }
  }

  void addDecode(int micros) {
    decodes.add(micros);
    while (decodes.length > 240) {
      decodes.removeFirst();
    }
  }
}

abstract final class GlSurfaces {
  /// Whether WebGL is available (EGL + OpenGL ES 3 loaded).
  static bool get available => b.nx_gl_available() != 0;

  static int create() => b.nx_surface_create();
  static void retain(int id) => b.nx_surface_retain(id);
  static void release(int id) => b.nx_surface_release(id);

  /// Counter of the newest presented frame (0: none yet).
  static int frame(int id) => b.nx_surface_frame(id);

  static final Map<int, _SurfacePresentation> _presentation = {};
  static final Stopwatch _presentationClock = Stopwatch()..start();

  /// Frames actually decoded and shown by a [GlSurfaceView]. Compare with
  /// [frame] to distinguish renderer throughput from presentation throughput.
  static int shown(int id) => _presentation[id]?.frames ?? 0;

  /// Size of the most recently shown drawing buffer.
  static int shownWidth(int id) => _presentation[id]?.width ?? 0;
  static int shownHeight(int id) => _presentation[id]?.height ?? 0;

  /// Time spent decoding the most recent frame on the UI isolate.
  static int decodeMicros(int id) => _presentation[id]?.decodeMicros ?? 0;

  /// Number of presentation intervals in the rolling window.
  static int presentSamples(int id) => _presentation[id]?.intervals.length ?? 0;

  /// Presentation cadence percentiles in microseconds (time between shown
  /// frames). These are measured on the UI isolate, after decode.
  static int presentP50Micros(int id) =>
      _percentile(_presentation[id]?.intervals, 0.50);
  static int presentP95Micros(int id) =>
      _percentile(_presentation[id]?.intervals, 0.95);
  static int presentP99Micros(int id) =>
      _percentile(_presentation[id]?.intervals, 0.99);

  /// Decode latency percentiles in microseconds for the same rolling window.
  static int decodeP50Micros(int id) =>
      _percentile(_presentation[id]?.decodes, 0.50);
  static int decodeP95Micros(int id) =>
      _percentile(_presentation[id]?.decodes, 0.95);
  static int decodeP99Micros(int id) =>
      _percentile(_presentation[id]?.decodes, 0.99);

  /// Called by the Flutter view after a decoded frame is installed.
  static void markShown(
    int id, {
    int width = 0,
    int height = 0,
    int decodeMicros = 0,
  }) {
    final stats = _presentation.putIfAbsent(id, _SurfacePresentation.new);
    final now = _presentationClock.elapsedMicroseconds;
    if (stats.lastShownMicros > 0) {
      stats.addInterval(now - stats.lastShownMicros);
    }
    stats.lastShownMicros = now;
    stats.frames++;
    stats.width = width;
    stats.height = height;
    stats.decodeMicros = decodeMicros;
    stats.addDecode(decodeMicros);
  }

  static int _percentile(ListQueue<int>? values, double p) {
    if (values == null || values.isEmpty) return 0;
    final sorted = values.toList()..sort();
    var index = ((sorted.length - 1) * p).round();
    if (index < 0) index = 0;
    if (index >= sorted.length) index = sorted.length - 1;
    return sorted[index];
  }

  /// The latest frame as premultiplied RGBA8, top row first. The returned
  /// view aliases native memory that stays valid until the next [acquire]
  /// of the same surface.
  static ({Uint8List pixels, int width, int height, int frame})? acquire(
    int id,
  ) {
    final w = b.nx_alloc(4).cast<Int32>();
    final h = b.nx_alloc(4).cast<Int32>();
    final f = b.nx_alloc(8).cast<Int64>();
    try {
      final ptr = b.nx_surface_acquire(id, w, h, f);
      if (ptr == nullptr || w.value <= 0 || h.value <= 0) return null;
      return (
        pixels: ptr.asTypedList(w.value * h.value * 4),
        width: w.value,
        height: h.value,
        frame: f.value,
      );
    } finally {
      b.nx_free(w.cast());
      b.nx_free(h.cast());
      b.nx_free(f.cast());
    }
  }
}
