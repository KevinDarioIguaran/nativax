import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nativa_render/nativa_render.dart' show NativaXImageResolver;
import 'package:path/path.dart' as p;

import 'runtime.dart';
import 'view.dart';

/// Listens for file changes and asks a [NativaXHotReloadView] to reload.
///
/// The controller is optional: the view can reload by itself. It is useful to
/// trigger reloads from a button, a test, or an external dev server.
class NativaXHotReloadController extends ChangeNotifier {
  NativaXHotReloadController();

  int _revision = 0;
  bool _reloading = false;
  Object? _lastError;

  int get revision => _revision;
  bool get isReloading => _reloading;
  Object? get lastError => _lastError;

  /// Requests a reload from disk. The view performs the actual read.
  Future<void> reload() async {
    if (_reloading) return;
    _reloading = true;
    _lastError = null;
    _revision++;
    notifyListeners();
  }

  void reportDone() {
    if (!_reloading) return;
    _reloading = false;
    notifyListeners();
  }

  void reportError(Object error) {
    _lastError = error;
    _reloading = false;
    notifyListeners();
  }
}

/// Development-only view that reads an HTML file and reloads it when the file
/// changes.
///
/// This is a **document hot reload**: HTML, CSS and JavaScript are re-parsed
/// and the runtime is recreated. It is intentionally not a state-preserving
/// hot patch of a running JavaScript realm (that would require serializing
/// arbitrary script state). Use [onBeforeReload]/[onAfterReload] to persist and
/// restore application state yourself.
class NativaXHotReloadView extends StatefulWidget {
  const NativaXHotReloadView({
    super.key,
    required this.sourcePath,
    this.config = const NativaXRuntimeConfig(),
    this.imageResolver,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.debounce = const Duration(milliseconds: 80),
    this.onBeforeReload,
    this.onAfterReload,
    this.onError,
  });

  final String sourcePath;
  final NativaXRuntimeConfig config;
  final NativaXImageResolver? imageResolver;
  final EdgeInsets padding;
  final NativaXHotReloadController? controller;
  final Duration debounce;
  final void Function(String source)? onBeforeReload;
  final void Function(NativaXRuntime runtime)? onAfterReload;
  final void Function(Object error)? onError;

  @override
  State<NativaXHotReloadView> createState() => _NativaXHotReloadViewState();
}

class _NativaXHotReloadViewState extends State<NativaXHotReloadView> {
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;
  String? _source;
  Object? _error;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onController);
    _read();
    _startWatching();
  }

  @override
  void didUpdateWidget(covariant NativaXHotReloadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourcePath != widget.sourcePath) {
      _stopWatching();
      _startWatching();
      _read();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _stopWatching();
    _debounce?.cancel();
    super.dispose();
  }

  void _onController() => _read();

  void _startWatching() {
    final file = File(widget.sourcePath);
    final directory = file.parent;
    try {
      _watch = directory
          .watch(events: FileSystemEvent.all)
          .listen((event) {
        if (p.basename(event.path) != p.basename(file.path)) return;
        _debounce?.cancel();
        _debounce = Timer(widget.debounce, _read);
      });
    } on FileSystemException catch (error) {
      // Watching is best-effort (for example on a platform without inotify).
      widget.onError?.call(error);
    }
  }

  void _stopWatching() {
    _watch?.cancel();
    _watch = null;
  }

  void _read() {
    try {
      // Dev-only file read: synchronous so editors cannot interleave a partial
      // write between the change event and the next frame.
      final source = File(widget.sourcePath).readAsStringSync();
      if (!mounted) return;
      widget.onBeforeReload?.call(source);
      setState(() {
        _source = source;
        _error = null;
        _revision++;
      });
      widget.controller?.reportDone();
    } catch (error) {
      if (!mounted) return;
      widget.onError?.call(error);
      widget.controller?.reportError(error);
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_source == null) {
      if (_error != null) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Text('NativaX hot reload: $_error'),
          ),
        );
      }
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return NativaXView(
      key: ValueKey(_revision),
      source: _source!,
      config: widget.config,
      imageResolver: widget.imageResolver,
      padding: widget.padding,
      onRuntimeReady: widget.onAfterReload,
    );
  }
}
