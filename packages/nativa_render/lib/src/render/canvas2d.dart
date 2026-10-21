import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;

import '../layout/preferred_width.dart';
import '../style_mapping.dart';
import 'gl_surface.dart';
import 'svg.dart' show parseSvgPath;

/// The bitmap behind one `<canvas>`.
class CanvasSurface {
  CanvasSurface(this.width, this.height);
  int width;
  int height;
  ui.Image? image;
  final ValueNotifier<int> version = ValueNotifier(0);
  _State state = _State();
  final List<_State> stack = [];

  void dispose() {
    image?.dispose();
    version.dispose();
  }
}

class _State {
  Object fill = const Color(0xff000000); // Color or gradient map
  Object stroke = const Color(0xff000000);
  double lineWidth = 1;
  StrokeCap cap = StrokeCap.butt;
  StrokeJoin join = StrokeJoin.miter;
  double miterLimit = 10;
  String font = '10px sans-serif';
  String textAlign = 'start';
  String textBaseline = 'alphabetic';
  double alpha = 1;
  BlendMode blend = BlendMode.srcOver;
  Color shadowColor = const Color(0x00000000);
  double shadowBlur = 0, shadowX = 0, shadowY = 0;
  List<double> dash = const [];
  double dashOffset = 0;
  Matrix4 transform = Matrix4.identity();

  _State copy() => _State()
    ..fill = fill
    ..stroke = stroke
    ..lineWidth = lineWidth
    ..cap = cap
    ..join = join
    ..miterLimit = miterLimit
    ..font = font
    ..textAlign = textAlign
    ..textBaseline = textBaseline
    ..alpha = alpha
    ..blend = blend
    ..shadowColor = shadowColor
    ..shadowBlur = shadowBlur
    ..shadowX = shadowX
    ..shadowY = shadowY
    ..dash = dash
    ..dashOffset = dashOffset
    ..transform = transform.clone();
}

/// Parses a CSS color string (`#hex`, `rgb()`, `hsl()`, names).
Color parseCssColor(String text, [Color fallback = const Color(0xff000000)]) {
  final tokens = CssTokenizer(text.trim()).tokenize();
  final v = parseColor(ValueStream(tokens));
  return v?.color == null ? fallback : Color(v!.color!.argb);
}

/// Parses the CSS `font` shorthand used by canvas contexts.
TextStyle canvasFont(String font, Color color) {
  final decls = expandDeclaration('font', CssTokenizer(font).tokenize());
  if (decls == null) return TextStyle(fontSize: 10, color: color);
  final size = decls['font-size'];
  final weight = decls['font-weight'];
  final family = decls['font-family'];
  double px = 10;
  if (size is Length) {
    px = switch (size.unit) { LengthUnit.px => size.value, LengthUnit.em || LengthUnit.rem => size.value * 16, _ => size.value };
  }
  final (f, fallback) = family is FontFamilyValue ? mapFontFamily(family.families) : (null, null);
  return TextStyle(
    fontSize: px,
    color: color,
    fontFamily: f,
    fontFamilyFallback: fallback,
    fontWeight: weight is NumberValue
        ? mapFontWeight(weight.value.round())
        : (weight is Keyword && weight.name == 'bold' ? FontWeight.bold : FontWeight.normal),
    fontStyle: decls['font-style'] is Keyword && (decls['font-style'] as Keyword).name != 'normal' ? FontStyle.italic : FontStyle.normal,
  );
}

/// Backs `<canvas>` 2D contexts for one document view.
class CanvasRegistry implements dom.CanvasHost {
  final Expando<CanvasSurface> _surfaces = Expando('nativax.canvas');
  final List<CanvasSurface> _all = [];

  CanvasSurface surfaceFor(dom.Element canvas) {
    var s = _surfaces[canvas];
    if (s == null) {
      s = CanvasSurface(
        int.tryParse(canvas.getAttribute('width') ?? '') ?? 300,
        int.tryParse(canvas.getAttribute('height') ?? '') ?? 150,
      );
      _surfaces[canvas] = s;
      _all.add(s);
    }
    return s;
  }

  void dispose() {
    for (final s in _all) {
      s.dispose();
    }
    _all.clear();
  }

  @override
  Map<String, double> measureText(String font, String text) {
    final tp = TextPainter(text: TextSpan(text: text, style: canvasFont(font, const Color(0xff000000))), textDirection: TextDirection.ltr)
      ..layout();
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final result = {'width': tp.width, 'ascent': ascent, 'descent': tp.height - ascent};
    tp.dispose();
    return result;
  }

