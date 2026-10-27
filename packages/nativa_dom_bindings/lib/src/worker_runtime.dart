import 'dart:async';
import 'dart:convert';

import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';

import 'dom_bindings.dart';
import 'environment.dart';
import 'messaging.dart';
import 'module_graph.dart';
import 'network.dart';

/// The script of a worker, resolved by its launcher before it starts.
class WorkerScript {
  const WorkerScript({required this.url, required this.type, required this.source, this.modules = const {}});

  final String url;

  /// `classic` or `module`.
  final String type;
  final String source;

  /// The module graph of a module worker, by absolute URL.
  final Map<String, String> modules;
}

/// One dedicated worker's global scope: its own JavaScriptCore engine, timers and
/// web platform (without `window`/`document`), wired to the page through
/// [messaging]. Runs on the isolate that creates it.
class WorkerRuntime {
  WorkerRuntime._(this.engine, this.timers, this.bindings);

  final JscEngine engine;
  final TimerHost timers;
  final DomBindings bindings;
  bool _closed = false;

  bool get isClosed => _closed;

  /// Starts the worker and runs [script]. [report] receives `error`,
  /// `console` and `close` events for the page.
  static WorkerRuntime start({
    required WorkerScript script,
    required int port,
    required NativaXMessaging messaging,
    required void Function(Map<String, Object?> event) report,
    String name = '',
    NativaXNetwork network = const DeniedNetwork(),
    JavaScriptEngineConfig engineConfig = const JavaScriptEngineConfig(
      memoryLimitBytes: 512 * 1024 * 1024,
      executionBudget: Duration(seconds: 30),
      maxJobsPerDrain: 1000000,
    ),
    bool canBlock = false,
    void Function(JscEngine engine)? beforeScript,
  }) {
    final engine = JscEngine(engineConfig);
    if (canBlock) engine.canBlock = true;
    late final WorkerRuntime runtime;
    void error(Object e) {
      if (e is JavaScriptException) {
        report({'type': 'error', 'message': '${e.name}: ${e.message}', 'filename': script.url, 'stack': e.stack});
      } else {
        report({'type': 'error', 'message': '$e', 'filename': script.url});
      }
    }

    final timers = TimerHost(engine, onError: error);
    installConsole(engine, (m) => report({'type': 'console', 'level': m.level.name, 'text': m.text}));
    final document = HtmlParser().parseDocument('').value;
    final bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(media: const MediaContext(width: 800, height: 600)),
      documentUrl: script.url,
      network: network,
      messaging: messaging,
      onScriptError: error,
      workerScope: WorkerScopeInfo(
        port: port,
        name: name,
        type: script.type,
        onClose: () => Timer.run(() {
          runtime.dispose();
          report({'type': 'close'});
        }),
        importScript: (url) => script.modules[url],
      ),
    )..install();
    runtime = WorkerRuntime._(engine, timers, bindings);
    beforeScript?.call(engine);
    bindings.harden();
    try {
      if (script.type == 'module') {
        engine.moduleHost = ModuleGraph(
          load: (_) async => null,
          sources: Map.of(script.modules),
          onModuleError: error,
        );
        engine.evaluateModule(script.source, url: script.url);
      } else {
        engine.evaluate(script.source, filename: script.url);
      }
    } catch (e) {
      error(e);
    }
    return runtime;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    timers.dispose();
    bindings.dispose();
    engine.dispose();
  }
}

/// Resolves a worker's script (and module graph) for a launcher. [load]
/// fetches text by absolute URL.
Future<WorkerScript?> resolveWorkerScript(WorkerRequest request, Future<String?> Function(String url) load) async {
  final inline = request.source;
  if (request.type != 'module') {
    final source = inline ?? await load(request.url);
    return source == null ? null : WorkerScript(url: request.url, type: 'classic', source: source);
  }
  final graph = ModuleGraph(load: load);
  await graph.prefetch(request.url, source: inline);
  final source = inline ?? graph.source(request.url);
  if (source == null) return null;
  return WorkerScript(url: request.url, type: 'module', source: source, modules: graph.sources);
}

/// Runs workers on the page's own isolate (no parallelism). Used when no
/// threaded launcher is configured; scripts load through [network].
class InProcessWorkerLauncher implements WorkerLauncher {
  InProcessWorkerLauncher({this.network = const DeniedNetwork()});

  final NativaXNetwork network;
  final Map<int, WorkerRuntime> _running = {};
  final Set<int> _terminated = {};

  Future<String?> _load(String url) async {
    try {
      final res = await network.fetch(NetworkRequest(url: Uri.parse(url)));
      if (res.status < 200 || res.status > 299) return null;
      return utf8.decode(res.body, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  @override
  void launch({
    required PortRouter router,
    required int endpoint,
    required int workerId,
    required int port,
    required WorkerRequest request,
    required void Function(Map<String, Object?> event) report,
  }) {
    resolveWorkerScript(request, _load).then((script) {
      if (_terminated.remove(workerId)) return;
      if (script == null) {
        report({'type': 'error', 'message': 'Failed to load worker script ${request.url}'});
        return;
      }
      final messaging = RouterMessaging.forEndpoint(router, endpoint);
      _running[workerId] = WorkerRuntime.start(
        script: script,
        port: port,
        name: request.name,
        messaging: messaging,
        network: network,
        report: (e) => Timer.run(() => report(e)),
      );
    });
  }

  @override
  void terminate(int workerId, {bool immediate = false}) {
    final w = _running.remove(workerId);
    if (w == null) {
      _terminated.add(workerId);
    } else {
      w.dispose();
    }
  }
}
