import 'dart:io';
import 'dart:math';

/// Deterministic generator for renderer benchmarks.
///
/// The output is a complete HTML document. Node counts are approximate for the
/// requested target; the exact count is written in a comment and can be checked
/// by parsing the document.
class RenderFixtureGenerator {
  RenderFixtureGenerator(this.family, {required this.nodes, this.seed = 20261023})
      : _rnd = Random(seed);

  final String family;
  final int nodes;
  final int seed;
  final Random _rnd;

  String _pick(List<String> values) => values[_rnd.nextInt(values.length)];

  String _paragraph() {
    const words = [
      'sistema', 'arquitectura', 'servicio', 'datos', 'red', 'cliente',
      'protocolo', 'cola', 'indice', 'sesion', 'evento', 'flujo',
    ];
    // 23k fixtures need to stay inside the default 4 MiB HTML input limit.
    // This is text volume, not a renderer shortcut; node counts are unchanged.
    final short = nodes >= 20000;
    final count = (short ? 4 : 12) + _rnd.nextInt(short ? 5 : 18);
    return List.generate(count, (_) => _pick(words)).join(' ') + '.';
  }

  String generate() {
    _count = 0;
    final buffer = StringBuffer(_head(_title()));
    switch (family) {
      case 'list-overflow':
        _listOverflow(buffer);
      case 'flex-grid':
        _flexGrid(buffer);
      case 'article':
        _article(buffer);
      case 'table':
        _table(buffer);
      case 'app-shell':
        _appShell(buffer);
      default:
        throw ArgumentError('unknown family: $family');
    }
    final current = RegExp(r'<[A-Za-z]').allMatches(buffer.toString()).length;
    final filler = nodes - current;
    if (filler > 0) {
      buffer.write('<div id="filler">');
      for (var i = 0; i < filler; i++) {
        buffer.write('<span></span>');
      }
      buffer.write('</div>');
    }
    final total = RegExp(r'<[A-Za-z]').allMatches(buffer.toString()).length;
    buffer.write('<!-- nodes=$total -->\n</body></html>\n');
    return buffer.toString();
  }

  int _count = 0;

  String _title() => switch (family) {
        'list-overflow' => 'Lista con overflow',
        'flex-grid' => 'Flex y grid',
        'article' => 'Artículo largo',
        'table' => 'Tabla grande',
        'app-shell' => 'App estilo Biblia',
        _ => family,
      };

  String _head(String title) => '''
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
* { box-sizing: border-box; }
body { margin: 0; font: 16px/1.6 system-ui, sans-serif; background: #f4f4f6; color: #1f2430; }
.app { display: grid; grid-template-columns: 240px 1fr; min-height: 100vh; }
.sidebar { background: #fff; border-right: 1px solid #d8dde6; padding: 12px; overflow-y: auto; }
.content { padding: 24px; }
.list { display: block; }
.row { padding: 10px 12px; border-bottom: 1px solid #e7eaf0; }
.card { border: 1px solid #d8dde6; border-radius: 8px; padding: 12px; background: #fff; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
.flexrow { display: flex; gap: 12px; align-items: center; }
.article p { margin: 0 0 1em; text-align: justify; }
table { border-collapse: collapse; width: 100%; }
td, th { border: 1px solid #d8dde6; padding: 6px 8px; }
img { max-width: 100%; height: auto; }
</style>
</head>
<body>
''';

  void _listOverflow(StringBuffer buffer) {
    buffer.write('<div class="app"><aside class="sidebar"><div id="list" class="list">');
    while (_count < nodes) {
      buffer.write('<div class="row">Fila ${_count + 1}: ${_paragraph()}</div>');
      _count++;
    }
    buffer.write('</div></aside><main class="content"><h1>Lista</h1>'
        '<p>Contenedor con scroll interno y $_count filas.</p></main></div>');
  }

  void _flexGrid(StringBuffer buffer) {
    buffer.write('<main class="content"><h1>Tarjetas</h1><div class="grid">');
    while (_count < nodes) {
      buffer.write('<article class="card"><h2>Tarjeta ${_count ~/ 4}</h2>'
          '<p>${_paragraph()}</p><div class="flexrow"><span>A</span><span>B</span><span>C</span></div></article>');
      _count += 4;
    }
    buffer.write('</div></main>');
  }

  void _article(StringBuffer buffer) {
    buffer.write('<main class="content" id="doc"><h1>Informe</h1>');
    while (_count < nodes) {
      buffer.write('<p>${_paragraph()}</p>');
      _count++;
    }
    buffer.write('</main>');
  }

  void _table(StringBuffer buffer) {
    buffer.write('<main class="content"><table><thead><tr><th>A</th><th>B</th><th>C</th></tr></thead><tbody>');
    while (_count < nodes) {
      buffer.write('<tr><td>${_paragraph()}</td><td>${_rnd.nextInt(1000)}</td>'
          '<td><img alt="x" src="data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 width=%2716%27 height=%2716%27%3E%3Crect width=%2716%27 height=%2716%27 fill=%27%23ddd%27/%3E%3C/svg%3E"></td></tr>');
      _count += 4;
    }
    buffer.write('</tbody></table></main>');
  }

  void _appShell(StringBuffer buffer) {
    buffer.write('<div class="app"><aside class="sidebar"><div id="list" class="list">');
    while (_count < nodes ~/ 3) {
      buffer.write('<div class="row">Libro ${_count + 1}: ${_paragraph()}</div>');
      _count++;
    }
    buffer.write('</div></aside><main class="content" id="doc">');
    buffer.write('<h1>Documento</h1>');
    while (_count < nodes) {
      buffer.write('<p class="verse">Versículo ${_count + 1}: ${_paragraph()}</p>');
      _count++;
    }
    buffer.write('</main></div>');
  }
}

void writeFixture(String family, int nodes, String outPath) {
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
      RenderFixtureGenerator(family, nodes: nodes).generate());
}
