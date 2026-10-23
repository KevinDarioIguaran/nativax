// Profile/AOT benchmark for NativaX large documents.
//
// It exercises the public rendering chain (NativaXRuntime -> DocumentView ->
// Flutter RenderObjects) without touching the engine internals. Build and run:
//
//   flutter build linux --profile
//   NATIVAX_BENCH_FILE=/tmp/list_10k.html \
//     build/linux/x64/profile/bundle/render_benchmark
//
// Scenarios: load (default), mutate, updateall, scroll, resize.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nativax/nativax.dart' hide Element;
import 'package:nativa_render/nativa_render.dart';

void main() async {
  final appWatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  final file = Platform.environment['NATIVAX_BENCH_FILE'];
  final asset = Platform.environment['NATIVAX_BENCH_HTML'];
  final source = file != null
      ? await File(file).readAsString()
      : await rootBundle.loadString(asset ?? 'assets/ten_thousand_nodes.html');
  final scenario = Platform.environment['NATIVAX_SCENARIO'] ?? 'load';
  final targetSelector =
      Platform.environment['NATIVAX_TARGET'] ?? '#doc';
  final root = Platform.environment['NATIVAX_BENCH_ROOT'];
  final loader = root == null ? const NativaXDenyAllResources() : NativaXDirectoryLoader(root);
  final scrollSteps =
      int.tryParse(Platform.environment['NATIVAX_SCROLL_STEPS'] ?? '') ?? 40;
  final holdMs =
      int.tryParse(Platform.environment['NATIVAX_FRAMES_MS'] ?? '') ?? 1200;

  developer.Timeline.startSync('nativax.create');
  final createWatch = Stopwatch()..start();
  final runtime = await NativaXRuntime.create(
    source: source,
    environment: StaticEnvironment(
      media: const MediaContext(width: 1440, height: 900),
      languages: const ['es-CO'],
      platform: 'linux',
    ),
    config: NativaXRuntimeConfig(
      resources: loader,
      engine: const JavaScriptEngineConfig(
        executionBudget: Duration(minutes: 2),
        maxJobsPerDrain: 10000000,
      ),
    ),
  );
  createWatch.stop();
  developer.Timeline.finishSync();

  print(
    'PHASE create=${createWatch.elapsedMilliseconds}ms '
    'nodes=${runtime.document.querySelectorAll('*').length} '
    'scenario=$scenario file=${file ?? asset}',
  );

  runApp(BenchApp(
    runtime: runtime,
    appWatch: appWatch,
    createMs: createWatch.elapsedMilliseconds,
    scenario: scenario,
    targetSelector: targetSelector,
    scrollSteps: scrollSteps,
    holdMs: holdMs,
  ));
  print('AFTER_RUN_APP wall=${appWatch.elapsedMilliseconds}ms');
}

class BenchApp extends StatefulWidget {
  const BenchApp({
    super.key,
    required this.runtime,
    required this.appWatch,
    required this.createMs,
    required this.scenario,
    required this.targetSelector,
    required this.scrollSteps,
    required this.holdMs,
  });

  final NativaXRuntime runtime;
  final Stopwatch appWatch;
  final int createMs;
  final String scenario;
  final String targetSelector;
  final int scrollSteps;
  final int holdMs;

  @override
  State<BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<BenchApp> {
  bool _first = true;
  bool _reported = false;
  final List<String> _frames = [];
  final List<int> _frameTotals = [];
  DateTime? _runStart;
  Timer? _holdTimer;
  double _width = 1440;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _afterFirstFrame() {
    if (!mounted) return;
    _runStart = DateTime.now();
    switch (widget.scenario) {
      case 'mutate':
        _mutateOnce();
      case 'updateall':
        _updateAll();
      case 'scroll':
        _scheduleScroll();
      case 'resize':
        _scheduleResize();
      default:
        // Let the timing callback deliver the first frame, and for documents
        // that populate after load, hold to catch later long frames.
        _holdTimer = Timer(Duration(milliseconds: widget.holdMs), () {
          _report();
          _finish();
        });
    }
  }

  void _mutateOnce() {
    final doc = widget.runtime.document;
    final target = widget.targetSelector == 'body'
        ? doc.body
        : doc.querySelector(widget.targetSelector) ?? doc.body;
    target?.setAttribute('data-bench', '1');
    SchedulerBinding.instance.scheduleFrame();
    _holdTimer = Timer(Duration(milliseconds: widget.holdMs), () {
      _report();
      _finish();
    });
  }

  /// Queue one DOM mutation per direct child, then let the document view
  /// coalesce them into a single frame.
  void _updateAll() {
    final doc = widget.runtime.document;
    final target = doc.querySelector(widget.targetSelector) ?? doc.body;
    if (target != null) {
      for (final child in target.children) {
        child.setAttribute('data-bench', '1');
      }
    }
    SchedulerBinding.instance.scheduleFrame();
    _holdTimer = Timer(Duration(milliseconds: widget.holdMs), () {
      _report();
      _finish();
    });
  }

  ScrollableState? _documentScrollable() {
    ScrollableState? best;
    double bestExtent = 0;
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        if (state.position.hasContentDimensions) {
          final extent = state.position.maxScrollExtent;
          if (extent > bestExtent) {
            best = state;
            bestExtent = extent;
          }
        }
      }
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return best;
  }

