import 'exceptions.dart';

/// A host function callable from script code as `__nx.host(name, ...args)`.
///
/// Arguments arrive JSON-decoded (null, bool, num, String, List, Map). The
/// return value must be JSON-encodable. Throw [JavaScriptHostError] to raise a
/// typed error in script code; any other exception surfaces as a generic
/// `Error` without Dart details.
typedef HostFunction = Object? Function(List<Object?> args);

/// Limits applied to one engine instance.
class JavaScriptEngineConfig {
  const JavaScriptEngineConfig({
    this.memoryLimitBytes = 64 * 1024 * 1024,
    this.maxStackBytes = 256 * 1024,
    this.executionBudget = const Duration(seconds: 1),
    this.maxJobsPerDrain = 10000,
  });

  /// Heap ceiling enforced by QuickJS' allocator. 0 disables the limit.
  final int memoryLimitBytes;

  /// Maximum native stack QuickJS may use before throwing `RangeError`.
  ///
  /// Scripts run on the calling thread (the Flutter UI thread), so this must
  /// stay well below that thread's stack (as low as 512 KiB on iOS
  /// secondary threads and 1 MiB on the iOS main thread).
  final int maxStackBytes;

  /// Wall-clock budget for one entry from Dart into script code, including
  /// the microtasks drained after it. Exceeding it raises
  /// [JavaScriptTimeoutException]. [Duration.zero] disables the budget.
  final Duration executionBudget;

  /// Upper bound on promise jobs executed per drain, as a guard against
  /// self-rescheduling microtask loops.
  final int maxJobsPerDrain;
}

/// Engine-neutral contract. NativaX ships one implementation
/// ([QuickJsEngine]); the interface exists so tests and future adapters (for
/// example JavaScriptCore) can plug in without touching the DOM bindings.
///
/// The API is synchronous on purpose: DOM bindings require script code to call
/// back into Dart and receive results synchronously, as browsers do. Long
/// running work is bounded by [JavaScriptEngineConfig.executionBudget].
abstract interface class JavaScriptEngine {
  bool get isDisposed;

  /// Evaluates a classic script and returns its completion value decoded from
  /// JSON (`undefined`, functions and other non-serializable values become
  /// `null`). Pending microtasks are drained before returning.
  Object? evaluate(String source, {String filename = '<nativax>'});

  /// Calls `globalThis[functionName](argument)`; [argument] is JSON-encoded.
  Object? callGlobal(String functionName, [Object? argument]);

  /// Registers [function] under [name] for `__nx.host(name, ...args)`.
  void registerHostFunction(String name, HostFunction function);

  /// Runs pending promise jobs. Returns how many ran.
  int drainMicrotasks();

  bool get hasPendingMicrotasks;

  /// Bytes currently allocated by the engine heap.
  int get memoryUsed;

  void collectGarbage();

  /// Releases the native runtime. Further calls throw
  /// [JavaScriptEngineStateException].
  void dispose();
}
