import 'dart:io';

import 'exceptions.dart';
import 'javascript_engine.dart';
import 'quickjs_engine.dart';
import 'v8_engine.dart';

/// The engine a page runtime uses when the host does not choose one:
/// [V8Engine] on desktop (Linux, macOS, Windows) when its cdylib loads and no
/// other V8 engine is live on this thread, [QuickJsEngine] otherwise (mobile,
/// no JIT, missing library, `NATIVAX_ENGINE=quickjs`).
///
/// [environment] defaults to [Platform.environment] (`NATIVAX_ENGINE`,
/// `NATIVAX_V8_LIB`).
JavaScriptEngine createDefaultJavaScriptEngine(
  JavaScriptEngineConfig config, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
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
