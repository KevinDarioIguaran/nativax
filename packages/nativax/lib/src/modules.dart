import 'dart:async';
import 'dart:typed_data';

import 'package:nativax_dom_bindings/nativax_dom_bindings.dart';

import 'resources.dart';

/// Whether [a] and [b] share scheme, host and port (`Uri.origin` only
/// supports http(s), and documents use `app://local/`).
bool sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

/// The key a [NativaXResourceLoader] receives for [url]: the path (and query)
/// for the document's own origin, the full URL otherwise.
String resourceKey(Uri url, Uri document) {
  if (!sameOrigin(url, document)) return url.toString();
  return url.hasQuery ? '${url.path}?${url.query}' : url.path;
}

/// The document's module graph, loading sources through a
/// [NativaXResourceLoader].
class DocumentModules extends ModuleGraph {
  DocumentModules({required NativaXResourceLoader resources, required Uri baseUrl, super.onModuleError})
      : super(load: (url) => resources.load(resourceKey(Uri.parse(url), baseUrl)));
}

/// Serves `fetch()`/XHR requests for the document's own origin from the
/// resource loader (so wasm, audio and textures ship with the app), and
/// sends every other request to [network].
class LocalResourceNetwork implements NativaXNetwork {
  LocalResourceNetwork({required this.resources, required this.documentUrl, required this.network});

  final NativaXResourceLoader resources;
  final Uri documentUrl;
  final NativaXNetwork network;

  static const _types = {
    'js': 'text/javascript',
    'mjs': 'text/javascript',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'css': 'text/css',
    'html': 'text/html',
    'txt': 'text/plain',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'ktx2': 'image/ktx2',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'glb': 'model/gltf-binary',
    'gltf': 'model/gltf+json',
    'bin': 'application/octet-stream',
  };

  @override
  Future<NetworkResponse> fetch(NetworkRequest request) async {
    final url = request.url;
    if (!sameOrigin(url, documentUrl)) return network.fetch(request);
    if (request.method != 'GET' && request.method != 'HEAD') {
      return NetworkResponse(status: 405, statusText: 'Method Not Allowed', body: Uint8List(0), url: url);
    }
    final bytes = await resources.loadBytes(resourceKey(url, documentUrl));
    if (bytes == null) {
      return NetworkResponse(status: 404, statusText: 'Not Found', body: Uint8List(0), url: url);
    }
    final ext = url.path.contains('.') ? url.path.split('.').last.toLowerCase() : '';
    return NetworkResponse(
      status: 200,
      statusText: 'OK',
      headers: [
        ('content-type', _types[ext] ?? 'application/octet-stream'),
        ('content-length', '${bytes.length}'),
      ],
      body: bytes,
      url: url,
    );
  }

  @override
  Future<NetworkSocket> connect(Uri url, List<String> protocols) => network.connect(url, protocols);
}
