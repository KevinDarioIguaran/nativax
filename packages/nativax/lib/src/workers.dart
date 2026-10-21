import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nativax_dom_bindings/nativax_dom_bindings.dart';
import 'package:nativax_js/nativax_js.dart';

/// Runs each dedicated worker on its own isolate (its own thread and
/// QuickJS runtime), like browsers. Ports, `fetch` and console/error reports
/// travel over isolate ports; `SharedArrayBuffer` memory and byte buffers are
/// shared natively (no copies through Dart).
class IsolateWorkerLauncher implements WorkerLauncher {
  IsolateWorkerLauncher({
    required this.loadScript,
    required this.network,
    this.engineConfig = const JavaScriptEngineConfig(
      memoryLimitBytes: 1024 * 1024 * 1024,
      maxStackBytes: 1024 * 1024,
      executionBudget: Duration(seconds: 30),
      maxJobsPerDrain: 1000000,
    ),
    this.maxWorkers = 16,
  });

  /// Loads worker scripts and modules by absolute URL.
  final Future<String?> Function(String url) loadScript;

  /// Serves `fetch()`/XHR from workers (the page's network policy).
  final NativaXNetwork network;
  final JavaScriptEngineConfig engineConfig;
  final int maxWorkers;
  final Map<int, _WorkerHandle> _workers = {};

  @override
  void launch({
    required PortRouter router,
    required int endpoint,
    required int workerId,
    required int port,
    required WorkerRequest request,
    required void Function(Map<String, Object?> event) report,
  }) {
    if (_workers.length >= maxWorkers) {
      Timer.run(() => report({'type': 'error', 'message': 'QuotaExceededError: too many workers'}));
      return;
    }
    final handle = _WorkerHandle();
    _workers[workerId] = handle;
    resolveWorkerScript(request, loadScript).then((script) async {
      if (handle.terminated) return;
      if (script == null) {
        report({'type': 'error', 'message': 'Failed to load worker script ${request.url}'});
        return;
      }
      final fromWorker = ReceivePort();
      final errors = ReceivePort();
      handle.ports.addAll([fromWorker, errors]);
      errors.listen((e) {
        final list = e as List;
        report({'type': 'error', 'message': '${list[0]}'});
      });
      fromWorker.listen((message) => _onWorkerMessage(handle, router, endpoint, report, message));
      try {
        handle.isolate = await Isolate.spawn(
          _workerMain,
          _Boot(
            toMain: fromWorker.sendPort,
            endpoint: endpoint,
            port: port,
            name: request.name,
            url: script.url,
            type: script.type,
            source: script.source,
            modules: script.modules,
            memoryLimit: engineConfig.memoryLimitBytes,
            stack: engineConfig.maxStackBytes,
            budgetMs: engineConfig.executionBudget.inMilliseconds,
            maxJobs: engineConfig.maxJobsPerDrain,
          ),
          onError: errors.sendPort,
          debugName: 'nativax-worker-$workerId${request.name.isEmpty ? '' : ' (${request.name})'}',
        );
        if (handle.terminated) handle.kill();
      } catch (e) {
        report({'type': 'error', 'message': 'Failed to start worker: $e'});
        handle.close();
      }
    });
  }

  void _onWorkerMessage(
    _WorkerHandle handle,
    PortRouter router,
    int endpoint,
    void Function(Map<String, Object?> event) report,
    Object? message,
  ) {
    if (message is SendPort) {
      handle.toWorker = message;
      router.connectEndpoint(
        endpoint,
        deliver: (port, wire) => message.send(['d', port, wire]),
        workerEvent: (worker, event) {},
      );
      return;
    }
    final m = message as List;
    switch (m[0]) {
      case 'pair':
        router.registerPair(m[1] as int, m[2] as int, endpoint);
      case 'post':
        router.post(m[1] as int, m[2] as String, (m[3] as List).cast<int>());
      case 'adopt':
        router.adopt(m[1] as int, endpoint);
      case 'close':
        router.close(m[1] as int);
      case 'report':
        final event = (m[1] as Map).cast<String, Object?>();
        report(event);
        if (event['type'] == 'close') handle.close();
      case 'fetch':
        _fetch(handle, m);
    }
  }

  void _fetch(_WorkerHandle handle, List m) {
    final id = m[1] as int;
    final body = m[5] as TransferableTypedData?;
    final request = NetworkRequest(
      url: Uri.parse(m[2] as String),
      method: m[3] as String,
      headers: [for (final h in (m[4] as List)) ((h as List)[0] as String, h[1] as String)],
      body: body?.materialize().asUint8List(),
    );
    network.fetch(request).then((res) {
      handle.toWorker?.send([
        'fetched',
        id,
        {
          'status': res.status,
          'statusText': res.statusText,
          'headers': [for (final (k, v) in res.headers) [k, v]],
          'url': res.url.toString(),
          'redirected': res.redirected,
        },
        TransferableTypedData.fromList([res.body]),
      ]);
    }, onError: (Object e) {
      handle.toWorker?.send(['fetched', id, {'error': '$e'}, null]);
    });
  }

  @override
  void terminate(int workerId) {
    final handle = _workers.remove(workerId);
    if (handle == null) return;
    handle.terminated = true;
    handle.toWorker?.send(['terminate']);
    // A worker busy in a long script cannot read the request: kill it.
    Timer(const Duration(milliseconds: 250), handle.kill);
  }
}

