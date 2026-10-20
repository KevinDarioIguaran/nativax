import 'package:nativax_dom/nativax_dom.dart';

import 'computed_style.dart';
import 'media_queries.dart';
import 'parser.dart';
import 'properties.dart';
import 'user_agent.dart';
import 'values.dart';

/// Cascade layers in ascending precedence (CSS Cascade 4 §6.1, without
/// user styles, animations or transitions).
enum _Layer { uaNormal, authorNormal, inlineNormal, authorImportant, inlineImportant, uaImportant }

class _IndexedRule {
  _IndexedRule(this.selector, this.declarations, this.order, this.isUserAgent);
  final ComplexSelector selector;
  final List<Declaration> declarations;
  final int order;
  final bool isUserAgent;
}

class _Match {
  _Match(this.layer, this.specificity, this.order, this.declaration);
  final _Layer layer;
  final Specificity specificity;
  final int order;
  final Declaration declaration;
}

/// Resolves computed styles for a document and keeps them up to date
/// incrementally.
///
/// * Styles are computed lazily and cached per element.
/// * [handleMutation] marks the minimal subtree dirty for each kind of DOM
///   change; [recompute] recomputes dirty elements top-down and reports
///   which elements' styles actually changed, so a renderer can rebuild only
///   those.
/// * A media context change re-evaluates `@media` rules; styles are
///   recomputed globally only if the active rule set changed or the viewport
///   size changed while viewport units are in use.
class StyleEngine {
  StyleEngine({
    required this.document,
    required MediaContext media,
    StyleSheet? userAgent,
  })  : _media = media,
        _ua = userAgent ?? _defaultUa {
    _rebuildIndex();
  }

  static final StyleSheet _defaultUa = StyleSheet.parse(userAgentStyleSheet);

  final Document document;
  final StyleSheet _ua;
  List<StyleSheet> _authorSheets = const [];
  MediaContext _media;

  final Map<Element, ComputedStyle> _styles = {};
  final Set<Element> _dirtyRoots = {};
  bool _allDirty = true;

  // Rule index by the subject compound's most selective simple selector.
  final Map<String, List<_IndexedRule>> _byId = {};
  final Map<String, List<_IndexedRule>> _byClass = {};
  final Map<String, List<_IndexedRule>> _byTag = {};
  final List<_IndexedRule> _universal = [];
  List<bool> _mediaState = const [];
  bool _usesSiblingCombinators = false;
  bool _usesViewportUnits = false;

  final Map<String, List<Declaration>> _inlineCache = {};

  /// Warnings from parsing inline `style` attributes.
  final List<CssWarning> inlineWarnings = [];

  /// Counters for diagnostics and benchmarks.
  int computeCount = 0;

  MediaContext get media => _media;

  set media(MediaContext value) {
    if (value == _media) return;
    final sizeChanged = value.width != _media.width || value.height != _media.height;
    _media = value;
    final state = _evaluateMedia();
    if (!_listEquals(state, _mediaState) || (sizeChanged && _usesViewportUnits)) {
      _rebuildIndex();
      _allDirty = true;
    }
  }

  List<StyleSheet> get authorSheets => _authorSheets;

  set authorSheets(List<StyleSheet> sheets) {
    _authorSheets = List.unmodifiable(sheets);
    _rebuildIndex();
    _allDirty = true;
  }

  /// The computed style of [element], computing it (and its ancestors) if
  /// needed.
  ComputedStyle styleOf(Element element) {
    if (_allDirty || _dirtyRoots.isNotEmpty) recompute();
    return _styles[element] ?? _compute(element);
  }

  /// Marks styles affected by [record] dirty.
  void handleMutation(MutationRecord record) {
    final target = record.target;
    switch (record.type) {
      case MutationType.childList:
        if (target is Element) {
          _markDirty(target);
        } else {
          _allDirty = true;
        }
        for (final n in record.removedNodes) {
          _forget(n);
        }
      case MutationType.attributes:
      case MutationType.property:
        if (target is! Element) return;
        if (record.name == 'style' && record.type == MutationType.attributes) {
          _markDirty(target);
        } else if (_usesSiblingCombinators && target.parentElement != null) {
          _markDirty(target.parentElement!);
        } else {
          _markDirty(target);
        }
      case MutationType.characterData:
        // Text changes affect no supported selector except :empty on the
        // parent, which is re-evaluated when the text node is added/removed.
        break;
    }
  }

  /// Marks [element] and its subtree for recomputation.
  void invalidate(Element element) => _markDirty(element);

  void invalidateAll() => _allDirty = true;

  void _markDirty(Element e) {
    // Skip if an ancestor is already dirty.
    for (Element? p = e; p != null; p = p.parentElement) {
      if (_dirtyRoots.contains(p)) return;
    }
    _dirtyRoots.removeWhere(e.contains);
    _dirtyRoots.add(e);
  }

