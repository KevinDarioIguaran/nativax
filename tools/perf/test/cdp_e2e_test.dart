import 'dart:io';

import 'package:nativa_perf/src/cdp.dart';
import 'package:test/test.dart';

/// Chrome-only integration test.
///   NATIVA_PERF_E2E=1 dart test test/cdp_e2e_test.dart
void main() {
  final enabled = Platform.environment['NATIVA_PERF_E2E'] == '1';
  final chrome = Platform.environment['CHROME'] ?? 'google-chrome';
  test(
    'CDP evaluates JS and reports performance metrics',
    () async {
      final session = await CdpChrome.launch(
        executable: chrome,
        width: 400,
        height: 300,
      );
      try {
        await session.setViewport(400, 300);
        await session.navigate(
          'data:text/html,<title>cdp</title><div id="x">hello</div>',
        );
        expect(await session.evaluate('1+1'), 2);
        expect(await session.evaluate('document.title'), 'cdp');
        expect(await session.evaluate('innerWidth'), 400);
        expect(await session.evaluate('innerHeight'), 300);
        final metrics = await session.metrics();
        expect(metrics.containsKey('Nodes'), isTrue);
        expect(metrics.containsKey('JSHeapUsedSize'), isTrue);
        expect(metrics['Nodes'], greaterThan(0));
      } finally {
        await session.close();
      }
    },
    skip: enabled
        ? false
        : 'set NATIVA_PERF_E2E=1 to run Chrome integration tests',
  );
}
