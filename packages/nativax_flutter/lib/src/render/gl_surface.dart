import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:nativax_js/nativax_js.dart';

/// Shows the frames a WebGL context (on any thread) publishes into a GL
/// surface. Polls the surface's frame counter once per vsync and decodes the
/// newest frame; the renderer thread never waits for the UI.
class GlSurfaceView extends StatefulWidget {
  const GlSurfaceView({super.key, required this.surface});
  final int surface;

  @override
  State<GlSurfaceView> createState() => _GlSurfaceViewState();
}

class _GlSurfaceViewState extends State<GlSurfaceView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  ui.Image? _image;
  int _shown = 0;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    GlSurfaces.retain(widget.surface);
    _ticker = createTicker((_) => _poll())..start();
  }

  @override
  void didUpdateWidget(GlSurfaceView old) {
    super.didUpdateWidget(old);
    if (old.surface != widget.surface) {
      GlSurfaces.retain(widget.surface);
      GlSurfaces.release(old.surface);
      _shown = 0;
    }
  }

  void _poll() {
    if (_decoding || GlSurfaces.frame(widget.surface) == _shown) return;
    final frame = GlSurfaces.acquire(widget.surface);
    if (frame == null) return;
    _decoding = true;
    final id = frame.frame;
    final decode = Stopwatch()..start();
    // decodeImageFromPixels copies the pixels before returning.
    ui.decodeImageFromPixels(frame.pixels, frame.width, frame.height, ui.PixelFormat.rgba8888, (image) {
      _decoding = false;
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _image;
      setState(() {
        _image = image;
        _shown = id;
      });
      GlSurfaces.markShown(
        widget.surface,
        width: frame.width,
        height: frame.height,
        decodeMicros: decode.elapsedMicroseconds,
      );
      old?.dispose();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _image?.dispose();
    GlSurfaces.release(widget.surface);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: RawImage(
          image: _image,
          fit: BoxFit.fill,
          width: double.infinity,
          height: double.infinity,
        ),
      );
}