  void _forget(Node n) {
    if (n is Element) _styles.remove(n);
    for (final d in n.descendants) {
      if (d is Element) _styles.remove(d);
    }
  }

  /// Recomputes dirty styles. Returns the elements whose computed style
  /// changed (including newly styled elements).
  Set<Element> recompute() {
    final changed = <Element>{};
    if (_allDirty) {
      _allDirty = false;
      _dirtyRoots.clear();
      final root = document.documentElement;
      if (root != null) _computeSubtree(root, changed);
      _styles.removeWhere((e, _) => !e.isConnected);
      return changed;
    }
    final roots = List.of(_dirtyRoots);
    _dirtyRoots.clear();
    for (final r in roots) {
      if (r.isConnected) _computeSubtree(r, changed);
    }
    return changed;
  }

  void _computeSubtree(Element root, Set<Element> changed) {
    final stack = <Element>[root];
    while (stack.isNotEmpty) {
      final e = stack.removeLast();
      final old = _styles[e];
      final style = _compute(e);
      if (old == null || old != style) changed.add(e);
      _styles[e] = style;
      for (final c in e.children.toList().reversed) {
        stack.add(c);
      }
    }
  }

  // --- rule index ------------------------------------------------------------

  List<bool> _evaluateMedia() {
    final state = <bool>[];
    void walk(List<CssRule> rules) {
      for (final r in rules) {
        if (r is MediaRule) {
          state.add(r.media.evaluate(_media));
          walk(r.rules);
        }
      }
    }

    for (final s in _authorSheets) {
      walk(s.rules);
    }
    walk(_ua.rules);
    return state;
  }

  void _rebuildIndex() {
    _byId.clear();
    _byClass.clear();
    _byTag.clear();
    _universal.clear();
    _usesSiblingCombinators = false;
    _usesViewportUnits = false;
    var order = 0;

    void add(StyleRule rule, bool ua) {
      for (final d in rule.declarations) {
        final v = d.value;
        if (v is Length && (v.unit == LengthUnit.vw || v.unit == LengthUnit.vh)) {
          _usesViewportUnits = true;
        }
      }
      for (final sel in rule.selectors.selectors) {
        if (sel.combinators.any((c) =>
            c == Combinator.nextSibling || c == Combinator.subsequentSibling)) {
          _usesSiblingCombinators = true;
        }
        final ir = _IndexedRule(sel, rule.declarations, order++, ua);
        final parts = sel.subject.parts;
        final id = parts.whereType<IdSelector>().firstOrNull;
        final cls = parts.whereType<ClassSelector>().firstOrNull;
        final tag = parts.whereType<TypeSelector>().firstOrNull;
        if (id != null) {
          _byId.putIfAbsent(id.id, () => []).add(ir);
        } else if (cls != null) {
          _byClass.putIfAbsent(cls.name, () => []).add(ir);
        } else if (tag != null) {
          _byTag.putIfAbsent(tag.name, () => []).add(ir);
        } else {
          _universal.add(ir);
        }
      }
    }

    void walk(List<CssRule> rules, bool ua) {
      for (final r in rules) {
        switch (r) {
          case StyleRule():
            add(r, ua);
          case MediaRule():
            if (r.media.evaluate(_media)) walk(r.rules, ua);
        }
      }
    }

    walk(_ua.rules, true);
    for (final s in _authorSheets) {
      walk(s.rules, false);
    }
    _mediaState = _evaluateMedia();
  }

  List<Declaration> _inlineDeclarations(String text) {
    final cached = _inlineCache[text];
    if (cached != null) return cached;
    final (decls, warnings) = CssParser(text).parseDeclarationList();
    inlineWarnings.addAll(warnings);
    if (inlineWarnings.length > 200) inlineWarnings.removeRange(0, 100);
    if (_inlineCache.length > 1024) _inlineCache.clear();
    return _inlineCache[text] = decls;
  }

