import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'javascript_engine.dart';
import 'quickjs_engine.dart' show NativeBuffers, nativaxHostPrelude;

// JavaScriptCore C API (JavaScriptCore/JSContextRef.h, JSObjectRef.h, ...).
// Every JSC reference is an opaque pointer here.
typedef _Ref = Pointer<Void>;
typedef _FnCallbackNative =
    _Ref Function(_Ref, _Ref, _Ref, Size, Pointer<_Ref>, Pointer<_Ref>);

typedef _GroupCreateN = _Ref Function();
typedef _CtxCreateN = _Ref Function(_Ref, _Ref);
typedef _RefN = Void Function(_Ref);
typedef _RefD = void Function(_Ref);
typedef _RefRefN = _Ref Function(_Ref);
typedef _CtxValN = Void Function(_Ref, _Ref);
typedef _CtxValD = void Function(_Ref, _Ref);
typedef _StrCreateN = _Ref Function(Pointer<Uint16>, Size);
typedef _StrCreateD = _Ref Function(Pointer<Uint16>, int);
typedef _StrLenN = Size Function(_Ref);
typedef _StrLenD = int Function(_Ref);
typedef _StrPtrN = Pointer<Uint16> Function(_Ref);
typedef _EvalN = _Ref Function(_Ref, _Ref, _Ref, _Ref, Int32, Pointer<_Ref>);
typedef _EvalD = _Ref Function(_Ref, _Ref, _Ref, _Ref, int, Pointer<_Ref>);
typedef _JsonN = _Ref Function(_Ref, _Ref, Uint32, Pointer<_Ref>);
typedef _JsonD = _Ref Function(_Ref, _Ref, int, Pointer<_Ref>);
typedef _CtxStrN = _Ref Function(_Ref, _Ref);
typedef _CtxValBoolN = Bool Function(_Ref, _Ref);
typedef _CtxValBoolD = bool Function(_Ref, _Ref);
typedef _ToStrN = _Ref Function(_Ref, _Ref, Pointer<_Ref>);
typedef _ToNumN = Double Function(_Ref, _Ref, Pointer<_Ref>);
typedef _ToNumD = double Function(_Ref, _Ref, Pointer<_Ref>);
typedef _MakeNumN = _Ref Function(_Ref, Double);
typedef _MakeNumD = _Ref Function(_Ref, double);
typedef _ObjMakeN = _Ref Function(_Ref, _Ref, _Ref);
typedef _MakeFnN =
    _Ref Function(_Ref, _Ref, Pointer<NativeFunction<_FnCallbackNative>>);
typedef _SetPropN = Void Function(_Ref, _Ref, _Ref, _Ref, Uint32, Pointer<_Ref>);
typedef _SetPropD = void Function(_Ref, _Ref, _Ref, _Ref, int, Pointer<_Ref>);
typedef _GetPropN = _Ref Function(_Ref, _Ref, _Ref, Pointer<_Ref>);
typedef _CallFnN = _Ref Function(_Ref, _Ref, _Ref, Size, Pointer<_Ref>, Pointer<_Ref>);
typedef _CallFnD = _Ref Function(_Ref, _Ref, _Ref, int, Pointer<_Ref>, Pointer<_Ref>);
typedef _TimeLimitN = Void Function(_Ref, Double, _Ref, _Ref);
typedef _TimeLimitD = void Function(_Ref, double, _Ref, _Ref);
typedef _TypedMakeN = _Ref Function(_Ref, Int32, Size, Pointer<_Ref>);
typedef _TypedMakeD = _Ref Function(_Ref, int, int, Pointer<_Ref>);
typedef _TypedPtrN = Pointer<Uint8> Function(_Ref, _Ref, Pointer<_Ref>);
typedef _TypedLenN = Size Function(_Ref, _Ref, Pointer<_Ref>);
typedef _TypedLenD = int Function(_Ref, _Ref, Pointer<_Ref>);

const int _kJSTypedArrayTypeUint8Array = 3;
const int _kJSPropertyAttributeDontEnum = 1 << 2;

