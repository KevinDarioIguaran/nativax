import 'dart:io';

import 'package:nativa_security/security.dart';
import 'package:test/test.dart';

void main() {
  test('security suite runs with controlled statuses', () async {
    final results = await SecurityRunner().run(securityCases());
    expect(results, hasLength(securityCases().length));
    expect(results.where((r) => r.status == SecurityStatus.error), isEmpty);
    expect(
      results.any((r) => r.id == 'events.programmatic_click_not_trusted' &&
          r.status == SecurityStatus.pass),
      isTrue,
    );
    expect(
      results.any((r) => r.id == 'xss.inner_html_does_not_execute' &&
          r.status == SecurityStatus.pass),
      isTrue,
    );
    // Former finding S-03: host callbacks now live in a private registry.
    expect(
      results.any((r) => r.id == 'internal.callback_globals' &&
          r.status == SecurityStatus.pass),
      isTrue,
    );
  });

  test('runner turns exceptions into ERROR without aborting the suite',
      () async {
    final results = await SecurityRunner().run([
      SecurityCase(
        id: 'throws',
        category: 'test',
        severity: 'low',
        description: 'test',
        run: () async => throw StateError('boom'),
      ),
      SecurityCase(
        id: 'ok',
        category: 'test',
        severity: 'low',
        description: 'test',
        run: () async => const SecurityCheck(
          status: SecurityStatus.pass,
          expected: 'ok',
          observed: 'ok',
        ),
      ),
    ]);
    expect(results[0].status, SecurityStatus.error);
    expect(results[1].status, SecurityStatus.pass);
  });

  test('writes and reloads a security report', () async {
    final dir = Directory.systemTemp.createTempSync('nativa_security_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final run = SecurityRun(
      metadata: collectSecurityMetadata(
        repoRoot: findSecurityRepoRoot(),
        command: 'test',
      ),
      results: [
        const SecurityResult(
          id: 'case',
          category: 'test',
          severity: 'low',
          description: 'synthetic',
          status: SecurityStatus.pass,
          expected: 'ok',
          observed: 'ok',
          durationMs: 1,
        ),
      ],
    );
    final files = writeSecurityReport(run, outputDir: dir.path);
    final loaded = loadSecurityRun(files.json);
    expect(loaded.results.single.id, 'case');
    expect(loaded.results.single.status, SecurityStatus.pass);
    expect(File(files.markdown).readAsStringSync(), contains('case'));
  });
}
