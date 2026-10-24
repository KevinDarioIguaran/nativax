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
final RegExp _asciiUpperRe = RegExp('[A-Z]');
final RegExp _asciiLowerRe = RegExp('[a-z]');

/// Throws `InvalidCharacterError` for names the parser could never produce.
void validateName(String name) {
  if (name.isEmpty || _invalidNameChars.hasMatch(name)) {
    throw DomException('InvalidCharacterError', 'invalid name "$name"');
  }
}

String _asciiLower(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5a) {
      return s.replaceAllMapped(_asciiUpperRe, (m) => m[0]!.toLowerCase());
    }
  }
  return s;
}

String _asciiUpper(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x61 && c <= 0x7a) {
      return s.replaceAllMapped(_asciiLowerRe, (m) => m[0]!.toUpperCase());
    }
  }
  return s;
}

class Element extends Node {
  Element(Document doc, String localName)
    : localName = _asciiLower(localName),
      super(doc);

  /// Lower-case tag name (`div`).
  final String localName;

  final LinkedHashMap<String, String> _attributes = LinkedHashMap();
  final Map<String, String?> _attributeNamespaces = {};
  final Map<String, String> _attributeNames = {};

  // Form-control state ("dirty" values that diverge from attributes).
  String? _value;
  bool? _checked;
  int? _selectedIndex;

  @override
  NodeType get nodeType => NodeType.element;

  /// Upper-case tag name (`DIV`), as in HTML documents.
  String get tagName => _asciiUpper(localName);

  @override
  String get nodeName => tagName;

  // --- attributes -----------------------------------------------------------

  UnmodifiableMapView<String, String> get attributes => UnmodifiableMapView({
        for (final entry in _attributes.entries)
          _nameOf(entry.key): entry.value,
      });

  Map<String, String?> get attributeNamespaces =>
      Map.unmodifiable(_attributeNamespaces);

  List<Map<String, Object?>> get attributeEntries => [
        for (final entry in _attributes.entries)
          {
            'name': _nameOf(entry.key),
            'localName': _attributeNamespaces[entry.key] == null
                ? _nameOf(entry.key)
                : localNameOf(_nameOf(entry.key)),
            'prefix': _attributeNamespaces[entry.key] != null &&
                    _nameOf(entry.key).contains(':')
                ? _nameOf(entry.key).split(':').first
                : null,
            'namespaceURI': _attributeNamespaces[entry.key],
            'value': entry.value,
          }
      ];

  String _nameOf(String key) => _attributeNames[key] ?? key;

  String? _keyFor(String name) {
    final lower = _asciiLower(name);
    final direct = _attributes.containsKey(name) ? name : null;
    if (direct != null) return direct;
    if (name == lower) {
      for (final key in _attributes.keys) {
        if (key == lower) return key;
        if (_nameOf(key) == lower) return key;
      }
      return null;
    }
    for (final key in _attributes.keys) {
      if (_asciiLower(_nameOf(key)) == lower) return key;
    }
    // No fallback to local name: `getAttribute('lang')` must not match
    // `xml:lang`, and namespaced attributes require getAttributeNS.
    return null;
  }

  String? getAttribute(String name) {
    final key = _keyFor(name);
    return key == null ? null : _attributes[key];
  }

  bool hasAttribute(String name) => _keyFor(name) != null;

  void setAttribute(String name, String value, {bool force = false}) {
    validateName(name);
    final existing = _keyFor(name);
    final key = existing ?? _asciiLower(name);
    final old = _attributes[key];
    if (old == value && !force && key != 'id' && key != 'class') return;
    _attributes[key] = value;
    _attributeNames[key] = _asciiLower(name);
    if (existing == null) _attributeNamespaces.remove(key);
    ownerDocument.notify(MutationRecord.attribute(this, localNameOf(_nameOf(key)), old));
  }

  String? getAttributeNS(String? namespace, String localName) {
    final wantNs = namespace == null || namespace.isEmpty ? null : namespace;
    for (final entry in _attributes.entries) {
      final ns = _attributeNamespaces[entry.key];
      final actualLocal = ns == null
          ? _nameOf(entry.key)
          : localNameOf(_nameOf(entry.key));
      if ((ns == wantNs) && actualLocal == localName) {
        return entry.value;
      }
    }
    return null;
  }

