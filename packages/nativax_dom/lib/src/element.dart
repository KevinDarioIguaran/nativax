import 'dart:collection';

import 'document.dart';
import 'events.dart';
import 'exceptions.dart';
import 'mutation.dart';
import 'node.dart';
import 'selectors.dart';
import 'serializer.dart';

/// Elements that never have children or an end tag.
const Set<String> voidElements = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'source', 'track', 'wbr', //
};

final RegExp _invalidNameChars = RegExp(r'''[\s"'>/=<\x00]''');

/// Throws `InvalidCharacterError` for names the parser could never produce.
void validateName(String name) {
  if (name.isEmpty || _invalidNameChars.hasMatch(name)) {
    throw DomException('InvalidCharacterError', 'invalid name "$name"');
  }
}

class Element extends Node {
  Element(Document doc, String localName)
      : localName = localName.toLowerCase(),
        super(doc);

  /// Lower-case tag name (`div`).
  final String localName;

  final LinkedHashMap<String, String> _attributes = LinkedHashMap();

  // Form-control state ("dirty" values that diverge from attributes).
  String? _value;
  bool? _checked;
  int? _selectedIndex;

  @override
  NodeType get nodeType => NodeType.element;

  /// Upper-case tag name (`DIV`), as in HTML documents.
  String get tagName => localName.toUpperCase();

  @override
  String get nodeName => tagName;

  // --- attributes -----------------------------------------------------------

  UnmodifiableMapView<String, String> get attributes =>
      UnmodifiableMapView(_attributes);

  String? getAttribute(String name) => _attributes[name.toLowerCase()];

  bool hasAttribute(String name) => _attributes.containsKey(name.toLowerCase());

  void setAttribute(String name, String value) {
    validateName(name);
    final key = name.toLowerCase();
    final old = _attributes[key];
    if (old == value) return;
    _attributes[key] = value;
    ownerDocument.notify(MutationRecord.attribute(this, key, old));
  }

  void removeAttribute(String name) {
    final key = name.toLowerCase();
    if (!_attributes.containsKey(key)) return;
    final old = _attributes.remove(key);
    ownerDocument.notify(MutationRecord.attribute(this, key, old));
  }

  bool toggleAttribute(String name, [bool? force]) {
    final present = hasAttribute(name);
    final want = force ?? !present;
    if (want && !present) setAttribute(name, '');
    if (!want && present) removeAttribute(name);
    return want;
  }

  /// Sets an attribute while building a parsed tree; no mutation record.
  void setParsedAttribute(String name, String value) {
    _attributes.putIfAbsent(name.toLowerCase(), () => value);
  }

  String get id => _attributes['id'] ?? '';
  set id(String value) => setAttribute('id', value);

  String get className => _attributes['class'] ?? '';
  set className(String value) => setAttribute('class', value);

  late final ClassList classList = ClassList._(this);

  // --- form controls -------------------------------------------------------

  bool get isFormControl =>
      localName == 'input' || localName == 'textarea' || localName == 'select';

  String get inputType => (getAttribute('type') ?? 'text').toLowerCase();

  bool get disabled => hasAttribute('disabled');

  /// Current value. Inputs default to the `value` attribute, textareas to
  /// their text, selects to the selected option's value.
  String get value {
    switch (localName) {
      case 'select':
        final option = selectedOption;
        return option == null ? '' : option.optionValue;
      case 'textarea':
        return _value ?? textContent;
      case 'option':
        return optionValue;
      default:
        if (inputType == 'checkbox' || inputType == 'radio') {
          return getAttribute('value') ?? 'on';
        }
        return _value ?? getAttribute('value') ?? '';
    }
  }

  set value(String v) {
    if (localName == 'select') {
      final options = this.options;
      final index = options.indexWhere((o) => o.optionValue == v);
      selectedIndex = index;
      return;
    }
    if (localName == 'option') {
      setAttribute('value', v);
      return;
    }
    if (_value == v) return;
    _value = v;
    ownerDocument.notify(MutationRecord.property(this, 'value'));
  }

