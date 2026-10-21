// Compares two box dumps produced by measure.js and prints the elements whose
// geometry differs, root causes first: an element is only reported when its
// parent matches, so one wrong container does not flood the output.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: compare.dart <chrome.json> <nativax.json> [tolerance]');
    exit(64);
  }
  Map<String, List<double>> read(String path) {
    final raw = jsonDecode(File(path).readAsStringSync().trim()) as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(k, [for (final n in v as List) (n as num).toDouble()]));
  }

  final chrome = read(args[0]);
  final nx = read(args[1]);
  final tol = args.length > 2 ? double.parse(args[2]) : 2.0;

  double delta(String k) {
    final a = chrome[k], b = nx[k];
    if (a == null || b == null) return double.infinity;
    var d = 0.0;
    for (var i = 0; i < 4; i++) {
      d = d > (a[i] - b[i]).abs() ? d : (a[i] - b[i]).abs();
    }
    return d;
  }

  String? parent(String k) {
    final i = k.lastIndexOf('>');
    return i < 0 ? null : k.substring(0, i);
  }

  var matched = 0;
  final roots = <String>[];
  for (final k in chrome.keys) {
    final d = delta(k);
    if (d <= tol) {
      matched++;
      continue;
    }
    final p = parent(k);
    if (p == null || !chrome.containsKey(p) || delta(p) <= tol) roots.add(k);
  }
  final missing = chrome.keys.where((k) => !nx.containsKey(k)).length;
  final extra = nx.keys.where((k) => !chrome.containsKey(k)).length;
  stdout.writeln('elements: chrome=${chrome.length} nativax=${nx.length} '
      'match(±${tol}px)=$matched (${(100 * matched / chrome.length).toStringAsFixed(1)} %) '
      'missing=$missing extra=$extra');
  roots.sort((a, b) => delta(b).compareTo(delta(a)));
  String fmt(List<double>? r) => r == null ? '—' : r.map((v) => v.toStringAsFixed(1)).join(', ');
  for (final k in roots.take(int.tryParse(Platform.environment['MIRROR_TOP'] ?? '') ?? 40)) {
    stdout.writeln('${delta(k).toStringAsFixed(1).padLeft(7)}  $k\n'
        '         chrome  [${fmt(chrome[k])}]\n         nativax [${fmt(nx[k])}]');
  }
}