/// Loaded JavaScriptCore entry points, shared by every [JscEngine] that uses
/// the same library path.
final class _Jsc {
  _Jsc(DynamicLibrary lib)
    : groupCreate = lib.lookupFunction<_GroupCreateN, _GroupCreateN>(
        'JSContextGroupCreate',
      ),
      groupRelease = lib.lookupFunction<_RefN, _RefD>('JSContextGroupRelease'),
      contextCreate = lib.lookupFunction<_CtxCreateN, _CtxCreateN>(
        'JSGlobalContextCreateInGroup',
      ),
      contextRelease = lib.lookupFunction<_RefN, _RefD>(
        'JSGlobalContextRelease',
      ),
      globalObject = lib.lookupFunction<_RefRefN, _RefRefN>(
        'JSContextGetGlobalObject',
      ),
      stringCreate = lib.lookupFunction<_StrCreateN, _StrCreateD>(
        'JSStringCreateWithCharacters',
      ),
      stringRelease = lib.lookupFunction<_RefN, _RefD>('JSStringRelease'),
      stringLength = lib.lookupFunction<_StrLenN, _StrLenD>(
        'JSStringGetLength',
      ),
      stringChars = lib.lookupFunction<_StrPtrN, _StrPtrN>(
        'JSStringGetCharactersPtr',
      ),
      evaluateScript = lib.lookupFunction<_EvalN, _EvalD>('JSEvaluateScript'),
      toJson = lib.lookupFunction<_JsonN, _JsonD>('JSValueCreateJSONString'),
      fromJson = lib.lookupFunction<_CtxStrN, _CtxStrN>(
        'JSValueMakeFromJSONString',
      ),
      makeUndefined = lib.lookupFunction<_RefRefN, _RefRefN>(
        'JSValueMakeUndefined',
      ),
      makeString = lib.lookupFunction<_CtxStrN, _CtxStrN>('JSValueMakeString'),
      makeNumber = lib.lookupFunction<_MakeNumN, _MakeNumD>(
        'JSValueMakeNumber',
      ),
      isObject = lib.lookupFunction<_CtxValBoolN, _CtxValBoolD>(
        'JSValueIsObject',
      ),
      isString = lib.lookupFunction<_CtxValBoolN, _CtxValBoolD>(
        'JSValueIsString',
      ),
      isFunction = lib.lookupFunction<_CtxValBoolN, _CtxValBoolD>(
        'JSObjectIsFunction',
      ),
      toStringCopy = lib.lookupFunction<_ToStrN, _ToStrN>(
        'JSValueToStringCopy',
      ),
      toNumber = lib.lookupFunction<_ToNumN, _ToNumD>('JSValueToNumber'),
      objectMake = lib.lookupFunction<_ObjMakeN, _ObjMakeN>('JSObjectMake'),
      makeFunction = lib.lookupFunction<_MakeFnN, _MakeFnN>(
        'JSObjectMakeFunctionWithCallback',
      ),
      setProperty = lib.lookupFunction<_SetPropN, _SetPropD>(
        'JSObjectSetProperty',
      ),
      getProperty = lib.lookupFunction<_GetPropN, _GetPropN>(
        'JSObjectGetProperty',
      ),
      callFunction = lib.lookupFunction<_CallFnN, _CallFnD>(
        'JSObjectCallAsFunction',
      ),
      protect = lib.lookupFunction<_CtxValN, _CtxValD>('JSValueProtect'),
      unprotect = lib.lookupFunction<_CtxValN, _CtxValD>('JSValueUnprotect'),
      collect = lib.lookupFunction<_RefN, _RefD>('JSGarbageCollect'),
      typedMake = lib.lookupFunction<_TypedMakeN, _TypedMakeD>(
        'JSObjectMakeTypedArray',
      ),
      typedBytes = lib.lookupFunction<_TypedPtrN, _TypedPtrN>(
        'JSObjectGetTypedArrayBytesPtr',
      ),
      typedLength = lib.lookupFunction<_TypedLenN, _TypedLenD>(
        'JSObjectGetTypedArrayByteLength',
      ),
      // Not in the public headers, but exported by every JSC build
      // (JSContextRefPrivate.h). Without it scripts cannot be interrupted,
      // so a library that lacks it is reported as unavailable.
      setTimeLimit = lib.lookupFunction<_TimeLimitN, _TimeLimitD>(
        'JSContextGroupSetExecutionTimeLimit',
      ),
      clearTimeLimit = lib.lookupFunction<_RefN, _RefD>(
        'JSContextGroupClearExecutionTimeLimit',
      ),
      memoryStatistics = lib.providesSymbol('JSGetMemoryUsageStatistics')
          ? lib.lookupFunction<_RefRefN, _RefRefN>('JSGetMemoryUsageStatistics')
          : null;

