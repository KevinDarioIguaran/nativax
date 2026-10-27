import 'dart:io';

import 'exceptions.dart';
import 'javascript_engine.dart';
import 'jsc_engine.dart';

/// The engine a page or worker runtime uses: [JscEngine], the host's
/// JavaScriptCore (`NATIVAX_JSC_LIB` overrides its path). Throws
/// [JavaScriptEngineStateException] where JavaScriptCore cannot be loaded
/// (Android and Windows ship none; the app must bundle one).
///
/// [environment] defaults to [Platform.environment].
JavaScriptEngine createDefaultJavaScriptEngine(
  JavaScriptEngineConfig config, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final path = env['NATIVAX_JSC_LIB'];
  return JscEngine(config, path == null || path.isEmpty ? null : path);
}

/// An engine by name for tools and harnesses. Only `jsc` exists.
/// Throws [JavaScriptEngineStateException] for any other name.
JavaScriptEngine createJavaScriptEngineNamed(
  String name, [
  JavaScriptEngineConfig config = const JavaScriptEngineConfig(),
]) => switch (name) {
  'jsc' => JscEngine(config),
  _ => throw JavaScriptEngineStateException(
    'unknown engine "$name"; NativaX runs on JavaScriptCore only (jsc)',
  ),
};
