import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:nativax/nativax.dart';
import 'package:nativax_dom/nativax_dom.dart' show canvasSurfaces;
import 'package:nativax_js/nativax_js.dart' show GlSurfaces;

/// Rolling presentation metrics for a NativaX app.
///
/// This widget deliberately avoids FPS averages: it reports p50/p95/p99 for
/// Flutter build/raster/total frame times, presentation cadence and decode
/// latency, plus the number of frames above 50 ms (jank). Every 2 s it writes
/// one JSON object when NATIVAX_METRICS_FILE is set.
///
/// It is a measurement tool only; it does not alter the app or the renderer.
class MetricsOverlay extends StatefulWidget {
  const MetricsOverlay({super.key, required this.runtime, this.label = ''});

  final NativaXRuntime runtime;
  final String label;

  @override
  State<MetricsOverlay> createState() => _MetricsOverlayState();
}

class _MetricsOverlayState extends State<MetricsOverlay> {
  static const _samplePeriod = Duration(seconds: 2);
  static const _jankThresholdUs = 50000;

  final List<int> _buildUs = [];
  final List<int> _rasterUs = [];
  final List<int> _totalUs = [];
  int _jankFrames = 0;
  int _uiFrames = 0;

  int? _lastFrame;
  int? _lastShown;
  DateTime? _lastSample;

  double? _renderFps;
  double? _shownFps;
  double? _uiFps;
  int _width = 0;
  int _height = 0;
  int _decodeP50 = 0;
  int _decodeP95 = 0;
  int _presentP50 = 0;
  int _presentP95 = 0;
  double _buildP95 = 0;
  double _rasterP95 = 0;
  double _totalP95 = 0;
  double _jankPct = 0;

