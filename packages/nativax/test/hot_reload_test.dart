import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

void main() {
  testWidgets('hot reload re-reads the file and updates the document',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('nativax_hot_');
    final file = File('${dir.path}/ui.html')
      ..writeAsStringSync(
        '<!doctype html><html><body><p>one</p></body></html>',
      );
    final controller = NativaXHotReloadController();
    addTearDown(() {
      controller.dispose();
      dir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NativaXHotReloadView(
          sourcePath: file.path,
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('one'), findsOneWidget);

    file.writeAsStringSync(
      '<!doctype html><html><body><p>two</p></body></html>',
    );
    await controller.reload();
    await tester.pump();
    await tester.pump();
    expect(find.text('two'), findsOneWidget);
    expect(controller.lastError, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
