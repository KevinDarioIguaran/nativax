import 'dart:convert';
import 'dart:io';

import 'package:nativa_visual/visual.dart';

const String _usage = '''
NativaX visual fidelity judge — headless Chromium vs headless NativaX.

Usage:
  dart run debug/engines/visual_comparison/bin/visual_check.dart [options] [page|dir ...]

Pages:
  <file.html>            compare one HTML page
  <dir>                  compare <dir>/index.html, or every subdirectory
                         containing index.html when <dir> has none
  --suite <id>           add a pinned fixture suite (repeatable)
  --all                  add every pinned suite (about 205 pages)
  --list                 list the pages that would run and exit
  --catalog <file>       write the selected page catalog as JSON and exit

Options:
  -w, --width <px>       reference window width (default 800)
  -H, --height <px>      layout viewport height (default 900). The Chromium
                         window/measurement offset is calibrated automatically.
  --out <dir>            output directory (default .visual/latest)
  --chrome <exe>         Chromium binary (default google-chrome / CHROME env)
  --scheme <light|dark>  prefers-color-scheme for both engines
  --setup-js <js>        script run after load in both engines
  --only <regex>         only pages whose id matches the regex
  --limit <n>            stop after n pages
  --resume               reuse chrome.json/nativax.json/*.png artifacts
  --pixel-csv            write pixels.csv (every mismatched pixel)
  --pixel-csv-all        write every pixel, not only mismatches
  --keep-staging         keep the staged page copies under each page
  --fail-under <pct>     also exit 1 when a page scores below this percentage
  --self-check           compare Chromium against a second Chromium render;
                         a correct judge reports 100 / PASS
  --json                 print the run JSON to stdout
  -h, --help             show this help

Examples:
  dart run debug/engines/visual_comparison/bin/visual_check.dart --suite 50projects50days
  dart run debug/engines/visual_comparison/bin/visual_check.dart --self-check
  dart run debug/engines/visual_comparison/bin/visual_check.dart examples/test-pages/form.html
''';

class _Cli {
  final pages = <String>[];
  final suites = <String>[];
  int width = 800;
  int height = 900;
  String out = '.visual/latest';
  String chrome = Platform.environment['CHROME'] ?? 'google-chrome';
  String scheme = 'light';
  String setupJs = '';
  String? only;
  int limit = 0;
  bool resume = false;
  bool pixelCsv = false;
  bool pixelCsvAll = false;
  bool keepStaging = false;
  double failUnder = 0;
  bool selfCheck = false;
  bool json = false;
  bool list = false;
  String? catalog;
  bool help = false;
}

