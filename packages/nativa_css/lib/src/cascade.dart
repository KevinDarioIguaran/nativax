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
enum _Layer {
  uaNormal,
  authorNormal,
  inlineNormal,
  authorImportant,
  inlineImportant,
  uaImportant,
}

class _IndexedRule {
  _IndexedRule(
    this.selector,
    this.declarations,
    this.order,
    this.isUserAgent, {
    required this.structural,
    required this.sibling,
  });
  final ComplexSelector selector;
  final List<Declaration> declarations;
  final int order;
  final bool isUserAgent;

  /// Selector depends on position/structure (`:first-*`, `:nth-*`, `:empty`,
  /// `:has`, ...).
  final bool structural;

  /// Selector uses `+` or `~`.
  final bool sibling;
}

class _Match {
  _Match(this.layer, this.specificity, this.order, this.declaration);
  final _Layer layer;
  final Specificity specificity;
  final int order;
  final Declaration declaration;
}

/// Indexed candidate rules for one pseudo-element kind. The subject is the
/// rightmost compound, exactly like Blink's RuleSet buckets.
class _RuleBuckets {
  final Map<String, List<_IndexedRule>> byId = {};
  final Map<String, List<_IndexedRule>> byClass = {};
  final Map<String, List<_IndexedRule>> byTag = {};
  final List<_IndexedRule> universal = [];

  bool get isEmpty =>
      byId.isEmpty && byClass.isEmpty && byTag.isEmpty && universal.isEmpty;

  void add(_IndexedRule ir) {
    final parts = ir.selector.subject.parts;
    final id = parts.whereType<IdSelector>().firstOrNull;
    final cls = parts.whereType<ClassSelector>().firstOrNull;
    final tag = parts.whereType<TypeSelector>().firstOrNull;
    if (id != null) {
      byId.putIfAbsent(id.id, () => []).add(ir);
    } else if (cls != null) {
      byClass.putIfAbsent(cls.name, () => []).add(ir);
    } else if (tag != null) {
      byTag.putIfAbsent(tag.name, () => []).add(ir);
    } else {
      universal.add(ir);
    }
  }

  Iterable<_IndexedRule> candidates(Element e) sync* {
    yield* universal;
    yield* byTag[e.localName] ?? const [];
    final id = e.getAttribute('id');
    if (id != null) yield* byId[id] ?? const [];
    for (final c in e.classList) {
      yield* byClass[c] ?? const [];
    }
  }
}