  @override
  void draw(dom.Element canvas, int width, int height, List<Object?> ops) {
    final s = surfaceFor(canvas);
    width = width.clamp(1, 8192);
    height = height.clamp(1, 8192);
    if (s.width != width || s.height != height) {
      s.width = width;
      s.height = height;
      s.image?.dispose();
      s.image = null;
      s.state = _State();
      s.stack.clear();
    }
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    _Replay(this, s, c).run(ops);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    s.image?.dispose();
    s.image = image;
    s.version.value++;
  }
}

class _Replay {
  _Replay(this.registry, this.surface, this.canvas);
  final CanvasRegistry registry;
  final CanvasSurface surface;
  final Canvas canvas;
  Path path = Path();
  int saves = 0;

  _State get st => surface.state;

  void run(List<Object?> ops) {
    // Clips from earlier batches are not kept; the image already has them
    // applied. Re-establish the current save depth so restores balance.
    final img = surface.image;
    if (img != null) canvas.drawImage(img, Offset.zero, Paint());
    for (final raw in ops) {
      if (raw is! List || raw.isEmpty) continue;
      try {
        _op(raw[0] as String, raw.sublist(1));
      } catch (_) {
        // Malformed commands are ignored, like invalid canvas calls.
      }
    }
    while (saves > 0) {
      canvas.restore();
      saves--;
    }
  }

  double n(List<Object?> a, int i) => (a[i] as num?)?.toDouble() ?? 0;

  Offset _pt(double x, double y) => MatrixUtils.transformPoint(st.transform, Offset(x, y));

  double get _scale {
    final m = st.transform.storage;
    return math.sqrt((m[0] * m[5] - m[1] * m[4]).abs()).clamp(0.0001, 1e6);
  }

  Paint _paint(Object style, {required bool stroke}) {
    final p = Paint()
      ..isAntiAlias = true
      ..blendMode = st.blend
      ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill;
    if (stroke) {
      p
        ..strokeWidth = st.lineWidth * _scale
        ..strokeCap = st.cap
        ..strokeJoin = st.join
        ..strokeMiterLimit = st.miterLimit;
    }
    if (style is Color) {
      p.color = style.withValues(alpha: style.a * st.alpha);
    } else if (style is Map) {
      p.shader = _gradient(style);
      p.color = Color.fromRGBO(0, 0, 0, st.alpha);
    }
    return p;
  }

  ui.Shader? _gradient(Map g) {
    final args = [for (final a in (g['args'] as List)) (a as num).toDouble()];
    final stops = [for (final s in (g['stops'] as List)) s as List];
    if (stops.isEmpty) return null;
    final colors = [for (final s in stops) parseCssColor('${s[1]}')];
    final offsets = [for (final s in stops) (s[0] as num).toDouble()];
    if (colors.length == 1) {
      colors.add(colors.first);
      offsets.add(1);
    }
    final m = st.transform.storage;
    switch (g['gradient']) {
      case 'radial':
        return ui.Gradient.radial(Offset(args[3], args[4]), args[5], colors, offsets, TileMode.clamp, m,
            Offset(args[0], args[1]), args[2]);
      case 'conic':
        return ui.Gradient.sweep(Offset(args[1], args[2]), colors, offsets, TileMode.clamp, args[0], args[0] + math.pi * 2, m);
      default:
        return ui.Gradient.linear(Offset(args[0], args[1]), Offset(args[2], args[3]), colors, offsets, TileMode.clamp, m);
    }
  }

  Path _dashed(Path p) {
    if (st.dash.isEmpty) return p;
    final out = Path();
    final dash = [for (final d in st.dash) d * _scale];
    for (final metric in p.computeMetrics()) {
      var d = -st.dashOffset * _scale;
      var k = 0;
      while (d < metric.length) {
        final seg = dash[k % dash.length];
        if (k.isEven && d + seg > 0) out.addPath(metric.extractPath(math.max(0, d), math.min(d + seg, metric.length)), Offset.zero);
        d += seg <= 0 ? 0.0001 : seg;
        k++;
      }
    }
    return out;
  }

