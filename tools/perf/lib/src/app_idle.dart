import 'dart:io';

import 'model.dart';
import 'proc_sampler.dart';

class AppIdleResult {
  const AppIdleResult({
    required this.status,
    required this.rssTailMb,
    required this.rssPeakMb,
    required this.cpuTailPct,
    required this.cpuPeakPct,
    required this.gpuBusyPct,
    required this.samples,
    this.error,
  });

  final String status;
  final double rssTailMb;
  final double rssPeakMb;
  final double cpuTailPct;
  final double cpuPeakPct;
  final double? gpuBusyPct;
  final List<ProcSample> samples;
  final String? error;

  Map<String, Object?> toJson() => {
    'status': status,
    'rss_tail_mb': _r(rssTailMb),
    'rss_peak_mb': _r(rssPeakMb),
    'cpu_tail_pct': _r(cpuTailPct),
    'cpu_peak_pct': _r(cpuPeakPct),
    'gpu_busy_pct': gpuBusyPct == null ? null : _r(gpuBusyPct!),
    'samples': [for (final s in samples) s.toJson()],
    if (error != null) 'error': error,
  };
}

/// Measures the real Flutter Linux app idling on a blank page.
///
/// This is the number that matters for the 250 MB / 0 % CPU target; the
/// offscreen `flutter test` baseline is only a harness reference.
Future<AppIdleResult> measureAppIdle({
  required String repoRoot,
  int warmupSeconds = 3,
  int idleSeconds = 5,
  bool build = false,
  void Function(String message)? log,
}) async {
  final bundle =
      '$repoRoot/examples/web-challenge/build/linux/x64/release/bundle';
  final executable = '$bundle/nativax_web_challenge_example';
  if (!File(executable).existsSync()) {
    if (!build) {
      return const AppIdleResult(
        status: 'unavailable',
        rssTailMb: 0,
        rssPeakMb: 0,
        cpuTailPct: 0,
        cpuPeakPct: 0,
        gpuBusyPct: null,
        samples: [],
        error: 'release bundle not built; pass --build',
      );
    }
    log?.call('building Linux release app ...');
    final result = await Process.run('flutter', [
      'build',
      'linux',
      '--release',
    ], workingDirectory: '$repoRoot/examples/web-challenge');
    if (result.exitCode != 0) {
      return AppIdleResult(
        status: 'failed',
        rssTailMb: 0,
        rssPeakMb: 0,
        cpuTailPct: 0,
        cpuPeakPct: 0,
        gpuBusyPct: null,
        samples: const [],
        error: 'build failed: ${result.stderr}',
      );
    }
  }

  final pageDir = Directory('$repoRoot/.perf/app-idle')
    ..createSync(recursive: true);
  File('${pageDir.path}/index.html').writeAsStringSync(
    '<!doctype html><html><head><meta charset="utf-8">'
    '<style>html,body{margin:0;padding:0;background:#fff}</style></head>'
    '<body><div id="idle">idle</div></body></html>',
  );

  log?.call(
    'launching app for ${warmupSeconds}s warmup + ${idleSeconds}s idle ...',
  );
  final process = await Process.start(
    'setsid',
    [executable],
    environment: {
      'NATIVAX_PERF_PAGE': pageDir.path,
      'GDK_BACKEND': Platform.environment['GDK_BACKEND'] ?? 'wayland,x11',
    },
    includeParentEnvironment: true,
  );
  final sampler = ProcTreeSampler(process.pid);
  await sampler.start();
  await Future<void>.delayed(Duration(seconds: warmupSeconds));
  final idleStartIndex = sampler.samples.length;
  await Future<void>.delayed(Duration(seconds: idleSeconds));
  await sampler.stop();
  process.kill(ProcessSignal.sigkill);
  await Process.run('kill', ['-KILL', '-${process.pid}']);

  final idleSamples = sampler.samples.length > idleStartIndex
      ? sampler.samples.sublist(idleStartIndex)
      : sampler.samples;
  double tailOf(List<double> values) {
    if (values.isEmpty) return 0;
    final tail = values.length <= 3
        ? values
        : values.sublist(values.length - 3);
    final sorted = [...tail]..sort();
    return sorted[sorted.length ~/ 2];
  }

  final rss = idleSamples.map((s) => s.rssMb).where((v) => v > 0).toList();
  final cpu = idleSamples.map((s) => s.cpuPct).toList();
  return AppIdleResult(
    status: rss.isEmpty ? 'failed' : 'ok',
    rssTailMb: tailOf(rss),
    rssPeakMb: rss.isEmpty ? 0 : rss.reduce((a, b) => a > b ? a : b),
    cpuTailPct: tailOf(cpu),
    cpuPeakPct: cpu.isEmpty ? 0 : cpu.reduce((a, b) => a > b ? a : b),
    gpuBusyPct: readGpuBusyPercent(),
    samples: idleSamples,
    error: rss.isEmpty ? 'the app exited before the idle window' : null,
  );
}

double _r(double value) => value.isFinite ? (value * 1000).round() / 1000 : 0;