  bool get checked => _checked ?? hasAttribute('checked');

  set checked(bool v) {
    if (checked == v && _checked != null) return;
    _checked = v;
    // Radio groups: checking one unchecks its siblings with the same name.
    if (v && localName == 'input' && inputType == 'radio') {
      final name = getAttribute('name');
      final scope = closest('form') ?? ownerDocument.documentElement;
      if (name != null && scope != null) {
        for (final other in scope.querySelectorAll('input[type=radio]')) {
          if (!identical(other, this) && other.getAttribute('name') == name) {
            other.checked = false;
          }
        }
      }
    }
    ownerDocument.notify(MutationRecord.property(this, 'checked'));
  }

  /// `<option>` elements of a `<select>`, including inside `<optgroup>`.
  List<Element> get options => descendants
      .whereType<Element>()
      .where((e) => e.localName == 'option')
      .toList();

  String get optionValue => getAttribute('value') ?? textContent.trim();

  int get selectedIndex {
    final opts = options;
    if (opts.isEmpty) return -1;
    final dirty = _selectedIndex;
    if (dirty != null) return dirty < opts.length ? dirty : -1;
    final i = opts.indexWhere((o) => o.hasAttribute('selected'));
    return i >= 0 ? i : 0;
  }

  set selectedIndex(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    ownerDocument.notify(MutationRecord.property(this, 'selectedIndex'));
  }

  Element? get selectedOption {
    final i = selectedIndex;
    return i < 0 ? null : options[i];
  }

  // --- activation ----------------------------------------------------------

  /// Simulates a click with the element's activation behavior, used both by
  /// `element.click()` in scripts and by taps in the renderer:
  ///
  /// * disabled form controls and buttons ignore clicks;
  /// * checkboxes toggle (and radios check) before dispatch, revert if the
  ///   click is canceled, and otherwise fire `input` and `change`;
  /// * submit buttons submit their form (see [requestSubmit]);
  /// * links call [Document.onNavigate].
  void click() {
    final isButtonLike = localName == 'button' || isFormControl;
    if (isButtonLike && disabled) return;
    final isToggle = localName == 'input' && (inputType == 'checkbox' || inputType == 'radio');
    final wasChecked = checked;
    if (isToggle) checked = inputType == 'checkbox' ? !wasChecked : true;
    final notCanceled = dispatchEvent(Event('click', bubbles: true, cancelable: true)..isTrusted = true);
    if (isToggle) {
      if (!notCanceled) {
        checked = wasChecked;
      } else if (checked != wasChecked) {
        dispatchEvent(Event('input', bubbles: true)..isTrusted = true);
        dispatchEvent(Event('change', bubbles: true)..isTrusted = true);
      }
      return;
    }
    if (!notCanceled) return;
    final submits = (localName == 'button' && (getAttribute('type') ?? 'submit').toLowerCase() == 'submit') ||
        (localName == 'input' && (inputType == 'submit' || inputType == 'image'));
    if (submits) {
      closest('form')?.requestSubmit();
      return;
    }
    final href = getAttribute('href');
    if (localName == 'a' && href != null) ownerDocument.onNavigate?.call(href, this);
  }

  /// Fires a cancelable `submit` event at this form; when not canceled,
  /// reports the submission through [Document.onSubmit].
  void requestSubmit() {
    if (localName != 'form') return;
    final ok = dispatchEvent(Event('submit', bubbles: true, cancelable: true)..isTrusted = true);
    if (ok) ownerDocument.onSubmit?.call(this);
  }

