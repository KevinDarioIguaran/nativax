import 'dart:io';

enum SecurityStatus {
  pass('PASS'),
  fail('FAIL'),
  error('ERROR'),
  skip('SKIP'),
  inconclusive('INCONCLUSIVE');

  const SecurityStatus(this.label);
  final String label;
}

class SecurityCheck {
  const SecurityCheck({
    required this.status,
    required this.expected,
    required this.observed,
    this.evidence = const [],
    this.remediation = '',
  });

  final SecurityStatus status;
  final String expected;
  final String observed;
  final List<String> evidence;
  final String remediation;
}

class SecurityCase {
  const SecurityCase({
    required this.id,
    required this.category,
    required this.severity,
    required this.description,
    required this.run,
  });

  final String id;
  final String category;

  /// `critical`, `high`, `medium`, `low`, `informational`.
  final String severity;
  final String description;
  final Future<SecurityCheck> Function() run;
}

class SecurityResult {
  const SecurityResult({
    required this.id,
    required this.category,
    required this.severity,
    required this.description,
    required this.status,
    required this.expected,
    required this.observed,
    required this.durationMs,
    this.evidence = const [],
    this.remediation = '',
  });

  final String id;
  final String category;
  final String severity;
  final String description;
  final SecurityStatus status;
  final String expected;
  final String observed;
  final int durationMs;
  final List<String> evidence;
  final String remediation;

  Map<String, Object?> toJson() => {
        'id': id,
        'category': category,
        'severity': severity,
        'description': description,
        'status': status.name,
        'expected': expected,
        'observed': observed,
        'durationMs': durationMs,
        'evidence': evidence,
        'remediation': remediation,
      };
}

class SecurityRun {
  const SecurityRun({required this.metadata, required this.results});
  final SecurityMetadata metadata;
  final List<SecurityResult> results;

  Map<String, Object?> toJson() => {
        'metadata': metadata.toJson(),
        'results': [for (final r in results) r.toJson()],
      };
}

class SecurityMetadata {
  const SecurityMetadata({
    required this.engine,
    required this.engineVersion,
    required this.dartVersion,
    required this.mode,
    required this.os,
    required this.osVersion,
    required this.arch,
    required this.timestamp,
    required this.command,
    required this.limits,
  });

  final String engine;
  final String engineVersion;
  final String dartVersion;
  final String mode;
  final String os;
  final String osVersion;
  final String arch;
  final DateTime timestamp;
  final String command;
  final Map<String, String> limits;

  Map<String, Object?> toJson() => {
        'engine': engine,
        'engineVersion': engineVersion,
        'dartVersion': dartVersion,
        'mode': mode,
        'os': os,
        'osVersion': osVersion,
        'arch': arch,
        'timestamp': timestamp.toIso8601String(),
        'command': command,
        'limits': limits,
      };
}

SecurityMetadata collectSecurityMetadata({
  required String repoRoot,
  required String command,
}) {
  var arch = 'unknown';
  try {
    if (!Platform.isWindows) {
      final r = Process.runSync('uname', ['-m']);
      if (r.exitCode == 0) arch = (r.stdout as String).trim();
    }
  } on ProcessException {
    // Unknown.
  }
  return SecurityMetadata(
    engine: 'QuickJS-ng',
    engineVersion: _version(repoRoot),
    dartVersion: Platform.version.split(' ').first,
    mode: const bool.fromEnvironment('dart.vm.product') ? 'AOT' : 'JIT',
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
    arch: arch,
    timestamp: DateTime.now(),
    command: command,
    limits: const {
      'memoryBytes': '64 MiB default (per runtime)',
      'stackBytes': '256 KiB default',
      'executionBudget': '1 s default',
      'microtasksPerDrain': '10,000 default',
      'timers': '1,000 active / 4 ms minimum',
      'nodes': '100,000 / depth 256',
    },
  );
}

String _version(String root) {
  final f = File('$root/packages/nativax_js/third_party/quickjs/quickjs.h');
  if (!f.existsSync()) return 'unknown';
  final text = f.readAsStringSync();
  String v(String name) =>
      RegExp('#define\\s+$name\\s+(\\d+)').firstMatch(text)?.group(1) ?? '0';
  return '${v('QJS_VERSION_MAJOR')}.${v('QJS_VERSION_MINOR')}.'
      '${v('QJS_VERSION_PATCH')}';
}

String findSecurityRepoRoot([String? start]) {
  var dir = Directory(
      start == null ? Directory.current.absolute.path : start);
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('nativax_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate the NativaX repository root');
    }
    dir = parent;
  }
}
