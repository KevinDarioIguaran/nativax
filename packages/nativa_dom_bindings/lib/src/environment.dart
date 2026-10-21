import 'package:nativa_css/nativa_css.dart';

/// Theme information exposed to scripts as `nativax.theme`. Colors are CSS
/// hex strings (`#rrggbbaa`) so they can be used directly in styles.
class ThemeSnapshot {
  const ThemeSnapshot({required this.brightness, this.colors = const {}});
  final String brightness; // 'light' | 'dark'
  final Map<String, String> colors;

  Map<String, Object?> toJson() => {'brightness': brightness, 'colors': colors};

  @override
  bool operator ==(Object o) =>
      o is ThemeSnapshot &&
      o.brightness == brightness &&
      o.colors.length == colors.length &&
      o.colors.entries.every((e) => colors[e.key] == e.value);

  @override
  int get hashCode => Object.hash(brightness, Object.hashAllUnordered(colors.entries.map((e) => '${e.key}=${e.value}')));
}

/// Theme modes a script may request through `nativax.theme.setMode()`.
enum ThemeModeRequest { light, dark, system }

/// Synchronous key-value storage behind `localStorage`.
abstract interface class KeyValueStorage {
  String? getItem(String key);
  void setItem(String key, String value);
  void removeItem(String key);
  void clear();
  List<String> keys();
}

/// In-memory storage with a size quota (characters of keys plus values).
class MemoryStorage implements KeyValueStorage {
  MemoryStorage({this.quota = 5 * 1024 * 1024});
  final int quota;
  final Map<String, String> _data = {};
  int _size = 0;

  /// Called after every change (for persistence).
  void Function(Map<String, String> data)? onChanged;

  Map<String, String> get data => Map.unmodifiable(_data);

  void load(Map<String, String> data) {
    _data
      ..clear()
      ..addAll(data);
    _size = _data.entries.fold(0, (s, e) => s + e.key.length + e.value.length);
  }

  @override
  String? getItem(String key) => _data[key];

  @override
  void setItem(String key, String value) {
    final old = _data[key];
    final delta = (old == null ? key.length : -old.length) + value.length;
    if (_size + delta > quota) {
      throw StorageQuotaExceeded();
    }
    _data[key] = value;
    _size += delta;
    onChanged?.call(_data);
  }

  @override
  void removeItem(String key) {
    final old = _data.remove(key);
    if (old != null) {
      _size -= key.length + old.length;
      onChanged?.call(_data);
    }
  }

  @override
  void clear() {
    _data.clear();
    _size = 0;
    onChanged?.call(_data);
  }

  @override
  List<String> keys() => _data.keys.toList();
}

class StorageQuotaExceeded implements Exception {}

/// Everything the browser-style APIs need from the embedding platform. The
/// Flutter layer implements this from `MediaQuery`, `Theme`, the platform
/// locale and the view's constraints; tests use [StaticEnvironment].
abstract interface class HostEnvironment {
  MediaContext get media;

  /// BCP 47 tags, most preferred first (`navigator.languages`).
  List<String> get languages;

  ThemeSnapshot get theme;

  /// `android`, `ios`, `linux`, `windows`, `macos`, `fuchsia` or `unknown`.
  String get platform;

  /// Storage for `localStorage`, or null to leave it undefined.
  KeyValueStorage? get localStorage;

  /// Applies a theme mode requested by script. Returns false if the
  /// embedder does not allow scripts to change the theme.
  bool requestThemeMode(ThemeModeRequest mode);
}

class StaticEnvironment implements HostEnvironment {
  StaticEnvironment({
    this.media = const MediaContext(width: 800, height: 600),
    this.languages = const ['en-US'],
    this.theme = const ThemeSnapshot(brightness: 'light'),
    this.platform = 'unknown',
    this.localStorage,
  });

  @override
  MediaContext media;
  @override
  List<String> languages;
  @override
  ThemeSnapshot theme;
  @override
  String platform;
  @override
  KeyValueStorage? localStorage;

  final List<ThemeModeRequest> themeRequests = [];

  @override
  bool requestThemeMode(ThemeModeRequest mode) {
    themeRequests.add(mode);
    return true;
  }
}