_Cli _parse(List<String> args) {
  final cli = _Cli();
  String? takeValue(String arg, String flag, int index) {
    if (arg == flag) {
      if (index + 1 >= args.length)
        throw ArgumentError('missing value for $flag');
      return args[index + 1];
    }
    if (arg.startsWith('$flag=')) return arg.substring(flag.length + 1);
    return null;
  }

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final width = takeValue(arg, '--width', i);
    if (width != null) {
      cli.width = int.parse(width);
      if (arg == '--width') i++;
      continue;
    }
    final shortWidth = takeValue(arg, '-w', i);
    if (shortWidth != null) {
      cli.width = int.parse(shortWidth);
      if (arg == '-w') i++;
      continue;
    }
    final height = takeValue(arg, '--height', i);
    if (height != null) {
      cli.height = int.parse(height);
      if (arg == '--height') i++;
      continue;
    }
    final shortHeight = takeValue(arg, '-H', i);
    if (shortHeight != null) {
      cli.height = int.parse(shortHeight);
      if (arg == '-H') i++;
      continue;
    }
    final out = takeValue(arg, '--out', i);
    if (out != null) {
      cli.out = out;
      if (arg == '--out') i++;
      continue;
    }
    final chrome = takeValue(arg, '--chrome', i);
    if (chrome != null) {
      cli.chrome = chrome;
      if (arg == '--chrome') i++;
      continue;
    }
    final scheme = takeValue(arg, '--scheme', i);
    if (scheme != null) {
      cli.scheme = scheme;
      if (arg == '--scheme') i++;
      continue;
    }
    final setup = takeValue(arg, '--setup-js', i);
    if (setup != null) {
      cli.setupJs = setup;
      if (arg == '--setup-js') i++;
      continue;
    }
    final only = takeValue(arg, '--only', i);
    if (only != null) {
      cli.only = only;
      if (arg == '--only') i++;
      continue;
    }
    final limit = takeValue(arg, '--limit', i);
    if (limit != null) {
      cli.limit = int.parse(limit);
      if (arg == '--limit') i++;
      continue;
    }
    final failUnder = takeValue(arg, '--fail-under', i);
    if (failUnder != null) {
      cli.failUnder = double.parse(failUnder);
      if (arg == '--fail-under') i++;
      continue;
    }
    final suite = takeValue(arg, '--suite', i);
    if (suite != null) {
      cli.suites.add(suite);
      if (arg == '--suite') i++;
      continue;
    }
    switch (arg) {
      case '--resume':
        cli.resume = true;
      case '--pixel-csv':
        cli.pixelCsv = true;
      case '--pixel-csv-all':
        cli.pixelCsv = true;
        cli.pixelCsvAll = true;
      case '--keep-staging':
        cli.keepStaging = true;
      case '--self-check':
        cli.selfCheck = true;
      case '--json':
        cli.json = true;
      case '--all':
        cli.suites.addAll(knownSuites.map((s) => s.id));
      case '--list':
        cli.list = true;
      case '--catalog':
        cli.catalog = args[++i];
      case '-h':
      case '--help':
        cli.help = true;
      default:
        if (arg.startsWith('-')) throw ArgumentError('unknown option: $arg');
        cli.pages.add(arg);
    }
  }
  return cli;
}