  void setAttributeNS(String? namespace, String qualifiedName, String value) {
    validateName(qualifiedName);
    final ns = namespace == null || namespace.isEmpty ? null : namespace;
    final local = localNameOf(qualifiedName);
    String? key;
    for (final entry in _attributes.keys) {
      if (_attributeNamespaces[entry] == ns &&
          localNameOf(_nameOf(entry)) == local) {
        key = entry;
        break;
      }
    }
    key ??= _attributes.keys.any((k) => _nameOf(k) == qualifiedName)
        ? '$qualifiedName\u0000${ns ?? ''}'
        : qualifiedName;
    final old = _attributes[key];
    _attributes[key] = value;
    _attributeNames[key] = qualifiedName;
    _attributeNamespaces[key] = ns;
    ownerDocument.notify(
        MutationRecord.attribute(this, local, old, namespace: ns));
  }

  void removeAttributeNS(String? namespace, String localName) {
    String? key;
    for (final entry in _attributes.entries) {
      final ns = _attributeNamespaces[entry.key];
      final actualLocal =
          ns == null ? _nameOf(entry.key) : localNameOf(_nameOf(entry.key));
      if (ns == namespace && actualLocal == localName) {
        key = entry.key;
        break;
      }
    }
    if (key == null) return;
    final old = _attributes.remove(key);
    _attributeNames.remove(key);
    final ns = _attributeNamespaces.remove(key);
    ownerDocument.notify(
        MutationRecord.attribute(this, localName, old, namespace: ns));
  }

  String localNameOf(String name) =>
      name.contains(':') ? name.split(':').last : name;

  void removeAttribute(String name) {
    final key = _keyFor(name);
    if (key == null) return;
    final old = _attributes.remove(key);
    _attributeNames.remove(key);
    _attributeNamespaces.remove(key);
    ownerDocument.notify(MutationRecord.attribute(this, localNameOf(_nameOf(key)), old));
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
    _attributes.putIfAbsent(_asciiLower(name), () => value);
  }

  String get id => getAttribute('id') ?? '';
  set id(String value) => setAttribute('id', value, force: true);

  String get className => getAttribute('class') ?? '';
  set className(String value) => setAttribute('class', value, force: true);

  late final ClassList classList = ClassList._(this);
  set classList(Object? _) {}

  // --- form controls -------------------------------------------------------

  bool get isFormControl =>
      localName == 'input' || localName == 'textarea' || localName == 'select';

  String get inputType => (getAttribute('type') ?? 'text').toLowerCase();

  bool get disabled {
    if (hasAttribute('disabled')) return true;
    final fieldset = closest('fieldset[disabled]');
    if (fieldset == null) return false;
    for (final c in fieldset.children) {
      if (c.localName == 'legend') return !c.contains(this);
    }
    return true;
  }

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

  // Selectedness of `<option>` in a `<select multiple>`.
  bool? _optionSelected;

  /// Whether this `<option>` is selected.
  bool get optionSelected {
    final select = closest('select');
    if (select == null) return _optionSelected ?? hasAttribute('selected');
    if (select.hasAttribute('multiple'))
      return _optionSelected ?? hasAttribute('selected');
    return identical(select.selectedOption, this);
  }

