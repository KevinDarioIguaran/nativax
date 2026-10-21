import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Indicators drawn inside native-looking form controls. They are painted
/// rather than taken from an icon font, so they look the same whether or not
/// the host app bundles Material icons, and they follow browser geometry.
enum ControlGlyphKind { chevron, calendar, clock }

class ControlGlyph extends StatelessWidget {
  const ControlGlyph({
    super.key,
    required this.kind,
    required this.color,
    this.size = 16,
    this.shift = 0,
  });

  final ControlGlyphKind kind;
  final Color color;

  /// Square area reserved for the glyph.
  final double size;

  /// Horizontal offset applied when painting (the select arrow sits in the
  /// control's padding, outside its content box).
  final double shift;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GlyphPainter(kind, color, shift)),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color, this.shift);
  final ControlGlyphKind kind;
  final Color color;
  final double shift;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2 + shift, size.height / 2);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true;
    switch (kind) {
      case ControlGlyphKind.chevron:
        // 10×6 chevron with a 2px stroke, as Chromium's menu list arrow.
        stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.miter;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 4, c.dy - 2)
            ..lineTo(c.dx, c.dy + 2)
            ..lineTo(c.dx + 4, c.dy - 2),
          stroke,
        );
      case ControlGlyphKind.calendar:
        // 11×12 calendar: 1px frame, 2px header bar and two binding tabs.
        final r = Rect.fromCenter(center: c, width: 11, height: 11).shift(const Offset(0, 0.5));
        stroke.strokeWidth = 1;
        canvas.drawRect(r.deflate(0.5), stroke);
        final fill = Paint()..color = color;
        canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 2.5), fill);
        canvas.drawRect(Rect.fromLTWH(r.left + 2, r.top - 1.5, 1, 1.5), fill);
        canvas.drawRect(Rect.fromLTWH(r.right - 3, r.top - 1.5, 1, 1.5), fill);
      case ControlGlyphKind.clock:
        stroke.strokeWidth = 1.4;
        const radius = 5.6;
        canvas.drawCircle(c, radius, stroke);
        stroke.strokeCap = StrokeCap.round;
        canvas.drawLine(c, c + const Offset(0, -3.4), stroke);
        canvas.drawLine(c, c + Offset(math.cos(math.pi / 5) * 2.6, math.sin(math.pi / 5) * 2.6), stroke);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind || old.color != color || old.shift != shift;
}