  /// Name/value pairs of the form's successful controls, in tree order.
  List<(String, String)> get formData {
    final out = <(String, String)>[];
    for (final e in descendants.whereType<Element>()) {
      final name = e.getAttribute('name');
      if (name == null || name.isEmpty || e.disabled || !e.isFormControl) continue;
      if (e.localName == 'input') {
        final t = e.inputType;
        if (t == 'submit' || t == 'button' || t == 'reset' || t == 'image') continue;
        if ((t == 'checkbox' || t == 'radio') && !e.checked) continue;
      }
      out.add((name, e.value));
    }
    return out;
  }

  // --- selectors -----------------------------------------------------------

  bool matches(String selectors) =>
      SelectorList.parse(selectors).matches(this);

  Element? closest(String selectors) {
    final list = SelectorList.parse(selectors);
    for (Element? e = this; e != null; e = e.parentElement) {
      if (list.matches(e)) return e;
    }
    return null;
  }

  Element? querySelector(String selectors) =>
      SelectorList.parse(selectors).first(this);

  List<Element> querySelectorAll(String selectors) =>
      SelectorList.parse(selectors).all(this);

  List<Element> getElementsByTagName(String name) {
    final n = name.toLowerCase();
    return descendants
        .whereType<Element>()
        .where((e) => n == '*' || e.localName == n)
        .toList();
  }

  List<Element> getElementsByClassName(String names) {
    final wanted = names.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (wanted.isEmpty) return const [];
    return descendants
        .whereType<Element>()
        .where((e) => wanted.every(e.classList.contains))
        .toList();
  }

  // --- serialization -------------------------------------------------------

  String get innerHtml => serializeChildren(this);
  String get outerHtml => serializeNode(this);

  Element? get firstElementChild => children.firstOrNull;
  Element? get lastElementChild => children.lastOrNull;

  Element? get nextElementSibling {
    for (var n = nextSibling; n != null; n = n.nextSibling) {
      if (n is Element) return n;
    }
    return null;
  }

  Element? get previousElementSibling {
    for (var n = previousSibling; n != null; n = n.previousSibling) {
      if (n is Element) return n;
    }
    return null;
  }

  @override
  Element cloneNode({bool deep = false}) {
    final copy = ownerDocument.createElement(localName);
    copy._attributes.addAll(_attributes);
    copy._value = _value;
    copy._checked = _checked;
    copy._selectedIndex = _selectedIndex;
    if (deep) {
      for (final c in rawChildren) {
        copy.appendParsed(c.cloneNode(deep: true));
      }
    }
    return copy;
  }

  @override
  String toString() => '<$localName${id.isEmpty ? '' : '#$id'}>';
}

/// Live view over the `class` attribute.
class ClassList extends IterableBase<String> {
  ClassList._(this._element);
  final Element _element;

  List<String> get _tokens => _element.className
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  @override
  Iterator<String> get iterator => _tokens.iterator;

  @override
  bool contains(Object? token) => _tokens.contains(token);

  void _validate(String token) {
    if (token.isEmpty) {
      throw DomException('SyntaxError', 'empty class token');
    }
    if (token.contains(RegExp(r'\s'))) {
      throw DomException('InvalidCharacterError', 'class token has spaces');
    }
  }

  void add(Iterable<String> tokens) {
    tokens.forEach(_validate);
    final current = _tokens;
    final next = [...current, ...tokens.where((t) => !current.contains(t))];
    if (next.length != current.length) _element.className = next.join(' ');
  }

  void remove(Iterable<String> tokens) {
    tokens.forEach(_validate);
    final current = _tokens;
    final next = current.where((t) => !tokens.contains(t)).toList();
    if (next.length != current.length) _element.className = next.join(' ');
  }

  bool toggle(String token, [bool? force]) {
    final want = force ?? !contains(token);
    want ? add([token]) : remove([token]);
    return want;
  }

  bool replace(String oldToken, String newToken) {
    _validate(oldToken);
    _validate(newToken);
    final current = _tokens;
    final i = current.indexOf(oldToken);
    if (i < 0) return false;
    current[i] = newToken;
    _element.className = current.toSet().join(' ');
    return true;
  }
}
