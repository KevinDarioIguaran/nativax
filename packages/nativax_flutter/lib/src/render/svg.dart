import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:nativax_css/nativax_css.dart';
import 'package:nativax_dom/nativax_dom.dart' as dom;

import '../layout/preferred_width.dart';
import '../style_mapping.dart';

/// Parses an SVG length attribute (user units; `%` of [basis]).
double? svgLength(String? v, [double basis = 0]) {
  if (v == null) return null;
  final t = v.trim();
  if (t.endsWith('%')) {
    final n = double.tryParse(t.substring(0, t.length - 1));
    return n == null ? null : basis * n / 100;
  }
  final m = RegExp(r'^(-?[\d.]+(?:e[-+]?\d+)?)(px|pt|em|rem)?$', caseSensitive: false).firstMatch(t);
  if (m == null) return null;
  final n = double.tryParse(m[1]!);
  if (n == null) return null;
  return switch (m[2]?.toLowerCase()) { 'pt' => n * 4 / 3, 'em' || 'rem' => n * 16, _ => n };
}

/// The `viewBox` rectangle, or null.
Rect? svgViewBox(dom.Element svg) {
  final parts = (svg.getAttribute('viewBox') ?? svg.getAttribute('viewbox') ?? '')
      .trim()
      .split(RegExp(r'[\s,]+'))
      .where((p) => p.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (parts.length != 4 || parts.any((p) => p == null) || parts[2]! <= 0 || parts[3]! <= 0) return null;
  return Rect.fromLTWH(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
}

/// Parses an SVG `transform` attribute into a matrix.
Matrix4 svgTransform(String? text) {
  final m = Matrix4.identity();
  if (text == null) return m;
  for (final f in RegExp(r'(\w+)\s*\(([^)]*)\)').allMatches(text)) {
    final a = f[2]!.trim().split(RegExp(r'[\s,]+')).where((x) => x.isNotEmpty).map(double.tryParse).whereType<double>().toList();
    switch (f[1]) {
      case 'translate':
        m.translateByDouble(a.isNotEmpty ? a[0] : 0, a.length > 1 ? a[1] : 0, 0, 1);
      case 'scale':
        final x = a.isNotEmpty ? a[0] : 1.0;
        m.scaleByDouble(x, a.length > 1 ? a[1] : x, 1, 1);
      case 'rotate':
        if (a.isEmpty) break;
        final r = a[0] * math.pi / 180;
        if (a.length >= 3) {
          m.translateByDouble(a[1], a[2], 0, 1);
          m.rotateZ(r);
          m.translateByDouble(-a[1], -a[2], 0, 1);
        } else {
          m.rotateZ(r);
        }
      case 'skewX':
        if (a.isNotEmpty) m.multiply(Matrix4.identity()..setEntry(0, 1, math.tan(a[0] * math.pi / 180)));
      case 'skewY':
        if (a.isNotEmpty) m.multiply(Matrix4.identity()..setEntry(1, 0, math.tan(a[0] * math.pi / 180)));
      case 'matrix':
        if (a.length == 6) {
          m.multiply(Matrix4.identity()
            ..setEntry(0, 0, a[0])
            ..setEntry(1, 0, a[1])
            ..setEntry(0, 1, a[2])
            ..setEntry(1, 1, a[3])
            ..setEntry(0, 3, a[4])
            ..setEntry(1, 3, a[5]));
        }
    }
  }
  return m;
}

/// Parses SVG path data (all commands, absolute and relative).
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?').allMatches(d).map((m) => m[0]!).toList();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  double? cx2, cy2; // last control point for S/T
  String prev = '';
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => i < tokens.length && !isCmd(tokens[i]) ? double.parse(tokens[i++]) : 0;
  bool hasNumber() => i < tokens.length && !isCmd(tokens[i]);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd.isEmpty) {
      break;
    }
    final rel = cmd == cmd.toLowerCase();
    final c = cmd.toUpperCase();
    double ax(double v) => rel ? x + v : v;
    double ay(double v) => rel ? y + v : v;
    switch (c) {
      case 'M':
        x = ax(n());
        y = ay(n());
        sx = x;
        sy = y;
        path.moveTo(x, y);
        cmd = rel ? 'l' : 'L'; // subsequent pairs are lineto
      case 'L':
        x = ax(n());
        y = ay(n());
        path.lineTo(x, y);
      case 'H':
        x = rel ? x + n() : n();
        path.lineTo(x, y);
      case 'V':
        y = rel ? y + n() : n();
        path.lineTo(x, y);
      case 'C':
        final x1 = ax(n()), y1 = ay(n()), x2 = ax(n()), y2 = ay(n()), ex = ax(n()), ey = ay(n());
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        cx2 = x2;
        cy2 = y2;
        x = ex;
        y = ey;
      case 'S':
        final rx = (prev == 'C' || prev == 'S') && cx2 != null ? 2 * x - cx2 : x;
        final ry = (prev == 'C' || prev == 'S') && cy2 != null ? 2 * y - cy2 : y;
        final x2 = ax(n()), y2 = ay(n()), ex = ax(n()), ey = ay(n());
        path.cubicTo(rx, ry, x2, y2, ex, ey);
        cx2 = x2;
        cy2 = y2;
        x = ex;
        y = ey;
      case 'Q':
        final x1 = ax(n()), y1 = ay(n()), ex = ax(n()), ey = ay(n());
        path.quadraticBezierTo(x1, y1, ex, ey);
        cx2 = x1;
        cy2 = y1;
        x = ex;
        y = ey;
      case 'T':
        final rx = (prev == 'Q' || prev == 'T') && cx2 != null ? 2 * x - cx2 : x;
        final ry = (prev == 'Q' || prev == 'T') && cy2 != null ? 2 * y - cy2 : y;
        final ex = ax(n()), ey = ay(n());
        path.quadraticBezierTo(rx, ry, ex, ey);
        cx2 = rx;
        cy2 = ry;
        x = ex;
        y = ey;
      case 'A':
        final rx = n().abs(), ry = n().abs(), rot = n(), large = n() != 0, sweep = n() != 0;
        final ex = ax(n()), ey = ay(n());
        if (rx == 0 || ry == 0) {
          path.lineTo(ex, ey);
        } else {
          path.arcToPoint(Offset(ex, ey), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
        }
        x = ex;
        y = ey;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
    }
    prev = c;
    if (c == 'Z' && hasNumber()) cmd = rel ? 'l' : 'L';
  }
  return path;
}

