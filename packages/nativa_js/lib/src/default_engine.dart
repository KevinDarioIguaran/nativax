import 'dart:io';

import 'exceptions.dart';
import 'javascript_engine.dart';
import 'jsc_engine.dart';
import 'quickjs_engine.dart';
import 'v8_engine.dart';

/// The engine a page runtime uses when the host does not choose one:
/// [V8Engine] on desktop (Linux, macOS, Windows) when its cdylib loads and no
/// other V8 engine is live on this thread, [QuickJsEngine] otherwise (mobile,
/// no JIT, missing library, `NATIVAX_ENGINE=quickjs`).
/// `NATIVAX_ENGINE=jsc` opts into [JscEngine] where JavaScriptCore loads
/// (`NATIVAX_JSC_LIB` overrides its path); elsewhere the usual choice applies.
///
/// [environment] defaults to [Platform.environment] (`NATIVAX_ENGINE`,
/// `NATIVAX_V8_LIB`, `NATIVAX_JSC_LIB`).
JavaScriptEngine createDefaultJavaScriptEngine(
  JavaScriptEngineConfig config, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  if (env['NATIVAX_ENGINE'] == 'jsc') {
    final path = env['NATIVAX_JSC_LIB'];
    if (JscEngine.isAvailable(path)) return JscEngine(config, path);
  }
  final desktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  if (desktop &&
      env['NATIVAX_ENGINE'] != 'quickjs' &&
      !V8Engine.hasLiveInstance) {
    final path = env['NATIVAX_V8_LIB'] ?? 'libnx_v8.so';
    if (V8Engine.isAvailable(path)) {
      try {
        return V8Engine(config, path);
      } on JavaScriptEngineStateException {
        // Fall through to QuickJS.
      }
    }
  }
  return QuickJsEngine(config);
}

/// An engine by name for tools and harnesses: `quickjs`, `v8` or `jsc`.
/// Throws [JavaScriptEngineStateException] when that engine cannot load.
JavaScriptEngine createJavaScriptEngineNamed(
  String name, [
  JavaScriptEngineConfig config = const JavaScriptEngineConfig(),
]) => switch (name) {
  'quickjs' => QuickJsEngine(config),
  'jsc' => JscEngine(config),
  'v8' => V8Engine(config),
  _ => throw JavaScriptEngineStateException('unknown engine "$name"'),
};
