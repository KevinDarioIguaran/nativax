import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

DecorationImage _image(String css) {
  final document = HtmlParser().parseDocument('<div></div>').value;
  final engine = StyleEngine(
    document: document,
    media: const MediaContext(width: 800, height: 600),
  )..authorSheets = [StyleSheet.parse('div { $css }')];
  final style = engine.styleOf(document.querySelector('div')!);
  return backgroundDecorationImage(MemoryImage(Uint8List(0)), style);
}

void main() {
  test('auto size paints the image at its natural size, tiled', () {
    final image = _image('background-image: url(a.png)');
    expect(image.fit, BoxFit.none);
    expect(image.repeat, ImageRepeat.repeat);
    expect(image.alignment, Alignment.topLeft);
  });

  test('no-repeat center maps to an untiled centred image', () {
    final image = _image('background: url(a.png) no-repeat center');
    expect(image.repeat, ImageRepeat.noRepeat);
    expect(image.alignment, Alignment.center);
  });

  test('cover, contain and full-size keywords map to BoxFit', () {
    expect(_image('background: url(a.png) center / cover').fit, BoxFit.cover);
    expect(_image('background-image: url(a.png); background-size: contain').fit,
        BoxFit.contain);
    expect(_image('background-image: url(a.png); background-size: 100% 100%').fit,
        BoxFit.fill);
    expect(_image('background-image: url(a.png); background-size: 100%').fit,
        BoxFit.fitWidth);
  });

  test('percentage and keyword positions map to an alignment', () {
    final image = _image(
      'background-image: url(a.png); background-position: right 25%; '
      'background-repeat: repeat-y',
    );
    expect(image.alignment, const Alignment(1, -0.5));
    expect(image.repeat, ImageRepeat.repeatY);
  });
}
