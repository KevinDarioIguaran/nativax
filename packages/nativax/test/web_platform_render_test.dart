import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

Future<NativaXRuntime> _mount(WidgetTester tester, String html, {List<Object>? errors}) async {
  NativaXRuntime? runtime;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NativaXView(
        source: html,
        config: NativaXRuntimeConfig(onScriptError: errors?.add),
        onRuntimeReady: (r) => runtime = r,
      ),
    ),
  ));
  for (var i = 0; i < 20 && runtime == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
  return runtime!;
}

void main() {
  testWidgets('canvas 2D draws into a bitmap shown by the view', (tester) async {
    final runtime = await _mount(tester, '''
<!doctype html><html><body style="margin:0">
<canvas id="c" width="20" height="10"></canvas>
<script>
  const ctx = document.getElementById('c').getContext('2d');
  ctx.fillStyle = '#ff0000';
  ctx.fillRect(0, 0, 10, 10);
  ctx.fillStyle = 'rgb(0, 0, 255)';
  ctx.beginPath(); ctx.arc(15, 5, 4, 0, Math.PI * 2); ctx.fill();
  window.measured = ctx.measureText('Hola').width > 0;
</script></body></html>''');
    await tester.pump();
    final image = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(image, isNotNull);
    expect(image!.width, 20);
    final bytes = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
    Uint8List px(int x, int y) => bytes!.buffer.asUint8List((y * 20 + x) * 4, 4);
    expect(px(2, 5), [255, 0, 0, 255]);
    expect(px(15, 5), [0, 0, 255, 255]);
    expect(px(15, 0)[3], 0, reason: 'outside the circle stays transparent');
    expect(runtime.engine.evaluate('window.measured'), true);
  });

  testWidgets('clicks carry viewport coordinates and offsets', (tester) async {
    final runtime = await _mount(tester, '''
<!doctype html><html><body style="margin:0">
<div id="d" style="margin-left:40px;width:100px;height:50px;background:#ccc"></div>
<script>
  document.getElementById('d').addEventListener('click', (e) => {
    const r = e.target.getBoundingClientRect();
    window.got = [Math.round(e.clientX), Math.round(e.clientY), Math.round(e.offsetX), Math.round(r.left), Math.round(r.width), e instanceof MouseEvent];
  });
</script></body></html>''');
    final box = find.byKey(ObjectKey(runtime.document.getElementById('d')));
    final origin = tester.getTopLeft(find.byType(NativaXView));
    await tester.tapAt(tester.getTopLeft(box) + const Offset(10, 5));
    await tester.pump();
    expect(runtime.engine.evaluate('window.got'), [
      (tester.getTopLeft(box).dx - origin.dx + 10).round(),
      (tester.getTopLeft(box).dy - origin.dy + 5).round(),
      10,
      40,
      100,
      true,
    ]);
  });

  testWidgets('original-app style script errors do not break the page', (tester) async {
    final errors = <Object>[];
    final runtime = await _mount(tester, '''
<!doctype html><html><body><p id="p">ok</p>
<script>document.addEventListener('DOMContentLoaded', () => { undefinedFunction(); });</script>
<script>document.getElementById('p').textContent = 'still running';</script>
</body></html>''', errors: errors);
    expect(runtime.document.getElementById('p')!.textContent, 'still running');
    expect(errors.single.toString(), contains('undefinedFunction'));
  });

  testWidgets('HTML5 drag and drop with delegated listeners', (tester) async {
    final runtime = await _mount(tester, '''
<!doctype html><html><body style="margin:0">
<ul id="l" style="list-style:none;padding:0;margin:0">
  <li draggable="true" data-i="0" style="height:40px">A</li>
  <li draggable="true" data-i="1" style="height:40px">B</li>
  <li draggable="true" data-i="2" style="height:40px">C</li>
</ul>
<script>
  const ul = document.getElementById('l');
  let drag = -1;
  window.log = [];
  ul.ondragstart = (e) => { drag = +e.target.closest('li').dataset.i; e.dataTransfer.setData('text/plain', 'x' + drag); };
  ul.ondragover = (e) => e.preventDefault();
  ul.ondrop = (e) => {
    e.preventDefault();
    const li = e.target.closest('li');
    window.log.push(drag + '->' + li.dataset.i + ':' + e.dataTransfer.getData('text'));
    ul.insertBefore(ul.children[drag], li.nextSibling);
  };
</script></body></html>''');
    final lis = runtime.document.querySelectorAll('li');
    final from = tester.getCenter(find.byKey(ObjectKey(lis[0])));
    final to = tester.getCenter(find.byKey(ObjectKey(lis[2])));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(runtime.engine.evaluate('window.log'), ['0->2:x0']);
    expect(runtime.document.querySelectorAll('li').map((e) => e.textContent.trim()), ['B', 'C', 'A']);
  });
}
