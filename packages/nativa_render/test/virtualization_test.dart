import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_render/nativa_render.dart';

const _media = MediaContext(width: 800, height: 600);

({dom.Document document, StyleEngine engine}) _document(
  String html, {
  String css = '',
}) {
  final parsed = HtmlParser().parseDocument(html);
  final engine = StyleEngine(document: parsed.value, media: _media);
  engine.authorSheets = [StyleSheet.parse(css)];
  return (document: parsed.value, engine: engine);
}

Widget _app(dom.Document document, StyleEngine engine, {double width = 800}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 600,
            child: NativaXDocumentView(
              document: document,
              styleEngine: engine,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ),
      ),
    );

String _rows(int count, {String css = '', String Function(int)? body}) {
  final b = StringBuffer('<!doctype html><html><head><style>');
  b.write('html,body{margin:0;padding:0}'
      '.row{height:20px;margin:0;padding:0;font-size:12px;line-height:20px}'
      '.tail{height:80px}'
      '$css');
  b.write('</style></head><body><div id="list">');
  for (var i = 0; i < count; i++) {
    b.write('<div class="row" id="row-$i">${body?.call(i) ?? 'Row $i'}</div>');
  }
  b.write('</div></body></html>');
  return b.toString();
}

int _renderObjectCount() {
  var count = 0;
  void visit(RenderObject o) {
    count++;
    o.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    final root = view.child;
    if (root != null) visit(root);
  }
  return count;
}

ScrollableState _rootScrollable(WidgetTester tester) {
  ScrollableState? best;
  double bestExtent = -1;
  for (final state in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
    if (!state.position.hasContentDimensions) continue;
    if (state.position.maxScrollExtent > bestExtent) {
      best = state;
      bestExtent = state.position.maxScrollExtent;
    }
  }
  expect(best, isNotNull, reason: 'document has no scrollable');
  return best!;
}