class _StyleSample {
  _StyleSample(this.element);
  final Element element;
  final Stopwatch watch = Stopwatch();
  int selectorStart = 0;
  int candidateStart = 0;
  int cacheHitStart = 0;
  int totalUs = 0;
  int childUs = 0;
  int ownUs = 0;
  int selectors = 0;
  int candidates = 0;
  bool cacheHit = false;
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
  }) : _media = media,
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
  final Map<String, List<_IndexedRule>> _hoverById = {};
  final Map<String, List<_IndexedRule>> _hoverByClass = {};
  final Map<String, List<_IndexedRule>> _hoverByTag = {};
  final List<_IndexedRule> _hoverUniversal = [];
  final List<_IndexedRule> _universal = [];
  final Map<String, _RuleBuckets> _pseudoBuckets = {};
  final Map<String, KeyframesRule> _keyframes = {};

  /// The active `@keyframes` rule named [name] (the last one wins).
  KeyframesRule? keyframes(String name) => _keyframes[name];
  final Map<Element, Map<String, ComputedStyle?>> _pseudoStyles = {};
  List<bool> _mediaState = const [];
  bool _usesSiblingCombinators = false;
  bool _structuralUniversal = false;
  final Set<String> _structuralTags = {};
  final Set<String> _structuralClasses = {};
  final Set<String> _structuralIds = {};
  final Set<String> _structuralAncestorTags = {};
  final Set<String> _structuralAncestorClasses = {};
  final Set<String> _structuralAncestorIds = {};
  bool _usesViewportUnits = false;
  final Map<String, Set<String>> _attributeTags = {};
  final Set<String> _attributeUniversal = {};
  bool _usesHover = false;
  bool _usesActive = false;
  bool _statefulAncestorUniversal = false;
  final Set<String> _statefulAncestorTags = {};
  final Set<String> _statefulAncestorClasses = {};
  final Set<String> _statefulAncestorIds = {};

  /// Whether any rule depends on `:hover` / `:active`; renderers only track
  /// pointer state when needed.
  bool get usesHover => _usesHover;

  /// Whether [element] can match a `:hover`-dependent rule. Renderers use it
  /// to add pointer regions only where they matter instead of on every node.
  bool mayHover(Element element) {
    if (!_usesHover) return false;
    if (_hoverUniversal.isNotEmpty) return true;
    final id = element.getAttribute('id');
    if (id != null && (_hoverById[id]?.isNotEmpty ?? false)) return true;
    for (final c in element.classList) {
      if (_hoverByClass[c]?.isNotEmpty ?? false) return true;
    }
    return _hoverByTag[element.localName]?.isNotEmpty ?? false;
  }

  bool get usesActive => _usesActive;

  final Map<String, List<Declaration>> _inlineCache = {};
  final Map<String, Map<String, CssValue>?> _expandedCache = {};

  /// Warnings from parsing inline `style` attributes.
  final List<CssWarning> inlineWarnings = [];

  /// Counters for diagnostics and benchmarks.
  int computeCount = 0;
  int subtreePasses = 0;
  int selectorEvaluations = 0;
  int matchedCacheHits = 0;
  int matchedCacheMisses = 0;
  int styleCacheHits = 0;
  final Map<String, int> computesByTag = {};

  /// Opt-in per-element style profiler. The host enables it with
  /// `NATIVAX_METRICS=1`; production leaves it off.
  bool metricsEnabled = false;
  int candidateRules = 0;
  final List<_StyleSample> _styleSamples = [];
  final List<_StyleSample> _styleStack = [];

  /// Matched declarations and computed styles shared by elements with the
  /// same signature (tag/id/classes/attributes) and the same parent style.
  /// This is the NativaX equivalent of Blink's MatchedPropertiesCache and
  /// shared style finder.
  final Map<String, List<Declaration>> _matchedCache = {};
  final Map<String, ComputedStyle> _computedCache = {};
  bool _matchedDirty = false;
  bool _computedDirty = false;
  bool _dirtyMayAffectDescendants = false;

  /// Allows benchmarks/tests to measure the uncached cascade. Production
  /// always leaves this enabled.
  bool useStyleCaches = true;
  static const int _maxCacheEntries = 8192;

  void _clearStyleCaches() {
    _matchedCache.clear();
    _computedCache.clear();
    _matchedDirty = false;
    _computedDirty = false;
  }

  void _ensureStyleCaches() {
    if (!useStyleCaches) {
      _clearStyleCaches();
      return;
    }
    if (_matchedDirty) _matchedCache.clear();
    if (_computedDirty) _computedCache.clear();
    _matchedDirty = false;
    _computedDirty = false;
  }

  int get dirtyRootCount => _dirtyRoots.length;

  String get ruleIndexInfo {
    final tags = _byTag.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final classes = _byClass.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return 'universal=${_universal.length} '
        'tagTop=${tags.take(6).map((e) => '${e.key}:${e.value.length}').join(',')} '
        'classTop=${classes.take(6).map((e) => '${e.key}:${e.value.length}').join(',')}';
  }

  bool _hasStatefulPseudo(List<SimpleSelector> parts) {
    for (final part in parts) {
      if (part is PseudoClassSelector) {
        if (PseudoClassSelector.stateful.contains(part.name)) return true;
        void scan(SelectorList? list) {
          if (list == null) return;
          for (final s in list.selectors) {
            for (final c in s.compounds) {
              if (_hasStatefulPseudo(c.parts)) return;
            }
          }
        }

        scan(part.inner);
        scan(part.of);
        final has = part.hasParts;
        if (has != null) {
          for (final (_, s) in has) {
            for (final c in s.compounds) {
              if (_hasStatefulPseudo(c.parts)) return true;
            }
          }
        }
      }
    }
    return false;
  }

  bool _needsStatefulAncestorKey(Element e) {
    if (_statefulAncestorUniversal) return true;
    if (_statefulAncestorTags.contains(e.localName)) return true;
    final id = e.getAttribute('id');
    if (id != null && _statefulAncestorIds.contains(id)) return true;
    for (final c in e.classList) {
      if (_statefulAncestorClasses.contains(c)) return true;
    }
    return false;
  }

  bool _needsStructuralKey(Element e) {
    if (_structuralUniversal) return true;
    if (_structuralTags.contains(e.localName)) return true;
    final id = e.getAttribute('id');
    if (id != null && _structuralIds.contains(id)) return true;
    for (final c in e.classList) {
      if (_structuralClasses.contains(c)) return true;
    }
    if (_structuralAncestorTags.isNotEmpty ||
        _structuralAncestorClasses.isNotEmpty ||
        _structuralAncestorIds.isNotEmpty) {
      for (Element? p = e.parentElement; p != null; p = p.parentElement) {
        if (_structuralAncestorTags.contains(p.localName)) return true;
        final pid = p.getAttribute('id');
        if (pid != null && _structuralAncestorIds.contains(pid)) return true;
        for (final c in p.classList) {
          if (_structuralAncestorClasses.contains(c)) return true;
        }
      }
    }
    return false;
  }

  /// Attributes that participate in selector matching or pseudo-class state
  /// even when no `[attr]` selector mentions them. Everything else (title,
  /// aria-*, data-* used only by scripts, ...) must not fragment the style
  /// cache for otherwise identical elements.
  static const Set<String> _signatureAttributes = {
    'style',
    'href',
    'disabled',
    'checked',
    'selected',
    'type',
    'open',
    'hidden',
    'contenteditable',
    'multiple',
    'required',
    'readonly',
    'placeholder',
    'value',
    'lang',
    'dir',
    'popover',
  };

  bool _signatureAttribute(Element e, String name) {
    if (_signatureAttributes.contains(name)) return true;
    if (_attributeUniversal.contains(name)) return true;
    return _attributeTags[name]?.contains(e.localName) ?? false;
  }

  String _elementSignature(
    Element e, {
    String? pseudo,
    ComputedStyle? parent,
    bool structural = false,
    bool sibling = false,
  }) {
    final b = StringBuffer()
      ..write(e.localName)
      ..write('\u0000')
      ..write(e.getAttribute('id') ?? '')
      ..write('\u0000');
    final classes = e.classList.toList()..sort();
    b.write(classes.join('.'));
    b.write('\u0000');
    final attrs = e.attributes;
    final names = attrs.keys.toList()..sort();
    for (final name in names) {
      if (name == 'class' || name == 'id') continue;
      if (!_signatureAttribute(e, name)) continue;
      b
        ..write(name)
        ..write('=')
        ..write(attrs[name])
        ..write('\u0001');
    }
    b
      ..write('\u0000')
      ..write(pseudo ?? '')
      ..write('\u0000')
      ..write(parent == null ? 0 : parent.hashCode);
    final doc = e.ownerDocument;
    b
      ..write('\u0000')
      ..write(identityHashCode(doc.hoverElement))
      ..write(':')
      ..write(identityHashCode(doc.pressedElement))
      ..write(':')
      ..write(identityHashCode(doc.activeElement))
      ..write(':')
      ..write(doc.targetId ?? '');
    if (structural) {
      final parentEl = e.parentElement;
      final siblings = parentEl?.children.toList() ?? const <Element>[];
      final index = siblings.indexWhere((c) => identical(c, e));
      final childCount = siblings.length;
      var indexOfType = 0;
      var countOfType = 0;
      for (final s in siblings) {
        if (s.localName == e.localName) {
          if (identical(s, e)) indexOfType = countOfType;
          countOfType++;
        }
      }
      b
        ..write('\u0000s')
        ..write(index)
        ..write(':')
        ..write(childCount)
        ..write(':')
        ..write(indexOfType)
        ..write(':')
        ..write(countOfType)
        ..write(':')
        ..write(e.childNodes.isEmpty ? 1 : 0);
      // Sibling combinators depend on the identity/content of neighbours;
      // keep the parent in the key only when such selectors exist.
      if (sibling) {
        b
          ..write('\u0000p')
          ..write(identityHashCode(parentEl));
      }
    }
    return b.toString();
  }

  /// Number of elements with a cached computed style (diagnostics/tests).
  int get cachedStyleCount => _styles.length;

  /// Structural-selector buckets used by the style cache (diagnostics).
  String get structuralInfo =>
      'u=$_structuralUniversal tags=${_structuralTags.join(',')} '
      'classes=${_structuralClasses.join(',')} ids=${_structuralIds.join(',')}';

  MediaContext get media => _media;

  set media(MediaContext value) {
    if (value == _media) return;
    final sizeChanged =
        value.width != _media.width || value.height != _media.height;
    _media = value;
    final state = _evaluateMedia();
    if (!_listEquals(state, _mediaState) ||
        (sizeChanged && _usesViewportUnits)) {
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
    final buckets = _pseudoBuckets[pseudo];
    if (buckets == null || buckets.isEmpty) return null;
    final origin = styleOf(element);
    final cache = _pseudoStyles.putIfAbsent(element, () => {});
    if (cache.containsKey(pseudo)) return cache[pseudo];
    final any = buckets
        .candidates(element)
        .any((r) => r.selector.matchesPseudo(element, pseudo));
    final style = any
        ? _compute(element, pseudo: pseudo, origin: origin)
        : null;
    cache[pseudo] = style;
    return style;
  }

  /// Whether any rule styles [pseudo]; lets renderers skip lookups.
  bool hasPseudoRules(String pseudo) =>
      _pseudoBuckets[pseudo]?.isEmpty == false;

  /// Marks styles affected by [record] dirty.
  void handleMutation(MutationRecord record) {
    final target = record.target;
    switch (record.type) {
      case MutationType.childList:
        // Structure (and therefore sibling/positional selectors) changed.
        _matchedDirty = true;
        _computedDirty = true;
        _dirtyMayAffectDescendants = true;
        if (target is Element) {
          _markDirty(target);
        } else {
          _allDirty = true;
        }
        for (final n in record.removedNodes) {
          _forget(n);
        }
      case MutationType.attributes:
        if (target is! Element) return;
        final name = (record.name ?? '').toLowerCase();
        if (name != 'class' &&
            name != 'id' &&
            name != 'style' &&
            !_attributeUniversal.contains(name) &&
            !(_attributeTags[name]?.contains(target.localName) ?? false)) {
          // No selector in the UA or author sheets reads this attribute.
          return;
        }
        // class/id/style and attributes used by selectors can change any
        // selector that descends from this element.
        _matchedDirty = true;
        _computedDirty = true;
        _dirtyMayAffectDescendants = true;
        if (record.name == 'style') {
          _markDirty(target);
        } else if (_usesSiblingCombinators && target.parentElement != null) {
          _markDirty(target.parentElement!);
        } else {
          _markDirty(target);
        }
      case MutationType.property:
        // DOM state (:checked, :disabled, :empty via value changes, ...).
        _matchedDirty = true;
        if (target is! Element) return;
        _dirtyMayAffectDescendants |= _needsStatefulAncestorKey(target);
        _markDirty(target);
      case MutationType.characterData:
        // Text data only affects structural selectors (`:empty`, `:has`, and
        // sibling combinators) on the parent. Unrelated UA/author structural
        // rules must not force a full subtree recompute.
        final parent = target.parentElement;
        final structural = parent != null && _needsStructuralKey(parent);
        if (structural) {
          _matchedDirty = true;
          _computedDirty = true;
        }
        _dirtyMayAffectDescendants |= structural;
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
    final mayAffectDescendants = _dirtyMayAffectDescendants;
    _dirtyMayAffectDescendants = false;
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
      if (changed.isNotEmpty) _computedDirty = true;
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
        final styleChanged = old == null || old != style;
        if (styleChanged) changed.add(r);
        // Descendants only need to be dropped when the mutation can affect
        // selector matching below this root or when the root's inherited
        // values changed. A plain text update with no structural selectors
        // keeps the whole subtree cached.
        if (mayAffectDescendants || styleChanged) {
          _forgetDescendantStyles(r);
        }
      } else {
        _computeSubtree(r, changed);
      }
    }
    if (changed.isNotEmpty) _computedDirty = true;
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
  ComputedStyle styleWithDeclarations(
    Element element,
    List<Declaration> extra,
  ) {
    styleOf(element);
    return _compute(element, extra: extra);
  }

  int get metricsOwnUs => _styleSamples.fold<int>(0, (a, s) => a + s.ownUs);

  String metricsSummary() {
    if (!metricsEnabled || _styleSamples.isEmpty) return 'style metrics: off';
    final own = _styleSamples.fold<int>(0, (a, s) => a + s.ownUs);
    final top = List<_StyleSample>.of(_styleSamples)
      ..sort((a, b) => b.ownUs.compareTo(a.ownUs));
    final b = StringBuffer(
      'STYLE_METRICS samples=${_styleSamples.length} '
      'ownMs=${(own / 1000).toStringAsFixed(1)} '
      'avgUs=${(own / _styleSamples.length).toStringAsFixed(0)} '
      'selectorsPer=${(selectorEvaluations / _styleSamples.length).toStringAsFixed(1)} '
      'candidatesPer=${(candidateRules / _styleSamples.length).toStringAsFixed(1)} '
      'hits=$styleCacheHits',
    );
    for (final s in top.take(10)) {
      b.write(
        ' | ${s.element.localName}'
        '${s.element.id.isEmpty ? '' : '#${s.element.id}'} '
        'own=${s.ownUs}us sel=${s.selectors} cand=${s.candidates}'
        '${s.cacheHit ? ' hit' : ''}',
      );
    }
    return b.toString();
  }

  Map<String, Object?> metricsJson() {
    final own = _styleSamples.fold<int>(0, (a, s) => a + s.ownUs);
    final top = List<_StyleSample>.of(_styleSamples)
      ..sort((a, b) => b.ownUs.compareTo(a.ownUs));
    return {
      'samples': _styleSamples.length,
      'ownMs': own / 1000,
      'avgOwnUs': _styleSamples.isEmpty ? 0 : own / _styleSamples.length,
      'selectorsPerElement': _styleSamples.isEmpty
          ? 0
          : selectorEvaluations / _styleSamples.length,
      'candidatesPerElement': _styleSamples.isEmpty
          ? 0
          : candidateRules / _styleSamples.length,
      'cacheHits': styleCacheHits,
      'top': [
        for (final s in top.take(12))
          {
            'tag': s.element.localName,
            'id': s.element.id,
            'ownUs': s.ownUs,
            'selectors': s.selectors,
            'candidates': s.candidates,
            'cacheHit': s.cacheHit,
          },
      ],
    };
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
    _hoverById.clear();
    _hoverByClass.clear();
    _hoverByTag.clear();
    _hoverUniversal.clear();
    _universal.clear();
    _pseudoBuckets.clear();
    _pseudoStyles.clear();
    _keyframes.clear();
    _usesHover = false;
    _usesActive = false;
    _statefulAncestorUniversal = false;
    _statefulAncestorTags.clear();
    _statefulAncestorClasses.clear();
    _statefulAncestorIds.clear();
    _attributeTags.clear();
    _attributeUniversal.clear();
    _usesSiblingCombinators = false;
    _structuralUniversal = false;
    _structuralTags.clear();
    _structuralClasses.clear();
    _structuralIds.clear();
    _structuralAncestorTags.clear();
    _structuralAncestorClasses.clear();
    _structuralAncestorIds.clear();
    _usesViewportUnits = false;
    var order = 0;

    void add(StyleRule rule, bool ua) {
      final selectorText = rule.selectorText;
      final collected = <String>{};
      void collectCompound(CompoundSelector compound, String? inheritedTag) {
        final tag =
            compound.parts.whereType<TypeSelector>().firstOrNull?.name ??
            inheritedTag;
        for (final part in compound.parts) {
          if (part is AttributeSelector) {
            final name = part.name.toLowerCase();
            collected.add(name);
            if (tag == null) {
              _attributeUniversal.add(name);
            } else {
              _attributeTags.putIfAbsent(name, () => <String>{}).add(tag);
            }
          } else if (part is PseudoClassSelector) {
            void collectList(SelectorList? list) {
              if (list == null) return;
              for (final s in list.selectors) {
                for (final c in s.compounds) {
                  collectCompound(c, tag);
                }
              }
            }

            collectList(part.inner);
            collectList(part.of);
            final has = part.hasParts;
            if (has != null) {
              for (final (_, s) in has) {
                for (final c in s.compounds) {
                  collectCompound(c, tag);
                }
              }
            }
          }
        }
      }

      for (final sel in rule.selectors.selectors) {
        for (final compound in sel.compounds) {
          collectCompound(compound, null);
        }
      }
      // Anything the AST walk could not associate with a tag is universal.
      for (final match in RegExp(
        r'(?<!\\)\[\s*(?:[-\w*]+\|)?([-\w:]+)',
      ).allMatches(selectorText)) {
        final name = match.group(1)!.toLowerCase();
        if (!collected.contains(name)) _attributeUniversal.add(name);
      }
      final structuralRule =
          selectorText.contains(':first-') ||
          selectorText.contains(':last-') ||
          selectorText.contains(':only-') ||
          selectorText.contains(':nth-') ||
          selectorText.contains(':empty') ||
          selectorText.contains(':has(') ||
          selectorText.contains('+') ||
          selectorText.contains('~');
      if (rule.selectorText.contains(':hover')) _usesHover = true;
      if (rule.selectorText.contains(':active')) _usesActive = true;
      for (final d in rule.declarations) {
        final v = d.value;
        if (v is Length &&
            (v.unit == LengthUnit.vw || v.unit == LengthUnit.vh)) {
          _usesViewportUnits = true;
        } else if (v is RawValue || v is RelativeValue) {
          final text = v.toString().toLowerCase();
          if (text.contains('vw') || text.contains('vh') || v is CalcLength) {
            _usesViewportUnits = true;
          }
        }
      }
      for (final sel in rule.selectors.selectors) {
        if (sel.combinators.any(
          (c) =>
              c == Combinator.nextSibling || c == Combinator.subsequentSibling,
        )) {
          _usesSiblingCombinators = true;
        }
        if (structuralRule) {
          final parts = sel.subject.parts;
          final id = parts.whereType<IdSelector>().firstOrNull;
          final cls = parts.whereType<ClassSelector>().firstOrNull;
          final tag = parts.whereType<TypeSelector>().firstOrNull;
          if (id != null) {
            _structuralIds.add(id.id);
          } else if (cls != null) {
            _structuralClasses.add(cls.name);
          } else if (tag != null) {
            _structuralTags.add(tag.name);
          } else {
            // A universal subject (`*:nth-child`, `:not(...)`, `~ *`) only
            // needs structural keys inside its ancestor constraints.
            var foundAncestor = false;
            for (final compound in sel.compounds.skip(1)) {
              for (final part in compound.parts) {
                if (part is IdSelector) {
                  _structuralAncestorIds.add(part.id);
                  foundAncestor = true;
                } else if (part is ClassSelector) {
                  _structuralAncestorClasses.add(part.name);
                  foundAncestor = true;
                } else if (part is TypeSelector) {
                  _structuralAncestorTags.add(part.name);
                  foundAncestor = true;
                }
              }
            }
            if (!foundAncestor) _structuralUniversal = true;
          }
        }
        for (var ci = 1; ci < sel.compounds.length; ci++) {
          final compound = sel.compounds[ci];
          if (!_hasStatefulPseudo(compound.parts)) continue;
          final tag = compound.parts.whereType<TypeSelector>().firstOrNull;
          final id = compound.parts.whereType<IdSelector>().firstOrNull;
          final cls = compound.parts.whereType<ClassSelector>().firstOrNull;
          if (id != null) {
            _statefulAncestorIds.add(id.id);
          } else if (cls != null) {
            _statefulAncestorClasses.add(cls.name);
          } else if (tag != null) {
            _statefulAncestorTags.add(tag.name);
          } else {
            _statefulAncestorUniversal = true;
          }
        }
        final ir = _IndexedRule(
          sel,
          rule.declarations,
          order++,
          ua,
          structural: structuralRule,
          sibling: sel.combinators.any(
            (c) =>
                c == Combinator.nextSibling ||
                c == Combinator.subsequentSibling,
          ),
        );
        if (selectorText.contains(':hover')) {
          for (final compound in sel.compounds) {
            if (!compound.parts.any(
              (p) => p is PseudoClassSelector && p.name == 'hover',
            )) {
              continue;
            }
            final hId = compound.parts.whereType<IdSelector>().firstOrNull;
            final hClass = compound.parts
                .whereType<ClassSelector>()
                .firstOrNull;
            final hTag = compound.parts.whereType<TypeSelector>().firstOrNull;
            if (hId != null) {
              _hoverById.putIfAbsent(hId.id, () => []).add(ir);
            } else if (hClass != null) {
              _hoverByClass.putIfAbsent(hClass.name, () => []).add(ir);
            } else if (hTag != null) {
              _hoverByTag.putIfAbsent(hTag.name, () => []).add(ir);
            } else {
              _hoverUniversal.add(ir);
            }
          }
        }
        final pseudo = sel.pseudoElement;
        if (pseudo != null) {
          _pseudoBuckets.putIfAbsent(pseudo, () => _RuleBuckets()).add(ir);
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
          case FontFaceRule():
            break;
        }
      }
    }

    walk(_ua.rules, true);
    for (final s in _authorSheets) {
      walk(s.rules, false);
    }
    _mediaState = _evaluateMedia();
    _expandedCache.clear();
    _clearStyleCaches();
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
    _ensureStyleCaches();
    final candidates = <_IndexedRule>[];
    void collect(Iterable<_IndexedRule>? rules) {
      if (rules == null) return;
      candidates.addAll(rules);
    }

    if (pseudo != null) {
      final pseudoBuckets = _pseudoBuckets[pseudo];
      if (pseudoBuckets != null) collect(pseudoBuckets.candidates(e));
    } else {
      collect(_universal);
      collect(_byTag[e.localName]);
      final id = e.getAttribute('id');
      if (id != null && id.isNotEmpty) collect(_byId[id]);
      final seenClasses = <String>{};
      for (final c in e.classList) {
        if (seenClasses.add(c)) collect(_byClass[c]);
      }
    }
    var structural = false;
    var sibling = false;
    for (final r in candidates) {
      structural |= r.structural;
      sibling |= r.sibling;
    }
    final cacheKey = _elementSignature(
      e,
      pseudo: pseudo,
      structural: structural,
      sibling: sibling,
    );
    final cached = useStyleCaches ? _matchedCache[cacheKey] : null;
    if (cached != null) {
      matchedCacheHits++;
      return cached;
    }
    matchedCacheMisses++;
    final matches = <_Match>[];
    for (final r in candidates) {
      candidateRules++;
      selectorEvaluations++;
      if (pseudo == null
          ? !r.selector.matches(e)
          : !r.selector.matchesPseudo(e, pseudo)) {
        continue;
      }
      for (final d in r.declarations) {
        final layer = r.isUserAgent
            ? (d.important ? _Layer.uaImportant : _Layer.uaNormal)
            : (d.important ? _Layer.authorImportant : _Layer.authorNormal);
        matches.add(_Match(layer, r.selector.specificity, r.order, d));
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
        expanded.forEach(
          (p, value) => matches.add(
            _Match(
              _Layer.authorNormal,
              Specificity.zero,
              i++,
              Declaration(p, value),
            ),
          ),
        );
      }
    }
    final inline = pseudo == null ? e.getAttribute('style') : null;
    if (inline != null && inline.trim().isNotEmpty) {
      var i = 0;
      for (final d in _inlineDeclarations(inline)) {
        matches.add(
          _Match(
            d.important ? _Layer.inlineImportant : _Layer.inlineNormal,
            Specificity.zero,
            i++,
            d,
          ),
        );
      }
    }
    matches.sort((a, b) {
      final l = a.layer.index - b.layer.index;
      if (l != 0) return l;
      final s = a.specificity.compareTo(b.specificity);
      if (s != 0) return s;
      return a.order - b.order;
    });
    final result = [for (final m in matches) m.declaration];
    if (useStyleCaches) {
      if (_matchedCache.length >= _maxCacheEntries) _matchedCache.clear();
      _matchedCache[cacheKey] = result;
    }
    return result;
  }

  // --- computation -------------------------------------------------------------

  ComputedStyle _compute(
    Element e, {
    String? pseudo,
    ComputedStyle? origin,
    List<Declaration>? extra,
  }) {
    if (!metricsEnabled) {
      return _computeInner(e, pseudo: pseudo, origin: origin, extra: extra);
    }
    final sample = _StyleSample(e)
      ..selectorStart = selectorEvaluations
      ..candidateStart = candidateRules
      ..cacheHitStart = styleCacheHits;
    sample.watch.start();
    _styleStack.add(sample);
    try {
      return _computeInner(e, pseudo: pseudo, origin: origin, extra: extra);
    } finally {
      sample.watch.stop();
      sample.totalUs = sample.watch.elapsedMicroseconds;
      sample.ownUs = sample.totalUs - sample.childUs;
      sample.selectors = selectorEvaluations - sample.selectorStart;
      sample.candidates = candidateRules - sample.candidateStart;
      sample.cacheHit = styleCacheHits > sample.cacheHitStart;
      _styleStack.removeLast();
      if (_styleStack.isNotEmpty) _styleStack.last.childUs += sample.totalUs;
      if (_styleSamples.length < 20000) _styleSamples.add(sample);
    }
  }

  Map<String, CssValue>? _expandCached(String property, String text) {
    final key = '$property\u0000$text';
    if (_expandedCache.containsKey(key)) return _expandedCache[key];
    final expanded = expandDeclaration(property, CssTokenizer(text).tokenize());
    if (_expandedCache.length >= 4096) _expandedCache.clear();
    _expandedCache[key] = expanded;
    return expanded;
  }

  ComputedStyle _computeInner(
    Element e, {
    String? pseudo,
    ComputedStyle? origin,
    List<Declaration>? extra,
  }) {
    _ensureStyleCaches();
    const profile = bool.fromEnvironment(
      'NATIVAX_RENDER_PROFILE',
      defaultValue: false,
    );
    final watch = profile ? (Stopwatch()..start()) : null;
    var _lastUs = 0;
    int lap() {
      final now = watch!.elapsedMicroseconds;
      final d = now - _lastUs;
      _lastUs = now;
      return d;
    }

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
    final parentUs = profile ? lap() : 0;
    String? styleCacheKey;
    if (extra == null) {
      styleCacheKey = _elementSignature(
        e,
        pseudo: pseudo,
        parent: parent,
        structural: _needsStructuralKey(e),
      );
      final shared = useStyleCaches ? _computedCache[styleCacheKey] : null;
      if (shared != null) {
        styleCacheHits++;
        return shared;
      }
    }
    final root = document.documentElement;
    final rootStyle = (root == null || (pseudo == null && identical(root, e)))
        ? null
        : _styles[root];

    final cascaded = cascadedDeclarations(e, pseudo: pseudo);
    if (extra != null) cascaded.addAll(extra);
    final cascadeUs = profile ? lap() : 0;
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
    final customUs = profile ? lap() : 0;

    final specified = <String, CssValue>{};
    for (final d in cascaded) {
      if (d.property.startsWith('--')) continue;
      final value = d.value;
      if (value is RawValue) {
        final text = _substituteVariables(value.text, custom);
        if (text == null) continue;
        final expanded = _expandCached(d.property, text);
        if (expanded != null) specified.addAll(expanded);
        continue;
      }
      specified[d.property] = value;
    }

    final specifiedUs = profile ? lap() : 0;
    CssValue specifiedOf(String p) {
      final spec = longhands[p]!;
      var v = specified[p];
      if (v is GlobalKeyword) {
        final inherit =
            v.name == 'inherit' || (v.name == 'unset' && spec.inherited);
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
        LengthUnit.rem =>
          (pseudo == null && identical(root, e) ? 16 : rootFont) * fs.value,
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
      } else if (p == 'font-weight' &&
          v is Keyword &&
          (v.name == 'bolder' || v.name == 'lighter')) {
        final pw = parent?.fontWeight ?? 400;
        v = NumberValue(
          v.name == 'bolder'
              ? (pw < 400 ? 400 : (pw < 600 ? 700 : 900)).toDouble()
              : (pw < 600 ? 100 : (pw < 800 ? 400 : 700)).toDouble(),
        );
      } else {
        v = absolutize(v);
      }
      if (v != longhands[p]!.initial) out[p] = v;
    }
    final longhandUs = profile ? lap() : 0;

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
    final parentIsFlex =
        parent != null && (parent.isFlexContainer || parent.isGridContainer);
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
    if (styleCacheKey != null && useStyleCaches) {
      if (_computedCache.length >= _maxCacheEntries) _computedCache.clear();
      _computedCache[styleCacheKey] = result;
    }
    if (watch != null && watch.elapsedMilliseconds >= 2) {
      final restUs = lap();
      // ignore: avoid_print
      print(
        'STYLE_SECTIONS <${e.localName}${e.id.isEmpty ? '' : '#${e.id}'}> '
        'total=${watch.elapsedMilliseconds}ms parent=${parentUs ~/ 1000}ms '
        'cascade=$cascadeUs custom=$customUs specified=$specifiedUs '
        'longhands=$longhandUs rest=$restUs',
      );
    }
    return result;
  }
}

