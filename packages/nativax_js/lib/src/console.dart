import 'javascript_engine.dart';

enum ConsoleLevel { log, info, warn, error, debug }

/// One `console.*` call. Arguments are formatted in script code (objects via
/// JSON.stringify, falling back to String()).
class ConsoleMessage {
  const ConsoleMessage(this.level, this.text);
  final ConsoleLevel level;
  final String text;

  @override
  String toString() => '[${level.name}] $text';
}

const String _consolePrelude = r'''
(() => {
  const host = __nx.host;
  const fmt = (v) => {
    if (typeof v === 'string') return v;
    if (v instanceof Error) return `${v.name}: ${v.message}`;
    if (typeof v === 'object' && v !== null) {
      try { return JSON.stringify(v); } catch (_) { return String(v); }
    }
    return String(v);
  };
  const make = (level) => (...args) => {
    host('console', level, args.map(fmt).join(' '));
  };
  globalThis.console = Object.freeze({
    log: make('log'), info: make('info'), warn: make('warn'),
    error: make('error'), debug: make('debug'),
  });
})();
''';

/// Installs `console.log/info/warn/error/debug`, forwarding to [sink].
/// Messages longer than [maxLength] characters are truncated.
void installConsole(
  JavaScriptEngine engine,
  void Function(ConsoleMessage message) sink, {
  int maxLength = 16 * 1024,
}) {
  engine.registerHostFunction('console', (args) {
    final level = ConsoleLevel.values.asNameMap()[args[0]] ?? ConsoleLevel.log;
    var text = args[1] as String? ?? '';
    if (text.length > maxLength) text = '${text.substring(0, maxLength)}…';
    sink(ConsoleMessage(level, text));
    return null;
  });
  engine.evaluate(_consolePrelude, filename: '<nativax:console>');
}
