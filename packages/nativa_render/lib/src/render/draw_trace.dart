import 'dart:io' as io;

import 'package:nativa_dom/nativa_dom.dart' as dom;

/// Opt-in, timestamped log of what the renderer actually draws.
///
/// Enable with `NATIVAX_TRACE_DRAW=1` on the host. It is deliberately
/// separate from the performance counters: it answers "which element was
/// painted, at what time, with what size", not "how many styles were
/// computed".
class NativaXDrawTrace {
  NativaXDrawTrace._();

  static bool enabled = _fromEnvironment();

  static bool _fromEnvironment() {
    try {
      return io.Platform.environment['NATIVAX_TRACE_DRAW'] == '1' ||
          io.Platform.environment['NATIVAX_TRACE_RENDER'] == '1';
    } catch (_) {
      return const bool.fromEnvironment('NATIVAX_TRACE_DRAW',
          defaultValue: false);
    }
  }
  static final Stopwatch _clock = Stopwatch();
  static final List<(int, String)> _slow = [];

  static void start() {
    if (_clock.isRunning) return;
    _clock.start();
  }

  static int get nowMs => _clock.elapsedMilliseconds;

  static String describe(dom.Element e) {
    final id = e.id.isEmpty ? '' : '#${e.id}';
    final classes = e.classList.isEmpty ? '' : '.${e.classList.join('.')}';
    final parent = e.parentElement;
    final parentName = parent == null
        ? ''
        : ' parent=<${parent.localName}'
            '${parent.id.isEmpty ? '' : '#${parent.id}'}>';
    return '<${e.localName}$id$classes>$parentName';
  }

  static void log(String message) {
    if (!enabled) return;
    start();
    // ignore: avoid_print
    print('DRAW ${nowMs}ms $message');
  }

  /// Logs only when the message is about a slow operation or a frame summary.
  /// This keeps trace files usable while full element tracing is enabled.
  static void slow(String message) => log(message);

  /// Records an operation that took [ms]; [flushSlowest] prints the worst
  /// operations of the frame with their element and phase.
  static void markSlow(String message, int ms) {
    if (!enabled || ms < 8) return;
    _slow.add((ms, message));
  }

  static void flushSlowest() {
    if (!enabled || _slow.isEmpty) return;
    _slow.sort((a, b) => b.$1.compareTo(a.$1));
    final b = StringBuffer('FRAME_SLOWEST');
    for (final e in _slow.take(8)) {
      b.write(' | ${e.$1}ms ${e.$2}');
    }
    // ignore: avoid_print
    print('DRAW ${nowMs}ms $b');
    _slow.clear();
  }
}
