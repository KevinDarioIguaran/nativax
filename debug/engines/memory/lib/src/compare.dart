import 'analysis.dart';
import 'model.dart';

class LeakChange {
  const LeakChange({
    required this.id,
    required this.before,
    required this.after,
    required this.status,
  });
  final String id;
  final LeakStatus? before;
  final LeakStatus? after;

  /// `regression`, `fixed`, `new`, `missing`, `stable`.
  final String status;
}

List<LeakChange> compareLeakRuns(LeakRun baseline, LeakRun current) {
  final out = <LeakChange>[];
  for (final before in baseline.results) {
    final after = current.byId(before.id);
    if (after == null) {
      out.add(LeakChange(
          id: before.id,
          before: before.status,
          after: null,
          status: 'missing'));
      continue;
    }
    String status;
    if (before.status == LeakStatus.pass &&
        after.status != LeakStatus.pass) {
      status = 'regression';
    } else if (before.status != LeakStatus.pass &&
        after.status == LeakStatus.pass) {
      status = 'fixed';
    } else {
      status = 'stable';
    }
    out.add(LeakChange(
        id: before.id, before: before.status, after: after.status, status: status));
  }
  for (final after in current.results) {
    if (baseline.byId(after.id) == null) {
      out.add(LeakChange(
          id: after.id,
          before: null,
          after: after.status,
          status: 'new'));
    }
  }
  return out;
}

String renderLeakComparison(
  List<LeakChange> changes, {
  required String baseline,
  required String current,
}) {
  final b = StringBuffer()
    ..writeln('# Comparación de fugas')
    ..writeln()
    ..writeln('- Base: `$baseline`')
    ..writeln('- Actual: `$current`')
    ..writeln()
    ..writeln('| Caso | Antes | Ahora | Cambio |')
    ..writeln('|---|---|---|---|');
  for (final change in changes) {
    b.writeln('| `${change.id}` | '
        '${change.before?.label ?? '—'} | ${change.after?.label ?? '—'} | '
        '${change.status} |');
  }
  final regressions =
      changes.where((c) => c.status == 'regression').length;
  b
    ..writeln()
    ..writeln('Regresiones confirmadas: **$regressions**');
  return b.toString();
}
