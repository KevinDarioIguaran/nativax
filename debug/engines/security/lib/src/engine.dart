import 'dart:io';

import 'package:nativa_js/nativa_js.dart';

/// The engine every case runs on: `NATIVAX_ENGINE` (`quickjs` by default, or
/// `jsc` / `v8`), so the same suite audits each backend.
JavaScriptEngine newEngine([
  JavaScriptEngineConfig config = const JavaScriptEngineConfig(),
]) => createJavaScriptEngineNamed(
  Platform.environment['NATIVAX_ENGINE'] ?? 'quickjs',
  config,
);
