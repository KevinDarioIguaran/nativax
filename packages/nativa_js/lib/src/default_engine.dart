import 'javascript_engine.dart';
import 'jsc_engine.dart';

/// The engine a page runtime uses when the host does not choose one:
/// [JscEngine] (JavaScriptCore) on every platform.
JavaScriptEngine createDefaultJavaScriptEngine(
  JavaScriptEngineConfig config, {
  Map<String, String>? environment,
}) {
  return JscEngine(config);
}