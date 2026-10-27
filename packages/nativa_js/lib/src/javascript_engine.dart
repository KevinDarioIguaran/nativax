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
    this.microtaskSlice = Duration.zero,
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

  /// Optional wall-clock slice for one microtask drain. When non-zero, the
  /// engine yields back to the host after this much work and leaves remaining
  /// promise jobs queued. Zero preserves browser-like full drains.
  final Duration microtaskSlice;
}

/// Engine-neutral contract. NativaX ships one implementation
/// ([JscEngine]); the interface exists so tests and future adapters (for
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

  /// Evaluates an ES module located at [url] (`import.meta.url`). Its
  /// imports are resolved and loaded through [moduleHost]. Evaluation is
  /// asynchronous when the module graph uses top-level `await`; rejections
  /// are reported to [ModuleHost.onError].
  void evaluateModule(String source, {required String url});

  /// Supplies module resolution and sources; null rejects every import.
  ModuleHost? get moduleHost;
  set moduleHost(ModuleHost? host);

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

/// Module resolution for [JavaScriptEngine.evaluateModule]. Module loading
/// in QuickJS is synchronous, so the host must have every source ready
/// (prefetched) when [source] is called.
abstract interface class ModuleHost {
  /// The absolute URL of [specifier] imported from the module at [base].
  /// Throw [JavaScriptHostError] to reject the import.
  String resolve(String base, String specifier);

  /// The source text of the module at [url], or null when unavailable.
  String? source(String url);

  /// A module evaluation (or one of its asynchronous imports) failed.
  void onError(JavaScriptException error);
}
