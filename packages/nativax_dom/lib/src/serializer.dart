import 'element.dart';
import 'node.dart';

/// Elements whose text children are serialized without escaping.
const Set<String> rawTextElements = {'script', 'style'};

String escapeText(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String escapeAttribute(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

String serializeNode(Node node) {
  final buf = StringBuffer();
  _write(node, buf);
  return buf.toString();
}

String serializeChildren(Node node) {
  final buf = StringBuffer();
  for (final c in node.rawChildren) {
    _write(c, buf);
  }
  return buf.toString();
}

void _write(Node node, StringBuffer buf) {
  switch (node) {
    case Element e:
      buf.write('<${e.localName}');
      e.attributes.forEach((k, v) => buf.write(' $k="${escapeAttribute(v)}"'));
      buf.write('>');
      if (voidElements.contains(e.localName)) return;
      final raw = rawTextElements.contains(e.localName);
      for (final c in e.rawChildren) {
        if (raw && c is Text) {
          buf.write(c.data);
        } else {
          _write(c, buf);
        }
      }
      buf.write('</${e.localName}>');
    case Text t:
      buf.write(escapeText(t.data));
    case Comment c:
      buf.write('<!--${c.data}-->');
    default:
      for (final c in node.rawChildren) {
        _write(c, buf);
      }
  }
}
