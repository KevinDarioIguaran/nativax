import 'package:nativa_dom/nativa_dom.dart' as dom;

/// Opt-in, timestamped log of what the renderer actually draws.
///
/// Enable with `NATIVAX_TRACE_DRAW=1` on the host. It is deliberately
/// separate from the performance counters: it answers "which element was
/// painted, at what time, with what size", not "how many styles were
/// computed".
class NativaXDrawTrace {
  NativaXDrawTrace._();

  static bool enabled = false;
  static final Stopwatch _clock = Stopwatch();

  static void start() {
    if (_clock.isRunning) return;
    _clock.start();
  }

  static int get nowMs => _clock.elapsedMilliseconds;

  static String describe(dom.Element e) {
    final id = e.id.isEmpty ? '' : '#${e.id}';
    final classes = e.classList.isEmpty ? '' : '.${e.classList.join('.')}';
    return '<${e.localName}$id$classes>';
  }

  static void log(String message) {
    if (!enabled) return;
    start();
    // ignore: avoid_print
    print('DRAW ${nowMs}ms $message');
  }
}