  final _GroupCreateN groupCreate;
  final _RefD groupRelease;
  final _CtxCreateN contextCreate;
  final _RefD contextRelease;
  final _RefRefN globalObject;
  final _StrCreateD stringCreate;
  final _RefD stringRelease;
  final _StrLenD stringLength;
  final _StrPtrN stringChars;
  final _EvalD evaluateScript;
  final _JsonD toJson;
  final _CtxStrN fromJson;
  final _RefRefN makeUndefined;
  final _CtxStrN makeString;
  final _MakeNumD makeNumber;
  final _CtxValBoolD isObject;
  final _CtxValBoolD isString;
  final _CtxValBoolD isFunction;
  final _ToStrN toStringCopy;
  final _ToNumD toNumber;
  final _ObjMakeN objectMake;
  final _MakeFnN makeFunction;
  final _SetPropD setProperty;
  final _GetPropN getProperty;
  final _CallFnD callFunction;
  final _CtxValD protect;
  final _CtxValD unprotect;
  final _RefD collect;
  final _TypedMakeD typedMake;
  final _TypedPtrN typedBytes;
  final _TypedLenD typedLength;
  final _TimeLimitD setTimeLimit;
  final _RefD clearTimeLimit;
  final _RefRefN? memoryStatistics;

  static final Map<String, _Jsc?> _loaded = {};

  /// The library at [path], or the platform's JavaScriptCore; null when it
  /// cannot be loaded or lacks a required symbol.
  static _Jsc? load(String? path) =>
      _loaded.putIfAbsent(path ?? '', () {
        for (final candidate in path != null ? [path] : _defaultPaths()) {
          try {
            return _Jsc(DynamicLibrary.open(candidate));
          } catch (_) {
            // Try the next candidate.
          }
        }
        return null;
      });

  static List<String> _defaultPaths() {
    final env = Platform.environment['NATIVAX_JSC_LIB'];
    if (env != null && env.isNotEmpty) return [env];
    if (Platform.isMacOS || Platform.isIOS) {
      return [
        '/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore',
      ];
    }
    if (Platform.isLinux) {
      return [
        'libjavascriptcoregtk-4.1.so.0',
        'libjavascriptcoregtk-6.0.so.1',
        'libjavascriptcoregtk-4.0.so.18',
      ];
    }
    // Android and Windows have no system JSC; an app that bundles one
    // (for example jsc-android's libjsc.so) passes its path.
    return const [];
  }
}

/// JavaScriptCore backend. It implements the same [JavaScriptEngine] contract
/// as [QuickJsEngine] and binds the host's JSC (system library or framework)
/// through `dart:ffi` at run time, so no platform links against it at build
/// time. [isAvailable] is false where JSC cannot be loaded; callers then use
/// QuickJS.
///
/// Opt-in: [createDefaultJavaScriptEngine] picks it only for
/// `NATIVAX_ENGINE=jsc`. Not supported here: ES modules, WebGL (`__nx.gl` is
/// null), and SharedArrayBuffer sharing across runtimes; pages that need them
/// stay on QuickJS.
///
/// Limits: the execution budget interrupts running script code
/// (uncatchable). The memory limit is checked after each top-level entry; a
/// page over it is reported through [memoryExhausted] and
/// [JavaScriptMemoryLimitException], and a single runaway allocation inside
/// one entry is bounded only by the time budget.
final class JscEngine implements JavaScriptEngine {
  JscEngine([this.config = const JavaScriptEngineConfig(), String? libraryPath])
    : _api = _Jsc.load(libraryPath) ??
          (throw JavaScriptEngineStateException(
            'JavaScriptCore is not available',
          )) {
    _group = _api.groupCreate();
    _ctx = _api.contextCreate(_group, nullptr);
    if (_ctx == nullptr) {
      _api.groupRelease(_group);
      throw JavaScriptEngineStateException('JSC context creation failed');
    }
    _registry = _api.objectMake(_ctx, nullptr, nullptr);
    _api.protect(_ctx, _registry);
    _install('__nx_host', _onHost);
    _install('__nx_register', _onRegister);
    _install('__nx_buffer_take', _onBufferTake);
    _install('__nx_buffer_put_raw', _onBufferPut);
    _describe = _evaluateRaw(_describeSource, '<nativax:describe>');
    _api.protect(_ctx, _describe);
    // __nx.putBuffer accepts any ArrayBuffer or view; hand the native side a
    // fresh Uint8Array so it reads bytes from offset 0.
    _evaluateRaw(_bufferPutShim, '<nativax:buffers>');
    evaluate(nativaxHostPrelude, filename: '<nativax:host>');
    _ready = true;
  }

