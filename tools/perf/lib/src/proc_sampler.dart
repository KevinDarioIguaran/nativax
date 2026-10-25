import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'model.dart';

class _ProcInfo {
  _ProcInfo(this.pid, this.ppid, this.rssPages, this.ticks);
  final int pid;
  final int ppid;
  final int rssPages;
  final int ticks;
}

/// Samples the resident memory and CPU of a process tree using `/proc`.
///
/// Only Linux is supported; on other platforms the sampler returns empty
/// samples instead of inventing numbers.
class ProcTreeSampler {
  ProcTreeSampler(
    this.rootPid, {
    this.interval = const Duration(milliseconds: 250),
  }) : _clock = Stopwatch()..start();

  final int rootPid;
  final Duration interval;
  final Stopwatch _clock;
  final List<ProcSample> samples = [];
  Timer? _timer;
  double? _previousTicks;
  int? _previousMs;
  int _pageSizeKb = 4;
  int _clkTck = 100;
  ProcSample _lastSample = const ProcSample(
    elapsedMs: 0,
    rssMb: 0,
    cpuPct: 0,
    processes: 0,
  );

  static bool get supported => Platform.isLinux;

  Future<void> start() async {
    if (!supported) return;
    await _readSystemConstants();
    await snapshot(record: true);
    _timer = Timer.periodic(interval, (_) => snapshot(record: true));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await snapshot(record: true);
  }

  Future<ProcSample> snapshot({bool record = false}) async {
    if (!supported)
      return const ProcSample(elapsedMs: 0, rssMb: 0, cpuPct: 0, processes: 0);
    final procs = <int, _ProcInfo>{};
    for (final entity in Directory('/proc').listSync(followLinks: false)) {
      final name = entity.path.split('/').last;
      final pid = int.tryParse(name);
      if (pid == null) continue;
      final info = _readProc(pid);
      if (info != null) procs[pid] = info;
    }
    final tree = _descendants(rootPid, procs);
    // The root may already be gone when the sampler stops; never record a
    // phantom 0 MB sample and call it idle memory.
    if (!procs.containsKey(rootPid)) {
      return _lastSample;
    }
    var rssPages = 0;
    var ticks = 0;
    for (final pid in tree) {
      final info = procs[pid];
      if (info == null) continue;
      rssPages += info.rssPages;
      ticks += info.ticks;
    }
    final nowMs = _clock.elapsedMilliseconds;
    var cpu = 0.0;
    if (_previousTicks != null && _previousMs != null && nowMs > _previousMs!) {
      final elapsedSeconds = (nowMs - _previousMs!) / 1000;
      cpu = (ticks - _previousTicks!) / (_clkTck * elapsedSeconds) * 100;
      if (cpu < 0) cpu = 0;
    }
    _previousTicks = ticks.toDouble();
    _previousMs = nowMs;
    final sample = ProcSample(
      elapsedMs: nowMs,
      rssMb: rssPages / 1024,
      cpuPct: cpu,
      processes: tree.length,
    );
    _lastSample = sample;
    if (record) samples.add(sample);
    return sample;
  }

  Set<int> _descendants(int root, Map<int, _ProcInfo> procs) {
    final children = <int, List<int>>{};
    for (final info in procs.values) {
      children.putIfAbsent(info.ppid, () => []).add(info.pid);
    }
    final result = <int>{};
    final stack = <int>[root];
    while (stack.isNotEmpty) {
      final pid = stack.removeLast();
      if (!result.add(pid)) continue;
      stack.addAll(children[pid] ?? const []);
    }
    return result;
  }

  _ProcInfo? _readProc(int pid) {
    try {
      final stat = File('/proc/$pid/stat').readAsStringSync();
      final close = stat.lastIndexOf(')');
      if (close < 0) return null;
      final fields = stat.substring(close + 2).split(' ');
      if (fields.length < 22) return null;
      final ppid = int.tryParse(fields[1]) ?? 0;
      final utime = int.tryParse(fields[11]) ?? 0;
      final stime = int.tryParse(fields[12]) ?? 0;
      final rssPages = int.tryParse(fields[21]) ?? 0;
      // Prefer PSS: summing RSS across Chrome's 15+ processes counts shared
      // libraries many times and produces a misleading 1 GB idle number.
      final pssKb = _readPssKb(pid);
      final rssKb = math.max(0, rssPages) * _pageSizeKb;
      return _ProcInfo(pid, ppid, pssKb ?? rssKb, utime + stime);
    } catch (_) {
      return null;
    }
  }

  int? _readPssKb(int pid) {
    try {
      final text = File('/proc/$pid/smaps_rollup').readAsStringSync();
      final match = RegExp(
        r'^Pss:\s+(\d+) kB',
        multiLine: true,
      ).firstMatch(text);
      if (match != null) return int.parse(match.group(1)!);
    } catch (_) {}
    return null;
  }

  Future<void> _readSystemConstants() async {
    try {
      final result = await Process.run('getconf', ['CLK_TCK']);
      final value = int.tryParse('${result.stdout}'.trim());
      if (value != null && value > 0) _clkTck = value;
    } catch (_) {
      // 100 is the Linux default.
    }
    try {
      final result = await Process.run('getconf', ['PAGESIZE']);
      final value = int.tryParse('${result.stdout}'.trim());
      if (value != null && value > 0) _pageSizeKb = value ~/ 1024;
    } catch (_) {
      // 4 KiB pages are the common default.
    }
  }
}

/// Returns the GPU busy percentage when the kernel exposes it, or null.
double? readGpuBusyPercent() {
  if (!Platform.isLinux) return null;
  try {
    final drm = Directory('/sys/class/drm');
    if (!drm.existsSync()) return null;
    for (final entity in drm.listSync(followLinks: false)) {
      final file = File('${entity.path}/device/gpu_busy_percent');
      if (!file.existsSync()) continue;
      final value = double.tryParse(file.readAsStringSync().trim());
      if (value != null) return value;
    }
  } catch (_) {}
  return null;
}
