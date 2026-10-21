import 'dart:async';

/// A dedicated worker the page asked for (`new Worker(url, options)`).
class WorkerRequest {
  const WorkerRequest({
    required this.url,
    this.type = 'classic',
    this.name = '',
    this.source,
  });

  /// Absolute script URL (`blob:` URLs come with [source]).
  final String url;

  /// `classic` or `module`.
  final String type;
  final String name;

  /// Script text when the page already holds it (blob and data URLs).
  final String? source;
}

/// Messaging for one script runtime (a document or a worker). `MessagePort`s
/// have process-wide ids; the implementation routes each message to the
/// runtime that owns the entangled port, possibly on another thread.
abstract class NativaXMessaging {
  /// Connects the runtime: [deliver] receives messages for ports it owns,
  /// [workerEvent] reports `error`/`close` of workers it started. Both run
  /// as tasks of the runtime's own event loop.
  void attach({
    required void Function(int port, String wire) deliver,
    required void Function(int worker, Map<String, Object?> event) workerEvent,
  });

  /// Allocates an entangled pair owned by this runtime.
  (int, int) pair();

  /// Sends [wire] (serialized message) from [port] to its partner; [ports]
  /// are the ports transferred inside it, now in transit.
  void post(int port, String wire, List<int> ports);

  /// This runtime received [port] in a message and now owns it.
  void adopt(int port);

  void close(int port);

  /// Starts a dedicated worker; returns its id and the page's side of the
  /// implicit channel (`worker.postMessage` / `worker.onmessage`).
  (int, int) startWorker(WorkerRequest request);

  void terminateWorker(int id);

  void dispose();
}

/// Starts the runtime of a worker for [PortRouter]. [port] is the worker's
/// side of its implicit channel; [endpoint] identifies it in the router.
abstract interface class WorkerLauncher {
  void launch({
    required PortRouter router,
    required int endpoint,
    required int workerId,
    required int port,
    required WorkerRequest request,
    required void Function(Map<String, Object?> event) report,
  });

  void terminate(int workerId);
}

class _PortState {
  _PortState(this.partner, this.owner);
  final int partner;

  /// Owning endpoint, or null while the port travels inside a message.
  int? owner;
  final List<String> queue = [];
  bool closed = false;
}

class _Endpoint {
  _Endpoint(this.deliver, this.workerEvent);
  final void Function(int port, String wire) deliver;
  final void Function(int worker, Map<String, Object?> event) workerEvent;
}

/// Routes port messages between endpoints (the page and its workers). Runs
/// on the page's isolate; endpoints on other isolates forward their calls to
/// it and receive deliveries through their own [_Endpoint.deliver].
class PortRouter {
  PortRouter({this.launcher});

  final WorkerLauncher? launcher;
  final Map<int, _PortState> _ports = {};
  final Map<int, _Endpoint> _endpoints = {};
  final Map<int, int> _workerOwner = {}; // worker id -> endpoint that started it
  final Map<int, int> _workerEndpoint = {}; // worker id -> worker's endpoint
  int _nextPort = 1;
  int _nextEndpoint = 1;
  int _nextWorker = 1;
  bool _disposed = false;

  int addEndpoint({
    required void Function(int port, String wire) deliver,
    required void Function(int worker, Map<String, Object?> event) workerEvent,
  }) {
    final id = _nextEndpoint++;
    _endpoints[id] = _Endpoint(deliver, workerEvent);
    return id;
  }

  /// Updates the callbacks of an endpoint reserved by [launch].
  void connectEndpoint(
    int id, {
    required void Function(int port, String wire) deliver,
    required void Function(int worker, Map<String, Object?> event) workerEvent,
  }) {
    _endpoints[id] = _Endpoint(deliver, workerEvent);
    // Messages that arrived before the worker was ready.
    for (final e in _ports.entries) {
      if (e.value.owner == id) _flush(e.key);
    }
  }

  void removeEndpoint(int id) {
    _endpoints.remove(id);
    for (final p in _ports.values) {
      if (p.owner == id) p.closed = true;
    }
  }

  (int, int) pair(int owner) {
    final a = _nextPort++, b = _nextPort++;
    registerPair(a, b, owner);
    return (a, b);
  }

  /// Registers a pair allocated elsewhere (worker isolates allocate their own
  /// ids so `new MessageChannel()` stays synchronous).
  void registerPair(int a, int b, int owner) {
    _ports[a] = _PortState(b, owner);
    _ports[b] = _PortState(a, owner);
  }