  set optionSelected(bool v) {
    final select = closest('select');
    if (select != null && !select.hasAttribute('multiple')) {
      if (v) select.selectedIndex = select.options.indexOf(this);
      return;
    }
    if (_optionSelected == v) return;
    _optionSelected = v;
    ownerDocument.notify(
      MutationRecord.property(select ?? this, 'selectedOptions'),
    );
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
  void click({bool trusted = false, Map<String, Object?> detail = const {}}) {
    final isButtonLike = localName == 'button' || isFormControl;
    if (isButtonLike && disabled) return;
    final isToggle =
        localName == 'input' &&
        (inputType == 'checkbox' || inputType == 'radio');
    final wasChecked = checked;
    if (isToggle) checked = inputType == 'checkbox' ? !wasChecked : true;
    final notCanceled = dispatchEvent(
      Event('click', bubbles: true, cancelable: true, detail: detail)
        ..isTrusted = trusted,
    );
    if (isToggle) {
      if (!notCanceled) {
        checked = wasChecked;
      } else if (checked != wasChecked) {
        dispatchEvent(Event('input', bubbles: true)..isTrusted = trusted);
        dispatchEvent(Event('change', bubbles: true)..isTrusted = trusted);
      }
      return;
    }
    if (!notCanceled) return;
    final submits =
        (localName == 'button' &&
            (getAttribute('type') ?? 'submit').toLowerCase() == 'submit') ||
        (localName == 'input' &&
            (inputType == 'submit' || inputType == 'image'));
    if (submits) {
      closest('form')?.requestSubmit(trusted: trusted);
      return;
    }
    if (localName == 'summary') {
      final details = parentElement;
      if (details != null &&
          details.localName == 'details' &&
          identical(
            details.children.firstWhere(
              (c) => c.localName == 'summary',
              orElse: () => this,
            ),
            this,
          )) {
        details.toggleAttribute('open');
        details.dispatchEvent(Event('toggle')..isTrusted = true);
      }
      return;
    }
    if (localName == 'input' && inputType == 'reset' ||
        localName == 'button' &&
            (getAttribute('type') ?? '').toLowerCase() == 'reset') {
      closest('form')?.reset();
      return;
    }
    final href = getAttribute('href');
    if (localName == 'a' && href != null)
      ownerDocument.onNavigate?.call(href, this);
  }

  /// Resets a form's controls to their default values.
  void reset() {
    if (localName != 'form') return;
    if (!dispatchEvent(
      Event('reset', bubbles: true, cancelable: true)..isTrusted = true,
    ))
      return;
    for (final e in descendants.whereType<Element>()) {
      if (!e.isFormControl) continue;
      e._value = null;
      e._checked = null;
      e._selectedIndex = null;
      e.customValidity = '';
      e.userInteracted = false;
      for (final o in e.options) {
        o._optionSelected = null;
      }
      ownerDocument.notify(MutationRecord.property(e, 'value'));
    }
  }

  // --- dialog --------------------------------------------------------------

  /// `HTMLDialogElement.returnValue`.
  String returnValue = '';

  /// `dialog.show()`: opens without blocking the page.
  void show() {
    if (localName != 'dialog' || hasAttribute('open')) return;
    setAttribute('open', '');
  }

  /// `dialog.showModal()`: opens in the top layer with a backdrop.
  void showModal() {
    if (localName != 'dialog') return;
    if (hasAttribute('open')) {
      if (ownerDocument.modalElements.contains(this)) return;
      throw DomException(
        'InvalidStateError',
        'The dialog is already open as a non-modal dialog.',
      );
    }
    if (!isConnected)
      throw DomException('InvalidStateError', 'The dialog is not connected.');
    ownerDocument.modalElements.add(this);
    setAttribute('open', '');
    ownerDocument.notifyStateChanged(this);
    // Focus the first focusable descendant (autofocus first).
    final target =
        querySelector('[autofocus]') ??
        querySelector(
          'button, input:not([type=hidden]), select, textarea, a[href], [tabindex]',
        );
    if (target != null) ownerDocument.requestFocus(target);
  }

  /// `dialog.close(returnValue)`.
  void close([String? result]) {
    if (localName != 'dialog' || !hasAttribute('open')) return;
    if (result != null) returnValue = result;
    final wasModal = ownerDocument.modalElements.remove(this);
    removeAttribute('open');
    if (wasModal) ownerDocument.notifyStateChanged(this);
    dispatchEvent(Event('close')..isTrusted = true);
  }

  /// Escape on a modal dialog: fires `cancel` and closes unless prevented.
  void requestCancel() {
    if (localName != 'dialog' || !hasAttribute('open')) return;
    if (dispatchEvent(Event('cancel', cancelable: true)..isTrusted = true))
      close();
  }

  /// Fires a cancelable `submit` event at this form; when not canceled,
  /// reports the submission through [Document.onSubmit].
  void requestSubmit({bool trusted = false}) {
    if (localName != 'form') return;
    final ok = dispatchEvent(
      Event('submit', bubbles: true, cancelable: true)..isTrusted = trusted,
    );
    if (ok) ownerDocument.onSubmit?.call(this);
  }

  // --- constraint validation -----------------------------------------------

  /// Message set by `setCustomValidity`.
  String customValidity = '';

  /// Set once the user edited or the form was submitted (`:user-invalid`).
  bool userInteracted = false;

  /// Whether this element is a candidate for constraint validation.
  bool get willValidate {
    if (!isFormControl || disabled) return false;
    if (localName != 'select' && hasAttribute('readonly')) return false;
    if (localName == 'input' &&
        const {
          'hidden',
          'button',
          'reset',
          'submit',
          'image',
        }.contains(inputType)) {
      return false;
    }
    for (Element? p = parentElement; p != null; p = p.parentElement) {
      if (p.localName == 'datalist') return false;
    }
    return true;
  }

  ValidityState get validity => ValidityState.of(this);

  bool checkValidity() {
    if (localName == 'form' || localName == 'fieldset') {
      var ok = true;
      for (final e in descendants.whereType<Element>()) {
        if (e.willValidate && !e.validity.valid) {
          ok = false;
          e.dispatchEvent(Event('invalid', cancelable: true)..isTrusted = true);
        }
      }
      return ok;
    }
    if (!willValidate || validity.valid) return true;
    dispatchEvent(Event('invalid', cancelable: true)..isTrusted = true);
    return false;
  }

  String get validationMessage {
    if (!willValidate) return '';
    final v = validity;
    if (v.customError) return customValidity;
    if (v.valueMissing) {
      return inputType == 'checkbox' && localName == 'input'
          ? 'Please check this box if you want to proceed.'
          : localName == 'select'
          ? 'Please select an item in the list.'
          : 'Please fill out this field.';
    }
    if (v.typeMismatch) {
      return inputType == 'email'
          ? 'Please enter an email address.'
          : 'Please enter a URL.';
    }
    if (v.patternMismatch) return 'Please match the requested format.';
    if (v.tooShort) {
      return 'Please lengthen this text to ${getAttribute('minlength')} characters or more '
          '(you are currently using ${value.length} characters).';
    }
    if (v.tooLong) return 'Please shorten this text.';
    if (v.rangeUnderflow)
      return 'Value must be greater than or equal to ${getAttribute('min')}.';
    if (v.rangeOverflow)
      return 'Value must be less than or equal to ${getAttribute('max')}.';
    if (v.stepMismatch) return 'Please enter a valid value.';
    if (v.badInput) return 'Please enter a number.';
    return '';
  }

  /// Name/value pairs of the form's successful controls, in tree order.
  List<(String, String)> get formData {
    final out = <(String, String)>[];
    for (final e in descendants.whereType<Element>()) {
      final name = e.getAttribute('name');
      if (name == null || name.isEmpty || e.disabled || !e.isFormControl)
        continue;
      if (e.localName == 'input') {
        final t = e.inputType;
        if (t == 'submit' || t == 'button' || t == 'reset' || t == 'image')
          continue;
        if ((t == 'checkbox' || t == 'radio') && !e.checked) continue;
      }
      out.add((name, e.value));
    }
    return out;
  }

  // --- selectors -----------------------------------------------------------

  bool matches(String selectors) => SelectorList.parse(selectors).matches(this, this);

  Element? closest(String selectors) {
    final list = SelectorList.parse(selectors);
    for (Element? e = this; e != null; e = e.parentElement) {
      if (list.matches(e, this)) return e;
    }
    return null;
  }

  Element? querySelector(String selectors) {
    final list = SelectorList.parse(selectors);
    if (selectors.contains(':scope') && list.matches(this, this)) return this;
    return list.first(this, this);
  }

  List<Element> querySelectorAll(String selectors) {
    final list = SelectorList.parse(selectors);
    final found = list.all(this, this);
    if (selectors.contains(':scope') && list.matches(this, this)) {
      found.insert(0, this);
    }
    return found;
  }

  List<Element> getElementsByTagName(String name) {
    final n = name.toLowerCase();
    return descendants
        .whereType<Element>()
        .where((e) => n == '*' || e.localName == n)
        .toList();
  }

  List<Element> getElementsByClassName(String names) {
    final wanted = names.split(RegExp(r'[\t\n\f\r ]+')).where((s) => s.isNotEmpty);
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
    copy._attributeNames.addAll(_attributeNames);
    copy._attributeNamespaces.addAll(_attributeNamespaces);
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

/// The constraint validation state of a form control (HTML §4.10.20).
class ValidityState {
  const ValidityState({
    this.valueMissing = false,
    this.typeMismatch = false,
    this.patternMismatch = false,
    this.tooLong = false,
    this.tooShort = false,
    this.rangeUnderflow = false,
    this.rangeOverflow = false,
    this.stepMismatch = false,
    this.badInput = false,
    this.customError = false,
  });

  final bool valueMissing;
  final bool typeMismatch;
  final bool patternMismatch;
  final bool tooLong;
  final bool tooShort;
  final bool rangeUnderflow;
  final bool rangeOverflow;
  final bool stepMismatch;
  final bool badInput;
  final bool customError;

  bool get valid =>
      !(valueMissing ||
          typeMismatch ||
          patternMismatch ||
          tooLong ||
          tooShort ||
          rangeUnderflow ||
          rangeOverflow ||
          stepMismatch ||
          badInput ||
          customError);

  static final RegExp _email = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
  );

  factory ValidityState.of(Element e) {
    if (!e.isFormControl) {
      return ValidityState(customError: e.customValidity.isNotEmpty);
    }
    final type = e.localName == 'input' ? e.inputType : e.localName;
    final value = e.value;
    final required = e.hasAttribute('required');
    var missing = false;
    if (required) {
      if (type == 'checkbox') {
        missing = !e.checked;
      } else if (type == 'radio') {
        final name = e.getAttribute('name');
        final scope = e.closest('form') ?? e.ownerDocument.documentElement;
        missing =
            !(e.checked ||
                (name != null &&
                    (scope
                            ?.querySelectorAll('input[type=radio]')
                            .any(
                              (r) =>
                                  r.getAttribute('name') == name && r.checked,
                            ) ??
                        false)));
      } else if (e.localName == 'select') {
        missing = value.isEmpty;
      } else {
        missing = value.isEmpty;
      }
    }
    var typeMismatch = false;
    if (value.isNotEmpty) {
      if (type == 'email') {
        final parts = e.hasAttribute('multiple') ? value.split(',') : [value];
        typeMismatch = parts.any((p) => !_email.hasMatch(p.trim()));
      } else if (type == 'url') {
        final uri = Uri.tryParse(value);
        typeMismatch = uri == null || !uri.hasScheme || uri.scheme.isEmpty;
      }
    }
    var patternMismatch = false;
    final pattern = e.getAttribute('pattern');
    if (pattern != null &&
        value.isNotEmpty &&
        const {
          'text',
          'search',
          'url',
          'tel',
          'email',
          'password',
        }.contains(type)) {
      try {
        patternMismatch = !RegExp(
          '^(?:$pattern)\$',
          unicode: true,
        ).hasMatch(value);
      } on FormatException {
        patternMismatch = false;
      }
    }
    final textual =
        e.localName == 'textarea' ||
        const {
          'text',
          'search',
          'url',
          'tel',
          'email',
          'password',
        }.contains(type);
    final dirty = e.userInteracted;
    final minLength = int.tryParse(e.getAttribute('minlength') ?? '');
    final maxLength = int.tryParse(e.getAttribute('maxlength') ?? '');
    // Length constraints only apply to user-edited values.
    final tooShort =
        textual &&
        dirty &&
        minLength != null &&
        value.isNotEmpty &&
        value.length < minLength;
    final tooLong =
        textual && dirty && maxLength != null && value.length > maxLength;
    var underflow = false, overflow = false, step = false, bad = false;
    if (const {'number', 'range'}.contains(type) && value.isNotEmpty) {
      final n = num.tryParse(value);
      if (n == null) {
        bad = true;
      } else {
        final min = num.tryParse(e.getAttribute('min') ?? '');
        final max = num.tryParse(e.getAttribute('max') ?? '');
        underflow = min != null && n < min;
        overflow = max != null && n > max;
        final stepAttr = e.getAttribute('step');
        final stepValue = stepAttr == 'any'
            ? null
            : num.tryParse(stepAttr ?? '1');
        if (stepValue != null && stepValue > 0) {
          final base = min ?? 0;
          final q = (n - base) / stepValue;
          step = (q - q.round()).abs() > 1e-9;
        }
      }
    }
    return ValidityState(
      valueMissing: missing,
      typeMismatch: typeMismatch,
      patternMismatch: patternMismatch,
      tooLong: tooLong,
      tooShort: tooShort,
      rangeUnderflow: underflow,
      rangeOverflow: overflow,
      stepMismatch: step,
      badInput: bad,
      customError: e.customValidity.isNotEmpty,
    );
  }
}

/// Live view over the `class` attribute.
class ClassList extends IterableBase<String> {
  ClassList._(this._element);
  final Element _element;

  static final RegExp _whitespace = RegExp(r'[\t\n\f\r ]');
  List<String>? _tokenCache;
  String? _tokenSource;

  List<String> get _tokens {
    final source = _element.className;
    if (identical(source, _tokenSource)) return _tokenCache!;
    final out = <String>[];
    final seen = <String>{};
    var start = -1;
    for (var i = 0; i < source.length; i++) {
      final c = source.codeUnitAt(i);
      final space = c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0c || c == 0x0d;
      if (space) {
        if (start >= 0) {
          final token = source.substring(start, i);
          if (seen.add(token)) out.add(token);
          start = -1;
        }
      } else if (start < 0) {
        start = i;
      }
    }
    if (start >= 0) {
      final token = source.substring(start);
      if (seen.add(token)) out.add(token);
    }
    _tokenSource = source;
    _tokenCache = out;
    return out;
  }

  @override
  Iterator<String> get iterator => _tokens.iterator;

  @override
  bool contains(Object? token) => _tokens.contains(token);

  void _validate(String token) {
    if (token.isEmpty) {
      throw DomException('SyntaxError', 'empty class token');
    }
    if (token.contains(_whitespace)) {
      throw DomException('InvalidCharacterError', 'class token has spaces');
    }
  }

  void add(Iterable<String> tokens) {
    final args = tokens.toList();
    args.forEach(_validate);
    final before = _element.getAttribute('class');
    final current = _tokens;
    final added = <String>{};
    final next = [
      ...current,
      ...args.where((t) => !current.contains(t) && added.add(t)),
    ];
    if (before != null || next.isNotEmpty) _element.className = next.join(' ');
  }

  void remove(Iterable<String> tokens) {
    final args = tokens.toList();
    args.forEach(_validate);
    final before = _element.getAttribute('class');
    final current = _tokens;
    final next = current.where((t) => !args.contains(t)).toList();
    if (before != null) _element.className = next.join(' ');
  }

  bool toggle(String token, [bool? force]) {
    _validate(token);
    final present = contains(token);
    final want = force ?? !present;
    if (want == present) return want;
    final current = _tokens;
    if (want) {
      current.add(token);
    } else {
      current.removeWhere((t) => t == token);
    }
    _element.className = current.join(' ');
    return want;
  }

  bool replace(String oldToken, String newToken) {
    if (oldToken.isEmpty || newToken.isEmpty) {
      throw DomException('SyntaxError', 'empty class token');
    }
    _validate(oldToken);
    _validate(newToken);
    final current = _tokens;
    final i = current.indexOf(oldToken);
    if (i < 0) return false;
    final before = _element.className;
    current[i] = newToken;
    final seen = <String>{};
    final value = current.where(seen.add).join(' ');
    if (value == before) {
      _element.setAttribute('class', value, force: true);
    } else {
      _element.className = value;
    }
    return true;
  }
}
