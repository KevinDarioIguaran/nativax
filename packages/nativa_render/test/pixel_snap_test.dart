import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  // Chromium paints backgrounds on the pixel-snapped border box: a box at
  // x = 10.7 with width 20.5 covers pixels 11..30 fully and nothing else.
  testWidgets('box background is snapped to whole pixels', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xff000000),
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10.7, top: 4.5),
              child: const SizedBox(
                width: 20.5,
                height: 6,
                child: CssBox(spec: CssBoxSpec(background: Color(0xffffffff))),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final row = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      // Red channel of row y = 6, pixels 9..32.
      return [for (var x = 9; x <= 32; x++) data.getUint8((6 * image.width + x) * 4)];
    });
    expect(row, [0, 0, for (var i = 0; i < 20; i++) 255, 0, 0]);
  });
}
