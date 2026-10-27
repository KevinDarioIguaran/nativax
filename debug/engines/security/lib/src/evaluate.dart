/// Accuracy audit of the security suite: runs every case once with no fault
/// (specificity: nothing may fail) and once per [SecurityFault] (sensitivity:
/// at least one case whose contract the fault breaks must fail).
library;

import 'faults.dart';
import 'model.dart';
import 'runner.dart';

bool _failed(SecurityResult r) =>
    r.status == SecurityStatus.fail || r.status == SecurityStatus.error;

Future<Map<String, Object?>> evaluateSuite(
  List<SecurityCase> Function() cases, {
  void Function(String line)? log,
  void Function(SecurityFault? fault, String caseId)? progress,
}) async {
  Future<List<SecurityResult>> runWith(SecurityFault? fault) => withFault(
    fault,
    () => SecurityRunner(
      onProgress: (id, i, n) => progress?.call(fault, id),
    ).run(cases()),
  );

  final baseline = await runWith(null);
  final baselineFailures = [
    for (final r in baseline)
      if (_failed(r)) r.id,
  ];
  log?.call(
    'baseline: ${baseline.length} cases, ${baselineFailures.length} failing',
  );
  final rows = <Map<String, Object?>>[];
  for (final fault in SecurityFault.values) {
    final results = await runWith(fault);
    final failing = [
      for (final r in results)
        if (_failed(r) && !baselineFailures.contains(r.id)) r.id,
    ];
    final expectedCases = [
      for (final r in results)
        if (fault.expects(r.id)) r.id,
    ];
    final detecting = [
      for (final id in failing)
        if (fault.expects(id)) id,
    ];
    final collateral = [
      for (final id in failing)
        if (!fault.expects(id)) id,
    ];
    rows.add({
      'fault': fault.name,
      'description': fault.description,
      'detected': detecting.isNotEmpty,
      'expectedCases': expectedCases.length,
      'detectingCases': detecting,
      'missedCases': [
        for (final id in expectedCases)
          if (!detecting.contains(id)) id,
      ],
      'collateralFailures': collateral,
    });
    log?.call(
      '${fault.name}: ${detecting.isNotEmpty ? 'DETECTED' : 'MISSED'} '
      '(${detecting.length}/${expectedCases.length} expected cases fail, '
      '${collateral.length} other)',
    );
  }
  final detected = rows.where((r) => r['detected'] == true).length;
  final expected = rows.fold<int>(0, (s, r) => s + (r['expectedCases'] as int));
  final failing = rows.fold<int>(
    0,
    (s, r) => s + (r['detectingCases'] as List).length,
  );
  return {
    'schema': 'nativa_security.audit/1',
    'cases': baseline.length,
    'baseline': {
      'pass': baseline.where((r) => r.status == SecurityStatus.pass).length,
      'skip': baseline.where((r) => r.status == SecurityStatus.skip).length,
      'failing': baselineFailures,
    },
    'faults': rows.length,
    'faultsDetected': detected,
    'faultDetectionRate': rows.isEmpty ? null : detected / rows.length,
    'expectedCaseFailures': expected,
    'observedExpectedFailures': failing,
    'caseSensitivity': expected == 0 ? null : failing / expected,
    'rows': rows,
  };
}
