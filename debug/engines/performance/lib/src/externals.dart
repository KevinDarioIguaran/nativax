import 'dart:io';

/// External benchmarks. Small MIT/Apache fixtures are vendored under
/// `fixtures/`; unlicensed suites are downloaded at runtime into `.perf/` and
/// never redistributed.
class ExternalSuite {
  const ExternalSuite({
    required this.id,
    required this.title,
    required this.url,
    required this.license,
    required this.description,
    this.fixture = true,
    this.repo,
    this.commit,
    this.fetchHint = '',
  });

  final String id;
  final String title;
  final String url;
  final String license;
  final String description;
  final bool fixture;
  final String? repo;
  final String? commit;
  final String fetchHint;
}

const List<ExternalSuite> externalSuites = [
  ExternalSuite(
    id: 'browserbench',
    title: 'Browser-Bench',
    url: 'https://dinithaw.github.io/Browser-Bench/',
    license: 'MIT',
    description: 'JS responsiveness workloads and composite score.',
    repo: 'dinithaw/Browser-Bench',
    commit: 'b20c04186bdf780434a53adaa3d0f66a5b27be2f',
  ),
  ExternalSuite(
    id: 'cerious',
    title: 'Cerious-Scroll benchmark',
    url: 'https://ceriousdevtech.github.io/cerious-scroll/benchmark.html',
    license: 'MIT',
    description: 'Scale/complexity sweep for a virtualized scroll library.',
    repo: 'ceriousdevtech/cerious-scroll',
    commit: 'a455a3e4e2a1a128e53b8673f78db8f72ecbbc4d',
  ),
  ExternalSuite(
    id: 'jsfb',
    title: 'js-framework-benchmark (vanilla keyed)',
    url: 'https://krausest.github.io/js-framework-benchmark/',
    license: 'Apache-2.0',
    description:
        'The official vanilla keyed implementation: create 1k/10k, update, clear.',
    repo: 'krausest/js-framework-benchmark',
    commit: 'master',
  ),
  ExternalSuite(
    id: 'uibench',
    title: 'UI Benchmark (localvoid)',
    url: 'https://localvoid.github.io/uibench/',
    license: 'no license file upstream',
    description:
        'React-based UI scenarios. Fetched at runtime, not redistributed.',
    fixture: false,
    repo: 'localvoid/uibench',
    commit: '3acab5c1900c642b1411faf5f690be43ec2cc578',
    fetchHint: 'dart run debug/engines/performance/bin/perf.dart fetch --source uibench',
  ),
  ExternalSuite(
    id: 'millionrows',
    title: 'million-rows-benchmark',
    url: 'https://github.com/alvarotolentino/million-rows-benchmark',
    license: 'no license file upstream',
    description:
        'React 19 + TanStack Virtual row benchmark. Needs npm build; not run by default.',
    fixture: false,
    repo: 'alvarotolentino/million-rows-benchmark',
    commit: '7b834fc561a914b266c5ff3571217053fce53bd1',
    fetchHint: 'Requires npm ci && npm run build; not automated yet.',
  ),
];

ExternalSuite? externalSuiteById(String id) {
  for (final suite in externalSuites) {
    if (suite.id == id) return suite;
  }
  return null;
}

String fixtureDir(String repoRoot, ExternalSuite suite) =>
    '$repoRoot/debug/engines/performance/fixtures/${suite.id}';
String fetchedDir(String repoRoot, ExternalSuite suite) =>
    '$repoRoot/.perf/suites/${suite.id}';

/// Returns the directory that contains `index.html`, or null when unavailable.
String? resolveExternalPage(String repoRoot, ExternalSuite suite) {
  if (suite.fixture) {
    final dir = fixtureDir(repoRoot, suite);
    if (File('$dir/index.html').existsSync()) return dir;
  }
  final fetched = fetchedDir(repoRoot, suite);
  if (File('$fetched/index.html').existsSync()) return fetched;
  return null;
}

/// Fetches the suites that are small enough to download without a build step.
/// Returns human-readable status lines.
Future<List<String>> fetchExternalSuites(
  String repoRoot, {
  List<String>? only,
}) async {
  final lines = <String>[];
  for (final suite in externalSuites) {
    if (only != null && only.isNotEmpty && !only.contains(suite.id)) continue;
    if (suite.fixture && resolveExternalPage(repoRoot, suite) != null) {
      lines.add('${suite.id}: vendored fixture present');
      continue;
    }
    if (suite.id == 'uibench') {
      final dir = Directory(fetchedDir(repoRoot, suite))
        ..createSync(recursive: true);
      final page = await _download(
        'https://localvoid.github.io/uibench/index.html',
        '${dir.path}/index.html',
      );
      final bundle = await _download(
        'https://localvoid.github.io/uibench/bundle.js',
        '${dir.path}/bundle.js',
      );
      if (page && bundle) {
        File('${dir.path}/.nativa-perf').writeAsStringSync(
          '${suite.url}\n${suite.commit}\n${suite.license}\n',
        );
        lines.add('${suite.id}: fetched from ${suite.url}');
      } else {
        lines.add('${suite.id}: download failed');
      }
      continue;
    }
    if (suite.id == 'millionrows') {
      lines.add(
        '${suite.id}: skipped (no upstream license and requires npm build; '
        'use ${suite.fetchHint})',
      );
      continue;
    }
    lines.add('${suite.id}: unavailable');
  }
  return lines;
}

Future<bool> _download(String url, String path) async {
  final result = await Process.run('curl', [
    '-sSL',
    '--fail',
    '--max-time',
    '60',
    '-o',
    path,
    url,
  ]);
  return result.exitCode == 0 && File(path).existsSync();
}
