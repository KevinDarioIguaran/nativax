import 'package:nativa_dom/nativa_dom.dart';

import 'computed_style.dart';
import 'media_queries.dart';
import 'parser.dart';
import 'properties.dart';
import 'tokenizer.dart';
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

  /// When true, [recompute] only computes the dirty roots (and their
  /// ancestors) instead of every descendant. Descendants are computed on
  /// demand by [styleOf], which is what makes it possible to skip style for
  /// subtrees that a virtualized renderer has not materialized. The default
  /// keeps the eager behavior expected by existing callers.
  bool lazySubtrees = false;

  // Rule index by the subject compound's most selective simple selector.
  final Map<String, List<_IndexedRule>> _byId = {};
  final Map<String, List<_IndexedRule>> _byClass = {};
  final Map<String, List<_IndexedRule>> _byTag = {};
  final List<_IndexedRule> _universal = [];
  final Map<String, List<_IndexedRule>> _pseudoRules = {};
  final Map<String, KeyframesRule> _keyframes = {};

  /// The active `@keyframes` rule named [name] (the last one wins).
  KeyframesRule? keyframes(String name) => _keyframes[name];
  final Map<Element, Map<String, ComputedStyle?>> _pseudoStyles = {};
  List<bool> _mediaState = const [];
  bool _usesSiblingCombinators = false;
  bool _usesViewportUnits = false;
  bool _usesHover = false;
  bool _usesActive = false;

  /// Whether any rule depends on `:hover` / `:active`; renderers only track
  /// pointer state when needed.
  bool get usesHover => _usesHover;
  bool get usesActive => _usesActive;

  final Map<String, List<Declaration>> _inlineCache = {};

  /// Warnings from parsing inline `style` attributes.
  final List<CssWarning> inlineWarnings = [];

  /// Counters for diagnostics and benchmarks.
  int computeCount = 0;
  int subtreePasses = 0;
  final Map<String, int> computesByTag = {};

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
    final cached = _styles[element];
    if (cached != null) return cached;
    return _styles[element] = _compute(element);
  }

  /// The style of [element]'s [pseudo] pseudo-element (`before`, `after`,
  /// `marker`, `placeholder`, ...), or null when no rule targets it. For
  /// `before`/`after` the caller must still check that `content` generates
  /// a box.
  ComputedStyle? pseudoStyleOf(Element element, String pseudo) {
    final rules = _pseudoRules[pseudo];
    if (rules == null || rules.isEmpty) return null;
    final origin = styleOf(element);
    final cache = _pseudoStyles.putIfAbsent(element, () => {});
    if (cache.containsKey(pseudo)) return cache[pseudo];
    final any = rules.any((r) => r.selector.matchesPseudo(element, pseudo));
    final style = any ? _compute(element, pseudo: pseudo, origin: origin) : null;
    cache[pseudo] = style;
    return style;
  }

  /// Whether any rule styles [pseudo]; lets renderers skip lookups.
  bool hasPseudoRules(String pseudo) => _pseudoRules[pseudo]?.isNotEmpty ?? false;

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
        // `:empty` depends on whether a child text node has data, so the
        // parent selector may now match or stop matching.
        final parent = target.parentElement;
        if (parent != null) {
          _markDirty(parent);
        } else {
          _allDirty = true;
        }
    }
  }

  /// Marks [element] dirty, and its subtree for recomputation.
  void invalidate(Element element) => _markDirty(element);

  /// Drops cached styles for [element] and its subtree without computing them.
  ///
  /// A virtualized renderer calls this for mutations in a subtree that has no
  /// render object: the DOM is already updated and [styleOf] will compute the
  /// fresh style when the element enters the viewport.
  void invalidateDeferred(Element element) => _forget(element);

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
    if (n is Element) {
      _styles.remove(n);
      _pseudoStyles.remove(n);
    }
    for (final d in n.descendants) {
      if (d is Element) {
        _styles.remove(d);
        _pseudoStyles.remove(d);
      }
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
      _pseudoStyles.clear();
      if (root != null) {
        if (lazySubtrees) {
          // A global invalidation (media change, new stylesheet) invalidates
          // every cached style; they are recomputed on demand.
          _styles.clear();
          final style = _compute(root);
          _styles[root] = style;
          changed.add(root);
        } else {
          _computeSubtree(root, changed);
        }
      }
      _styles.removeWhere((e, _) => !e.isConnected);
      return changed;
    }
    final roots = List.of(_dirtyRoots);
    _dirtyRoots.clear();
    for (final r in roots) {
      if (!r.isConnected) continue;
      if (lazySubtrees) {
        final old = _styles[r];
        final style = _compute(r);
        _styles[r] = style;
        if (old == null || old != style) changed.add(r);
        // Selector dependencies below the dirty root (siblings, :has, :empty,
        // inherited values) may have changed even when the root's own style is
        // identical. Drop the cached descendants; they are recomputed on
        // demand, so this stays lazy.
        _forgetDescendantStyles(r);
      } else {
        _computeSubtree(r, changed);
      }
    }
    return changed;
  }

  /// Drops cached styles below [root] so they are recomputed on demand. The
  /// root itself keeps its freshly computed style.
  void _forgetDescendantStyles(Element root) {
    for (final d in root.descendants) {
      if (d is Element) {
        _styles.remove(d);
        _pseudoStyles.remove(d);
      }
    }
  }

  void _computeSubtree(Element root, Set<Element> changed) {
    subtreePasses++;
    final stack = <Element>[root];
    while (stack.isNotEmpty) {
      final e = stack.removeLast();
      final old = _styles[e];
      final style = _compute(e);
      if (old == null || old != style) changed.add(e);
      _styles[e] = style;
      _pseudoStyles.remove(e);
      for (final c in e.children.toList().reversed) {
        stack.add(c);
      }
    }
  }

  // --- rule index ------------------------------------------------------------

  /// [element]'s style with [extra] declarations applied on top of its
  /// cascade (keyframes are computed this way, so `em`, `var()` and
  /// `currentcolor` resolve in the element's context). Not cached.
  ComputedStyle styleWithDeclarations(Element element, List<Declaration> extra) {
    styleOf(element);
    return _compute(element, extra: extra);
  }

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
    _pseudoRules.clear();
    _pseudoStyles.clear();
    _keyframes.clear();
    _usesHover = false;
    _usesActive = false;
    _usesSiblingCombinators = false;
    _usesViewportUnits = false;
    var order = 0;

    void add(StyleRule rule, bool ua) {
      if (rule.selectorText.contains(':hover')) _usesHover = true;
      if (rule.selectorText.contains(':active')) _usesActive = true;
      for (final d in rule.declarations) {
        final v = d.value;
        if (v is Length && (v.unit == LengthUnit.vw || v.unit == LengthUnit.vh)) {
          _usesViewportUnits = true;
        } else if (v is RawValue || v is RelativeValue) {
          final text = v.toString().toLowerCase();
          if (text.contains('vw') || text.contains('vh') || v is CalcLength) {
            _usesViewportUnits = true;
          }
        }
      }
      for (final sel in rule.selectors.selectors) {
        if (sel.combinators.any((c) =>
            c == Combinator.nextSibling || c == Combinator.subsequentSibling)) {
          _usesSiblingCombinators = true;
        }
        final ir = _IndexedRule(sel, rule.declarations, order++, ua);
        final pseudo = sel.pseudoElement;
        if (pseudo != null) {
          _pseudoRules.putIfAbsent(pseudo, () => []).add(ir);
          continue;
        }
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
          case KeyframesRule():
            _keyframes[r.name] = r;
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
  List<Declaration> cascadedDeclarations(Element e, {String? pseudo}) {
    final matches = <_Match>[];
    void consider(List<_IndexedRule>? rules) {
      if (rules == null) return;
      for (final r in rules) {
        if (pseudo == null ? !r.selector.matches(e) : !r.selector.matchesPseudo(e, pseudo)) continue;
        for (final d in r.declarations) {
          final layer = r.isUserAgent
              ? (d.important ? _Layer.uaImportant : _Layer.uaNormal)
              : (d.important ? _Layer.authorImportant : _Layer.authorNormal);
          matches.add(_Match(layer, r.selector.specificity, r.order, d));
        }
      }
    }

    if (pseudo != null) {
      consider(_pseudoRules[pseudo]);
    } else {
      consider(_universal);
      consider(_byTag[e.localName]);
      final id = e.getAttribute('id');
      if (id != null && id.isNotEmpty) consider(_byId[id]);
      final seenClasses = <String>{};
      for (final c in e.classList) {
        if (seenClasses.add(c)) consider(_byClass[c]);
      }
    }
    // SVG presentation attributes count as author rules with specificity 0
    // that precede every style sheet rule.
    if (pseudo == null && _svgElements.contains(e.localName)) {
      var i = -100000;
      for (final name in _presentationAttributes) {
        final v = e.getAttribute(name);
        if (v == null || v.trim().isEmpty) continue;
        final expanded = expandDeclaration(name, CssTokenizer(v).tokenize());
        if (expanded == null) continue;
        expanded.forEach((p, value) => matches.add(_Match(_Layer.authorNormal, Specificity.zero, i++, Declaration(p, value))));
      }
    }
    final inline = pseudo == null ? e.getAttribute('style') : null;
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

  ComputedStyle _compute(Element e, {String? pseudo, ComputedStyle? origin, List<Declaration>? extra}) {
    const profile = bool.fromEnvironment('NATIVAX_RENDER_PROFILE', defaultValue: false);
    final watch = profile ? (Stopwatch()..start()) : null;
    computeCount++;
    computesByTag[e.localName] = (computesByTag[e.localName] ?? 0) + 1;
    // A pseudo-element inherits from its originating element.
    final parentEl = pseudo != null ? e : e.parentElement;
    final ComputedStyle? parent;
    if (pseudo != null) {
      parent = origin;
    } else if (parentEl != null) {
      parent = _styles[parentEl] ??= _compute(parentEl);
    } else {
      parent = null;
    }
    final root = document.documentElement;
    final rootStyle = (root == null || (pseudo == null && identical(root, e))) ? null : _styles[root];

    final cascaded = cascadedDeclarations(e, pseudo: pseudo);
    if (extra != null) cascaded.addAll(extra);
    final custom = <String, String>{};
    if (parent != null) custom.addAll(parent.customProperties);
    // Custom properties cascade and inherit independently of the order in
    // which their consumers appear. Resolve references between them first.
    for (final d in cascaded) {
      if (!d.property.startsWith('--')) continue;
      final raw = d.value;
      if (raw is RawValue) custom[d.property] = raw.text;
    }
    for (final key in custom.keys.toList()) {
      final resolved = _substituteVariables(custom[key]!, custom);
      if (resolved != null) custom[key] = resolved;
    }

    final specified = <String, CssValue>{};
    for (final d in cascaded) {
      if (d.property.startsWith('--')) continue;
      final value = d.value;
      if (value is RawValue) {
        final text = _substituteVariables(value.text, custom);
        if (text == null) continue;
        final expanded = expandDeclaration(
            d.property, CssTokenizer(text).tokenize());
        if (expanded != null) specified.addAll(expanded);
        continue;
      }
      specified[d.property] = value;
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
        LengthUnit.rem => (pseudo == null && identical(root, e) ? 16 : rootFont) * fs.value,
        LengthUnit.vw => _media.width * fs.value / 100,
        LengthUnit.vh => _media.height * fs.value / 100,
      };
    }
    out['font-size'] = Length.px(fontSize);
    final remBase = pseudo == null && identical(root, e) ? fontSize : rootFont;

    // color next: currentcolor in `color` means the parent's color.
    final colorValue = specifiedOf('color') as ColorValue;
    final color = colorValue.color ?? parent?.color ?? CssColor.black;
    out['color'] = ColorValue(color);

    Length absLength(Length v) => switch (v.unit) {
          LengthUnit.px || LengthUnit.percent => v,
          LengthUnit.em => Length.px(v.value * fontSize),
          LengthUnit.rem => Length.px(v.value * remBase),
          LengthUnit.vw => Length.px(_media.width * v.value / 100),
          LengthUnit.vh => Length.px(_media.height * v.value / 100),
        };

    CssValue absolutize(CssValue v) {
      if (v is Length) return absLength(v);
      if (v is RelativeValue) return (v as RelativeValue).absolutize(absLength);
      return v;
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

    // Border and outline widths snap to whole device pixels (CSS Values 4
    // "snap as a border width"): below one device pixel rounds up to one,
    // otherwise floors. Browsers do this, so 1.5px draws as 1px at DPR 1.
    for (final p in _snappedWidths) {
      final v = out[p] ?? longhands[p]!.initial;
      if (v is! Length || v.unit != LengthUnit.px || v.value <= 0) continue;
      final dpr = _media.devicePixelRatio <= 0 ? 1.0 : _media.devicePixelRatio;
      final device = v.value * dpr;
      final snapped = (device < 1 ? 1.0 : device.floorToDouble()) / dpr;
      if (snapped != v.value) out[p] = Length.px(snapped);
    }

    // Blockification: flex and grid items, absolutely positioned boxes and
    // the root.
    final display = (out['display'] as Keyword?)?.name ?? 'inline';
    final parentIsFlex = parent != null && (parent.isFlexContainer || parent.isGridContainer);
    final position = (out['position'] as Keyword?)?.name;
    final absolute = position == 'absolute' || position == 'fixed';
    if (parentIsFlex || absolute || parentEl == null) {
      final blockified = switch (display) {
        'inline' || 'inline-block' => 'block',
        'inline-flex' => 'flex',
        'inline-grid' => 'grid',
        _ => display,
      };
      if (blockified != display) out['display'] = Keyword(blockified);
    }
    final result = ComputedStyle(out, customProperties: custom);
    if (watch != null && watch.elapsedMilliseconds >= 2) {
      // ignore: avoid_print
      print('STYLE_SLOW <${e.localName}${e.id.isEmpty ? '' : '#${e.id}'}> '
          '${watch.elapsedMilliseconds}ms tag=${e.localName}');
    }
    return result;
  }
}

const _snappedWidths = [
  'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width', 'outline-width',
];

const _svgElements = {
  'svg', 'g', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon', 'path', 'text', 'tspan', 'use',
  'symbol', 'defs', 'marker', 'image', 'foreignobject',
};

const _presentationAttributes = [
  'fill', 'stroke', 'stroke-width', 'fill-opacity', 'stroke-opacity', 'stroke-linecap', 'stroke-linejoin',
  'fill-rule', 'opacity', 'font-size', 'font-family', 'font-weight', 'text-anchor', 'dominant-baseline',
  'visibility', 'display', 'color', 'stroke-dasharray',
];

/// Substitutes `var(--name[, fallback])` and common safe-area `env()` values.
/// Returns null when a reference cannot be resolved.
String? _substituteVariables(String text, Map<String, String> custom) {
  var out = text;
  for (var pass = 0; pass < 32; pass++) {
    final lower = out.toLowerCase();
    var start = -1;
    for (var i = lower.indexOf('var('); i >= 0; i = lower.indexOf('var(', i + 1)) {
      if (i == 0 || !_isIdentChar(lower.codeUnitAt(i - 1))) {
        start = i;
        break;
      }
    }
    if (start < 0) break;
    final open = start + 3; // points at '('
    final close = _matchingParen(out, open);
    if (close < 0) return null;
    final inner = out.substring(open + 1, close);
    final comma = _topLevelComma(inner);
    final name = (comma < 0 ? inner : inner.substring(0, comma)).trim();
    final fallback = comma < 0 ? null : inner.substring(comma + 1).trim();
    String? replacement;
    if (name.startsWith('--')) replacement = custom[name];
    if (replacement == null) replacement = fallback;
    if (replacement == null) return null;
    out = out.substring(0, start) + replacement + out.substring(close + 1);
  }
  // `env(safe-area-inset-*)` is 0 in a Flutter view without OS insets.
  out = out.replaceAllMapped(
    RegExp(r'env\(\s*[^,)]+\s*(?:,\s*([^)]*))?\)', caseSensitive: false),
    (m) => (m.group(1) ?? '0px').trim(),
  );
  return out;
}

bool _isIdentChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    c == 0x2d ||
    c == 0x5f;

int _matchingParen(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x28) depth++;
    if (text.codeUnitAt(i) == 0x29) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _topLevelComma(String text) {
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x28 || c == 0x5b || c == 0x7b) depth++;
    if (c == 0x29 || c == 0x5d || c == 0x7d) depth--;
    if (c == 0x2c && depth == 0) return i;
  }
  return -1;
}

bool _listEquals(List<bool> a, List<bool> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