  /// Whether JavaScriptCore can be loaded from [path] (or the platform
  /// default, or `NATIVAX_JSC_LIB`). Cached per path.
  static bool isAvailable([String? path]) => _Jsc.load(path) != null;

  static const _describeSource = r'''
(() => {
  const S = JSON.stringify, Str = String;
  return (e) => {
    try {
      if (e !== null && (typeof e === 'object' || typeof e === 'function')) {
        return S({
          name: e.name === undefined ? 'Error' : Str(e.name),
          message: e.message === undefined ? '' : Str(e.message),
          stack: e.stack === undefined || e.stack === null ? null : Str(e.stack),
        });
      }
      return S({ name: 'Error', message: Str(e) });
    } catch (_) {
      return '{"name":"Error","message":"unprintable exception"}';
    }
  };
})()
''';

  static const _bufferPutShim = r'''
(() => {
  const raw = globalThis.__nx_buffer_put_raw;
  delete globalThis.__nx_buffer_put_raw;
  const U8 = Uint8Array, isView = ArrayBuffer.isView;
  globalThis.__nx_buffer_put = (v) => {
    if (isView(v)) return raw(new U8(v.buffer, v.byteOffset, v.byteLength).slice());
    if (v instanceof ArrayBuffer ||
        (typeof SharedArrayBuffer === 'function' && v instanceof SharedArrayBuffer)) {
      return raw(new U8(v).slice());
    }
    throw new TypeError('ArrayBuffer or view expected');
  };
})();
''';

  final JavaScriptEngineConfig config;
  final _Jsc _api;
  late final _Ref _group;
  late final _Ref _ctx;
  late final _Ref _registry;
  late final _Ref _describe;
  final List<NativeCallable<_FnCallbackNative>> _callables = [];
  final Map<String, HostFunction> _hostFunctions = {};
  int _depth = 0;
  bool _disposed = false;
  bool _memoryExhausted = false;
  // A nested entry hit the budget; the outermost entry reports it even if
  // script code caught the error that surfaced from the host call.
  bool _timedOut = false;
  final Stopwatch _entryWatch = Stopwatch();
  int _scriptUsSinceCheck = 0;
  int _memoryCheckIntervalUs = 0;
  bool _ready = false;

  @override
  ModuleHost? moduleHost;

  /// Receives unexpected Dart exceptions thrown by host functions. They are
  /// reported to script code only as a generic `Error`.
  void Function(Object error, StackTrace stack)? onHostError;

  @override
  bool get isDisposed => _disposed;

  /// The heap went over [JavaScriptEngineConfig.memoryLimitBytes] (sticky;
  /// the runtime uses it to reload the page on QuickJS).
  bool get memoryExhausted => _memoryExhausted;

  /// Checks the heap against the memory limit now, without sampling (the
  /// runtime calls it once page startup scripts have run). Throws
  /// [JavaScriptMemoryLimitException] when over it.
  void enforceMemoryLimit() {
    _checkAlive();
    if (_depth == 0) _checkMemory(force: true);
  }

  @override
  void registerHostFunction(String name, HostFunction function) {
    _checkAlive();
    _hostFunctions[name] = function;
  }

  @override
  Object? evaluate(String source, {String filename = '<nativax>'}) {
    _checkAlive();
    return _enter(() => _toDart(_evaluateRaw(source, filename)));
  }

  @override
  void evaluateModule(String source, {required String url}) {
    _checkAlive();
    throw JavaScriptEngineStateException(
      'JavaScriptCore modules are not supported; use QuickJsEngine',
    );
  }

