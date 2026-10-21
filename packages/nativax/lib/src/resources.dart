import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the document's own resources: `<script src>`, module imports,
/// `<link rel="stylesheet">` and same-origin `fetch()` (wasm, audio, images).
/// NativaX never fetches anything by itself: the host decides what exists.
///
/// [url] is the request path for same-origin resources (for example
/// `/assets/app.js`, query and fragment included) or the absolute URL for any
/// other origin, which loaders normally deny by returning null.
abstract class NativaXResourceLoader {
  const NativaXResourceLoader();

  Future<String?> load(String url);

  /// Binary contents. The default decodes nothing: it UTF-8 encodes [load];
  /// loaders backed by files or asset bundles override it.
  Future<Uint8List?> loadBytes(String url) async {
    final text = await load(url);
    return text == null ? null : utf8.encode(text);
  }
}

class NativaXDenyAllResources extends NativaXResourceLoader {
  const NativaXDenyAllResources();

  @override
  Future<String?> load(String url) async => null;

  @override
  Future<Uint8List?> loadBytes(String url) async => null;
}

/// The path of a same-origin request inside a resource root, or null when it
/// is cross-origin or tries to leave the root.
String? _relativePath(String url) {
  if (url.contains('://') || url.startsWith('//')) return null;
  var path = url.split('?').first.split('#').first;
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  path = Uri.decodeFull(path);
  if (path.isEmpty) return null;
  final parts = path.split('/');
  if (parts.any((p) => p == '..')) return null;
  return path;
}

/// Serves resources from a Flutter asset directory ([root], `assets/www/` by
/// default). List every subdirectory under `flutter: assets:` in pubspec.
class NativaXAssetLoader extends NativaXResourceLoader {
  NativaXAssetLoader({this.root = 'assets/www/', AssetBundle? bundle}) : _bundle = bundle;

  final String root;
  final AssetBundle? _bundle;

  AssetBundle get bundle => _bundle ?? rootBundle;

  String? _key(String url) {
    final path = _relativePath(url);
    if (path == null) return null;
    return path.startsWith(root) ? path : '$root$path';
  }

  @override
  Future<String?> load(String url) async {
    final bytes = await loadBytes(url);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    final key = _key(url);
    if (key == null) return null;
    try {
      final data = await bundle.load(key);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }
}

/// Serves resources from a directory on disk (desktop development, or
/// content downloaded by the app). Paths cannot escape [directory].
class NativaXDirectoryLoader extends NativaXResourceLoader {
  NativaXDirectoryLoader(this.directory);

  final String directory;

  File? _file(String url) {
    final path = _relativePath(url);
    if (path == null) return null;
    return File('$directory/$path');
  }

  @override
  Future<String?> load(String url) async {
    final bytes = await loadBytes(url);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<Uint8List?> loadBytes(String url) async {
    final f = _file(url);
    if (f == null) return null;
    try {
      return await f.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }
}