const _snappedWidths = [
  'border-top-width',
  'border-right-width',
  'border-bottom-width',
  'border-left-width',
  'outline-width',
];

const _svgElements = {
  'svg',
  'g',
  'rect',
  'circle',
  'ellipse',
  'line',
  'polyline',
  'polygon',
  'path',
  'text',
  'tspan',
  'use',
  'symbol',
  'defs',
  'marker',
  'image',
  'foreignobject',
};

const _presentationAttributes = [
  'fill',
  'stroke',
  'stroke-width',
  'fill-opacity',
  'stroke-opacity',
  'stroke-linecap',
  'stroke-linejoin',
  'fill-rule',
  'opacity',
  'font-size',
  'font-family',
  'font-weight',
  'text-anchor',
  'dominant-baseline',
  'visibility',
  'display',
  'color',
  'stroke-dasharray',
];

/// Substitutes `var(--name[, fallback])` and common safe-area `env()` values.
/// Returns null when a reference cannot be resolved.
String? _substituteVariables(String text, Map<String, String> custom) {
  var out = text;
  // Fast path: the vast majority of declarations contain neither a custom
  // property reference nor env(); avoid lowercasing and scanning them.
  if (!out.contains('var(') && !out.contains('env(')) return out;
  for (var pass = 0; pass < 32; pass++) {
    final lower = out.toLowerCase();
    var start = -1;
    for (
      var i = lower.indexOf('var(');
      i >= 0;
      i = lower.indexOf('var(', i + 1)
    ) {
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