  Timer? _timer;
  RandomAccessFile? _out;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _openMetricsFile();
    _timer = Timer.periodic(_samplePeriod, (_) => _sample());
  }

  void _openMetricsFile() {
    final path = Platform.environment['NATIVAX_METRICS_FILE'];
    if (path == null || path.isEmpty) return;
    try {
      _out = File(path).openSync(mode: FileMode.append);
    } catch (error) {
      debugPrint('metrics: cannot open $path: $error');
    }
  }

  @override
  void didUpdateWidget(MetricsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) {
      _resetWindow();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    try {
      _out?.closeSync();
    } catch (_) {}
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _buildUs.add(timing.buildDuration.inMicroseconds);
      _rasterUs.add(timing.rasterDuration.inMicroseconds);
      _totalUs.add(timing.totalSpan.inMicroseconds);
      _uiFrames++;
      if (timing.totalSpan.inMicroseconds > _jankThresholdUs) _jankFrames++;
    }
  }

  void _resetWindow() {
    _buildUs.clear();
    _rasterUs.clear();
    _totalUs.clear();
    _uiFrames = 0;
    _jankFrames = 0;
    _lastFrame = null;
    _lastShown = null;
    _lastSample = null;
    _renderFps = null;
    _shownFps = null;
    _uiFps = null;
  }

  int? _findSurface() {
    final element = widget.runtime.document.querySelector('#webgl');
    final direct = element == null ? null : canvasSurfaces[element];
    if (direct != null) return direct;
    for (final canvas in widget.runtime.document.querySelectorAll('canvas')) {
      final surface = canvasSurfaces[canvas];
      if (surface != null) return surface;
    }
    return null;
  }

  void _sample() {
    final surface = _findSurface();
    if (surface == null) return;

    final now = DateTime.now();
    final frame = GlSurfaces.frame(surface);
    final shown = GlSurfaces.shown(surface);
    final lastSample = _lastSample;
    final lastFrame = _lastFrame;
    final lastShown = _lastShown;
    final build = List<int>.of(_buildUs);
    final raster = List<int>.of(_rasterUs);
    final total = List<int>.of(_totalUs);
    final uiFrames = _uiFrames;
    final jankFrames = _jankFrames;
    _buildUs.clear();
    _rasterUs.clear();
    _totalUs.clear();
    _uiFrames = 0;
    _jankFrames = 0;
    _lastFrame = frame;
    _lastShown = shown;
    _lastSample = now;

    if (lastSample == null || lastFrame == null || lastShown == null) {
      return;
    }
    final seconds = now.difference(lastSample).inMicroseconds / 1e6;
    if (seconds <= 0) return;

    final renderFps = (frame - lastFrame) / seconds;
    final shownFps = (shown - lastShown) / seconds;
    final uiFps = uiFrames / seconds;
    final jankPct = uiFrames == 0 ? 0.0 : jankFrames * 100.0 / uiFrames;

    final width = GlSurfaces.shownWidth(surface);
    final height = GlSurfaces.shownHeight(surface);
    final decodeP50 = GlSurfaces.decodeP50Micros(surface);
    final decodeP95 = GlSurfaces.decodeP95Micros(surface);
    final presentP50 = GlSurfaces.presentP50Micros(surface);
    final presentP95 = GlSurfaces.presentP95Micros(surface);
    final buildP95 = _percentileUs(build, 0.95) / 1000.0;
    final rasterP95 = _percentileUs(raster, 0.95) / 1000.0;
    final totalP95 = _percentileUs(total, 0.95) / 1000.0;

    if (!mounted) return;
    setState(() {
      _renderFps = renderFps;
      _shownFps = shownFps;
      _uiFps = uiFps;
      _width = width;
      _height = height;
      _decodeP50 = decodeP50;
      _decodeP95 = decodeP95;
      _presentP50 = presentP50;
      _presentP95 = presentP95;
      _buildP95 = buildP95;
      _rasterP95 = rasterP95;
      _totalP95 = totalP95;
      _jankPct = jankPct;
    });

    final label = widget.label.isEmpty
        ? (Platform.environment['NATIVAX_METRICS_LABEL'] ?? 'run')
        : widget.label;
    final dpr = Platform.environment['NATIVAX_GAME_DPR'] ?? '1.0';
    final noBackdrop = Platform.environment['NATIVAX_NO_BACKDROP'] == '1';

    debugPrint(
      'metrics[$label]: render=${renderFps.toStringAsFixed(1)}fps '
      'shown=${shownFps.toStringAsFixed(1)}fps ui=${uiFps.toStringAsFixed(1)}fps '
      'buffer=${width}x$height '
      'decode=${_ms(decodeP50)}/${_ms(decodeP95)}ms '
      'present=${_ms(presentP50)}/${_ms(presentP95)}ms '
      'ui_total=${totalP95.toStringAsFixed(1)}ms '
      'build=${buildP95.toStringAsFixed(1)}ms raster=${rasterP95.toStringAsFixed(1)}ms '
      'jank=${jankPct.toStringAsFixed(1)}%',
    );

    final record = <String, Object?>{
      'label': label,
      'timestamp': now.toIso8601String(),
      'dpr': dpr,
      'no_backdrop': noBackdrop,
      'seconds': double.parse(seconds.toStringAsFixed(3)),
      'render_fps': _round(renderFps),
      'shown_fps': _round(shownFps),
      'ui_fps': _round(uiFps),
      'buffer_w': width,
      'buffer_h': height,
      'frames': uiFrames,
      'jank': jankFrames,
      'jank_pct': _round(jankPct),
      'decode_ms': {
        'p50': _ms(decodeP50),
        'p95': _ms(decodeP95),
        'p99': _ms(GlSurfaces.decodeP99Micros(surface)),
      },
      'present_ms': {
        'p50': _ms(presentP50),
        'p95': _ms(presentP95),
        'p99': _ms(GlSurfaces.presentP99Micros(surface)),
      },
      'build_ms': {
        'p50': _ms(_percentileUs(build, 0.50)),
        'p95': _ms(_percentileUs(build, 0.95)),
        'p99': _ms(_percentileUs(build, 0.99)),
      },
      'raster_ms': {
        'p50': _ms(_percentileUs(raster, 0.50)),
        'p95': _ms(_percentileUs(raster, 0.95)),
        'p99': _ms(_percentileUs(raster, 0.99)),
      },
      'total_ms': {
        'p50': _ms(_percentileUs(total, 0.50)),
        'p95': _ms(_percentileUs(total, 0.95)),
        'p99': _ms(_percentileUs(total, 0.99)),
      },
    };

    try {
      _out?.writeStringSync('${jsonEncode(record)}\n');
      _out?.flushSync();
    } catch (error) {
      debugPrint('metrics: write failed: $error');
    }
  }

  static int _percentileUs(List<int> values, double p) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.of(values)..sort();
    var index = ((sorted.length - 1) * p).round();
    if (index < 0) index = 0;
    if (index >= sorted.length) index = sorted.length - 1;
    return sorted[index];
  }

  static double _ms(int micros) =>
      double.parse((micros / 1000.0).toStringAsFixed(2));

  static double _round(double value) => double.parse(value.toStringAsFixed(2));

  @override
  Widget build(BuildContext context) {
    final render = _renderFps;
    final shown = _shownFps;
    final ui = _uiFps;
    final body = render == null
        ? 'MÉTRICAS: esperando frames'
        : 'render ${render.toStringAsFixed(0)} · '
              'shown ${shown?.toStringAsFixed(0) ?? '--'} · '
              'UI ${ui?.toStringAsFixed(0) ?? '--'} fps\n'
              'buffer ${_width}x$_height · '
              'decode ${_ms(_decodeP50).toStringAsFixed(0)}/${_ms(_decodeP95).toStringAsFixed(0)} ms · '
              'present ${_ms(_presentP50).toStringAsFixed(0)}/${_ms(_presentP95).toStringAsFixed(0)} ms\n'
              'UI total p95 ${_totalP95.toStringAsFixed(1)} ms · '
              'build ${_buildP95.toStringAsFixed(1)} · '
              'raster ${_rasterP95.toStringAsFixed(1)} · '
              'jank ${_jankPct.toStringAsFixed(1)}%';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          body,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            height: 1.35,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