class _WorkerHandle {
  Isolate? isolate;
  SendPort? toWorker;
  bool terminated = false;
  final List<ReceivePort> ports = [];

  void kill() {
    isolate?.kill(priority: Isolate.immediate);
    isolate = null;
    close();
  }

  void close() {
    for (final p in ports) {
      p.close();
    }
    ports.clear();
  }
}

class _Boot {
  const _Boot({
    required this.toMain,
    required this.endpoint,
    required this.port,
    required this.name,
    required this.url,
    required this.type,
    required this.source,
    required this.modules,
    required this.memoryLimit,
    required this.stack,
    required this.budgetMs,
    required this.maxJobs,
  });

  final SendPort toMain;
  final int endpoint;
  final int port;
  final String name;
  final String url;
  final String type;
  final String source;
  final Map<String, String> modules;
  final int memoryLimit;
  final int stack;
  final int budgetMs;
  final int maxJobs;
}

/// Worker isolate entry point.
void _workerMain(_Boot boot) {
  final inbox = ReceivePort();
  boot.toMain.send(inbox.sendPort);
  final messaging = _RemoteMessaging(boot.toMain, boot.endpoint);
  final network = _RemoteNetwork(boot.toMain);
  final runtime = WorkerRuntime.start(
    script: WorkerScript(url: boot.url, type: boot.type, source: boot.source, modules: boot.modules),
    port: boot.port,
    name: boot.name,
    messaging: messaging,
    network: network,
    canBlock: true,
    engineConfig: JavaScriptEngineConfig(
      memoryLimitBytes: boot.memoryLimit,
      maxStackBytes: boot.stack,
      executionBudget: Duration(milliseconds: boot.budgetMs),
      maxJobsPerDrain: boot.maxJobs,
    ),
    report: (event) => boot.toMain.send(['report', event]),
  );
  inbox.listen((message) {
    final m = message as List;
    switch (m[0]) {
      case 'd':
        if (!runtime.isClosed) messaging.deliver(m[1] as int, m[2] as String);
      case 'fetched':
        network.complete(m[1] as int, (m[2] as Map).cast<String, Object?>(), m[3] as TransferableTypedData?);
      case 'terminate':
        runtime.dispose();
        inbox.close();
    }
  });
}

/// The worker's view of the page's [PortRouter].
class _RemoteMessaging extends NativaXMessaging {
  _RemoteMessaging(this._toMain, this._endpoint);

  final SendPort _toMain;
  final int _endpoint;
  int _next = 1;
  void Function(int port, String wire)? _deliver;

  void deliver(int port, String wire) => _deliver?.call(port, wire);

  @override
  void attach({
    required void Function(int port, String wire) deliver,
    required void Function(int worker, Map<String, Object?> event) workerEvent,
  }) {
    _deliver = deliver;
  }

  /// Worker-allocated ids live in their own range, so `new MessageChannel()`
  /// needs no round trip to the page.
  int _id() => (_endpoint << 32) + _next++;

  @override
  (int, int) pair() {
    final a = _id(), b = _id();
    _toMain.send(['pair', a, b]);
    return (a, b);
  }

  @override
  void post(int port, String wire, List<int> ports) => _toMain.send(['post', port, wire, ports]);

  @override
  void adopt(int port) => _toMain.send(['adopt', port]);

  @override
  void close(int port) => _toMain.send(['close', port]);

  @override
  (int, int) startWorker(WorkerRequest request) =>
      throw UnsupportedError('nested workers are not supported');

  @override
  void terminateWorker(int id) {}

  @override
  void dispose() {}
}

/// `fetch()` from a worker, served by the page's network policy.
class _RemoteNetwork implements NativaXNetwork {
  _RemoteNetwork(this._toMain);

  final SendPort _toMain;
  final Map<int, Completer<NetworkResponse>> _pending = {};
  int _next = 1;

  @override
  Future<NetworkResponse> fetch(NetworkRequest request) {
    final id = _next++;
    final c = Completer<NetworkResponse>();
    _pending[id] = c;
    final body = request.body;
    _toMain.send([
      'fetch',
      id,
      request.url.toString(),
      request.method,
      [for (final (k, v) in request.headers) [k, v]],
      body == null ? null : TransferableTypedData.fromList([body]),
    ]);
    final t = request.timeout;
    return t == null ? c.future : c.future.timeout(t);
  }

  void complete(int id, Map<String, Object?> result, TransferableTypedData? body) {
    final c = _pending.remove(id);
    if (c == null) return;
    final error = result['error'];
    if (error != null) {
      c.completeError(NetworkDenied('$error'));
      return;
    }
    c.complete(NetworkResponse(
      status: result['status'] as int,
      statusText: result['statusText'] as String? ?? '',
      headers: [for (final h in (result['headers'] as List)) ((h as List)[0] as String, h[1] as String)],
      body: body?.materialize().asUint8List() ?? Uint8List(0),
      url: Uri.parse(result['url'] as String),
      redirected: result['redirected'] == true,
    ));
  }

  @override
  Future<NetworkSocket> connect(Uri url, List<String> protocols) =>
      Future.error(const NetworkDenied('WebSocket is not available in workers yet'));
}