  void post(int port, String wire, List<int> transferred) {
    final from = _ports[port];
    if (from == null || from.closed) return;
    for (final t in transferred) {
      _ports[t]?.owner = null;
    }
    final to = _ports[from.partner];
    if (to == null || to.closed) return;
    to.queue.add(wire);
    _flush(from.partner);
  }

  void adopt(int port, int owner) {
    final p = _ports[port];
    if (p == null) return;
    p.owner = owner;
    _flush(port);
  }

  void close(int port) {
    final p = _ports.remove(port);
    if (p == null) return;
    p.closed = true;
    final partner = _ports[p.partner];
    partner?.closed = true;
    _ports.remove(p.partner);
  }

  void _flush(int port) {
    final p = _ports[port];
    if (p == null || p.queue.isEmpty) return;
    final owner = p.owner;
    final endpoint = owner == null ? null : _endpoints[owner];
    if (endpoint == null) return;
    final messages = List.of(p.queue);
    p.queue.clear();
    for (final m in messages) {
      endpoint.deliver(port, m);
    }
  }

  (int, int) startWorker(int owner, WorkerRequest request) {
    final launcher = this.launcher;
    if (launcher == null) throw UnsupportedError('workers are not available in this runtime');
    final id = _nextWorker++;
    final endpoint = _nextEndpoint++;
    final (pagePort, workerPort) = (_nextPort++, _nextPort++);
    _ports[pagePort] = _PortState(workerPort, owner);
    _ports[workerPort] = _PortState(pagePort, endpoint);
    _workerOwner[id] = owner;
    _workerEndpoint[id] = endpoint;
    launcher.launch(
      router: this,
      endpoint: endpoint,
      workerId: id,
      port: workerPort,
      request: request,
      report: (event) {
        if (_disposed) return;
        final o = _workerOwner[id];
        if (o != null) _endpoints[o]?.workerEvent(id, event);
        if (event['type'] == 'close') _forgetWorker(id);
      },
    );
    return (id, pagePort);
  }

  void terminateWorker(int id) {
    if (!_workerOwner.containsKey(id)) return;
    launcher?.terminate(id);
    _forgetWorker(id);
  }

  void _forgetWorker(int id) {
    _workerOwner.remove(id);
    final endpoint = _workerEndpoint.remove(id);
    if (endpoint != null) removeEndpoint(endpoint);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in List.of(_workerOwner.keys)) {
      launcher?.terminate(id);
    }
    _workerOwner.clear();
    _workerEndpoint.clear();
    _endpoints.clear();
    _ports.clear();
  }
}

/// [NativaXMessaging] for a runtime on the router's own isolate. Deliveries
/// are posted as event-loop tasks, never run inside the sender's call.
class RouterMessaging extends NativaXMessaging {
  RouterMessaging(this.router, {this.ownsRouter = false});

  /// A page runtime with its own router: ports work within the page, and
  /// workers run through [launcher] (none: `new Worker` throws).
  RouterMessaging.local({WorkerLauncher? launcher}) : this(PortRouter(launcher: launcher), ownsRouter: true);

  /// A worker started by [PortRouter.startWorker] on the router's isolate,
  /// using the endpoint the router reserved for it.
  RouterMessaging.forEndpoint(this.router, int endpoint)
      : ownsRouter = false,
        _reserved = endpoint;

  final PortRouter router;
  final bool ownsRouter;
  int? _reserved;
  late int _endpoint;
  bool _attached = false;

  int get endpoint => _endpoint;

  @override
  void attach({
    required void Function(int port, String wire) deliver,
    required void Function(int worker, Map<String, Object?> event) workerEvent,
  }) {
    void d(int port, String wire) => Timer.run(() => deliver(port, wire));
    void w(int worker, Map<String, Object?> event) => Timer.run(() => workerEvent(worker, event));
    final reserved = _reserved;
    if (reserved != null) {
      _endpoint = reserved;
      router.connectEndpoint(reserved, deliver: d, workerEvent: w);
    } else {
      _endpoint = router.addEndpoint(deliver: d, workerEvent: w);
    }
    _attached = true;
  }

  @override
  (int, int) pair() => router.pair(_endpoint);

  @override
  void post(int port, String wire, List<int> ports) => router.post(port, wire, ports);

  @override
  void adopt(int port) => router.adopt(port, _endpoint);

  @override
  void close(int port) => router.close(port);

  @override
  (int, int) startWorker(WorkerRequest request) => router.startWorker(_endpoint, request);

  @override
  void terminateWorker(int id) => router.terminateWorker(id);

  @override
  void dispose() {
    if (_attached) router.removeEndpoint(_endpoint);
    if (ownsRouter) router.dispose();
  }
}
