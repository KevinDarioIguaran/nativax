import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:nativax/nativax.dart';

import 'metrics_overlay.dart';

void main() => runApp(const GamePlayerApp());

/// Self-contained desktop shell for the production Vite bundle in
/// `assets/game/`. The web sources themselves are not modified: NativaX loads
/// `index.html`, its scripts, workers and media through the asset loader.
class GamePlayerApp extends StatefulWidget {
  const GamePlayerApp({super.key});

  static final _resources = NativaXAssetLoader(root: 'assets/game/');

  /// Loads the unmodified production bundle. The optional host override is a
  /// performance experiment: it does not edit the game's sources or assets, it
  /// only asks NativaX to skip the expensive live-backdrop blur.
  static Future<String?> _loadSource() async {
    var source = await _resources.load('index.html');
    if (source == null) return null;
    if (Platform.environment['NATIVAX_NO_BACKDROP'] == '1') {
      source = source.replaceFirst(
        '</head>',
        '<style id="nativax-host-perf">'
            '*,*::before,*::after{backdrop-filter:none!important;'
            '-webkit-backdrop-filter:none!important;}'
            '</style></head>',
      );
    }
    return source;
  }

  /// Internal canvas scale. The Flutter window keeps its native resolution;
  /// only the WebGL drawing buffer is reduced before the CPU readback.
  static double get renderScale {
    final parsed = double.tryParse(
      Platform.environment['NATIVAX_GAME_DPR'] ?? '',
    );
    if (parsed == null || parsed < 0.5 || parsed > 2) return 1;
    return parsed;
  }

  @override
  State<GamePlayerApp> createState() => _GamePlayerAppState();
}

class _GamePlayerAppState extends State<GamePlayerApp> {
  NativaXRuntime? _runtime;
  Timer? _autostart;
  late final Future<String?> _sourceFuture;

  /// Metrics are opt-in. A metrics file implies the overlay because every
  /// benchmark run needs a visible sanity check, but normal play stays clean.
  static bool get _metricsEnabled =>
      Platform.environment['NATIVAX_METRICS'] == '1' ||
      (Platform.environment['NATIVAX_METRICS_FILE']?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _sourceFuture = GamePlayerApp._loadSource();
  }

  @override
  void dispose() {
    _autostart?.cancel();
    super.dispose();
  }

  /// Test/automation hook. Dispatches a real DOM click from the host instead
  /// of calling into the JavaScript engine from a timer, which is not safe
  /// while a script is executing.
  void _maybeAutostart(NativaXRuntime runtime) {
    if (Platform.environment['NATIVAX_AUTOSTART'] != '1') return;
    _autostart?.cancel();
    _autostart = Timer.periodic(const Duration(seconds: 1), (timer) {
      final button = runtime.document.querySelector('button.start-button');
      if (button == null || !button.classList.contains('visible')) return;
      timer.cancel();
      button.click(trusted: true);
      debugPrint('autostart: dispatched DOM click');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Three.js Multiplayer Starter — NativaX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: FutureBuilder<String?>(
          future: _sourceFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorView('No se pudo leer el bundle: ${snapshot.error}');
            }
            final source = snapshot.data;
            if (source == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Stack(
              children: [
                NativaXView(
                  source: source,
                  padding: EdgeInsets.zero,
                  config: NativaXRuntimeConfig(
                    engineFactory: Platform.environment['NATIVAX_ENGINE'] == 'v8'
                        ? V8Engine.new
                        : null,
                    engine: const JavaScriptEngineConfig(
                      memoryLimitBytes: 512 << 20,
                      executionBudget: Duration(seconds: 30),
                      maxJobsPerDrain: 1000000,
                    ),
                    resources: GamePlayerApp._resources,
                    documentUrl: 'app://game/index.html',
                    devicePixelRatio: GamePlayerApp.renderScale,
                    onScriptError: (error) =>
                        debugPrint('NativaX script error: $error'),
                    onConsole: (message) =>
                        debugPrint('${message.level.name}: ${message.text}'),
                    onDiagnostic: (message) => debugPrint('diag: $message'),
                  ),
                  onRuntimeReady: (runtime) {
                    if (mounted) setState(() => _runtime = runtime);
                    _maybeAutostart(runtime);
                  },
                ),
                if (_runtime != null && _metricsEnabled)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: IgnorePointer(
                      child: MetricsOverlay(runtime: _runtime!),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
