import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nativax_css/nativax_css.dart' hide MediaQuery;
import 'package:nativax_dom_bindings/nativax_dom_bindings.dart';

/// [HostEnvironment] backed by the current Flutter context.
///
/// The fields are mutable so the same object can be updated when the viewport,
/// theme or locale changes without rebuilding the JavaScript environment.
class FlutterHostEnvironment implements HostEnvironment {
  FlutterHostEnvironment({
    this.media = const MediaContext(width: 800, height: 600),
    this.languages = const ['en-US'],
    this.theme = const ThemeSnapshot(brightness: 'light'),
    this.platform = 'linux',
    this.devicePixelRatio,
    this.localStorage,
    this.onThemeMode,
  });

  @override
  MediaContext media;

  /// Overrides the Flutter [MediaQuery] ratio exposed to scripts.
  final double? devicePixelRatio;

  @override
  List<String> languages;

  @override
  ThemeSnapshot theme;

  @override
  String platform;

  @override
  KeyValueStorage? localStorage;

  /// Called when a script invokes `nativax.theme.setMode(...)`.
  bool Function(ThemeModeRequest mode)? onThemeMode;

  @override
  bool requestThemeMode(ThemeModeRequest mode) => onThemeMode?.call(mode) ?? false;

  /// Reads MediaQuery, Theme and locale from [context].
  void updateFromContext(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq != null) {
      media = MediaContext(
        width: mq.size.width,
        height: mq.size.height,
        devicePixelRatio: devicePixelRatio ?? mq.devicePixelRatio,
        prefersDark: mq.platformBrightness == Brightness.dark,
        prefersReducedMotion: mq.disableAnimations,
      );
    }

    final themeData = Theme.of(context);
    final scheme = themeData.colorScheme;
    final brightness = themeData.brightness;
    theme = ThemeSnapshot(
      brightness: brightness == Brightness.dark ? 'dark' : 'light',
      colors: {
        'primary': _hex(scheme.primary),
        'onPrimary': _hex(scheme.onPrimary),
        'secondary': _hex(scheme.secondary),
        'onSecondary': _hex(scheme.onSecondary),
        'surface': _hex(scheme.surface),
        'onSurface': _hex(scheme.onSurface),
        'error': _hex(scheme.error),
        'onError': _hex(scheme.onError),
      },
    );

    final current = Localizations.maybeLocaleOf(context);
    final locales = <String>{
      if (current != null) current.toLanguageTag(),
      for (final locale in PlatformDispatcher.instance.locales)
        locale.toLanguageTag(),
    };
    languages = locales.isEmpty ? const ['en-US'] : locales.toList();

    platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static String _hex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    final a = (color.a * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b$a';
  }
}