Future<void> main(List<String> arguments) async {
  _Cli cli;
  try {
    cli = _parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    stderr.writeln(_usage);
    exit(64);
  } on ArgumentError catch (error) {
    stderr.writeln('error: ${error.message}');
    stderr.writeln(_usage);
    exit(64);
  }
  if (cli.help) {
    stdout.writeln(_usage);
    return;
  }

  final repoRoot = _findRepoRoot();
  final out = Directory(cli.out).absolute.path;
  Directory(out).createSync(recursive: true);

  // Resolve fixture suites.
  final pages = <PageSource>[];
  for (final id in cli.suites) {
    final suite = suiteById(id);
    if (suite == null) {
      stderr.writeln(
        'error: unknown suite "$id". Known: '
        '${knownSuites.map((s) => s.id).join(', ')}',
      );
      exit(64);
    }
    final root = await ensureSuite(repoRoot, suite);
    pages.addAll(discoverSuitePages(root, suite));
  }

  for (final path in cli.pages) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      pages.add(pageFromPath(path));
    } else if (type == FileSystemEntityType.directory) {
      final direct = File('${Directory(path).absolute.path}/index.html');
      if (direct.existsSync()) {
        pages.add(pageFromPath(path));
      } else {
        pages.addAll(discoverPages(path, suite: _lastSegment(path)));
        final htmls =
            Directory(path)
                .listSync()
                .whereType<File>()
                .where((f) => f.path.toLowerCase().endsWith('.html'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final html in htmls) {
          pages.add(
            PageSource(
              id: '${_lastSegment(path)}/${_lastSegment(html.path).replaceAll('.html', '')}',
              suite: _lastSegment(path),
              entry: html.path,
              directory: Directory(path).absolute.path,
            ),
          );
        }
      }
    } else {
      stderr.writeln('error: not found: $path');
      exit(66);
    }
  }

  if (pages.isEmpty && cli.suites.isEmpty) {
    final vendored =
        '$repoRoot/debug/engines/visual_comparison/fixtures/50projects50days';
    if (Directory(vendored).existsSync()) {
      pages.addAll(discoverPages(vendored, suite: '50projects50days'));
    }
    final testPages = '$repoRoot/examples/test-pages';
    if (Directory(testPages).existsSync()) {
      for (final file
          in Directory(testPages).listSync().whereType<File>().where(
            (f) => f.path.toLowerCase().endsWith('.html'),
          )) {
        pages.add(
          PageSource(
            id: 'test-pages/${_lastSegment(file.path).replaceAll('.html', '')}',
            suite: 'test-pages',
            entry: file.path,
            directory: testPages,
          ),
        );
      }
    }
  }

  final unique = <String, PageSource>{for (final page in pages) page.id: page};
  var selected = unique.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  if (cli.only != null) {
    final pattern = RegExp(cli.only!);
    selected = selected.where((p) => pattern.hasMatch(p.id)).toList();
  }
  if (cli.limit > 0) selected = selected.take(cli.limit).toList();

  if (selected.isEmpty) {
    stderr.writeln('error: no pages selected');
    exit(65);
  }
  if (cli.catalog != null) {
    final catalogJson = [
      for (final page in selected)
        {
          'id': page.id,
          'suite': page.suite,
          'entry': page.entry,
          'directory': page.directory,
        },
    ];
    final file = File(cli.catalog!);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(catalogJson),
    );
  }
  if (cli.list) {
    final listJson = [
      for (final page in selected)
        {
          'id': page.id,
          'suite': page.suite,
          'entry': page.entry,
          'directory': page.directory,
        },
    ];
    if (cli.json) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(listJson));
    } else {
      for (final page in selected) {
        stdout.writeln(page.id);
      }
    }
    return;
  }

  final chromeVersion = await _chromeVersion(cli.chrome);
  final int frameDelta;
  try {
    frameDelta = await calibrateChromeFrame(
      executable: cli.chrome,
      width: cli.width,
      height: cli.height,
    );
  } catch (error) {
    stderr.writeln(
      'error: could not calibrate Chromium layout viewport: $error',
    );
    exit(69);
  }
  final options = JudgeOptions(
    repoRoot: repoRoot,
    outputDir: out,
    width: cli.width,
    height: cli.height,
    frameDelta: frameDelta,
    scheme: cli.scheme,
    setupJs: cli.setupJs,
    pixelCsv: cli.pixelCsv,
    pixelCsvAll: cli.pixelCsvAll,
    keepStaging: cli.keepStaging,
    chromeExecutable: cli.chrome,
    chromeVersion: chromeVersion,
    git: await readGitRevision(repoRoot),
  );

  stdout.writeln('NativaX visual judge');
  stdout.writeln('  reference: $chromeVersion');
  stdout.writeln(
    '  viewport:  ${cli.width}x${cli.height} '
    '(frame offset ${frameDelta}px applied to measurement)',
  );
  stdout.writeln('  output:    $out');
  stdout.writeln('  pages:     ${selected.length}');
  stdout.writeln('');

  final started = DateTime.now();
  final reports = <PageReport>[];
  final digits = selected.length.toString().length;
  RunReport liveReport() => RunReport(
    startedAt: started,
    duration: DateTime.now().difference(started),
    chromeVersion: chromeVersion,
    viewportWidth: cli.width,
    viewportHeight: cli.height,
    scheme: cli.scheme,
    frozenAnimations: true,
    outputDir: out,
    pages: List<PageReport>.of(reports),
    command:
        'dart run debug/engines/visual_comparison/bin/visual_check.dart ${arguments.join(' ')}',
  );
  var index = 0;
  for (final page in selected) {
    index++;
    final prefix =
        '[${index.toString().padLeft(digits)}/${selected.length}] ${page.id}';
    stdout.write('$prefix ... ');
    final stopwatch = Stopwatch()..start();
    PageJudgeResult result;
    try {
      if (cli.selfCheck) {
        result = await selfCheck(page, options);
      } else if (cli.resume) {
        final reused = await reusePage(page, options);
        result = reused ?? await judgePage(page, options);
      } else {
        result = await judgePage(page, options);
      }
    } catch (error, stack) {
      stdout.writeln('ERROR $error');
      stderr.writeln(stack);
      reports.add(
        PageReport(
          page: page,
          viewportWidth: cli.width,
          viewportHeight: cli.height,
          scheme: cli.scheme,
          artifactsDir: pageArtifactsDirectory(out, page.id),
          checks: [
            EnvCheck(name: 'judge', ok: false, hard: true, detail: '$error'),
          ],
          failure: '$error',
        ),
      );
      liveReport().writeLiveResults(out);
      continue;
    }
    reports.add(result.report);
    liveReport().writeLiveResults(out);
    final eval = result.report.evaluation;
    if (eval == null) {
      stdout.writeln('INVALID  ${result.report.failure ?? ''}');
      continue;
    }
    stdout.writeln(
      '${eval.verdict.label.padRight(7)} '
      'overall ${(eval.overall * 100).toStringAsFixed(1)} %  '
      'pos ${(eval.position! * 100).toStringAsFixed(1)}  '
      'layout ${(eval.layout! * 100).toStringAsFixed(1)}  '
      'color ${eval.color == null ? '—' : (eval.color! * 100).toStringAsFixed(1)}  '
      'design ${eval.design == null ? '—' : (eval.design! * 100).toStringAsFixed(1)}  '
      'px ${eval.mismatchedPixelPct.toStringAsFixed(2)} %  '
      '(${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)',
    );
  }

  final run = RunReport(
    startedAt: started,
    duration: DateTime.now().difference(started),
    chromeVersion: chromeVersion,
    viewportWidth: cli.width,
    viewportHeight: cli.height,
    scheme: cli.scheme,
    frozenAnimations: true,
    outputDir: out,
    pages: reports,
    command:
        'dart run debug/engines/visual_comparison/bin/visual_check.dart ${arguments.join(' ')}',
  );
  run.write(out);

  final failed = reports
      .where((p) => p.verdict == Verdict.fail || p.verdict == Verdict.invalid)
      .length;
  final below = cli.failUnder > 0
      ? reports
            .where((p) => p.overall == null || p.overall! * 100 < cli.failUnder)
            .length
      : 0;

  stdout.writeln('');
  stdout.writeln(
    'Summary: ${run.count(Verdict.pass)} PASS, ${run.count(Verdict.warn)} WARN, '
    '${run.count(Verdict.fail)} FAIL, ${run.count(Verdict.invalid)} INVALID '
    '(${run.pages.length} pages, mean overall '
    '${(run.meanOverall * 100).toStringAsFixed(2)} %)',
  );
  stdout.writeln('Report:  $out/report.md');
  stdout.writeln('JSON:    $out/report.json');
  stdout.writeln('Table:   $out/results.json');
  if (cli.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(run.toJson()));
  }

  if (cli.selfCheck) {
    final bad = reports
        .where((p) => p.verdict != Verdict.pass || (p.overall ?? 0) < 0.999)
        .toList();
    if (bad.isNotEmpty) {
      stderr.writeln(
        'self-check FAILED: ${bad.map((p) => p.page.id).join(', ')}',
      );
      exit(1);
    }
    stdout.writeln('self-check OK: reference vs reference scored 100 % / PASS');
    return;
  }
  if (failed > 0 || below > 0) exit(1);
}

Future<String> _chromeVersion(String executable) async {
  try {
    final result = await Process.run(executable, ['--version']);
    final text = '${result.stdout}${result.stderr}'.trim().split('\n').first;
    return text.isEmpty ? executable : text;
  } catch (_) {
    return executable;
  }
}

String _findRepoRoot() {
  var directory = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: nativa_workspace')) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return Directory.current.absolute.path;
}

String _lastSegment(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.isEmpty ? path : parts.last;
}