  void _scheduleScroll() {
    final scrollable = _documentScrollable();
    if (scrollable == null) {
      print('SCROLL no scrollable');
      _report();
      _finish();
      return;
    }
    final max = scrollable.position.maxScrollExtent;
    _step = 0;
    void tick() {
      if (!mounted) return;
      if (_step >= widget.scrollSteps) {
        _report();
        _finish();
        return;
      }
      final t = _step / (widget.scrollSteps - 1).clamp(1, 1 << 30);
      // Down to the end and back, with no easing.
      final y = _step < widget.scrollSteps ~/ 2
          ? max * (t * 2)
          : max * (2 - t * 2);
      scrollable.position.jumpTo(y.clamp(0, max));
      _step++;
      SchedulerBinding.instance.addPostFrameCallback((_) => tick());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tick());
  }

  void _scheduleResize() {
    var n = 0;
    void tick() {
      if (!mounted) return;
      if (n >= 6) {
        _report();
        _finish();
        return;
      }
      setState(() => _width = n.isEven ? 1024 : 1440);
      n++;
      SchedulerBinding.instance.addPostFrameCallback((_) => tick());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tick());
  }

  String _topTags(Map<String, int> tags) {
    final entries = tags.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(8).map((e) => '${e.key}:${e.value}').join(',');
  }

  int _countRenderObjects() {
    var count = 0;
    void visit(RenderObject object) {
      count++;
      object.visitChildren(visit);
    }

    for (final view in RendererBinding.instance.renderViews) {
      final root = view.child;
      if (root != null) visit(root);
    }
    return count;
  }

  int _countElements() {
    var count = 0;
    void visit(Element element) {
      count++;
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return count;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMilliseconds;
      final raster = t.rasterDuration.inMilliseconds;
      final total = t.totalSpan.inMilliseconds;
      if (total <= 0 && build <= 0 && raster <= 0) continue;
      final line =
          'FRAME wall=${widget.appWatch.elapsedMilliseconds}ms '
          'total=${total}ms build=${build}ms raster=${raster}ms';
      _frames.add(line);
      _frameTotals.add(total);
      if (_first) {
        _first = false;
        print('FIRST_FRAME $line nodes=${widget.runtime.document.querySelectorAll('*').length} '
            'renderObjects=${_countRenderObjects()} widgets=${_countElements()} '
            'create=${widget.createMs}ms builds=${NativeXBuildStats.elementBuilds} '
            'virtual=${NativeXBuildStats.virtualBlocks}/${NativeXBuildStats.virtualItems} '
            'styleComputes=${widget.runtime.styleEngine.computeCount} '
            'subtreePasses=${widget.runtime.styleEngine.subtreePasses} '
            'lazy=${widget.runtime.styleEngine.lazySubtrees} '
            'tags=${_topTags(widget.runtime.styleEngine.computesByTag)} '
            'file=${Platform.environment['NATIVAX_BENCH_FILE'] ?? ''}');
      }
    }
  }

  void _report() {
    if (_reported) return;
    _reported = true;
    final totals = List<int>.of(_frameTotals)..sort();
    final p95 = totals.isEmpty
        ? 0
        : totals[((totals.length - 1) * 0.95).round().clamp(0, totals.length - 1)];
    final over50 = _frameTotals.where((v) => v > 50).length;
    print(
      'SUMMARY scenario=${widget.scenario} '
      'nodes=${widget.runtime.document.querySelectorAll('*').length} '
      'frames=${_frameTotals.length} over50=$over50 p95=${p95}ms '
      'max=${totals.isEmpty ? 0 : totals.last}ms '
      'renderObjects=${_countRenderObjects()} widgets=${_countElements()} '
      'documentHeight=${widget.runtime.document.layoutHost?.documentHeight.toStringAsFixed(0) ?? '-'}',
    );
    for (final f in _frames) {
      print(f);
    }
  }

  void _finish() {
    _holdTimer?.cancel();
    // Give the last frame a chance to be reported before process exit.
    Timer(const Duration(milliseconds: 100), () => exit(0));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _width,
            height: 900,
            child: NativaXDocumentView(
              document: widget.runtime.document,
              styleEngine: widget.runtime.styleEngine,
            ),
          ),
        ),
      ),
    );
  }
}
