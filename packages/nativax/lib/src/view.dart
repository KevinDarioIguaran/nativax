import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart' show MemoryStorage, PlatformServices, ThemeModeRequest;
import 'package:nativa_render/nativa_render.dart';

import 'flutter_environment.dart';
import 'runtime.dart';

/// Public NativaX widget: loads a document and renders it with Flutter.
///
/// The runtime is created asynchronously because external stylesheets/scripts
/// may require host-provided resources. Pass a [NativaXResourceLoader] in
/// [config] to allow them; by default all external resources are denied.
class NativaXView extends StatefulWidget {
  const NativaXView({
    super.key,
    required this.source,
    this.config = const NativaXRuntimeConfig(),
    this.imageResolver,
    this.padding = EdgeInsets.zero,
    this.onRuntimeReady,
  });

  final String source;
  final NativaXRuntimeConfig config;
  final NativaXImageResolver? imageResolver;
  final EdgeInsets padding;

  /// Called after a runtime is created, for example to connect a hot-reload
  /// controller or a debug inspector.
  final void Function(NativaXRuntime runtime)? onRuntimeReady;

  @override
  State<NativaXView> createState() => _NativaXViewState();
}

class _NativaXViewState extends State<NativaXView> {
  late final FlutterHostEnvironment _environment;
  NativaXRuntime? _runtime;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _environment = FlutterHostEnvironment(
      // Browsers always provide localStorage; default to memory.
      localStorage: widget.config.storage ?? MemoryStorage(),
      devicePixelRatio: widget.config.devicePixelRatio,
      onThemeMode: _onThemeMode,
    );
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _environment.updateFromContext(context);
    _runtime?.environmentChanged();
  }

  @override
  void didUpdateWidget(covariant NativaXView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _reload();
    }
  }

  @override
  void dispose() {
    _generation++;
    _runtime?.dispose();
    super.dispose();
  }

  void _reload() {
    _runtime?.dispose();
    _runtime = null;
    _error = null;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final runtime = await NativaXRuntime.create(
        source: widget.source,
        config: widget.config,
        environment: _environment,
        platformServices: widget.config.services ?? _defaultServices(),
      );
      if (!mounted || generation != _generation) {
        runtime.dispose();
        return;
      }
      setState(() => _runtime = runtime);
      widget.onRuntimeReady?.call(runtime);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  /// Flutter-backed clipboard and haptics; alerts become snack bars when a
  /// [ScaffoldMessenger] is available.
  PlatformServices _defaultServices() => PlatformServices(
        writeClipboard: (text) => Clipboard.setData(ClipboardData(text: text)),
        readClipboard: () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        vibrate: (pattern) {
          if (pattern.isEmpty || pattern.every((p) => p == 0)) return true;
          HapticFeedback.vibrate();
          return true;
        },
        alert: (message) {
          if (!mounted) return;
          final messenger = ScaffoldMessenger.maybeOf(context);
          if (messenger == null) {
            widget.config.onDiagnostic?.call('alert: $message');
            return;
          }
          messenger.showSnackBar(SnackBar(content: Text(message)));
        },
      );

  bool _onThemeMode(ThemeModeRequest mode) {
    final callback = widget.config.onThemeMode;
    if (callback != null) return callback(mode);
    widget.config.onDiagnostic?.call(
        'script requested theme mode "${mode.name}" but the host did not '
        'provide NativaXRuntimeConfig.onThemeMode');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text('NativaX error: $_error')),
      );
    }
    final runtime = _runtime;
    if (runtime == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return NativaXDocumentView(
      document: runtime.document,
      styleEngine: runtime.styleEngine,
      imageResolver: widget.imageResolver,
      padding: widget.padding,
      onDiagnostic: widget.config.onDiagnostic,
    );
  }
}
