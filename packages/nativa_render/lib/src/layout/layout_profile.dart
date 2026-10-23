/// Opt-in layout profiler for the renderer.
///
/// Enable at compile time with `--dart-define=NATIVAX_RENDER_PROFILE=true`.
/// It attributes layout, dry-layout and intrinsic passes by kind so a frame's
/// build/layout cost can be diagnosed without changing the visual tree.
class LayoutProfile {
  LayoutProfile._();

  static const bool enabled =
      bool.fromEnvironment('NATIVAX_RENDER_PROFILE', defaultValue: false);

  static final Map<String, _Bucket> _buckets = {};
  static final List<_Entry> _stack = [];

  static void begin(String kind) {
    if (!enabled) return;
    _stack.add(_Entry(kind, Stopwatch()..start()));
  }

  static void end() {
    if (!enabled || _stack.isEmpty) return;
    final entry = _stack.removeLast();
    entry.watch.stop();
    final us = entry.watch.elapsedMicroseconds;
    if (_stack.isNotEmpty) _stack.last.childUs += us;
    final bucket = _buckets.putIfAbsent(entry.kind, () => _Bucket());
    bucket.calls++;
    bucket.totalUs += us;
    bucket.selfUs += us - entry.childUs;
    if (us > bucket.maxUs) bucket.maxUs = us;
  }

  static T measure<T>(String kind, T Function() body) {
    if (!enabled) return body();
    begin(kind);
    try {
      return body();
    } finally {
      end();
    }
  }

  static void reset() {
    _buckets.clear();
    _stack.clear();
  }

  static String summary() {
    if (!enabled || _buckets.isEmpty) return 'layout profile: no data';
    final entries = _buckets.entries.toList()
      ..sort((a, b) => b.value.selfUs.compareTo(a.value.selfUs));
    final b = StringBuffer('LAYOUT_PROFILE');
    for (final e in entries.take(12)) {
      final s = e.value;
      b.write(' | ${e.key} calls=${s.calls} '
          'self=${(s.selfUs / 1000).toStringAsFixed(1)}ms '
          'total=${(s.totalUs / 1000).toStringAsFixed(1)}ms '
          'max=${(s.maxUs / 1000).toStringAsFixed(1)}ms');
    }
    return b.toString();
  }
}

class _Entry {
  _Entry(this.kind, this.watch);
  final String kind;
  final Stopwatch watch;
  int childUs = 0;
}

class _Bucket {
  int calls = 0;
  int totalUs = 0;
  int selfUs = 0;
  int maxUs = 0;
}