  /// Matched declarations for [e], in ascending cascade precedence.
  List<Declaration> cascadedDeclarations(Element e) {
    final matches = <_Match>[];
    void consider(List<_IndexedRule>? rules) {
      if (rules == null) return;
      for (final r in rules) {
        if (!r.selector.matches(e)) continue;
        for (final d in r.declarations) {
          final layer = r.isUserAgent
              ? (d.important ? _Layer.uaImportant : _Layer.uaNormal)
              : (d.important ? _Layer.authorImportant : _Layer.authorNormal);
          matches.add(_Match(layer, r.selector.specificity, r.order, d));
        }
      }
    }

    consider(_universal);
    consider(_byTag[e.localName]);
    final id = e.getAttribute('id');
    if (id != null && id.isNotEmpty) consider(_byId[id]);
    final seenClasses = <String>{};
    for (final c in e.classList) {
      if (seenClasses.add(c)) consider(_byClass[c]);
    }
    final inline = e.getAttribute('style');
    if (inline != null && inline.trim().isNotEmpty) {
      var i = 0;
      for (final d in _inlineDeclarations(inline)) {
        matches.add(_Match(
          d.important ? _Layer.inlineImportant : _Layer.inlineNormal,
          Specificity.zero,
          i++,
          d,
        ));
      }
    }
    matches.sort((a, b) {
      final l = a.layer.index - b.layer.index;
      if (l != 0) return l;
      final s = a.specificity.compareTo(b.specificity);
      if (s != 0) return s;
      return a.order - b.order;
    });
    return [for (final m in matches) m.declaration];
  }

  // --- computation -------------------------------------------------------------

  ComputedStyle _compute(Element e) {
    computeCount++;
    final parentEl = e.parentElement;
    final parent = parentEl == null ? null : (_styles[parentEl] ?? _compute(parentEl));
    final root = document.documentElement;
    final rootStyle = (root == null || identical(root, e)) ? null : _styles[root];

    final specified = <String, CssValue>{};
    for (final d in cascadedDeclarations(e)) {
      specified[d.property] = d.value;
    }

    CssValue specifiedOf(String p) {
      final spec = longhands[p]!;
      var v = specified[p];
      if (v is GlobalKeyword) {
        final inherit = v.name == 'inherit' || (v.name == 'unset' && spec.inherited);
        if (inherit && parent != null) return parent[p];
        return spec.initial;
      }
      if (v == null) {
        return spec.inherited && parent != null ? parent[p] : spec.initial;
      }
      return v;
    }

    final parentFont = parent?.fontSize ?? 16;
    final rootFont = rootStyle?.fontSize ?? 16;
    final out = <String, CssValue>{};

    // font-size first: em and % refer to the parent's font size.
    final fs = specifiedOf('font-size');
    double fontSize = parentFont;
    if (fs is Length) {
      fontSize = switch (fs.unit) {
        LengthUnit.px => fs.value,
        LengthUnit.percent => parentFont * fs.value / 100,
        LengthUnit.em => parentFont * fs.value,
        LengthUnit.rem => (identical(root, e) ? 16 : rootFont) * fs.value,
        LengthUnit.vw => _media.width * fs.value / 100,
        LengthUnit.vh => _media.height * fs.value / 100,
      };
    }
    out['font-size'] = Length.px(fontSize);
    final remBase = identical(root, e) ? fontSize : rootFont;

    // color next: currentcolor in `color` means the parent's color.
    final colorValue = specifiedOf('color') as ColorValue;
    final color = colorValue.color ?? parent?.color ?? CssColor.black;
    out['color'] = ColorValue(color);

    CssValue absolutize(CssValue v) {
      if (v is! Length) return v;
      return switch (v.unit) {
        LengthUnit.px || LengthUnit.percent => v,
        LengthUnit.em => Length.px(v.value * fontSize),
        LengthUnit.rem => Length.px(v.value * remBase),
        LengthUnit.vw => Length.px(_media.width * v.value / 100),
        LengthUnit.vh => Length.px(_media.height * v.value / 100),
      };
    }

    for (final p in longhands.keys) {
      if (p == 'font-size' || p == 'color') continue;
      var v = specifiedOf(p);
      if (p == 'line-height' && v is Length && v.unit == LengthUnit.percent) {
        v = Length.px(fontSize * v.value / 100);
      } else if (p == 'font-weight' && v is Keyword && (v.name == 'bolder' || v.name == 'lighter')) {
        final pw = parent?.fontWeight ?? 400;
        v = NumberValue(v.name == 'bolder'
            ? (pw < 400 ? 400 : (pw < 600 ? 700 : 900)).toDouble()
            : (pw < 600 ? 100 : (pw < 800 ? 400 : 700)).toDouble());
      } else {
        v = absolutize(v);
      }
      if (v != longhands[p]!.initial) out[p] = v;
    }

    // Blockification: flex items, absolutely positioned boxes and the root.
    final display = (out['display'] as Keyword?)?.name ?? 'inline';
    final parentIsFlex = parent != null && parent.isFlexContainer;
    final absolute = (out['position'] as Keyword?)?.name == 'absolute';
    if (parentIsFlex || absolute || parentEl == null) {
      final blockified = switch (display) {
        'inline' || 'inline-block' => 'block',
        'inline-flex' => 'flex',
        _ => display,
      };
      if (blockified != display) out['display'] = Keyword(blockified);
    }
    return ComputedStyle(out);
  }
}

bool _listEquals(List<bool> a, List<bool> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
