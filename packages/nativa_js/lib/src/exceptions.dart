/// An exception thrown by script code and not caught inside the engine.
class JavaScriptException implements Exception {
  JavaScriptException({
    required this.name,
    required this.message,
    this.stack,
  });

  /// The `name` of the thrown error (`TypeError`, `ReferenceError`, ...), or
  /// `Error` when a non-Error value was thrown.
  final String name;
  final String message;

  /// The engine's stack trace, when available.
  final String? stack;

  @override
  String toString() => '$name: $message${stack == null ? '' : '\n$stack'}';
}

/// Script execution exceeded the configured time budget and was interrupted.
///
/// Interruption is uncatchable from script code: `try/catch` cannot swallow it.
class JavaScriptTimeoutException extends JavaScriptException {
  JavaScriptTimeoutException({required super.message, super.stack})
      : super(name: 'TimeoutError');
}

/// The script hit the engine's memory limit and was stopped. The engine
/// itself remains usable.
class JavaScriptMemoryLimitException extends JavaScriptException {
  JavaScriptMemoryLimitException({required super.message, super.stack})
      : super(name: 'MemoryLimitError');
}

/// The engine has been disposed, or could not be created.
class JavaScriptEngineStateException implements Exception {
  JavaScriptEngineStateException(this.message);
  final String message;

  @override
  String toString() => 'JavaScriptEngineStateException: $message';
}

/// Thrown by a host function to raise a specific error type in script code.
///
/// [type] must be one of the standard constructors (`Error`, `TypeError`,
/// `RangeError`, `SyntaxError`); anything else is raised as `Error` with
/// `name` set to [type] (for example `NotFoundError`).
class JavaScriptHostError implements Exception {
  JavaScriptHostError(this.type, this.message);
  final String type;
  final String message;

  @override
  String toString() => '$type: $message';
}