  @override
  Object? callGlobal(String functionName, [Object? argument]) {
    _checkAlive();
    return _enter(() {
      final name = _string(functionName);
      final exception = calloc<_Ref>();
      try {
        var fn = _api.getProperty(_ctx, _registry, name, nullptr);
        if (!_isCallable(fn)) {
          fn = _api.getProperty(_ctx, _api.globalObject(_ctx), name, nullptr);
        }
        if (!_isCallable(fn)) {
          throw JavaScriptException(
            name: 'TypeError',
            message: '$functionName is not a function',
          );
        }
        final args = calloc<_Ref>();
        try {
          args.value = argument == null
              ? _api.makeUndefined(_ctx)
              : _fromJson(jsonEncode(argument));
          final result = _api.callFunction(
            _ctx,
            fn,
            _api.globalObject(_ctx),
            1,
            args,
            exception,
          );
          if (exception.value != nullptr) throw _error(exception.value);
          return _toDart(result);
        } finally {
          calloc.free(args);
        }
      } finally {
        calloc.free(exception);
        _api.stringRelease(name);
      }
    });
  }

  /// JSC runs promise jobs before each top-level API call returns, so none
  /// are ever left queued.
  @override
  int drainMicrotasks() {
    _checkAlive();
    return 0;
  }

  @override
  bool get hasPendingMicrotasks {
    _checkAlive();
    return false;
  }

  /// Bytes the JSC heap holds: its capacity plus extra (out-of-cell) memory
  /// such as array buffers. 0 when the library does not export
  /// `JSGetMemoryUsageStatistics`.
  @override
  int get memoryUsed {
    _checkAlive();
    final stats = _api.memoryStatistics;
    if (stats == null) return 0;
    final object = stats(_ctx);
    if (object == nullptr) return 0;
    return _numberProperty(object, 'heapCapacity') +
        _numberProperty(object, 'extraMemorySize');
  }

  int _numberProperty(_Ref object, String name) {
    final key = _string(name);
    try {
      final value = _api.getProperty(_ctx, object, key, nullptr);
      final number = _api.toNumber(_ctx, value, nullptr);
      return number.isFinite ? number.toInt() : 0;
    } finally {
      _api.stringRelease(key);
    }
  }

  @override
  void collectGarbage() {
    _checkAlive();
    _api.collect(_ctx);
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
    _api.unprotect(_ctx, _describe);
    _api.unprotect(_ctx, _registry);
    _api.contextRelease(_ctx);
    _api.groupRelease(_group);
    for (final callable in _callables) {
      callable.close();
    }
  }

  void _checkAlive() {
    if (_disposed) {
      throw JavaScriptEngineStateException('engine has been disposed');
    }
  }

  /// Only the outermost entry arms the time budget; nested entries
  /// (script -> host -> script) run within it.
  T _enter<T>(T Function() body) {
    final outermost = _depth == 0;
    final budget = config.executionBudget;
    if (outermost && budget > Duration.zero) {
      _api.setTimeLimit(
        _group,
        budget.inMicroseconds / Duration.microsecondsPerSecond,
        nullptr,
        nullptr,
      );
    }
    if (outermost) {
      _timedOut = false;
      _entryWatch
        ..reset()
        ..start();
    }
    _depth++;
    try {
      final result = body();
      if (outermost && _timedOut) {
        throw JavaScriptTimeoutException(
          message: 'script exceeded its execution budget',
        );
      }
      return result;
    } on JavaScriptTimeoutException {
      _timedOut = true;
      rethrow;
    } finally {
      _depth--;
      if (outermost && !_disposed) {
        _api.clearTimeLimit(_group);
        if (_timedOut) _absorbTermination();
        _scriptUsSinceCheck += _entryWatch.elapsedMicroseconds;
        _checkMemory();
      }
    }
  }

  /// A termination raised inside a nested entry stays pending in the VM
  /// after script code resumes; let it fire on a no-op top-level entry so
  /// the next real entry starts clean.
  void _absorbTermination() {
    for (var i = 0; i < 2; i++) {
      try {
        _evaluateRaw('0', '<nativax:reset>');
        return;
      } on JavaScriptException {
        // The pending termination fired here.
      }
    }
  }

