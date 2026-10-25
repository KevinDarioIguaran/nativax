import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 800, height: 600);

({dom.Document document, StyleEngine engine}) _document(String html) {
  final parsed = HtmlParser().parseDocument(
    '<!doctype html><html><body>$html</body></html>',
  );
  return (
    document: parsed.value,
    engine: StyleEngine(document: parsed.value, media: _media),
  );
}

Widget _app(dom.Document document, StyleEngine engine) => MaterialApp(
  home: Scaffold(
    body: NativaXDocumentView(
      document: document,
      styleEngine: engine,
      padding: const EdgeInsets.all(8),
    ),
  ),
);

/// Video is not decoded by NativaX today: the renderer keeps the browser-like
/// box and the DOM media contract reports MEDIA_ERR_SRC_NOT_SUPPORTED. These
/// quality-profile tests lock that documented boundary and the layout at each
/// resolution; they are not a claim of playback.
void main() {
  const cases = <({String id, String attrs, double w, double h})>[
    (id: '360p', attrs: 'width="640" height="360"', w: 640, h: 360),
    (id: '480p', attrs: 'width="854" height="480"', w: 768, h: 432),
    (id: '720p', attrs: 'width="1280" height="720"', w: 768, h: 432),
    (id: '1080p', attrs: 'width="1920" height="1080"', w: 768, h: 432),
    (id: '1440p', attrs: 'width="2560" height="1440"', w: 768, h: 432),
    (id: '2160p', attrs: 'width="3840" height="2160"', w: 768, h: 432),
    (id: 'portrait', attrs: 'width="720" height="1280"', w: 720, h: 1280),
    (id: 'square', attrs: 'width="1080" height="1080"', w: 768, h: 768),
    (id: 'ultrawide', attrs: 'width="2560" height="1080"', w: 768, h: 324),
    (
      id: 'controls',
      attrs: 'width="640" height="360" controls',
      w: 640,
      h: 360,
    ),
    (
      id: 'autoplay-muted',
      attrs: 'width="640" height="360" autoplay muted',
      w: 640,
      h: 360,
    ),
    (id: 'loop', attrs: 'width="640" height="360" loop', w: 640, h: 360),
    (
      id: 'preload-none',
      attrs: 'width="640" height="360" preload="none"',
      w: 640,
      h: 360,
    ),
    (
      id: 'poster',
      attrs: 'width="640" height="360" poster="poster.png"',
      w: 640,
      h: 360,
    ),
    (
      id: 'playsinline',
      attrs: 'width="640" height="360" playsinline',
      w: 640,
      h: 360,
    ),
    (
      id: 'crossorigin',
      attrs: 'width="640" height="360" crossorigin="anonymous"',
      w: 640,
      h: 360,
    ),
    (id: 'source-child', attrs: 'width="640" height="360"', w: 640, h: 360),
    (
      id: 'css-size',
      attrs: 'width="640" height="360" style="width:320px;height:180px"',
      w: 320,
      h: 180,
    ),
    (
      id: 'css-half-width',
      attrs: 'width="640" height="360" style="width:50%;height:180px"',
      w: 384,
      h: 180,
    ),
    (id: 'width-only', attrs: 'width="640"', w: 640, h: 320),
    (
      id: 'muted-controls-720p',
      attrs: 'width="1280" height="720" controls muted',
      w: 768,
      h: 432,
    ),
    (
      id: 'autoplay-loop-1080p',
      attrs: 'width="1920" height="1080" autoplay loop muted',
      w: 768,
      h: 432,
    ),
    (
      id: 'css-object-fit',
      attrs:
          'width="640" height="360" style="width:320px;height:180px;object-fit:cover"',
      w: 320,
      h: 180,
    ),
    (
      id: 'css-max-width',
      attrs: 'width="1920" height="1080" style="max-width:640px"',
      w: 640,
      h: 360,
    ),
    (id: 'default', attrs: '', w: 300, h: 150),
  ];

  for (final item in cases) {
    testWidgets('video quality contract ${item.id}', (tester) async {
      final source = item.id == 'source-child'
          ? '<video id="v" ${item.attrs}><source src="clip.mp4" type="video/mp4"></video>'
          : '<video id="v" ${item.attrs}></video>';
      final ctx = _document(source);
      await tester.pumpWidget(_app(ctx.document, ctx.engine));
      await tester.pump();
      final label = find.text('▶ video');
      expect(label, findsOneWidget);
      final box = find.ancestor(of: label, matching: find.byType(AspectRatio));
      expect(box, findsOneWidget);
      final size = tester.getSize(box);
      expect(size.width, closeTo(item.w, 0.5));
      expect(size.height, closeTo(item.h, 0.5));
    });
  }
}
