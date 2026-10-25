import 'dart:io';

/// Stylesheet shared by the reference and NativaX. Animated pages otherwise
/// produce screenshot noise that is unrelated to conversion fidelity.
/// The judge reports `frozen-animations` in the environment section.
const String freezeCss = '''
*, *::before, *::after {
  animation: none !important;
  transition: none !important;
  scroll-behavior: auto !important;
  caret-color: transparent !important;
}
''';

/// Script shared by the reference and NativaX: modal dialogs return at once
/// instead of blocking headless Chrome until the judge's timeout.
const String dialogsScript = '''
window.alert = function () {};
window.confirm = function () { return false; };
window.prompt = function () { return null; };
''';

/// Copies a fixture page into a private working directory.
Directory stagePage(String sourceDirectory, Directory target, {String? entry}) {
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  _copyContents(Directory(sourceDirectory), target);
  final index = File('${target.path}/index.html');
  if (!index.existsSync()) {
    final html = entry ?? _singleHtml(sourceDirectory);
    if (html == null) {
      throw StateError('no index.html in $sourceDirectory');
    }
    File(html).copySync(index.path);
  }
  injectHead(index, '<style id="__visual_freeze">$freezeCss</style>');
  injectHeadStart(index, '<script id="__visual_dialogs">$dialogsScript</script>');
  return target;
}

String? _singleHtml(String sourceDirectory) {
  final html = Directory(sourceDirectory)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.html'))
      .toList();
  return html.length == 1 ? html.first.path : null;
}

void _copyContents(Directory source, Directory target) {
  for (final entity in source.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == '.git' || name == 'node_modules' || name == '.nativa-suite')
      continue;
    if (entity is File) {
      entity.copySync('${target.path}/$name');
    } else if (entity is Directory) {
      final child = Directory('${target.path}/$name')..createSync();
      _copyContents(entity, child);
    } else if (entity is Link) {
      final resolved = entity.resolveSymbolicLinksSync();
      final file = File(resolved);
      if (file.existsSync()) {
        file.copySync('${target.path}/$name');
      }
    }
  }
}

/// Inserts [snippet] right after `<head>` so it runs before page scripts,
/// falling back to [injectHead].
void injectHeadStart(File index, String snippet) {
  final text = index.readAsStringSync();
  final head = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false).firstMatch(text);
  if (head == null) {
    injectHead(index, snippet);
    return;
  }
  index.writeAsStringSync(
    '${text.substring(0, head.end)}$snippet${text.substring(head.end)}',
  );
}

/// Inserts [snippet] right before `</head>` so `<meta charset>` keeps its
/// position, falling back to the start of the document.
void injectHead(File index, String snippet) {
  var text = index.readAsStringSync();
  final headClose = text.toLowerCase().lastIndexOf('</head>');
  if (headClose >= 0) {
    text =
        '${text.substring(0, headClose)}$snippet${text.substring(headClose)}';
  } else {
    final html = RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(text);
    if (html != null) {
      text =
          '${text.substring(0, html.end)}$snippet${text.substring(html.end)}';
    } else {
      text = '$snippet$text';
    }
  }
  index.writeAsStringSync(text);
}

/// Inserts [snippet] before the last `</body>`.
void injectBody(File index, String snippet) {
  final text = index.readAsStringSync();
  final close = text.toLowerCase().lastIndexOf('</body>');
  final updated = close < 0
      ? '$text$snippet'
      : '${text.substring(0, close)}$snippet${text.substring(close)}';
  index.writeAsStringSync(updated);
}

/// Injects a line into the `<body>` so it is visible to the page.
void injectBodyMarker(File index, String markerId) {
  injectBody(
    index,
    '<div id="$markerId" data-nativa-visual="1" style="display:none"></div>',
  );
}