  /// Heap statistics walk the heap (~16 ms at 200k objects), so they are
  /// taken once the script time since the last check reaches 20x that
  /// check's cost: under 5 % overhead, and allocation (which takes script
  /// time) cannot outrun the check for long.
  void _checkMemory({bool force = false}) {
    final limit = config.memoryLimitBytes;
    if (!_ready || limit <= 0 || _memoryExhausted) return;
    if (_api.memoryStatistics == null) return;
    if (!force && _scriptUsSinceCheck < _memoryCheckIntervalUs) return;
    final cost = Stopwatch()..start();
    var used = memoryUsed;
    if (used > limit) {
      _api.collect(_ctx);
      used = memoryUsed;
    }
    _memoryCheckIntervalUs = cost.elapsedMicroseconds * 20;
    _scriptUsSinceCheck = 0;
    if (used <= limit) return;
    _memoryExhausted = true;
    throw JavaScriptMemoryLimitException(
      message: 'heap limit of $limit bytes reached',
    );
  }

  bool _isCallable(_Ref value) =>
      value != nullptr &&
      _api.isObject(_ctx, value) &&
      _api.isFunction(_ctx, value);

  /// Evaluates [source] and returns the raw result; throws on exceptions.
  _Ref _evaluateRaw(String source, String filename) {
    final script = _string(source);
    final url = _string(filename);
    final exception = calloc<_Ref>();
    try {
      final result = _api.evaluateScript(
        _ctx,
        script,
        nullptr,
        url,
        1,
        exception,
      );
      if (exception.value != nullptr) throw _error(exception.value);
      return result;
    } finally {
      calloc.free(exception);
      _api.stringRelease(url);
      _api.stringRelease(script);
    }
  }

  /// A JSString holding [value] as UTF-16 (NUL-safe). Caller releases it.
  _Ref _string(String value) {
    final units = value.codeUnits;
    final buffer = calloc<Uint16>(units.isEmpty ? 1 : units.length);
    try {
      buffer.asTypedList(units.length).setAll(0, units);
      return _api.stringCreate(buffer, units.length);
    } finally {
      calloc.free(buffer);
    }
  }

  /// Copies and releases a JSString.
  String _takeString(_Ref string) {
    try {
      final length = _api.stringLength(string);
      if (length == 0) return '';
      return String.fromCharCodes(
        _api.stringChars(string).asTypedList(length),
      );
    } finally {
      _api.stringRelease(string);
    }
  }

  _Ref _fromJson(String json) {
    final string = _string(json);
    try {
      return _api.fromJson(_ctx, string);
    } finally {
      _api.stringRelease(string);
    }
  }

  Object? _toDart(_Ref value) {
    if (value == nullptr) return null;
    final exception = calloc<_Ref>();
    try {
      final json = _api.toJson(_ctx, value, 0, exception);
      if (exception.value != nullptr) throw _error(exception.value);
      // undefined, functions and symbols have no JSON form.
      if (json == nullptr) return null;
      return jsonDecode(_takeString(json));
    } finally {
      calloc.free(exception);
    }
  }

  JavaScriptException _error(_Ref value) {
    // The watchdog's termination exception: the budget was exceeded.
    final text = _api.toStringCopy(_ctx, value, nullptr);
    final plain = text == nullptr ? '' : _takeString(text);
    if (plain.contains('JavaScript execution terminated') ||
        plain.contains('JavaScript execution exceeded timeout')) {
      return JavaScriptTimeoutException(
        message: 'script exceeded its execution budget',
      );
    }
    final args = calloc<_Ref>()..value = value;
    try {
      final described = _api.callFunction(
        _ctx,
        _describe,
        nullptr,
        1,
        args,
        nullptr,
      );
      final Map<String, Object?> desc =
          described != nullptr && _api.isString(_ctx, described)
          ? (jsonDecode(
                  _takeString(_api.toStringCopy(_ctx, described, nullptr)),
                ) as Map)
                .cast<String, Object?>()
          : {'name': 'Error', 'message': plain};
      return JavaScriptException(
        name: desc['name'] as String? ?? 'Error',
        message: desc['message'] as String? ?? '',
        stack: desc['stack'] as String?,
      );
    } finally {
      calloc.free(args);
    }
  }