List<Offset> _points(String? text) {
  final n = (text ?? '').trim().split(RegExp(r'[\s,]+')).where((x) => x.isNotEmpty).map(double.tryParse).whereType<double>().toList();
  return [for (var i = 0; i + 1 < n.length; i += 2) Offset(n[i], n[i + 1])];
}

/// One painted shape, kept for hit testing.
class _Shape {
  _Shape(this.element, this.path, this.transform, this.filled, this.strokeWidth);
  final dom.Element element;
  final Path path;
  final Matrix4 transform;
  final bool filled;
  final double strokeWidth;
}

/// Renders an inline `<svg>` subtree.
class SvgView extends StatelessWidget {
  const SvgView({super.key, required this.element, required this.styleEngine});
  final dom.Element element;
  final StyleEngine styleEngine;

  @override
  Widget build(BuildContext context) {
    final style = styleEngine.styleOf(element);
    final vb = svgViewBox(element);
    final attrW = svgLength(element.getAttribute('width'));
    final attrH = svgLength(element.getAttribute('height'));
    final aspect = vb != null ? vb.width / vb.height : (attrW != null && attrH != null && attrH > 0 ? attrW / attrH : 2.0);
    final painter = _SvgPainter(element, styleEngine, vb, style);
    Widget canvas = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (d) {
        final target = painter.hit(d.localPosition);
        (target ?? element).click(trusted: true);
      },
      child: CustomPaint(painter: painter, size: Size.infinite),
    );
    canvas = style.height != null ? SizedBox.expand(child: canvas) : AspectRatio(aspectRatio: aspect, child: canvas);
    return style.width != null ? canvas : PreferredWidth(width: attrW ?? 300, child: canvas);
  }
}