  void _drawPath(Path p, Paint paint) {
    if (st.shadowColor.a > 0 && (st.shadowBlur > 0 || st.shadowX != 0 || st.shadowY != 0)) {
      final shadow = Paint()
        ..color = st.shadowColor.withValues(alpha: st.shadowColor.a * st.alpha)
        ..style = paint.style
        ..strokeWidth = paint.strokeWidth
        ..maskFilter = st.shadowBlur > 0 ? MaskFilter.blur(BlurStyle.normal, st.shadowBlur / 2) : null;
      canvas.drawPath(p.shift(Offset(st.shadowX, st.shadowY)), shadow);
    }
    canvas.drawPath(p, paint);
  }

  Path _rectPath(double x, double y, double w, double h) => Path()
    ..moveTo(_pt(x, y).dx, _pt(x, y).dy)
    ..lineTo(_pt(x + w, y).dx, _pt(x + w, y).dy)
    ..lineTo(_pt(x + w, y + h).dx, _pt(x + w, y + h).dy)
    ..lineTo(_pt(x, y + h).dx, _pt(x, y + h).dy)
    ..close();

  /// Applies a path-building command to [target] (device space).
  void _pathOp(Path target, String name, List<Object?> a) {
    switch (name) {
      case 'moveTo':
        final p = _pt(n(a, 0), n(a, 1));
        target.moveTo(p.dx, p.dy);
      case 'lineTo':
        final p = _pt(n(a, 0), n(a, 1));
        target.lineTo(p.dx, p.dy);
      case 'closePath':
        target.close();
      case 'bezierCurveTo':
        final p1 = _pt(n(a, 0), n(a, 1)), p2 = _pt(n(a, 2), n(a, 3)), p3 = _pt(n(a, 4), n(a, 5));
        target.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
      case 'quadraticCurveTo':
        final p1 = _pt(n(a, 0), n(a, 1)), p2 = _pt(n(a, 2), n(a, 3));
        target.quadraticBezierTo(p1.dx, p1.dy, p2.dx, p2.dy);
      case 'rect':
        target.addPath(_rectPath(n(a, 0), n(a, 1), n(a, 2), n(a, 3)), Offset.zero);
      case 'roundRect':
        final radii = (a[4] as List?)?.map((r) => (r as num).toDouble()).toList() ?? [0.0];
        final r = Radius.circular(radii.isEmpty ? 0 : radii.first);
        final local = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(n(a, 0), n(a, 1), n(a, 2), n(a, 3)), r));
        target.addPath(local.transform(st.transform.storage), Offset.zero);
      case 'arc':
        _arc(target, n(a, 0), n(a, 1), n(a, 2), n(a, 2), 0, n(a, 3), n(a, 4), a[5] == true);
      case 'ellipse':
        _arc(target, n(a, 0), n(a, 1), n(a, 2), n(a, 3), n(a, 4), n(a, 5), n(a, 6), a[7] == true);
      case 'arcTo':
        // Approximated as a line to the corner (radius rounding omitted).
        final p = _pt(n(a, 0), n(a, 1));
        target.lineTo(p.dx, p.dy);
      case 'svgPath':
        target.addPath(parseSvgPath('${a[0]}').transform(st.transform.storage), Offset.zero);
    }
  }

  void _arc(Path target, double cx, double cy, double rx, double ry, double rot, double start, double end, bool ccw) {
    var sweep = end - start;
    const tau = math.pi * 2;
    if (!ccw && sweep >= tau || ccw && sweep <= -tau) {
      sweep = ccw ? -tau : tau;
    } else {
      if (!ccw && sweep < 0) sweep = (sweep % tau + tau) % tau;
      if (ccw && sweep > 0) sweep = -((-sweep % tau + tau) % tau);
    }
    final local = Path();
    final rect = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
    if (sweep.abs() >= tau - 1e-9) {
      local.arcTo(rect, start, sweep / 2, true);
      local.arcTo(rect, start + sweep / 2, sweep / 2, false);
    } else {
      local.arcTo(rect, start, sweep, true);
    }
    final m = st.transform.clone()
      ..translateByDouble(cx, cy, 0, 1)
      ..rotateZ(rot);
    final transformed = local.transform(m.storage);
    // The arc connects to the current point with a line.
    target.extendWithPath(transformed, Offset.zero);
  }

  void _op(String name, List<Object?> a) {
    switch (name) {
      case 'reset':
        surface.image?.dispose();
        surface.image = null;
        canvas.drawPaint(Paint()..blendMode = BlendMode.clear);
        surface.state = _State();
        surface.stack.clear();
        path = Path();
      case 'save':
        surface.stack.add(st.copy());
        canvas.save();
        saves++;
      case 'restore':
        if (surface.stack.isNotEmpty) surface.state = surface.stack.removeLast();
        if (saves > 0) {
          canvas.restore();
          saves--;
        }
      case 'setTransform':
        st.transform = Matrix4.identity()
          ..setEntry(0, 0, n(a, 0))
          ..setEntry(1, 0, n(a, 1))
          ..setEntry(0, 1, n(a, 2))
          ..setEntry(1, 1, n(a, 3))
          ..setEntry(0, 3, n(a, 4))
          ..setEntry(1, 3, n(a, 5));
      case 'set':
        _set('${a[0]}', a[1]);
      case 'clearRect':
        canvas.drawPath(_rectPath(n(a, 0), n(a, 1), n(a, 2), n(a, 3)), Paint()..blendMode = BlendMode.clear);
      case 'fillRect':
        _drawPath(_rectPath(n(a, 0), n(a, 1), n(a, 2), n(a, 3)), _paint(st.fill, stroke: false));
      case 'strokeRect':
        _drawPath(_dashed(_rectPath(n(a, 0), n(a, 1), n(a, 2), n(a, 3))), _paint(st.stroke, stroke: true));
      case 'beginPath':
        path = Path();
      case 'fill':
        final target = a.isNotEmpty && a[0] is List ? _fromOps(a[0] as List) : path;
        target.fillType = a.length > 1 && a[1] == 'evenodd' ? PathFillType.evenOdd : PathFillType.nonZero;
        _drawPath(target, _paint(st.fill, stroke: false));
      case 'stroke':
        final target = a.isNotEmpty && a[0] is List ? _fromOps(a[0] as List) : path;
        _drawPath(_dashed(target), _paint(st.stroke, stroke: true));
      case 'clip':
        final target = a.isNotEmpty && a[0] is List ? _fromOps(a[0] as List) : path;
        target.fillType = a.length > 1 && a[1] == 'evenodd' ? PathFillType.evenOdd : PathFillType.nonZero;
        canvas.clipPath(target);
      case 'fillText':
      case 'strokeText':
        _text('${a[0]}', n(a, 1), n(a, 2), a.length > 3 && a[3] is num ? n(a, 3) : null, stroke: name == 'strokeText');
      case 'drawCanvas':
        // Canvas-to-canvas copies are not supported across surfaces yet.
        break;
      default:
        _pathOp(path, name, a);
    }
  }

  Path _fromOps(List ops) {
    final p = Path();
    for (final o in ops) {
      if (o is List && o.isNotEmpty) _pathOp(p, '${o[0]}', o.sublist(1));
    }
    return p;
  }

  void _set(String prop, Object? v) {
    switch (prop) {
      case 'fillStyle':
        st.fill = v is Map ? v : parseCssColor('$v');
      case 'strokeStyle':
        st.stroke = v is Map ? v : parseCssColor('$v');
      case 'lineWidth':
        st.lineWidth = (v as num).toDouble();
      case 'lineCap':
        st.cap = switch ('$v') { 'round' => StrokeCap.round, 'square' => StrokeCap.square, _ => StrokeCap.butt };
      case 'lineJoin':
        st.join = switch ('$v') { 'round' => StrokeJoin.round, 'bevel' => StrokeJoin.bevel, _ => StrokeJoin.miter };
      case 'miterLimit':
        st.miterLimit = (v as num).toDouble();
      case 'font':
        st.font = '$v';
      case 'textAlign':
        st.textAlign = '$v';
      case 'textBaseline':
        st.textBaseline = '$v';
      case 'globalAlpha':
        st.alpha = (v as num).toDouble();
      case 'globalCompositeOperation':
        st.blend = switch ('$v') {
          'source-in' => BlendMode.srcIn,
          'source-out' => BlendMode.srcOut,
          'source-atop' => BlendMode.srcATop,
          'destination-over' => BlendMode.dstOver,
          'destination-in' => BlendMode.dstIn,
          'destination-out' => BlendMode.dstOut,
          'destination-atop' => BlendMode.dstATop,
          'lighter' => BlendMode.plus,
          'copy' => BlendMode.src,
          'xor' => BlendMode.xor,
          'multiply' => BlendMode.multiply,
          'screen' => BlendMode.screen,
          'overlay' => BlendMode.overlay,
          'darken' => BlendMode.darken,
          'lighten' => BlendMode.lighten,
          'color-dodge' => BlendMode.colorDodge,
          'color-burn' => BlendMode.colorBurn,
          'hard-light' => BlendMode.hardLight,
          'soft-light' => BlendMode.softLight,
          'difference' => BlendMode.difference,
          'exclusion' => BlendMode.exclusion,
          'hue' => BlendMode.hue,
          'saturation' => BlendMode.saturation,
          'color' => BlendMode.color,
          'luminosity' => BlendMode.luminosity,
          _ => BlendMode.srcOver,
        };
      case 'shadowColor':
        st.shadowColor = parseCssColor('$v', const Color(0x00000000));
      case 'shadowBlur':
        st.shadowBlur = (v as num).toDouble();
      case 'shadowOffsetX':
        st.shadowX = (v as num).toDouble();
      case 'shadowOffsetY':
        st.shadowY = (v as num).toDouble();
      case 'lineDash':
        st.dash = [for (final d in (v as List)) (d as num).toDouble()];
      case 'lineDashOffset':
        st.dashOffset = (v as num).toDouble();
    }
  }

  void _text(String text, double x, double y, double? maxWidth, {required bool stroke}) {
    final style = stroke ? st.stroke : st.fill;
    final color = style is Color ? style.withValues(alpha: style.a * st.alpha) : Color.fromRGBO(0, 0, 0, st.alpha);
    var ts = canvasFont(st.font, color);
    if (stroke) {
      ts = ts.copyWith(
        color: null,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = st.lineWidth
          ..color = color,
      );
    }
    final tp = TextPainter(text: TextSpan(text: text, style: ts), textDirection: TextDirection.ltr)..layout();
    var sx = 1.0;
    if (maxWidth != null && tp.width > maxWidth && tp.width > 0) sx = maxWidth / tp.width;
    final w = tp.width * sx;
    final dx = switch (st.textAlign) { 'center' => -w / 2, 'right' || 'end' => -w, _ => 0.0 };
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final dy = switch (st.textBaseline) {
      'top' || 'hanging' => 0.0,
      'middle' => -tp.height / 2,
      'bottom' || 'ideographic' => -tp.height,
      _ => -ascent,
    };
    canvas.save();
    canvas.transform(st.transform.storage);
    canvas.translate(x + dx, y + dy);
    if (sx != 1) canvas.scale(sx, 1);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
    tp.dispose();
  }
}

