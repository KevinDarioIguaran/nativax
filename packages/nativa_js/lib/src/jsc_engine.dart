import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'ffi/bindings.dart' as b;
import 'javascript_engine.dart';
import 'host_prelude.dart';
import 'module_source.dart';
import 'native_buffers.dart';

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
typedef _Deallocator = Void Function(Pointer<Void>, Pointer<Void>);
typedef _BufferNoCopyN =
    _Ref Function(
      _Ref,
      Pointer<Void>,
      Size,
      Pointer<NativeFunction<_Deallocator>>,
      Pointer<Void>,
      Pointer<_Ref>,
    );
typedef _BufferNoCopyD =
    _Ref Function(
      _Ref,
      Pointer<Void>,
      int,
      Pointer<NativeFunction<_Deallocator>>,
      Pointer<Void>,
      Pointer<_Ref>,
    );
typedef _BufferPtrN = Pointer<Void> Function(_Ref, _Ref, Pointer<_Ref>);

const int _kJSTypedArrayTypeUint8Array = 3;
const int _kJSPropertyAttributeDontEnum = 1 << 2;

/// Loaded JavaScriptCore entry points, shared by every [JscEngine] that uses
/// the same library path.
final class _Jsc {
  _Jsc(DynamicLibrary lib)
    : _lib = lib,
      groupCreate = lib.lookupFunction<_GroupCreateN, _GroupCreateN>(
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
      bufferNoCopy = lib.lookupFunction<_BufferNoCopyN, _BufferNoCopyD>(
        'JSObjectMakeArrayBufferWithBytesNoCopy',
      ),
      bufferBytes = lib.lookupFunction<_BufferPtrN, _BufferPtrN>(
        'JSObjectGetArrayBufferBytesPtr',
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
      synchronousCollect =
          lib.providesSymbol('JSSynchronousGarbageCollectForDebugging')
          ? lib.lookupFunction<_RefN, _RefD>(
              'JSSynchronousGarbageCollectForDebugging',
            )
          : null,
      memoryStatistics = lib.providesSymbol('JSGetMemoryUsageStatistics')
          ? lib.lookupFunction<_RefRefN, _RefRefN>('JSGetMemoryUsageStatistics')
          : null;

  final DynamicLibrary _lib;
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
  final _BufferNoCopyD bufferNoCopy;
  final _BufferPtrN bufferBytes;
  final _TimeLimitD setTimeLimit;
  final _RefD clearTimeLimit;
  final _RefRefN? memoryStatistics;
  final _RefD? synchronousCollect;
  late final String? version = () {
    int? part(String name) => _lib.providesSymbol(name)
        ? _lib.lookupFunction<Uint32 Function(), int Function()>(name)()
        : null;
    final major = part('jsc_get_major_version');
    if (major == null) return null;
    return '$major.${part('jsc_get_minor_version')}.${part('jsc_get_micro_version')}';
  }();

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

/// The NativaX script engine: JavaScriptCore behind the [JavaScriptEngine]
/// contract. It binds the host's JSC (system library or framework) through
/// `dart:ffi` at run time, so no platform links against it at build time.
/// [isAvailable] is false where JSC cannot be loaded (Android and Windows
/// ship none; an app bundles one and passes its path).
///
/// Modules: JSC's C API has no module loader. [evaluateModule] runs modules
/// without `import`/`export` declarations (bundles) as a strict async
/// function body with `import.meta.url` from the host, and rejects the rest.
/// Not supported yet: WebGL (`__nx.gl` is null) and SharedArrayBuffer
/// sharing across runtimes.
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
    _created = true;
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
    _install('__nx_sab_alloc', _onSabAlloc);
    _install('__nx_sab_share_raw', _onSabShare);
    _install('__nx_sab_open_raw', _onSabOpen);
    _install('__nx_sab_wait_raw', _onSabWait);
    _install('__nx_sab_notify_raw', _onSabNotify);
    _describe = _evaluateRaw(_describeSource, '<nativax:describe>');
    _api.protect(_ctx, _describe);
    // __nx.putBuffer accepts any ArrayBuffer or view; hand the native side a
    // fresh Uint8Array so it reads bytes from offset 0.
    _evaluateRaw(_bufferPutShim, '<nativax:buffers>');
    _evaluateRaw(_wasmAsyncShim, '<nativax:wasm>');
    _evaluateRaw(_sharedArrayBufferShim, '<nativax:sab>');
    _evaluateRaw(_queueMicrotaskShim, '<nativax:microtask>');
    _evaluateRaw(_moduleRegistry, '<nativax:modules>');
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
    _ready = true;
  }

  /// Whether JavaScriptCore can be loaded from [path] (or the platform
  /// default, or `NATIVAX_JSC_LIB`). Cached per path.
  static bool isAvailable([String? path]) => _Jsc.load(path) != null;

  /// Sets JavaScriptCore options (`JSC_<name>` environment variables, for
  /// example `{'useJIT': 'false'}`) for this process. JSC reads them once,
  /// when it initializes, so call this before the first [JscEngine] is
  /// created; returns false if an engine already exists.
  static bool configure(Map<String, String> options) {
    if (_created) return false;
    for (final MapEntry(:key, :value) in options.entries) {
      _setEnvironment('JSC_$key', value);
    }
    return true;
  }

  static bool _created = false;

  static void _setEnvironment(String name, String value) {
    final process = DynamicLibrary.process();
    final n = name.toNativeUtf8();
    final v = value.toNativeUtf8();
    try {
      if (Platform.isWindows) {
        final putenv = DynamicLibrary.open('ucrtbase.dll').lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Utf8>, Pointer<Utf8>)
        >('_putenv_s');
        putenv(n, v);
      } else {
        final setenv = process.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, Pointer<Utf8>, int)
        >('setenv');
        setenv(n, v, 1);
      }
    } finally {
      calloc.free(n);
      calloc.free(v);
    }
  }

  /// The loaded JavaScriptCore's version (`major.minor.micro`) where the
  /// library reports it (WebKitGTK), `system` otherwise, or `unavailable`.
  static String version([String? path]) {
    final api = _Jsc.load(path);
    if (api == null) return 'unavailable';
    return api.version ?? 'system';
  }

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

  // JSC finishes asynchronous WebAssembly compilation on its own run loop,
  // which a Dart host never spins, so those promises would never settle.
  // The async entry points compile synchronously inside a promise instead.
  static const _wasmAsyncShim = r'''
(() => {
  const W = globalThis.WebAssembly;
  if (!W) return;
  const { Module, Instance } = W;
  const compile = (bytes) => new Promise((resolve) => resolve(new Module(bytes)));
  const instantiate = (source, imports) => new Promise((resolve) => {
    if (source instanceof Module) {
      resolve(new Instance(source, imports));
    } else {
      const module = new Module(source);
      resolve({ module, instance: new Instance(module, imports) });
    }
  });
  const bytesOf = async (source) => {
    const response = await source;
    if (!response || typeof response.arrayBuffer !== 'function') {
      throw new TypeError('WebAssembly streaming expects a Response');
    }
    return response.arrayBuffer();
  };
  const methods = {
    compile,
    instantiate,
    compileStreaming: async (source) => compile(await bytesOf(source)),
    instantiateStreaming: async (source, imports) =>
      instantiate(await bytesOf(source), imports),
  };
  for (const [name, value] of Object.entries(methods)) {
    Object.defineProperty(W, name, { value, writable: true, configurable: true });
  }
})();
''';

  // A JSC API context has no SharedArrayBuffer, and JSC cannot wrap
  // external memory in one. NativaX's SharedArrayBuffer is an ArrayBuffer
  // over a reference-counted native block (nativax_bridge.c) whose prototype
  // is SharedArrayBuffer.prototype: every runtime that opens it sees the
  // same bytes, and Atomics.add/load/store/... work on views of it.
  // Atomics.wait/notify on Int32Array views of it go through a native futex
  // (nx_sab_wait/nx_sab_notify); wait throws unless [canBlock] is set.
  static const _sharedArrayBufferShim = r'''
(() => {
  const alloc = globalThis.__nx_sab_alloc;
  const shareRaw = globalThis.__nx_sab_share_raw;
  const openRaw = globalThis.__nx_sab_open_raw;
  delete globalThis.__nx_sab_alloc;
  delete globalThis.__nx_sab_share_raw;
  delete globalThis.__nx_sab_open_raw;
  if (typeof globalThis.SharedArrayBuffer === 'function') return;
  const setProto = Object.setPrototypeOf;
  const byteLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
  function SharedArrayBuffer(length) {
    if (new.target === undefined) {
      throw new TypeError("Constructor SharedArrayBuffer requires 'new'");
    }
    const n = length === undefined ? 0 : Math.trunc(Number(length));
    if (!(n >= 0) || n > 0x7fffffff) throw new RangeError('Invalid array buffer length');
    const buffer = alloc(n);
    setProto(buffer, new.target.prototype);
    return buffer;
  }
  const proto = Object.create(ArrayBuffer.prototype, {
    constructor: { value: SharedArrayBuffer, writable: true, configurable: true },
    [Symbol.toStringTag]: { value: 'SharedArrayBuffer', configurable: true },
    growable: { get() { return false; }, configurable: true },
    slice: {
      value(start, end) {
        const len = byteLength.call(this);
        const rel = (v, d) => {
          const x = v === undefined ? d : Math.trunc(Number(v)) || 0;
          return x < 0 ? Math.max(len + x, 0) : Math.min(x, len);
        };
        const from = rel(start, 0);
        const to = rel(end, len);
        const out = new SharedArrayBuffer(Math.max(to - from, 0));
        new Uint8Array(out).set(new Uint8Array(this, from, Math.max(to - from, 0)));
        return out;
      },
      writable: true, configurable: true,
    },
  });
  Object.defineProperty(SharedArrayBuffer, 'prototype', { value: proto, writable: false });
  Object.defineProperty(globalThis, 'SharedArrayBuffer', {
    value: SharedArrayBuffer, writable: true, enumerable: false, configurable: true,
  });
  globalThis.__nx_sab_share = (sab) => shareRaw(sab);
  globalThis.__nx_sab_open = (id) => setProto(openRaw(id), proto);

  const waitRaw = globalThis.__nx_sab_wait_raw;
  const notifyRaw = globalThis.__nx_sab_notify_raw;
  delete globalThis.__nx_sab_wait_raw;
  delete globalThis.__nx_sab_notify_raw;
  const A = Atomics;
  const nativeWait = A.wait;
  const nativeNotify = A.notify;
  const isView = ArrayBuffer.isView;
  const ours = (ta) => isView(ta) && ta.buffer instanceof SharedArrayBuffer;
  const cell = (ta, index) => {
    if (!(ta instanceof Int32Array)) {
      throw new TypeError('Atomics.wait/notify on a SharedArrayBuffer need an Int32Array');
    }
    const i = Number(index);
    if (!Number.isInteger(i) || i < 0 || i >= ta.length) {
      throw new RangeError('Invalid atomic access index');
    }
    return ta.byteOffset + i * 4;
  };
  const results = ['ok', 'not-equal', 'timed-out'];
  Object.defineProperty(A, 'wait', {
    value: function wait(ta, index, value, timeout) {
      if (!ours(ta)) return nativeWait.call(A, ta, index, value, timeout);
      const offset = cell(ta, index);
      let t = timeout === undefined ? Infinity : Number(timeout);
      if (Number.isNaN(t)) t = Infinity;
      t = Math.max(t, 0);
      return results[waitRaw(ta.buffer, offset, Number(value) | 0, t === Infinity ? -1 : t)];
    },
    writable: true, configurable: true,
  });
  Object.defineProperty(A, 'notify', {
    value: function notify(ta, index, count) {
      if (!ours(ta)) return nativeNotify.call(A, ta, index, count);
      const offset = cell(ta, index);
      const n = count === undefined ? -1 : Math.max(Math.trunc(Number(count)) || 0, 0);
      return notifyRaw(ta.buffer, offset, n === Infinity ? -1 : Math.min(n, 0x7fffffff));
    },
    writable: true, configurable: true,
  });
})();
''';

  // Module registry for modules rewritten by ModuleTransform. Records live
  // in a closure scripts cannot reach. A module awaiting a dependency marks
  // `waiting`; an import that would close a cycle of waits gets the
  // (partially evaluated) namespace instead of deadlocking, like ES module
  // cycles.
  static const _moduleRegistry = r'''
(() => {
  const raw = globalThis.__nx_host;
  const register = globalThis.__nx_register;
  const S = JSON.stringify;
  const hasOwn = Object.prototype.hasOwnProperty;
  const defineProperty = Object.defineProperty;
  const keys = Object.keys;
  const errors = { TypeError, SyntaxError, ReferenceError, RangeError };
  const evalCode = (0, eval);
  const call = (op, ...args) => {
    const r = raw(S(['__module', [op, ...args]]));
    if (r && hasOwn.call(r, 'error')) {
      const C = errors[r.error.type] || Error;
      throw new C(r.error.message);
    }
    return r ? r.ok : undefined;
  };
  const records = new Map();
  const closesCycle = (from, target) => {
    for (let cur = target, n = 0; cur && n < 100000; n++) {
      if (cur === from) return true;
      const r = records.get(cur);
      cur = r ? r.waiting : null;
    }
    return false;
  };
  const link = (url, fn) => {
    const existing = records.get(url);
    if (existing) return existing.promise;
    const ns = Object.create(null);
    defineProperty(ns, Symbol.toStringTag, { value: 'Module' });
    const record = { ns, evaluating: true, waiting: null, promise: null };
    records.set(url, record);
    const exportNames = (getters) => {
      for (const k of keys(getters)) {
        defineProperty(ns, k, { get: getters[k], enumerable: true });
      }
    };
    const star = (other) => {
      for (const k of keys(other)) {
        if (k !== 'default' && !hasOwn.call(ns, k)) {
          defineProperty(ns, k, { get: () => other[k], enumerable: true });
        }
      }
    };
    const resolve = (spec) => call('resolve', url, String(spec));
    const importFrom = (spec) => {
      const target = resolve(spec);
      const dep = records.get(target);
      if (dep && dep.evaluating && closesCycle(url, target)) {
        return Promise.resolve(dep.ns);
      }
      record.waiting = target;
      const done = () => { record.waiting = null; };
      return link(target).then((m) => { done(); return m; }, (e) => { done(); throw e; });
    };
    importFrom.binding = (m, name, spec) => {
      if (!hasOwn.call(m, name)) {
        throw new SyntaxError(`The requested module '${spec}' does not provide an export named '${name}'`);
      }
      return m[name];
    };
    const dynamic = (spec) => new Promise((ok) => ok(link(resolve(spec))));
    const meta = Object.freeze({ url, resolve });
    record.promise = (async () => {
      try {
        if (!fn) {
          const code = call('load', url);
          if (code === null || code === undefined) {
            throw new TypeError(`Failed to load module script: ${url}`);
          }
          fn = evalCode(code);
        }
        await fn(importFrom, exportNames, meta, dynamic, star);
        return ns;
      } finally {
        record.evaluating = false;
      }
    })();
    return record.promise;
  };
  register('__nx_module_run', (url, fn) => link(url, fn));
})();
''';

  // A JSC API context has no `queueMicrotask` (QuickJS-ng and browsers
  // do). Errors thrown by the callback go to `reportError` when a prelude
  // defines it, as in browsers.
  static const _queueMicrotaskShim = r'''
(() => {
  if (typeof globalThis.queueMicrotask === 'function') return;
  const resolved = Promise.resolve();
  const report = (e) => {
    const r = globalThis.reportError;
    if (typeof r === 'function') r(e);
  };
  Object.defineProperty(globalThis, 'queueMicrotask', {
    value: function queueMicrotask(callback) {
      if (typeof callback !== 'function') {
        throw new TypeError("Failed to execute 'queueMicrotask': parameter 1 is not of type 'Function'.");
      }
      resolved.then(() => callback()).catch(report);
    },
    writable: true, enumerable: false, configurable: true,
  });
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
  /// the runtime reports the page as over budget).
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

  /// Lets `Atomics.wait` block the calling thread. Enable it only on worker
  /// isolates; the UI thread must never block (browsers throw there too).
  set canBlock(bool value) {
    _checkAlive();
    _canBlock = value;
  }

  bool _canBlock = false;

  /// Runs an ES module. A module that declares no `import`/`export` (a
  /// bundle) runs as a strict async function body; any other is rewritten by
  /// [ModuleTransform] and linked by the engine's module registry, which
  /// loads dependencies through [moduleHost] (sources must be prefetched).
  /// Top-level `this` is undefined, declarations are module-scoped,
  /// top-level `await` works and `import.meta.url` is [url]. Imported
  /// bindings are snapshots taken when the dependency finished evaluating,
  /// not live bindings. Errors after the call returns go to [moduleHost]'s
  /// `onError`; an unsupported module shape throws [JavaScriptException].
  @override
  void evaluateModule(String source, {required String url}) {
    _checkAlive();
    final scan = ModuleSourceScan.of(source);
    if (!scan.linksModules) {
      final body = scan.replaceImportMeta(source, '__nx_import_meta');
      final wrapped =
          '(async function (__nx_import_meta) {\'use strict\';\n$body\n})'
          '.call(undefined, Object.freeze({ url: ${jsonEncode(url)} }))';
      _enter(() {
        _catchModuleError(_evaluateRaw(wrapped, url));
        return null;
      });
      return;
    }
    final String code;
    try {
      code = ModuleTransform.transform(source);
    } on ModuleTransformException catch (e) {
      throw JavaScriptException(name: 'SyntaxError', message: '${e.message} ($url)');
    }
    _enter(() {
      final fn = _evaluateRaw(code, url);
      final run = _registryFunction('__nx_module_run');
      if (run == null) return null;
      final args = calloc<_Ref>(2);
      final exception = calloc<_Ref>();
      final urlString = _string(url);
      try {
        args[0] = _api.makeString(_ctx, urlString);
        args[1] = fn;
        final promise = _api.callFunction(_ctx, run, nullptr, 2, args, exception);
        if (exception.value != nullptr) throw _error(exception.value);
        _catchModuleError(promise);
      } finally {
        _api.stringRelease(urlString);
        calloc.free(args);
        calloc.free(exception);
      }
      return null;
    });
  }

  // Sends a rejection of [promise] to the `__nx_module_error` callback.
  void _catchModuleError(_Ref promise) {
    final onError = _registryFunction('__nx_module_error');
    if (onError == null || !_api.isObject(_ctx, promise)) return;
    final key = _string('catch');
    final args = calloc<_Ref>()..value = onError;
    final exception = calloc<_Ref>();
    try {
      final catcher = _api.getProperty(_ctx, promise, key, nullptr);
      if (_isCallable(catcher)) {
        _api.callFunction(_ctx, catcher, promise, 1, args, exception);
        if (exception.value != nullptr) throw _error(exception.value);
      }
    } finally {
      calloc.free(args);
      calloc.free(exception);
      _api.stringRelease(key);
    }
  }

  Object? _moduleRequest(List<Object?> args) {
    final op = args[0] as String;
    final host = moduleHost;
    if (host == null) {
      throw JavaScriptHostError('TypeError', 'modules are not enabled');
    }
    switch (op) {
      case 'resolve':
        return host.resolve(args[1] as String, args[2] as String);
      case 'load':
        final source = host.source(args[1] as String);
        if (source == null) return null;
        try {
          return ModuleTransform.transform(source);
        } on ModuleTransformException catch (e) {
          throw JavaScriptHostError('SyntaxError', '${e.message} (${args[1]})');
        }
    }
    throw JavaScriptHostError('TypeError', 'unknown module request');
  }

  _Ref? _registryFunction(String name) {
    final key = _string(name);
    try {
      final fn = _api.getProperty(_ctx, _registry, key, nullptr);
      return _isCallable(fn) ? fn : null;
    } finally {
      _api.stringRelease(key);
    }
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

  /// Engine heap bytes from `JSGetMemoryUsageStatistics` (0 when the
  /// library does not export it): the live heap at the last collection
  /// (`heapSize`, which JSC only counts while collecting) plus out-of-cell
  /// memory such as array buffers. Before the first collection, the
  /// reserved heap (`heapCapacity`). Call [collectGarbage] first for a
  /// current figure.
  @override
  int get memoryUsed {
    _checkAlive();
    final stats = _heapStats();
    if (stats == null) return 0;
    return (stats.size > 0 ? stats.size : stats.capacity) + stats.extra;
  }

  ({int size, int capacity, int extra})? _heapStats() {
    final stats = _api.memoryStatistics;
    if (stats == null) return null;
    final object = stats(_ctx);
    if (object == nullptr) return null;
    return (
      size: _numberProperty(object, 'heapSize'),
      capacity: _numberProperty(object, 'heapCapacity'),
      extra: _numberProperty(object, 'extraMemorySize'),
    );
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

  /// A full collection, synchronous when the library exports
  /// `JSSynchronousGarbageCollectForDebugging` (`JSGarbageCollect` only
  /// schedules one). Then calls the `__nx_after_gc` callback a prelude may
  /// register, because JSC does not run FinalizationRegistry callbacks
  /// without its run loop.
  @override
  void collectGarbage() {
    _checkAlive();
    final collect = _api.synchronousCollect ?? _api.collect;
    collect(_ctx);
    if (_depth == 0 && _registryFunction('__nx_after_gc') != null) {
      callGlobal('__nx_after_gc');
      // What the callback released (cache entries) is garbage only now.
      collect(_ctx);
    }

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
    final reserved = _heapStats();
    var used = reserved == null ? 0 : reserved.capacity + reserved.extra;
    if (used > limit) {
      // Reserved bytes include garbage; only live bytes after a full
      // collection count against the limit.
      (_api.synchronousCollect ?? _api.collect)(_ctx);
      final live = _heapStats();
      used = live == null ? 0 : live.size + live.extra;
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
      // A value without a JSON form (cycles, BigInt, a throwing toJSON) is
      // returned as null, not as a script error: the engine contract.
      if (exception.value != nullptr) return null;
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

  _Ref _onSabAlloc(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    final length = argc < 1 ? 0 : _api.toNumber(ctx, argv[0], nullptr).toInt();
    final data = b.nx_sab_alloc(length);
    if (data == nullptr) {
      exc.value = _makeString(ctx, 'SharedArrayBuffer allocation failed');
      return _api.makeUndefined(ctx);
    }
    return _api.bufferNoCopy(
      ctx,
      data,
      length,
      Native.addressOf<NativeFunction<_Deallocator>>(b.nx_sab_release),
      nullptr,
      exc,
    );
  }

  _Ref _onSabShare(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    final data = argc < 1 || !_api.isObject(ctx, argv[0])
        ? nullptr
        : _api.bufferBytes(ctx, argv[0], nullptr);
    final id = data == nullptr ? 0 : b.nx_sab_share(data);
    if (id == 0) {
      exc.value = _makeString(ctx, 'SharedArrayBuffer expected');
      return _api.makeUndefined(ctx);
    }
    return _api.makeNumber(ctx, id.toDouble());
  }

  // The address of a 32-bit cell of a shared block, or null when [buffer]
  // is not one or [offset] is outside it.
  Pointer<Void>? _sabCell(_Ref ctx, _Ref buffer, _Ref offsetValue) {
    if (!_api.isObject(ctx, buffer)) return null;
    final base = _api.bufferBytes(ctx, buffer, nullptr);
    if (base == nullptr || b.nx_sab_is_block(base) == 0) return null;
    final offset = _api.toNumber(ctx, offsetValue, nullptr).toInt();
    if (offset < 0 || offset % 4 != 0 || offset + 4 > b.nx_sab_length(base)) {
      return null;
    }
    return Pointer<Void>.fromAddress(base.address + offset);
  }

  _Ref _onSabWait(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    if (!_canBlock) {
      exc.value = _makeString(ctx, 'TypeError: Atomics.wait cannot be called in this context');
      return _api.makeUndefined(ctx);
    }
    final cell = argc < 4 ? null : _sabCell(ctx, argv[0], argv[1]);
    if (cell == null) {
      exc.value = _makeString(ctx, 'invalid shared cell');
      return _api.makeUndefined(ctx);
    }
    final expected = _api.toNumber(ctx, argv[2], nullptr).toInt();
    final timeout = _api.toNumber(ctx, argv[3], nullptr);
    return _api.makeNumber(
      ctx,
      b.nx_sab_wait(cell, expected.toSigned(32), timeout).toDouble(),
    );
  }

  _Ref _onSabNotify(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    final cell = argc < 3 ? null : _sabCell(ctx, argv[0], argv[1]);
    if (cell == null) {
      exc.value = _makeString(ctx, 'invalid shared cell');
      return _api.makeUndefined(ctx);
    }
    final count = _api.toNumber(ctx, argv[2], nullptr).toInt();
    return _api.makeNumber(ctx, b.nx_sab_notify(cell, count).toDouble());
  }

  _Ref _onSabOpen(_Ref ctx, int argc, Pointer<_Ref> argv, Pointer<_Ref> exc) {
    final id = argc < 1 ? 0 : _api.toNumber(ctx, argv[0], nullptr).toInt();
    final data = b.nx_sab_open(id);
    if (data == nullptr) {
      exc.value = _makeString(ctx, 'unknown shared buffer $id');
      return _api.makeUndefined(ctx);
    }
    return _api.bufferNoCopy(
      ctx,
      data,
      b.nx_sab_length(data),
      Native.addressOf<NativeFunction<_Deallocator>>(b.nx_sab_release),
      nullptr,
      exc,
    );
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
