import 'package:nativa_dom/nativa_dom.dart';
import 'package:test/test.dart';

/// Builds `<html><body><div id=a class="x y"><p>one</p><p class=x>two</p>
/// </div><ul><li>1</li><li>2</li><li>3</li><li>4</li></ul></body></html>`.
Document sample() {
  final d = Document();
  final html = d.createElement('html');
  final body = d.createElement('body');
  d.appendChild(html);
  html.appendChild(d.createElement('head'));
  html.appendChild(body);
  final div = d.createElement('div')
    ..setAttribute('id', 'a')
    ..setAttribute('class', 'x y');
  body.appendChild(div);
  div.appendChild(d.createElement('p')..textContent = 'one');
  div.appendChild(d.createElement('p')
    ..className = 'x'
    ..textContent = 'two');
  final ul = d.createElement('ul');
  body.appendChild(ul);
  for (var i = 1; i <= 4; i++) {
    ul.appendChild(d.createElement('li')..textContent = '$i');
  }
  return d;
}

void main() {
  group('tree', () {
    test('structure and navigation', () {
      final d = sample();
      expect(d.documentElement!.localName, 'html');
      expect(d.body!.children.map((e) => e.localName), ['div', 'ul']);
      final div = d.getElementById('a')!;
      expect(div.parentElement, d.body);
      expect(div.nextElementSibling!.localName, 'ul');
      expect(div.firstElementChild!.textContent, 'one');
      expect(d.body!.textContent, 'onetwo1234');
      expect(div.isConnected, isTrue);
    });

    test('insertBefore, removeChild, replaceChild', () {
      final d = sample();
      final ul = d.querySelector('ul')!;
      final first = ul.firstElementChild!;
      final x = d.createElement('li')..textContent = '0';
      ul.insertBefore(x, first);
      expect(ul.children.map((e) => e.textContent), ['0', '1', '2', '3', '4']);
      ul.removeChild(x);
      expect(x.parentNode, isNull);
      expect(x.isConnected, isFalse);
      final y = d.createElement('li')..textContent = 'Y';
      ul.replaceChild(y, first);
      expect(ul.children.map((e) => e.textContent), ['Y', '2', '3', '4']);
    });

    test('moving a node removes it from its old parent', () {
      final d = sample();
      final li = d.querySelector('li')!;
      d.getElementById('a')!.appendChild(li);
      expect(d.querySelectorAll('ul > li').length, 3);
      expect(d.getElementById('a')!.lastElementChild, li);
    });

    test('fragments insert their children', () {
      final d = sample();
      final f = d.createDocumentFragment()
        ..appendChild(d.createElement('b'))
        ..appendChild(d.createTextNode('t'));
      d.body!.appendChild(f);
      expect(f.childNodes, isEmpty);
      expect(d.body!.lastChild!.nodeName, '#text');
    });

    test('hierarchy errors', () {
      final d = sample();
      final div = d.getElementById('a')!;
      expect(() => div.firstElementChild!.appendChild(div),
          throwsA(isA<DomException>().having((e) => e.name, 'name', 'HierarchyRequestError')));
      expect(() => d.createTextNode('t').appendChild(d.createElement('b')),
          throwsA(isA<DomException>()));
      expect(() => div.removeChild(d.body!),
          throwsA(isA<DomException>().having((e) => e.name, 'name', 'NotFoundError')));
      final other = Document();
      final adopted = other.createElement('i');
      div.appendChild(adopted);
      expect(adopted.ownerDocument, d);
      expect(adopted.parentNode, div);
      expect(() => d.createElement('bad name'),
          throwsA(isA<DomException>().having((e) => e.name, 'name', 'InvalidCharacterError')));
    });

    test('adoptNode detaches and rewrites ownerDocument recursively', () {
      final source = sample();
      final target = Document();
      final div = source.getElementById('a')!;
      final paragraph = div.firstElementChild!;
      expect(target.adoptNode(div), same(div));
      expect(div.parentNode, isNull);
      expect(div.ownerDocument, same(target));
      expect(paragraph.ownerDocument, same(target));
      expect(
          () => target.adoptNode(target),
          throwsA(isA<DomException>()
              .having((e) => e.name, 'name', 'NotSupportedError')));
    });

    test('textContent setter replaces children', () {
      final d = sample();
      final div = d.getElementById('a')!..textContent = 'plain';
      expect(div.childNodes.single, isA<Text>());
      expect(div.textContent, 'plain');
      div.textContent = '';
      expect(div.childNodes, isEmpty);
    });

    test('cloneNode copies attributes and, when deep, children', () {
      final d = sample();
      final div = d.getElementById('a')!;
      final shallow = div.cloneNode();
      expect(shallow.getAttribute('class'), 'x y');
      expect(shallow.childNodes, isEmpty);
      final deep = div.cloneNode(deep: true);
      expect(deep.textContent, 'onetwo');
      expect(deep.parentNode, isNull);
    });
  });

  group('attributes and classList', () {
    test('get/set/remove/toggle, case-insensitive names', () {
      final d = sample();
      final div = d.getElementById('a')!;
      div.setAttribute('Data-X', '1');
      expect(div.getAttribute('data-x'), '1');
      expect(div.hasAttribute('DATA-X'), isTrue);
      div.removeAttribute('data-x');
      expect(div.getAttribute('data-x'), isNull);
      expect(div.toggleAttribute('hidden'), isTrue);
      expect(div.toggleAttribute('hidden'), isFalse);
    });

    test('classList', () {
      final d = sample();
      final div = d.getElementById('a')!;
      expect(div.classList.toList(), ['x', 'y']);
      div.classList.add(['z', 'x']);
      expect(div.className, 'x y z');
      div.classList.remove(['x']);
      expect(div.classList.toggle('y'), isFalse);
      expect(div.className, 'z');
      expect(div.classList.replace('z', 'w'), isTrue);
      expect(() => div.classList.add(['a b']), throwsA(isA<DomException>()));
    });
  });

  group('selectors', () {
    late Document d;
    setUp(() => d = sample());

    List<String> texts(String sel) =>
        d.querySelectorAll(sel).map((e) => e.textContent).toList();

    test('type, class, id, universal, grouping', () {
      expect(texts('p'), ['one', 'two']);
      expect(texts('.x').length, 2); // div.x and p.x
      expect(d.querySelector('#a')!.localName, 'div');
      expect(d.querySelectorAll('*').length, 11);
      expect(texts('p.x, li:first-child'), ['two', '1']);
    });

    test('combinators', () {
      expect(texts('body p'), ['one', 'two']);
      expect(texts('body > p'), isEmpty);
      expect(texts('div > p'), ['one', 'two']);
      expect(texts('li + li'), ['2', '3', '4']);
      expect(texts('p ~ p'), ['two']);
    });

    test('attributes', () {
      d.querySelector('li')!.setAttribute('data-k', 'alpha-beta');
      expect(texts('[data-k]'), ['1']);
      expect(texts('[data-k="alpha-beta"]'), ['1']);
      expect(texts('[data-k^=alpha]'), ['1']);
      expect(texts(r'[data-k$=beta]'), ['1']);
      expect(texts('[data-k*=a-b]'), ['1']);
      expect(texts('[data-k|=alpha]'), ['1']);
      expect(texts('[class~=y]'), ['onetwo']);
      expect(texts('[data-k=ALPHA-BETA i]'), ['1']);
      d.querySelector('li')!.setAttribute('lang', 'en-US');
      expect(texts('[lang|=en]'), ['1']);
      expect(texts('[lang|=EN i]'), ['1']);
    });

    test('pseudo-classes', () {
      expect(texts('li:first-child'), ['1']);
      expect(texts('li:last-child'), ['4']);
      expect(texts('li:nth-child(2)'), ['2']);
      expect(texts('li:nth-child(odd)'), ['1', '3']);
      expect(texts('li:nth-child(2n+2)'), ['2', '4']);
      expect(texts('li:nth-child(-n+2)'), ['1', '2']);
      expect(texts('li:nth-last-child(1)'), ['4']);
      expect(texts('li:not(:first-child):not(:last-child)'), ['2', '3']);
      expect(texts('p:not(.x)'), ['one']);
      expect(d.querySelector(':root')!.localName, 'html');
      final p = d.querySelector('p')!;
      d.documentElement!.setAttribute('lang', 'en-US');
      expect(p.matches(':lang(en)'), isTrue);
      p.setAttribute('lang', 'es-ES');
      expect(p.matches(':lang(es)'), isTrue);
      expect(p.matches(':lang(ES)'), isTrue);
      expect(p.matches(':lang(en)'), isFalse);
    });

    test('specificity', () {
      Specificity s(String sel) => SelectorList.parse(sel).selectors.single.specificity;
      expect(s('*'), Specificity.zero);
      expect(s('li'), const Specificity(0, 0, 1));
      expect(s('ul li.x'), const Specificity(0, 1, 2));
      expect(s('#a > p:first-child'), const Specificity(1, 1, 1));
      expect(s('p:not(#a)'), const Specificity(1, 0, 1));
      expect(s('[href]'), const Specificity(0, 1, 0));
    });

    test('matches and closest', () {
      final p = d.querySelector('p.x')!;
      expect(p.matches('#a > .x'), isTrue);
      expect(p.closest('div')!.id, 'a');
      expect(p.closest('ul'), isNull);
    });

    test('invalid selectors throw SyntaxError', () {
      for (final bad in ['', 'div >', '..a', 'p::bogus', 'p:bogus', '[x=', 'a,', 'p::before span']) {
        expect(() => d.querySelector(bad),
            throwsA(isA<DomException>().having((e) => e.name, 'name', 'SyntaxError')),
            reason: bad);
      }
    });

    test('pseudo-elements parse but never match elements', () {
      expect(d.querySelector('p::before'), isNull);
      expect(d.querySelector('p:after'), isNull);
      final sel = SelectorList.parse('p.x::after').selectors.single;
      final p = d.querySelector('p.x')!;
      expect(sel.pseudoElement, 'after');
      expect(sel.matchesPseudo(p, 'after'), isTrue);
      expect(sel.matchesPseudo(p, 'before'), isFalse);
      expect(sel.specificity, const Specificity(0, 1, 2));
    });

    test('interaction state pseudo-classes', () {
      final p = d.querySelector('p.x')!;
      final records = <MutationRecord>[];
      d.addMutationListener(records.add);
      expect(p.matches(':hover'), isFalse);
      d.hoverElement = p;
      expect(p.matches(':hover'), isTrue);
      expect(p.parentElement!.matches(':hover'), isTrue);
      expect(records.where((r) => r.name == ':state'), isNotEmpty);
      d.pressedElement = p;
      expect(p.matches(':active'), isTrue);
      d.hoverElement = null;
      expect(p.matches(':hover'), isFalse);
    });

    test('constraint validation', () {
      final f = d.createElement('form');
      final email = d.createElement('input')
        ..setAttribute('type', 'email')
        ..setAttribute('required', '');
      final n = d.createElement('input')
        ..setAttribute('type', 'number')
        ..setAttribute('min', '1')
        ..setAttribute('max', '10');
      f..appendChild(email)..appendChild(n);
      d.body!.appendChild(f);
      expect(email.validity.valueMissing, isTrue);
      expect(email.matches(':invalid'), isTrue);
      expect(email.matches(':user-invalid'), isFalse);
      email.value = 'nope';
      expect(email.validity.typeMismatch, isTrue);
      email.value = 'a@b.co';
      expect(email.validity.valid, isTrue);
      n.value = '11';
      expect(n.validity.rangeOverflow, isTrue);
      expect(n.matches(':out-of-range'), isTrue);
      expect(f.checkValidity(), isFalse);
      n.value = '5';
      email.customValidity = 'custom';
      expect(email.validationMessage, 'custom');
      email.customValidity = '';
      expect(f.checkValidity(), isTrue);
    });

    test('getElementsBy*', () {
      expect(d.getElementsByTagName('li').length, 4);
      expect(d.getElementsByClassName('x').length, 2);
      expect(d.getElementsByClassName('x y').single.id, 'a');
    });
  });

  group('events', () {
    test('capture, target, bubble order and currentTarget', () {
      final d = sample();
      final p = d.querySelector('p')!;
      final div = p.parentElement!;
      final log = <String>[];
      void on(EventTarget t, String name, {bool capture = false}) =>
          t.addEventListener('click', CallbackListener((e) {
            log.add('$name:${e.eventPhase.name}');
            expect(e.currentTarget, t);
            expect(e.target, p);
          }), capture: capture);
      on(d, 'doc-capture', capture: true);
      on(div, 'div-capture', capture: true);
      on(p, 'p');
      on(div, 'div');
      on(d, 'doc');
      p.dispatchEvent(Event('click', bubbles: true));
      expect(log, [
        'doc-capture:capturing',
        'div-capture:capturing',
        'p:atTarget',
        'div:bubbling',
        'doc:bubbling',
      ]);
    });

    test('non-bubbling events stop at the target', () {
      final d = sample();
      final p = d.querySelector('p')!;
      var bubbled = false;
      d.body!.addEventListener('focus', CallbackListener((_) => bubbled = true));
      p.dispatchEvent(Event('focus'));
      expect(bubbled, isFalse);
    });

    test('stopPropagation and stopImmediatePropagation', () {
      final d = sample();
      final p = d.querySelector('p')!;
      final log = <String>[];
      p.addEventListener('click', CallbackListener((e) {
        log.add('1');
        e.stopImmediatePropagation();
      }));
      p.addEventListener('click', CallbackListener((_) => log.add('2')));
      d.body!.addEventListener('click', CallbackListener((_) => log.add('body')));
      p.dispatchEvent(Event('click', bubbles: true));
      expect(log, ['1']);
    });

    test('preventDefault only for cancelable events', () {
      final d = sample();
      final p = d.querySelector('p')!;
      p.addEventListener('x', CallbackListener((e) => e.preventDefault()));
      expect(p.dispatchEvent(Event('x', cancelable: true)), isFalse);
      expect(p.dispatchEvent(Event('x')), isTrue);
    });

    test('duplicate listeners are ignored; once and removal work', () {
      final d = sample();
      final p = d.querySelector('p')!;
      var n = 0;
      void cb(Event e) => n++;
      p.addEventListener('c', CallbackListener(cb));
      p.addEventListener('c', CallbackListener(cb));
      p.dispatchEvent(Event('c'));
      expect(n, 1);
      p.removeEventListener('c', CallbackListener(cb));
      p.dispatchEvent(Event('c'));
      expect(n, 1);
      p.addEventListener('c', CallbackListener(cb), once: true);
      p.dispatchEvent(Event('c'));
      p.dispatchEvent(Event('c'));
      expect(n, 2);
      expect(p.eventListenerCount, 0);
    });

    test('listener errors are reported and dispatch continues', () {
      final d = sample();
      final errors = <Object>[];
      d.onListenerError = (e, _) => errors.add(e);
      final p = d.querySelector('p')!;
      var after = false;
      p.addEventListener('c', CallbackListener((_) => throw StateError('x')));
      p.addEventListener('c', CallbackListener((_) => after = true));
      p.dispatchEvent(Event('c'));
      expect(errors.single, isA<StateError>());
      expect(after, isTrue);
    });

    test('dispose removes all listeners', () {
      final d = sample();
      final p = d.querySelector('p')!;
      p.addEventListener('c', CallbackListener((_) {}));
      d.dispose();
      expect(p.eventListenerCount, 0);
    });
  });

  group('mutations', () {
    test('records for child, attribute, text and property changes', () {
      final d = sample();
      final records = <MutationRecord>[];
      d.addMutationListener(records.add);
      final div = d.getElementById('a')!;
      div.setAttribute('title', 't');
      div.setAttribute('title', 't'); // no-op
      (div.firstChild!.firstChild as Text).data = 'uno';
      final input = d.createElement('input');
      div.appendChild(input);
      input.value = 'v';
      div.removeChild(input);
      expect(records.map((r) => (r.type, r.name)), [
        (MutationType.attributes, 'title'),
        (MutationType.characterData, null),
        (MutationType.childList, null),
        (MutationType.property, 'value'),
        (MutationType.childList, null),
      ]);
      expect(records[2].addedNodes.single, input);
      expect(records[4].removedNodes.single, input);
    });
  });

  group('form controls', () {
    test('input value defaults to attribute then diverges', () {
      final d = sample();
      final input = d.createElement('input')..setAttribute('value', 'a');
      expect(input.value, 'a');
      input.value = 'b';
      expect(input.value, 'b');
      expect(input.getAttribute('value'), 'a');
    });

    test('radio groups are exclusive', () {
      final d = sample();
      final form = d.createElement('form');
      d.body!.appendChild(form);
      final r1 = d.createElement('input')
        ..setAttribute('type', 'radio')
        ..setAttribute('name', 'g');
      final r2 = r1.cloneNode();
      form..appendChild(r1)..appendChild(r2);
      r1.checked = true;
      r2.checked = true;
      expect([r1.checked, r2.checked], [false, true]);
      expect(d.querySelectorAll(':checked'), [r2]);
    });

    test('select value and selectedIndex', () {
      final d = sample();
      final select = d.createElement('select');
      for (final v in ['a', 'b', 'c']) {
        select.appendChild(d.createElement('option')
          ..setAttribute('value', v)
          ..textContent = v.toUpperCase());
      }
      expect(select.value, 'a');
      select.value = 'c';
      expect(select.selectedIndex, 2);
      select.value = 'zzz';
      expect(select.selectedIndex, -1);
      expect(select.value, '');
    });
  });

  group('limits', () {
    test('node count limit', () {
      final d = Document(limits: const DocumentLimits(maxNodes: 10));
      final html = d.createElement('html');
      d.appendChild(html);
      for (var i = 0; i < 8; i++) {
        html.appendChild(d.createElement('p'));
      }
      expect(d.connectedNodeCount, 10);
      expect(() => html.appendChild(d.createElement('p')),
          throwsA(isA<DomException>().having((e) => e.name, 'name', 'QuotaExceededError')));
      html.removeChild(html.firstChild!);
      html.appendChild(d.createElement('p'));
    });

    test('depth limit applies to detached trees too', () {
      final d = Document(limits: const DocumentLimits(maxDepth: 5));
      Element e = d.createElement('div');
      final root = e;
      expect(() {
        for (var i = 0; i < 10; i++) {
          final c = d.createElement('div');
          e.appendChild(c);
          e = c;
        }
      }, throwsA(isA<DomException>()));
      expect(root.descendants.length, lessThanOrEqualTo(5));
    });
  });

  group('serialization', () {
    test('escapes text and attributes; void and raw text elements', () {
      final d = Document();
      final div = d.createElement('div')..setAttribute('title', 'a"b&c');
      div.appendChild(d.createTextNode('1 < 2 & 3'));
      div.appendChild(d.createElement('br'));
      div.appendChild(d.createElement('script')..appendChild(d.createTextNode('a<b')));
      expect(div.outerHtml,
          '<div title="a&quot;b&amp;c">1 &lt; 2 &amp; 3<br><script>a<b</script></div>');
    });
  });

  group('activation behavior', () {
    test('checkbox toggles and fires input/change; canceled click reverts', () {
      final d = sample();
      final cb = d.createElement('input')..setAttribute('type', 'checkbox');
      d.body!.appendChild(cb);
      final log = <String>[];
      for (final t in ['click', 'input', 'change']) {
        cb.addEventListener(t, CallbackListener((e) => log.add('${e.type}:${cb.checked}')));
      }
      cb.click();
      expect(log, ['click:true', 'input:true', 'change:true']);
      log.clear();
      final cancel = CallbackListener((e) => e.preventDefault());
      cb.addEventListener('click', cancel);
      cb.click();
      expect(cb.checked, isTrue);
      expect(log, ['click:false']);
    });

    test('submit button submits its form unless prevented', () {
      final d = sample();
      final form = d.createElement('form');
      final name = d.createElement('input')
        ..setAttribute('name', 'n')
        ..setAttribute('value', 'Ana');
      final button = d.createElement('button')..textContent = 'Go';
      form..appendChild(name)..appendChild(button);
      d.body!.appendChild(form);
      final submitted = <List<(String, String)>>[];
      d.onSubmit = (f) => submitted.add(f.formData);
      button.click();
      expect(submitted.single, [('n', 'Ana')]);
      form.addEventListener('submit', CallbackListener((e) => e.preventDefault()));
      button.click();
      expect(submitted.length, 1);
    });

    test('disabled controls ignore clicks; links report navigation', () {
      final d = sample();
      final b = d.createElement('button')..setAttribute('disabled', '');
      var clicked = false;
      b.addEventListener('click', CallbackListener((_) => clicked = true));
      b.click();
      expect(clicked, isFalse);
      final a = d.createElement('a')..setAttribute('href', 'https://example.com');
      String? went;
      d.onNavigate = (href, _) => went = href;
      a.click();
      expect(went, 'https://example.com');
    });
  });
}
