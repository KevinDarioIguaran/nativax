import 'dart:collection';
import 'dart:ffi';
import 'dart:typed_data';

import 'ffi/bindings.dart' as b;

/// Moves byte buffers between Dart and script code without JSON: Dart parks
/// bytes under an id, and script code adopts them as an `ArrayBuffer` with
/// `__nx.takeBuffer(id)` (and the reverse with `__nx.putBuffer(view)`). Ids
/// are process-wide, so they also cross isolates.
abstract final class NativeBuffers {
  /// Copies [bytes] into native memory and returns its id.
  static int put(Uint8List bytes) {
    final ptr = b.nx_alloc(bytes.isEmpty ? 1 : bytes.length).cast<Uint8>();
    if (bytes.isNotEmpty) ptr.asTypedList(bytes.length).setAll(0, bytes);
    return b.nx_buffer_put(ptr.cast(), bytes.length);
  }

  /// Removes the buffer [id] and returns a copy of its bytes, or null if no
  /// such buffer is parked.
  static Uint8List? take(int id) {
    final len = b.nx_alloc(sizeOf<Int64>()).cast<Int64>();
    try {
      final ptr = b.nx_buffer_take(id, len);
      if (len.value < 0) return null;
      final out = Uint8List.fromList(ptr.cast<Uint8>().asTypedList(len.value));
      b.nx_free(ptr);
      return out;
    } finally {
      b.nx_free(len.cast());
    }
  }
}

/// Canvas backing stores shared between script runtimes (any thread) and the
/// UI: WebGL contexts publish frames into a surface; the renderer shows the
/// latest one.
class _SurfacePresentation {
  int frames = 0;
  int width = 0;
  int height = 0;
  int decodeMicros = 0;
  int lastShownMicros = 0;
  final ListQueue<int> intervals = ListQueue<int>();
  final ListQueue<int> decodes = ListQueue<int>();

  void addInterval(int micros) {
    if (micros <= 0) return;
    intervals.add(micros);
    while (intervals.length > 240) {
      intervals.removeFirst();
    }
  }

  void addDecode(int micros) {
    decodes.add(micros);
    while (decodes.length > 240) {
      decodes.removeFirst();
    }
  }
}

abstract final class GlSurfaces {
  /// Whether WebGL is available (EGL + OpenGL ES 3 loaded).
  static bool get available => b.nx_gl_available() != 0;

  static int create() => b.nx_surface_create();
  static void retain(int id) => b.nx_surface_retain(id);
  static void release(int id) => b.nx_surface_release(id);

  /// Counter of the newest presented frame (0: none yet).
  static int frame(int id) => b.nx_surface_frame(id);

  static final Map<int, _SurfacePresentation> _presentation = {};
  static final Stopwatch _presentationClock = Stopwatch()..start();

  /// Frames actually decoded and shown by a [GlSurfaceView]. Compare with
  /// [frame] to distinguish renderer throughput from presentation throughput.
  static int shown(int id) => _presentation[id]?.frames ?? 0;

  /// Size of the most recently shown drawing buffer.
  static int shownWidth(int id) => _presentation[id]?.width ?? 0;
  static int shownHeight(int id) => _presentation[id]?.height ?? 0;

  /// Time spent decoding the most recent frame on the UI isolate.
  static int decodeMicros(int id) => _presentation[id]?.decodeMicros ?? 0;

  /// Number of presentation intervals in the rolling window.
  static int presentSamples(int id) => _presentation[id]?.intervals.length ?? 0;

  /// Presentation cadence percentiles in microseconds (time between shown
  /// frames). These are measured on the UI isolate, after decode.
  static int presentP50Micros(int id) =>
      _percentile(_presentation[id]?.intervals, 0.50);
  static int presentP95Micros(int id) =>
      _percentile(_presentation[id]?.intervals, 0.95);
  static int presentP99Micros(int id) =>
      _percentile(_presentation[id]?.intervals, 0.99);

  /// Decode latency percentiles in microseconds for the same rolling window.
  static int decodeP50Micros(int id) =>
      _percentile(_presentation[id]?.decodes, 0.50);
  static int decodeP95Micros(int id) =>
      _percentile(_presentation[id]?.decodes, 0.95);
  static int decodeP99Micros(int id) =>
      _percentile(_presentation[id]?.decodes, 0.99);

  /// Called by the Flutter view after a decoded frame is installed.
  static void markShown(
    int id, {
    int width = 0,
    int height = 0,
    int decodeMicros = 0,
  }) {
    final stats = _presentation.putIfAbsent(id, _SurfacePresentation.new);
    final now = _presentationClock.elapsedMicroseconds;
    if (stats.lastShownMicros > 0) {
      stats.addInterval(now - stats.lastShownMicros);
    }
    stats.lastShownMicros = now;
    stats.frames++;
    stats.width = width;
    stats.height = height;
    stats.decodeMicros = decodeMicros;
    stats.addDecode(decodeMicros);
  }

  static int _percentile(ListQueue<int>? values, double p) {
    if (values == null || values.isEmpty) return 0;
    final sorted = values.toList()..sort();
    var index = ((sorted.length - 1) * p).round();
    if (index < 0) index = 0;
    if (index >= sorted.length) index = sorted.length - 1;
    return sorted[index];
  }

  /// The latest frame as premultiplied RGBA8, top row first. The returned
  /// view aliases native memory that stays valid until the next [acquire]
  /// of the same surface.
  static ({Uint8List pixels, int width, int height, int frame})? acquire(
    int id,
  ) {
    final w = b.nx_alloc(4).cast<Int32>();
    final h = b.nx_alloc(4).cast<Int32>();
    final f = b.nx_alloc(8).cast<Int64>();
    try {
      final ptr = b.nx_surface_acquire(id, w, h, f);
      if (ptr == nullptr || w.value <= 0 || h.value <= 0) return null;
      return (
        pixels: ptr.asTypedList(w.value * h.value * 4),
        width: w.value,
        height: h.value,
        frame: f.value,
      );
    } finally {
      b.nx_free(w.cast());
      b.nx_free(h.cast());
      b.nx_free(f.cast());
    }
  }
}