/// Displays a `<canvas>` bitmap scaled to the element's box.
class CanvasView extends StatelessWidget {
  const CanvasView({super.key, required this.element, required this.registry, required this.style});
  final dom.Element element;
  final CanvasRegistry? registry;
  final ComputedStyle style;

  @override
  Widget build(BuildContext context) {
    final w = double.tryParse(element.getAttribute('width') ?? '') ?? 300;
    final h = double.tryParse(element.getAttribute('height') ?? '') ?? 150;
    final gl = dom.canvasSurfaces[element];
    final surface = gl != null ? null : registry?.surfaceFor(element);
    Widget image = gl != null
        ? GlSurfaceView(surface: gl)
        : surface == null
        ? SizedBox(width: w, height: h)
        : ValueListenableBuilder<int>(
            valueListenable: surface.version,
            builder: (context, _, __) => RawImage(image: surface.image, fit: BoxFit.fill, width: w, height: h),
          );
    // The game's full-screen WebGL canvas is fixed to the viewport, so its
    // parent supplies tight constraints and it can expand. 2D canvases use
    // their intrinsic aspect ratio: wrapping a RawImage in an expanding box
    // inside an inline/absolute layout can hand RenderImage an infinite size.
    if (gl != null && style.height != null) {
      final view = View.of(context);
      final viewportWidth = view.physicalSize.width / view.devicePixelRatio;
      final viewportHeight = view.physicalSize.height / view.devicePixelRatio;
      // A fixed full-viewport canvas. The host scroll view may shave a couple
      // of logical pixels from the available width, so stay just inside it:
      // RenderImage cannot be given infinite constraints.
      image = SizedBox(
          width: viewportWidth - 2, height: viewportHeight, child: image);
    } else {
      image = AspectRatio(aspectRatio: h <= 0 ? 2 : w / h, child: image);
    }
    // Like browsers, the default CSS size is the bitmap size in px.
    return style.width != null ? image : PreferredWidth(width: w, child: image);
  }
}