Future<void> _pumpFrames(WidgetTester tester, [int n = 3]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('live render objects stay bounded as rows grow', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final counts = <int, int>{};
    for (final n in [100, 1000, 10000]) {
      final ctx = _document(_rows(n));
      await tester.pumpWidget(_app(ctx.document, ctx.engine));
      await _pumpFrames(tester);
      counts[n] = _renderObjectCount();
      expect(find.text('Row 0'), findsOneWidget);
      expect(find.text('Row ${n - 1}'), findsNothing,
          reason: 'the last row must not be built while at the top');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    expect(counts[1000]! - counts[100]!, lessThan(40),
        reason: 'render objects must not grow with the document');
    expect(counts[10000]! - counts[100]!, lessThan(60),
        reason: 'render objects must not grow with the document');
  });

  testWidgets('fast scroll and scroll to the end stay bounded', (tester) async {
    final ctx = _document(_rows(10000));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    final before = _renderObjectCount();
    final scrollable = _rootScrollable(tester);
    final max = scrollable.position.maxScrollExtent;
    expect(max, greaterThan(100000), reason: 'the list must be tall');

    for (var i = 0; i < 20; i++) {
      scrollable.position.jumpTo(max * i / 19);
      await tester.pump();
    }
    scrollable.position.jumpTo(max);
    await _pumpFrames(tester, 4);

    expect(find.text('Row 9999'), findsOneWidget);
    expect(_renderObjectCount() - before, lessThan(80),
        reason: 'scrolling must recycle the window, not accumulate it');
  });

  testWidgets('scroll anchoring keeps the visible row in place after correction',
      (tester) async {
    // The first rows are short and the tail is tall, so the initial estimate
    // is wrong for every row after the first screen. Anchoring must absorb the
    // correction when those rows are materialized.
    final ctx = _document(_rows(1000, body: (i) => i >= 40 ? 'Tall $i' : 'Row $i',
        css: '#row-40, #row-41, #row-42, #row-43, #row-44, #row-45, #row-46, '
            '#row-47, #row-48, #row-49, .row:nth-child(n+40) { height:80px }'));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    final scrollable = _rootScrollable(tester);
    scrollable.position.jumpTo(2000);
    await _pumpFrames(tester, 5);

    final materialized = <dom.Element>[];
    for (final e in ctx.document.querySelectorAll('.row')) {
      final box = elementRenderBoxes[e];
      if (box != null && box.attached && box.hasSize) materialized.add(e);
    }
    expect(materialized.length, greaterThan(2));
    materialized.sort((a, b) =>
        elementRenderBoxes[a]!.localToGlobal(Offset.zero).dy.compareTo(
            elementRenderBoxes[b]!.localToGlobal(Offset.zero).dy));
    final anchor = materialized.first;
    final before = elementRenderBoxes[anchor]!.localToGlobal(Offset.zero).dy;
    // Force another measure/correction cycle.
    await _pumpFrames(tester, 3);
    final after = elementRenderBoxes[anchor]!.localToGlobal(Offset.zero).dy;
    expect((after - before).abs(), lessThan(2.0),
        reason: 'the anchor row moved on screen after height correction');
  });

  testWidgets('scrollIntoView and boxOf materialize an offscreen row',
      (tester) async {
    final ctx = _document(_rows(600));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    final target = ctx.document.getElementById('row-500')!;
    expect(elementRenderBoxes[target], isNull,
        reason: 'the target must start outside the materialized window');

    final estimated = ctx.document.layoutHost!.boxOf(target);
    expect(estimated, isNotNull, reason: 'virtualized geometry must answer');
    expect(estimated!.offsetY, greaterThan(5000));

    ctx.document.layoutHost!.scrollIntoView(target);
    await _pumpFrames(tester, 8);

    final box = ctx.document.layoutHost!.boxOf(target);
    expect(box, isNotNull);
    expect(box!.y, inInclusiveRange(-1, 600));
    expect(find.text('Row 500'), findsOneWidget);
  });

  testWidgets('focus materializes an offscreen control', (tester) async {
    final ctx = _document(_rows(600, body: (i) => '<button id="btn-$i">B$i</button>'));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    final button = ctx.document.getElementById('btn-500')!;
    expect(elementRenderBoxes[button], isNull);
    ctx.document.requestFocus(button);
    await _pumpFrames(tester, 8);
    final box = ctx.document.layoutHost!.boxOf(button);
    expect(box, isNotNull);
    expect(box!.y, inInclusiveRange(-1, 600));
  });

  testWidgets('offscreen mutation is applied to the DOM and appears in view',
      (tester) async {
    final ctx = _document(_rows(600));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    final row = ctx.document.getElementById('row-400')!;
    expect(elementRenderBoxes[row], isNull);
    row.textContent = 'Cambiado fuera de vista';
    await _pumpFrames(tester, 2);
    expect(row.textContent, 'Cambiado fuera de vista');
    expect(find.text('Cambiado fuera de vista'), findsNothing);

    ctx.document.layoutHost!.scrollIntoView(row);
    await _pumpFrames(tester, 8);
    expect(find.text('Cambiado fuera de vista'), findsOneWidget);
  });

  testWidgets('insertion and removal in the middle keep the window coherent',
      (tester) async {
    final ctx = _document(_rows(600));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    final list = ctx.document.getElementById('list')!;
    final before = _renderObjectCount();

    final inserted = ctx.document.createElement('div')
      ..className = 'row'
      ..id = 'row-new'
      ..textContent = 'Insertada';
    list.insertBefore(inserted, ctx.document.getElementById('row-300'));
    await _pumpFrames(tester, 3);
    expect(list.children.length, 601);
    expect(_renderObjectCount() - before, lessThan(80));

    ctx.document.layoutHost!.scrollIntoView(inserted);
    await _pumpFrames(tester, 8);
    expect(find.text('Insertada'), findsOneWidget);

    inserted.remove();
    await _pumpFrames(tester, 3);
    expect(list.children.length, 600);
    expect(ctx.document.getElementById('row-new'), isNull);
  });

  testWidgets('viewport resize keeps virtualization active', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctx = _document(_rows(2000));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    final before = _renderObjectCount();
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 1999'), findsNothing);

    tester.view.physicalSize = const Size(420, 600);
    await tester.pump();
    await _pumpFrames(tester, 4);
    expect(find.text('Row 0'), findsOneWidget);
    expect(_renderObjectCount() - before, lessThan(80));
  });

  testWidgets('stress: 20k rows stay inside the frame and object budgets',
      (tester) async {
    final watch = Stopwatch()..start();
    final ctx = _document(_rows(20000));
    await tester.pumpWidget(_app(ctx.document, ctx.engine));
    await _pumpFrames(tester);
    watch.stop();
    // Budgets are deliberately loose for debug/JIT CI but fail on a regression
    // that builds the document eagerly (which is seconds to minutes).
    expect(watch.elapsedMilliseconds, lessThan(8000),
        reason: '20k rows took ${watch.elapsedMilliseconds}ms to reach the first frame');
    expect(_renderObjectCount(), lessThan(500),
        reason: 'render object count grew with N');
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 19999'), findsNothing);
  });
}
