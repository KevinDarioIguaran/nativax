import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class CdpException implements Exception {
  CdpException(this.message);
  final String message;
  @override
  String toString() => 'CdpException: $message';
}

/// Minimal Chrome DevTools Protocol client used by the performance suite.
///
/// Launches one headless Chrome, creates one tab and drives it through the
/// page WebSocket. No npm package, no puppeteer.
class CdpChrome {
  CdpChrome._(this._process, this._profile, this._socket);

  final Process _process;
  final Directory _profile;
  final WebSocket _socket;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  int _nextId = 1;
  bool _closed = false;

  int get pid => _process.pid;

  static Future<CdpChrome> launch({
    String executable = 'google-chrome',
    int width = 800,
    int height = 900,
    List<String> extraArgs = const [],
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final profile = Directory.systemTemp.createTempSync('nativa-perf-chrome-');
    final process = await Process.start(executable, [
      ...extraArgs,
      '--headless=new',
      if (Platform.environment['NATIVAX_PERF_NO_SANDBOX'] == '1') '--no-sandbox',
      '--disable-gpu',
      '--disable-crash-reporter',
      '--disable-breakpad',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-background-networking',
      '--disable-sync',
      '--disable-extensions',
      '--disable-dev-shm-usage',
      '--host-resolver-rules=MAP * ~NOTFOUND',
      '--user-data-dir=${profile.path}',
      '--remote-debugging-port=0',
      '--window-size=$width,$height',
      'about:blank',
    ]);
    final stderrBuffer = StringBuffer();
    process.stderr.listen((data) => stderrBuffer.write(utf8.decode(data, allowMalformed: true)));
    final portFile = File('${profile.path}/DevToolsActivePort');
    final deadline = DateTime.now().add(timeout);
    while (!portFile.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        process.kill(ProcessSignal.sigkill);
        throw CdpException(
          'Chromium did not open a DevTools port: '
          '${stderrBuffer.toString().split('\n').take(4).join(' | ')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final lines = portFile.readAsLinesSync();
    if (lines.isEmpty) throw CdpException('empty DevToolsActivePort');
    final port = int.parse(lines.first);
    final client = HttpClient();
    Map<String, dynamic>? tab;
    final httpDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (tab == null) {
      if (DateTime.now().isAfter(httpDeadline)) {
        client.close(force: true);
        process.kill(ProcessSignal.sigkill);
        throw CdpException('Chromium did not expose a page target');
      }
      try {
        final request = await client.putUrl(
          Uri.parse('http://127.0.0.1:$port/json/new?about:blank'),
        );
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) tab = decoded;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    client.close(force: true);
    final wsUrl = tab['webSocketDebuggerUrl'] as String?;
    if (wsUrl == null) {
      process.kill(ProcessSignal.sigkill);
      throw CdpException('page target has no webSocketDebuggerUrl');
    }
    final socket = await WebSocket.connect(wsUrl);
    final chrome = CdpChrome._(process, profile, socket);
    socket.listen(
      chrome._onMessage,
      onDone: () => chrome._failPending('DevTools socket closed'),
      onError: (Object error) => chrome._failPending('$error'),
    );
    await chrome.send('Page.enable');
    await chrome.send('Runtime.enable');
    await chrome.send('Performance.enable');
    await chrome.send('Network.enable');
    await chrome.send('Network.setBlockedURLs', {
      'urls': ['http://*', 'https://*'],
    });
    return chrome;
  }

  void _onMessage(dynamic data) {
    final text = data is String ? data : utf8.decode(data as List<int>);
    final message = jsonDecode(text) as Map<String, dynamic>;
    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer != null) {
        if (message['error'] != null) {
          completer.completeError(CdpException('${message['error']}'));
        } else {
          completer.complete(message);
        }
      }
    } else {
      _events.add(message);
    }
  }

  void _failPending(String reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(CdpException(reason));
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) {
    if (_closed) throw CdpException('DevTools session is closed');
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode({
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      }),
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw CdpException('DevTools timeout: $method');
      },
    );
  }

  Future<void> setCpuThrottlingRate(double rate) async {
    if (rate > 1) {
      await send('Emulation.setCPUThrottlingRate', {'rate': rate});
    }
  }

  Future<void> setViewport(int width, int height) async {
    await send('Emulation.setDeviceMetricsOverride', {
      'width': width,
      'height': height,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
  }

  Future<void> navigate(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final loaded = _events.stream
        .firstWhere((event) => event['method'] == 'Page.loadEventFired')
        .timeout(
          timeout,
          onTimeout: () => throw CdpException('page load timeout: $url'),
        );
    final response = await send('Page.navigate', {'url': url});
    if (response['errorText'] != null) {
      throw CdpException('navigation failed: ${response['errorText']}');
    }
    await loaded;
    // Let the first frame settle; scenarios that need more time wait
    // explicitly.
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<dynamic> evaluate(
    String expression, {
    bool awaitPromise = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final response = await send('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': awaitPromise,
      'userGesture': true,
    }, timeout);
    final result = response['result'] as Map<String, dynamic>?;
    if (result == null) throw CdpException('empty evaluate result');
    final exception = result['exceptionDetails'];
    if (exception != null) {
      final text =
          exception['exception']?['description'] ??
          exception['text'] ??
          exception;
      throw CdpException('JS exception: $text');
    }
    final remote = result['result'];
    if (remote is Map<String, dynamic>) return remote['value'];
    return null;
  }

  Future<Map<String, double>> metrics() async {
    final response = await send('Performance.getMetrics');
    final list = (response['result']?['metrics'] as List?) ?? const [];
    return {
      for (final metric in list)
        if (metric is Map)
          metric['name'] as String: (metric['value'] as num).toDouble(),
    };
  }

  Future<String> version() async {
    final response = await send('Browser.getVersion');
    return (response['result']?['product'] as String?) ?? 'Chromium';
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await send('Browser.close', null, const Duration(seconds: 2));
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    await _events.close();
    _process.kill(ProcessSignal.sigkill);
    try {
      _profile.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Deterministic pseudo-random generator so page fixtures are reproducible.
List<double> seededValues(int count, {int seed = 1}) {
  final random = Random(seed);
  return [for (var i = 0; i < count; i++) random.nextDouble()];
}
