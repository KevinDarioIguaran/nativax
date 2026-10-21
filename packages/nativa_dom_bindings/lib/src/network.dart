import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// An HTTP request issued by `fetch()` or `XMLHttpRequest`.
class NetworkRequest {
  const NetworkRequest({
    required this.url,
    this.method = 'GET',
    this.headers = const [],
    this.body,
    this.timeout,
  });

  final Uri url;
  final String method;
  final List<(String, String)> headers;
  final Uint8List? body;
  final Duration? timeout;
}

class NetworkResponse {
  const NetworkResponse({
    required this.status,
    this.statusText = '',
    this.headers = const [],
    required this.body,
    required this.url,
    this.redirected = false,
  });

  final int status;
  final String statusText;
  final List<(String, String)> headers;
  final Uint8List body;
  final Uri url;
  final bool redirected;
}

/// A connected WebSocket. Incoming messages are [String] or [Uint8List].
abstract interface class NetworkSocket {
  Stream<Object> get messages;
  String get protocol;
  void send(Object data);
  Future<void> close([int? code, String? reason]);
  int? get closeCode;
  String? get closeReason;
}

/// Network access for scripts. NativaX never touches the network on its
/// own: the embedder passes an implementation that decides what is allowed.
abstract interface class NativaXNetwork {
  /// Throws [NetworkDenied] for requests the policy rejects.
  Future<NetworkResponse> fetch(NetworkRequest request);

  Future<NetworkSocket> connect(Uri url, List<String> protocols);
}

class NetworkDenied implements Exception {
  const NetworkDenied(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The default: every request fails as if offline.
class DeniedNetwork implements NativaXNetwork {
  const DeniedNetwork();

  @override
  Future<NetworkResponse> fetch(NetworkRequest request) =>
      Future.error(const NetworkDenied('network access is disabled for this document'));

  @override
  Future<NetworkSocket> connect(Uri url, List<String> protocols) =>
      Future.error(const NetworkDenied('network access is disabled for this document'));
}

/// `dart:io` networking restricted by [allow] (for example an origin
/// allowlist). Requests [allow] rejects fail like blocked requests.
class IoNetwork implements NativaXNetwork {
  IoNetwork({required this.allow, this.userAgent = 'NativaX/0.1', this.maxResponseBytes = 32 * 1024 * 1024});

  final bool Function(Uri url) allow;
  final String userAgent;
  final int maxResponseBytes;
  final HttpClient _client = HttpClient();

  @override
  Future<NetworkResponse> fetch(NetworkRequest request) async {
    final url = request.url;
    if (!(url.isScheme('http') || url.isScheme('https')) || !allow(url)) {
      throw NetworkDenied('request to ${url.origin} blocked by policy');
    }
    Future<NetworkResponse> run() async {
      final req = await _client.openUrl(request.method, url);
      req.followRedirects = true;
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
      for (final (k, v) in request.headers) {
        req.headers.add(k, v);
      }
      final body = request.body;
      if (body != null) req.add(body);
      final res = await req.close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) throw const NetworkDenied('response too large');
      }
      final headers = <(String, String)>[];
      res.headers.forEach((name, values) {
        for (final v in values) {
          headers.add((name, v));
        }
      });
      final finalUrl = res.redirects.isEmpty ? url : url.resolveUri(res.redirects.last.location);
      return NetworkResponse(
        status: res.statusCode,
        statusText: res.reasonPhrase,
        headers: headers,
        body: builder.takeBytes(),
        url: finalUrl,
        redirected: res.redirects.isNotEmpty,
      );
    }

    final t = request.timeout;
    return t == null ? run() : run().timeout(t);
  }

  @override
  Future<NetworkSocket> connect(Uri url, List<String> protocols) async {
    if (!(url.isScheme('ws') || url.isScheme('wss')) || !allow(url)) {
      throw NetworkDenied('connection to ${url.origin} blocked by policy');
    }
    final ws = await WebSocket.connect(url.toString(), protocols: protocols.isEmpty ? null : protocols);
    return _IoSocket(ws);
  }

  void close() => _client.close(force: true);
}

class _IoSocket implements NetworkSocket {
  _IoSocket(this._ws);
  final WebSocket _ws;

  @override
  Stream<Object> get messages => _ws.map((m) => m is List<int> ? Uint8List.fromList(m) : m as Object);

  @override
  String get protocol => _ws.protocol ?? '';

  @override
  void send(Object data) => _ws.add(data);

  @override
  Future<void> close([int? code, String? reason]) => _ws.close(code, reason);

  @override
  int? get closeCode => _ws.closeCode;

  @override
  String? get closeReason => _ws.closeReason;
}

/// Platform services behind `navigator.clipboard`, `navigator.vibrate`,
/// `alert()` and friends. Every member is optional: the defaults report the
/// feature as unavailable.
class PlatformServices {
  const PlatformServices({this.writeClipboard, this.readClipboard, this.vibrate, this.alert, this.openUrl});

  final Future<void> Function(String text)? writeClipboard;
  final Future<String?> Function()? readClipboard;
  final bool Function(List<int> pattern)? vibrate;

  /// Shows a message (`alert`). Script execution does not block.
  final void Function(String message)? alert;

  /// Navigation to another document (`location.href = ...`, links).
  final void Function(Uri url)? openUrl;
}

String base64Bytes(Uint8List bytes) => base64Encode(bytes);
Uint8List bytesFromBase64(String s) => base64Decode(s);