class _SvgPainter extends CustomPainter {
  _SvgPainter(this.root, this.engine, this.viewBox, this.rootStyle);
  final dom.Element root;
  final StyleEngine engine;
  final Rect? viewBox;
  final ComputedStyle rootStyle;
  final List<_Shape> _shapes = [];
  Matrix4 _base = Matrix4.identity();

  Matrix4 _viewTransform(Size size) {
    final vb = viewBox;
    final m = Matrix4.identity();
    if (vb == null) return m;
    // preserveAspectRatio: xMidYMid meet.
    final s = math.min(size.width / vb.width, size.height / vb.height);
    final dx = (size.width - vb.width * s) / 2 - vb.left * s;
    final dy = (size.height - vb.height * s) / 2 - vb.top * s;
    m.translateByDouble(dx, dy, 0, 1);
    m.scaleByDouble(s, s, 1, 1);
    return m;
  }

  dom.Element? hit(Offset p) {
    for (final s in _shapes.reversed) {
      final inv = Matrix4.tryInvert(s.transform);
      if (inv == null) continue;
      final local = MatrixUtils.transformPoint(inv, p);
      if (s.filled && s.path.contains(local)) return s.element;
      if (s.strokeWidth > 0) {
        final b = s.path.getBounds().inflate(s.strokeWidth / 2 + 2);
        if (!s.filled && b.contains(local)) return s.element;
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _shapes.clear();
    _base = _viewTransform(size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.transform(_base.storage);
    _children(canvas, root, _base, size);
    canvas.restore();
  }

  void _children(Canvas canvas, dom.Element parent, Matrix4 transform, Size size) {
    for (final c in parent.children) {
      _paint(canvas, c, transform, size);
    }
  }

  void _paint(Canvas canvas, dom.Element e, Matrix4 parentTransform, Size size) {
    final style = engine.styleOf(e);
    if (style.display == Display.none) return;
    final local = svgTransform(e.getAttribute('transform'));
    final transform = parentTransform.clone()..multiply(local);
    final vb = viewBox;
    final bw = vb?.width ?? size.width, bh = vb?.height ?? size.height;
    double len(String name, [double basis = 0]) => svgLength(e.getAttribute(name), basis) ?? 0;
    Path? path;
    switch (e.localName) {
      case 'g':
      case 'a':
      case 'svg':
        canvas.save();
        canvas.transform(local.storage);
        final layer = style.opacity < 1;
        if (layer) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, style.opacity));
        _children(canvas, e, transform, size);
        if (layer) canvas.restore();
        canvas.restore();
        return;
      case 'rect':
        final x = len('x', bw), y = len('y', bh), w = len('width', bw), h = len('height', bh);
        if (w <= 0 || h <= 0) return;
        var rx = svgLength(e.getAttribute('rx'), bw), ry = svgLength(e.getAttribute('ry'), bh);
        rx ??= ry;
        ry ??= rx;
        final r = Rect.fromLTWH(x, y, w, h);
        path = (rx ?? 0) > 0
            ? (Path()..addRRect(RRect.fromRectXY(r, math.min(rx!, w / 2), math.min(ry!, h / 2))))
            : (Path()..addRect(r));
      case 'circle':
        final r = len('r', math.sqrt((bw * bw + bh * bh) / 2));
        if (r <= 0) return;
        path = Path()..addOval(Rect.fromCircle(center: Offset(len('cx', bw), len('cy', bh)), radius: r));
      case 'ellipse':
        final rx = len('rx', bw), ry = len('ry', bh);
        if (rx <= 0 || ry <= 0) return;
        path = Path()..addOval(Rect.fromCenter(center: Offset(len('cx', bw), len('cy', bh)), width: rx * 2, height: ry * 2));
      case 'line':
        path = Path()
          ..moveTo(len('x1', bw), len('y1', bh))
          ..lineTo(len('x2', bw), len('y2', bh));
      case 'polyline':
      case 'polygon':
        final pts = _points(e.getAttribute('points'));
        if (pts.length < 2) return;
        path = Path()..addPolygon(pts, e.localName == 'polygon');
      case 'path':
        path = parseSvgPath(e.getAttribute('d') ?? '');
      case 'text':
        _text(canvas, e, style, local, bw, bh);
        return;
      default:
        return; // defs, title, desc, unsupported elements
    }
    if (style.visibility != 'visible') return;
    path.fillType = style['fill-rule'].toString() == 'evenodd' ? PathFillType.evenOdd : PathFillType.nonZero;
    canvas.save();
    canvas.transform(local.storage);
    final opacity = style.opacity;
    final fill = style.fillColor;
    final stroke = style.strokeColor;
    final fillAlpha = (style['fill-opacity'] as NumberValue).value * opacity;
    final strokeAlpha = (style['stroke-opacity'] as NumberValue).value * opacity;
    final isLine = e.localName == 'line' || e.localName == 'polyline';
    if (fill != null && !isLine) {
      final c = toColor(fill);
      canvas.drawPath(path, Paint()..color = c.withValues(alpha: c.a * fillAlpha));
    }
    if (stroke != null && style.strokeWidth > 0) {
      final c = toColor(stroke);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth
        ..color = c.withValues(alpha: c.a * strokeAlpha)
        ..strokeCap = switch (style['stroke-linecap'].toString()) { 'round' => StrokeCap.round, 'square' => StrokeCap.square, _ => StrokeCap.butt }
        ..strokeJoin = switch (style['stroke-linejoin'].toString()) { 'round' => StrokeJoin.round, 'bevel' => StrokeJoin.bevel, _ => StrokeJoin.miter };
      canvas.drawPath(_dashed(path, style.strokeDashArray), paint);
    }
    canvas.restore();
    _shapes.add(_Shape(e, path, transform, fill != null && !isLine, stroke != null ? style.strokeWidth : 0));
  }

  Path _dashed(Path p, List<double> dash) {
    if (dash.isEmpty || dash.every((d) => d == 0)) return p;
    final pattern = dash.length.isOdd ? [...dash, ...dash] : dash;
    final out = Path();
    for (final m in p.computeMetrics()) {
      var d = 0.0;
      var k = 0;
      var draw = true;
      while (d < m.length) {
        final seg = pattern[k % pattern.length];
        if (draw) out.addPath(m.extractPath(d, math.min(d + seg, m.length)), Offset.zero);
        d += seg <= 0 ? 0.0001 : seg;
        draw = !draw;
        k++;
      }
    }
    return out;
  }

  void _text(Canvas canvas, dom.Element e, ComputedStyle style, Matrix4 local, double bw, double bh) {
    final text = e.textContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return;
    final fill = style.fillColor;
    final ts = textStyleFor(style).copyWith(color: fill == null ? const Color(0x00000000) : toColor(fill));
    final tp = TextPainter(text: TextSpan(text: text, style: ts), textDirection: TextDirection.ltr)..layout();
    final x = svgLength(e.getAttribute('x'), bw) ?? 0;
    final y = svgLength(e.getAttribute('y'), bh) ?? 0;
    final anchor = style['text-anchor'].toString();
    final dx = anchor == 'middle' ? -tp.width / 2 : (anchor == 'end' ? -tp.width : 0.0);
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final db = style['dominant-baseline'].toString();
    final dy = db == 'middle' || db == 'central' ? -tp.height / 2 : (db == 'hanging' || db == 'text-top' ? 0.0 : -baseline);
    canvas.save();
    canvas.transform(local.storage);
    tp.paint(canvas, Offset(x + dx, y + dy));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvgPainter old) => true;
}
