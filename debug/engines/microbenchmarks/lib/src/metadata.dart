import 'dart:io';

import 'package:nativa_js/nativa_js.dart' show JscEngine;
import 'package:path/path.dart' as p;

import 'model.dart';

/// Builds the environment metadata included in every JSON report.
/// [repoRoot] is accepted for compatibility; the engine version comes from
/// the loaded JavaScriptCore.
RunMetadata collectMetadata({String? repoRoot}) {
  return RunMetadata(
    engine: 'JavaScriptCore',
    engineVersion: JscEngine.version(),
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
