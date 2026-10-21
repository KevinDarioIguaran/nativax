import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

class _Assets extends NativaXResourceLoader {
  const _Assets();
  @override
  Future<String?> load(String url) async {
    if (url.startsWith('http')) return null;
    var path = url.split('?').first;
    if (path.startsWith('/')) path = path.substring(1);
    if (!path.startsWith('assets/')) path = 'assets/$path';
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return null;
    }
  }
}

void main() {
  testWidgets('the challenge boots without script errors', (tester) async {
    final errors = <Object>[];
    NativaXRuntime? runtime;
    final source = await rootBundle.loadString('assets/index.html');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NativaXView(
          source: source,
          config: NativaXRuntimeConfig(
            resources: const _Assets(),
            onScriptError: errors.add,
          ),
          onRuntimeReady: (value) => runtime = value,
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(errors, isEmpty, reason: errors.join('\n'));
    expect(runtime, isNotNull);
    expect(runtime!.styleEngine.authorSheets, isNotEmpty);

    final body = runtime!.document.body!;
    final bodyStyle = runtime!.styleEngine.styleOf(body);
    expect(bodyStyle.backgroundColor.argb, isNot(0),
        reason: 'styles.css should set a visible body background');
    expect(bodyStyle.fontFamily.join(','), contains('Segoe UI'));

    final header = runtime!.document.querySelector('.top')!;
    final headerStyle = runtime!.styleEngine.styleOf(header);
    expect(headerStyle.backgroundGradient, isNotNull,
        reason: 'the header paints its linear-gradient');
  });
}