  void _install(
    String name,
    _Ref Function(_Ref, int, Pointer<_Ref>, Pointer<_Ref>) handler,
  ) {
    final callable = NativeCallable<_FnCallbackNative>.isolateLocal(
      (_Ref ctx, _Ref fn, _Ref self, int argc, Pointer<_Ref> argv,
          Pointer<_Ref> exception) {
        try {
          return handler(ctx, argc, argv, exception);
        } on JavaScriptTimeoutException {
          exception.value = _makeString(ctx, 'execution budget exceeded');
          return _api.makeUndefined(ctx);
        } catch (error, stack) {
          onHostError?.call(error, stack);
          exception.value = _makeString(ctx, 'internal host error');
          return _api.makeUndefined(ctx);
        }
      },
    );
    _callables.add(callable);
    final key = _string(name);
    try {
      final function = _api.makeFunction(_ctx, key, callable.nativeFunction);
      _api.setProperty(
        _ctx,
        _api.globalObject(_ctx),
        key,
        function,
        _kJSPropertyAttributeDontEnum,
        nullptr,
      );
    } finally {
      _api.stringRelease(key);
    }
  }

  _Ref _makeString(_Ref ctx, String value) {
    final string = _string(value);
    try {
      return _api.makeString(ctx, string);
    } finally {
      _api.stringRelease(string);
    }
  }

  String? _argString(_Ref ctx, int argc, Pointer<_Ref> argv, int index) {
    if (index >= argc || !_api.isString(ctx, argv[index])) return null;
    return _takeString(_api.toStringCopy(ctx, argv[index], nullptr));
  }

  _Ref _onHost(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    final request = _argString(ctx, argc, argv, 0);
    if (request == null) {
      exc.value = _makeString(ctx, '__nx_host expects a string');
      return _api.makeUndefined(ctx);
    }
    return _fromJson(_dispatchHost(request));
  }

  _Ref _onRegister(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    final name = _argString(ctx, argc, argv, 0);
    if (name == null || argc < 2 || !_isCallable(argv[1])) {
      exc.value = _makeString(ctx, '__nx_register expects (name, function)');
      return _api.makeUndefined(ctx);
    }
    final key = _string(name);
    try {
      _api.setProperty(ctx, _registry, key, argv[1], 0, nullptr);
    } finally {
      _api.stringRelease(key);
    }
    return _api.makeUndefined(ctx);
  }

  _Ref _onBufferTake(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    final id = argc < 1 ? -1 : _api.toNumber(ctx, argv[0], nullptr).toInt();
    final bytes = NativeBuffers.take(id);
    if (bytes == null) {
      exc.value = _makeString(ctx, 'unknown buffer $id');
      return _api.makeUndefined(ctx);
    }
    final array = _api.typedMake(
      ctx,
      _kJSTypedArrayTypeUint8Array,
      bytes.length,
      exc,
    );
    if (array == nullptr) return _api.makeUndefined(ctx);
    if (bytes.isNotEmpty) {
      _api.typedBytes(ctx, array, nullptr).asTypedList(bytes.length).setAll(
        0,
        bytes,
      );
    }
    final key = _string('buffer');
    try {
      return _api.getProperty(ctx, array, key, exc);
    } finally {
      _api.stringRelease(key);
    }
  }

  _Ref _onBufferPut(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    if (argc < 1 || !_api.isObject(ctx, argv[0])) {
      exc.value = _makeString(ctx, 'Uint8Array expected');
      return _api.makeUndefined(ctx);
    }
    final length = _api.typedLength(ctx, argv[0], nullptr);
    final data = _api.typedBytes(ctx, argv[0], nullptr);
    final bytes = length == 0 || data == nullptr
        ? Uint8List(0)
        : Uint8List.fromList(data.asTypedList(length));
    return _api.makeNumber(ctx, NativeBuffers.put(bytes).toDouble());
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
      return jsonEncode({'ok': fn(args)});
    } on JavaScriptHostError catch (e) {
      return jsonEncode({
        'error': {'type': e.type, 'message': e.message},
      });
    } on JavaScriptTimeoutException {
      // The budget is spent; the outer frame is terminated by the watchdog
      // as soon as it resumes, so this reply is never observed by script.
      rethrow;
    } on JavaScriptException catch (e) {
      return jsonEncode({
        'error': {'type': e.name, 'message': e.message},
      });
    }
  }
}
