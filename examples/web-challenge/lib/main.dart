import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nativax/nativax.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;

void main() => runApp(const WebChallengeApp());

/// Loads the demo from Flutter assets. NativaX never fetches external files
/// on its own: this loader is the only bridge between `<link>`/`<script src>`
/// and the host's asset bundle.
class _AssetLoader extends NativaXResourceLoader {
  const _AssetLoader();

  @override
  Future<String?> load(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) return null;
    var path = url.split('?').first.split('#').first;
    if (path.startsWith('/')) path = path.substring(1);
    if (!path.startsWith('assets/')) path = 'assets/$path';
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      return null;
    }
  }
}

/// Test hook used by `tools/perf` for app-level idle measurements. When
/// NATIVAX_PERF_PAGE points to a directory, the app loads that page and its
/// relative files instead of the bundled demo. It is inactive by default.
class _FileLoader extends NativaXResourceLoader {
  const _FileLoader(this.dir);
  final String dir;

  @override
  Future<String?> load(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) return null;
    var path = url.split('?').first.split('#').first;
    if (path.startsWith('/')) path = path.substring(1);
    final file = File('$dir/$path');
    return file.existsSync() ? file.readAsStringSync() : null;
  }
}

/// The demo probes these services; every other host stays blocked.
const _allowedHosts = {
  'jsonplaceholder.typicode.com',
  'ws.postman-echo.com',
  'picsum.photos',
  'fastly.picsum.photos',
  'interactive-examples.mdn.mozilla.net',
};

bool _allowed(Uri url) => _allowedHosts.contains(url.host);

final _network = IoNetwork(allow: _allowed);

ImageProvider? _images(dom.Element element, String src) {
  final url = Uri.tryParse(src);
  if (url == null || !url.isScheme('https') || !_allowed(url)) return null;
  return NetworkImage(src);
}

class WebChallengeApp extends StatelessWidget {
  const WebChallengeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NativaX Web Challenge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xff0b5fd6)),
      home: Scaffold(
        body: SafeArea(
          child: FutureBuilder<String>(
            future: Platform.environment['NATIVAX_PERF_PAGE'] == null
                ? rootBundle.loadString('assets/index.html')
                : Future<String>.value(
                    File(
                      '${Platform.environment['NATIVAX_PERF_PAGE']}/index.html',
                    ).readAsStringSync(),
                  ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'No se pudo cargar el ejemplo: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return NativaXView(
                source: snapshot.data!,
                padding: EdgeInsets.zero,
                imageResolver: _images,
                config: NativaXRuntimeConfig(
                  resources: Platform.environment['NATIVAX_PERF_PAGE'] == null
                      ? const _AssetLoader()
                      : _FileLoader(Platform.environment['NATIVAX_PERF_PAGE']!),
                  documentUrl: 'app://web-challenge/index.html',
                  network: _network,
                ),
                onRuntimeReady: (runtime) {
                  // The page itself reports unsupported browser APIs; this
                  // hook is useful when running with a debugger.
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
