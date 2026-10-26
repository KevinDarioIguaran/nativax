import 'dart:io';

import 'package:path/path.dart' as p;

import 'model.dart';

/// Builds the environment metadata included in every JSON report.
///
/// [engineName] selects which engine the run used. The default (`quickjs`) is
/// the product engine; `v8` is the documented reference run through the same
/// Dart bridge (`NATIVAX_V8_LIB`).
RunMetadata collectMetadata({
  String? repoRoot,
  String engineName = 'quickjs',
}) {
  final root = repoRoot ?? findRepoRoot();
  final isV8 = engineName == 'v8';
  return RunMetadata(
    engine: isV8 ? 'V8 (libnx_v8.so)' : 'QuickJS-ng',
    engineVersion: isV8
        ? 'v8 crate 152.2.0 (tools/v8-spike)'
        : quickJsVersion(root),
    dartVersion: Platform.version.split(' ').first,
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    arch: _architecture(),
    mode: _executionMode(),
    clock: 'dart:core Stopwatch (monotonic)',
    clockFrequencyHz: Stopwatch().frequency,
    // Stopwatch exposes microseconds; the underlying clock resolution can be
    // coarser, so this is a documented lower bound, not a promise.
    clockResolutionMs: 1000 / Stopwatch().frequency,
    timestamp: DateTime.now(),
  );
}

String _executionMode() {
  const product = bool.fromEnvironment('dart.vm.product');
  if (product) return 'AOT';
  const profile = bool.fromEnvironment('dart.vm.profile');
  if (profile) return 'profile';
  return 'JIT';
}

String _architecture() {
  try {
    if (Platform.isWindows) {
      final arch = Platform.environment['PROCESSOR_ARCHITECTURE'];
      return arch?.toLowerCase() ?? 'unknown';
    }
    final result = Process.runSync('uname', ['-m']);
    if (result.exitCode == 0) {
      final value = (result.stdout as String).trim();
      if (value.isNotEmpty) return value;
    }
  } on ProcessException {
    // Fall through.
  }
  return 'unknown';
}

String quickJsVersion(String repoRoot) {
  final header = File(p.join(repoRoot, 'packages', 'nativa_js',
      'third_party', 'quickjs', 'quickjs.h'));
  if (!header.existsSync()) return 'unknown';
  final text = header.readAsStringSync();
  String value(String name, String fallback) {
    final match = RegExp('#define\\s+$name\\s+(\\d+)').firstMatch(text);
    return match?.group(1) ?? fallback;
  }

  return '${value('QJS_VERSION_MAJOR', '0')}.'
      '${value('QJS_VERSION_MINOR', '0')}.'
      '${value('QJS_VERSION_PATCH', '0')}';
}

/// Locates the repository root by walking up until the benchmark workspace
/// pubspec is found.
String findRepoRoot([String? start]) {
  var dir = Directory(p.absolute(start ?? Directory.current.path));
  while (true) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('nativa_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate the NativaX repository root');
    }
    dir = parent;
  }
}
