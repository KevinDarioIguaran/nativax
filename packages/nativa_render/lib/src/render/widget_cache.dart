import 'package:flutter/widgets.dart';
import 'package:nativa_dom/nativa_dom.dart' as dom;

/// Reuses already-built widget subtrees across document rebuilds.
///
/// A mutation invalidates the changed element, its ancestors (so the path is
/// rebuilt) and, when styles can affect descendants, its subtree. Unchanged
/// children are returned as the *same* widget instance, which makes Flutter
/// skip their build/layout subtree entirely.
class NativaXWidgetCache {
  final Map<dom.Element, Widget> _widgets = {};

  int get length => _widgets.length;
  int hits = 0;
  int misses = 0;

  Widget? get(dom.Element element) {
    final widget = _widgets[element];
    if (widget != null) hits++;
    return widget;
  }

  void put(dom.Element element, Widget widget) {
    misses++;
    _widgets[element] = widget;
  }

  /// Invalidates [element] and every ancestor. The path must be rebuilt so
  /// the parent can pick up the changed child; siblings stay cached.
  void invalidatePath(dom.Element element) {
    for (dom.Element? e = element; e != null; e = e.parentElement) {
      _widgets.remove(e);
    }
  }

  /// Invalidates [element], its ancestors and its whole subtree.
  void invalidateSubtree(dom.Element element) {
    invalidatePath(element);
    for (final n in element.descendants) {
      if (n is dom.Element) _widgets.remove(n);
    }
  }

  /// Drops a removed node (and its descendants) so the cache cannot keep
  /// detached DOM subtrees alive.
  void remove(dom.Node node) {
    if (node is dom.Element) {
      _widgets.remove(node);
      for (final n in node.descendants) {
        if (n is dom.Element) _widgets.remove(n);
      }
    }
  }

  void clear() {
    _widgets.clear();
    hits = 0;
    misses = 0;
  }
}
