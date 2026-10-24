import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

class Harness {
  Harness(String html, {StaticEnvironment? env}) {
    document = HtmlParser().parseDocument(html).value;
    engine = QuickJsEngine();
    environment = env ?? StaticEnvironment(localStorage: MemoryStorage());
    installConsole(engine, logs.add);
    bindings = DomBindings(
      engine: engine,
      document: document,
      environment: environment,
      onScriptError: errors.add,
    )..install();
    document.onListenerError = (e, _) => errors.add(e);
  }

  late final Document document;
  late final QuickJsEngine engine;
  late final StaticEnvironment environment;
  late final DomBindings bindings;
  final logs = <ConsoleMessage>[];
  final errors = <Object>[];

  Object? js(String src) => engine.evaluate(src);

  void dispose() {
    bindings.dispose();
    engine.dispose();
  }
}

void main() {
  late Harness h;
  tearDown(() => h.dispose());

  group('document API', () {
    setUp(() => h = Harness('<div id=app class="a b"><h1 id=title>Hola</h1>'
        '<ul><li class=item>1</li><li class=item>2</li></ul></div>'));

    test('getElementById, querySelector(All), textContent', () {
      expect(h.js('document.getElementById("title").textContent'), 'Hola');
      expect(h.js('document.querySelector(".item").textContent'), '1');
      expect(h.js('document.querySelectorAll(".item").map(e => e.textContent)'), ['1', '2']);
      expect(h.js('document.getElementsByClassName("item").length'), 2);
      expect(h.js('document.getElementsByTagName("li").length'), 2);
      expect(h.js('document.querySelector("#nope")'), isNull);
    });

    test('wrapper identity is stable', () {
      expect(h.js('document.getElementById("app") === document.querySelector("div")'), true);
      expect(h.js('document.body.parentNode === document.documentElement'), true);
      expect(h.js('document.documentElement.parentNode === document'), true);
    });

    test('createElement + appendChild mutate the real DOM', () {
      h.js('const el = document.createElement("div");'
          'el.textContent = "Hola desde NativaX";'
          'el.id = "nuevo";'
          'document.body.appendChild(el);');
      final el = h.document.getElementById('nuevo')!;
      expect(el.textContent, 'Hola desde NativaX');
      expect(el.parentElement, h.document.body);
    });

    test('attributes, classList, dataset', () {
      h.js('const app = document.getElementById("app");'
          'app.setAttribute("data-user-id", "7");'
          'app.classList.add("c"); app.classList.remove("a"); app.classList.toggle("b");');
      final app = h.document.getElementById('app')!;
      expect(app.className, 'c');
      expect(app.getAttribute('data-user-id'), '7');
      expect(h.js('app.dataset.userId'), '7');
      h.js('app.dataset.theme = "dark"');
      expect(app.getAttribute('data-theme'), 'dark');
      expect(h.js('app.classList.contains("c")'), true);
      expect(h.js('[...app.classList]'), ['c']);
      expect(h.js('app.hasAttribute("id") && app.getAttribute("missing") === null'), true);
    });

    test('tree navigation and removal', () {
      expect(h.js('document.querySelector("ul").children.length'), 2);
      h.js('const ul = document.querySelector("ul"); ul.removeChild(ul.firstElementChild);');
      expect(h.document.querySelectorAll('li').length, 1);
      h.js('document.querySelector("li").remove()');
      expect(h.document.querySelectorAll('li'), isEmpty);
      h.js('const a = document.createElement("li"), b = document.createElement("li");'
          'a.textContent = "a"; b.textContent = "b";'
          'ul.append(a); ul.replaceChild(b, a);');
      expect(h.document.querySelector('ul')!.innerHtml, '<li>b</li>');
    });

    test('innerHTML parses with the safe fragment parser; scripts are inert', () {
      h.js('document.getElementById("app").innerHTML = '
          '"<p class=x>uno <b>dos</b></p><script>globalThis.ran = true</script>"');
      expect(h.document.querySelector('p.x b')!.textContent, 'dos');
      expect(h.js('typeof ran'), 'undefined');
      expect(h.js('document.getElementById("app").innerHTML'),
          '<p class="x">uno <b>dos</b></p><script>globalThis.ran = true</script>');
    });

    test('adoptNode moves nodes and keeps attribute identity', () {
      final result = h.js('''
        (() => {
          const other = document.implementation.createHTMLDocument("T");
          const div = other.createElement("div");
          div.setAttribute("data-a", "1");
          const attr = div.getAttributeNode("data-a");
          const before = [div.ownerDocument === other, attr.ownerDocument === other];
          const returned = document.adoptNode(div);
          return [before, returned === div, div.parentNode === null,
                  div.ownerDocument === document, attr.ownerDocument === document,
                  div.getAttributeNode("data-a") === attr];
        })()
      ''');
      expect(result, [
        [true, true],
        true,
        true,
        true,
        true,
        true,
      ]);
    });

    test('appending to an XML document updates tagName', () {
      expect(
          h.js('''
            (() => {
              const el = document.createElement("t");
              const xml = document.implementation
                .createDocument("http://www.w3.org/1999/xhtml", "div", null)
                .documentElement;
              xml.appendChild(el);
              return [el.tagName, el.ownerDocument.contentType];
            })()
          '''),
          ['t', 'application/xhtml+xml']);
    });

    test('DOM errors become typed exceptions', () {
      expect(h.js('try { document.body.appendChild(document.documentElement) } catch (e) { e.name }'),
          'HierarchyRequestError');
      expect(h.js('try { document.querySelector("::x") } catch (e) { e.name }'), 'SyntaxError');
      expect(h.js('try { document.createElement("a b") } catch (e) { e.name }'), 'InvalidCharacterError');
      expect(h.js('try { document.body.appendChild({}) } catch (e) { e.name }'), 'TypeError');
    });

    test('inline style via element.style', () {
      h.js('const t = document.getElementById("title");'
          't.style.color = "red"; t.style.fontSize = "20px"; t.style.setProperty("margin", "4px");'
          't.style.width = "banana";');
      final t = h.document.getElementById('title')!;
      expect(t.getAttribute('style'), 'color: red; font-size: 20px; margin: 4px;');
      expect(h.js('t.style.fontSize'), '20px');
      h.js('t.style.color = ""');
      expect(t.getAttribute('style'), 'font-size: 20px; margin: 4px;');
    });

    test('scripts cannot reach Dart objects or the raw bridge', () {
      expect(h.js('Object.getOwnPropertyNames(document)'), isEmpty);
      expect(h.js('typeof __nx_host'), 'undefined');
      expect(h.js('try { new Node() } catch (e) { e.name }'), 'TypeError');
    });
  });

  group('events', () {
    setUp(() => h = Harness('<button id=increment>+</button><span id=count>0</span>'));

    test('the counter example: click listener updates the DOM', () {
      h.js('''
        const button = document.querySelector("#increment");
        const output = document.querySelector("#count");
        let count = 0;
        button.addEventListener("click", () => {
          count += 1;
          output.textContent = String(count);
        });
      ''');
      final button = h.document.getElementById('increment')!;
      button.click();
      button.click();
      expect(h.document.getElementById('count')!.textContent, '2');
    });

    test('event object: target, currentTarget, phases, preventDefault', () {
      h.js('''
        globalThis.log = [];
        document.body.addEventListener("click", (e) => {
          log.push(["body", e.target.id, e.currentTarget === document.body, e.eventPhase]);
        }, true);
        document.getElementById("increment").addEventListener("click", function (e) {
          log.push(["btn", this === e.currentTarget, e.eventPhase, e.isTrusted, e.type]);
          e.preventDefault();
        });
        window.addEventListener("click", (e) => log.push(["win", e.defaultPrevented]));
      ''');
      h.document.getElementById('increment')!.click();
      expect(h.js('log'), [
        ['body', 'increment', true, 1],
        ['btn', true, 2, false, 'click'],
        ['win', true],
      ]);
    });

    test('stopPropagation from script', () {
      h.js('globalThis.hits = 0;'
          'document.body.addEventListener("click", () => hits++);'
          'document.getElementById("increment").addEventListener("click", (e) => e.stopPropagation());');
      h.document.getElementById('increment')!.click();
      expect(h.js('hits'), 0);
    });

    test('duplicate listeners are ignored; removal and once work; callbacks are released', () {
      h.js('globalThis.n = 0; const f = () => n++; const b = document.getElementById("increment");'
          'b.addEventListener("click", f); b.addEventListener("click", f);');
      final b = h.document.getElementById('increment')!;
      b.click();
      expect(h.js('n'), 1);
      expect(h.bindings.liveListeners, 1);
      h.js('b.removeEventListener("click", f)');
      b.click();
      expect(h.js('n'), 1);
      expect(h.bindings.liveListeners, 0);
      h.js('b.addEventListener("click", () => n += 10, { once: true })');
      b.click();
      b.click();
      expect(h.js('n'), 11);
      expect(h.bindings.liveListeners, 0);
    });

    test('dispatchEvent with CustomEvent keeps identity and detail', () {
      h.js('''
        globalThis.got = null;
        const ev = new CustomEvent("ping", { bubbles: true, detail: { x: 1 } });
        document.body.addEventListener("ping", (e) => { got = [e === ev, e.detail.x, e.target.id]; });
        globalThis.ret = document.getElementById("count").dispatchEvent(ev);
      ''');
      expect(h.js('got'), [true, 1, 'count']);
      expect(h.js('ret'), true);
    });

    test('event handler properties can be cleared', () {
      h.js('''
        const d = document.createElement('div');
        d.onanimationend = () => {};
        const set = d.onanimationend !== null;
        d.onanimationend = null;
        globalThis.out = [set, d.onanimationend];
      ''');
      expect(h.js('out'), [true, null]);
    });

    test('script-created click events dispatch to detached nodes', () {
      h.js('''
        const t = document.createElement('div');
        let fired = false;
        t.addEventListener('click', () => { fired = true; });
        t.dispatchEvent(new Event('click'));
        globalThis.fired = fired;
      ''');
      expect(h.js('fired'), true);
    });

    test('prefixed animation handler aliases', () {
      h.js('''
        const d = document.getElementById('count');
        let n = 0;
        d.onwebkitanimationend = () => n++;
        d.addEventListener('webkitAnimationEnd', () => n++);
        d.dispatchEvent(new AnimationEvent('webkitAnimationEnd'));
        globalThis.n = n;
      ''');
      expect(h.js('n'), 2);
    });

    test('createEvent is uninitialized until initEvent', () {
      h.js('''
        const e = document.createEvent('CustomEvent');
        globalThis.out = [e.__initialized, e.type];
        try { document.dispatchEvent(e); out.push('ok'); }
        catch (err) { out.push(err.name); }
        e.initEvent('x', false, false);
        out.push(e.__initialized, e.type);
        out.push(document.dispatchEvent(e));
      ''');
      expect(h.js('out'), [false, '', 'InvalidStateError', true, 'x', true]);
    });

    test('window.event is replaceable and restored around dispatch', () {
      h.js('''
        window.event = 'foo';
        globalThis.seen = [];
        const target = document.getElementById('increment');
        const click = new Event('click');
        target.addEventListener('click', () => { seen.push(window.event === click); });
        target.dispatchEvent(click);
        seen.push(window.event);
      ''');
      expect(h.js('seen'), [false, 'foo']);
    });

    test('event constants, legacy flags and null init dictionaries', () {
      h.js('''
        globalThis.out = [];
        const e = new Event("x", { cancelable: true });
        out.push(e.NONE, Event.prototype.BUBBLING_PHASE, e.returnValue);
        out.push(e.cancelBubble);
        e.cancelBubble = true;
        out.push(e.cancelBubble);
        e.returnValue = false;
        out.push(e.defaultPrevented, e.returnValue);
        const c = new CustomEvent("y");
        c.initCustomEvent("z", true, true, { a: 1 });
        out.push(c.type, c.bubbles, c.cancelable, c.detail.a);
        const n = new Event("n", null);
        out.push(n.bubbles, n.cancelable);
      ''');
      expect(h.js('out'), [
        0, 3, true, false, true, true, false, 'z', true, true, 1, false, false,
      ]);
    });

    test('onclick handler property and return false', () {
      h.js('globalThis.c = 0; const b = document.getElementById("increment");'
          'b.onclick = () => { c++; return false; };');
      final b = h.document.getElementById('increment')!;
      final notCanceled = b.dispatchEvent(Event('click', cancelable: true));
      expect(notCanceled, isFalse);
      h.js('b.onclick = null');
      b.click();
      expect(h.js('c'), 1);
    });

    test('listener exceptions are reported, other listeners still run', () {
      h.js('globalThis.after = false; const b = document.getElementById("increment");'
          'b.addEventListener("click", () => { throw new Error("boom") });'
          'b.addEventListener("click", () => { after = true });');
      h.document.getElementById('increment')!.click();
      expect(h.js('after'), true);
      expect(h.errors.single, isA<JavaScriptException>().having((e) => e.message, 'message', 'boom'));
    });

    test('listener exceptions reach window.onerror', () {
      h.js('''
        globalThis.reported = [];
        window.onerror = (message) => { reported.push([typeof message, String(message)]); };
        const b = document.getElementById('increment');
        b.addEventListener('click', () => { throw new Error('boom'); });
        b.click();
      ''');
      expect(h.js('reported'), [[ 'string', 'boom' ]]);
    });

    test('input events carry trusted detail fields', () {
      h.js('globalThis.seen = null;'
          'document.body.addEventListener("keydown", (e) => { seen = [e.key, e.isTrusted]; });');
      h.document.getElementById('increment')!
          .dispatchEvent(Event('keydown', bubbles: true, detail: {'key': 'Enter'})..isTrusted = true);
      expect(h.js('seen'), ['Enter', true]);
    });
  });

  group('forms', () {
    setUp(() => h = Harness('<form id=f><input id=name name=name value=Ana>'
        '<input id=ok type=checkbox name=ok><select id=s><option value=a>A</option>'
        '<option value=b>B</option></select><button id=go>Go</button></form>'));

    test('value, checked, select; submit can be prevented from script', () {
      h.js('document.getElementById("name").value = "Luis";'
          'document.getElementById("ok").checked = true;'
          'document.getElementById("s").value = "b";');
      expect(h.document.getElementById('name')!.value, 'Luis');
      expect(h.js('document.getElementById("s").selectedIndex'), 1);
      h.js('globalThis.data = null; document.getElementById("f").addEventListener("submit", (e) => {'
          '  e.preventDefault(); data = document.getElementById("name").value; });');
      var submitted = false;
      h.document.onSubmit = (_) => submitted = true;
      h.document.getElementById('go')!.click();
      expect(h.js('data'), 'Luis');
      expect(submitted, isFalse);
    });
  });

  group('browser-style APIs over the host environment', () {
    setUp(() => h = Harness('<p>x</p>',
        env: StaticEnvironment(
          media: const MediaContext(width: 390, height: 844, prefersDark: true, devicePixelRatio: 3),
          languages: ['es-CO', 'en'],
          theme: const ThemeSnapshot(brightness: 'dark', colors: {'primary': '#6750a4ff'}),
          platform: 'android',
          localStorage: MemoryStorage(quota: 64),
        )));

    test('navigator, window metrics, nativax.platform', () {
      expect(h.js('[navigator.language, navigator.languages, navigator.platform, nativax.platform]'),
          ['es-CO', ['es-CO', 'en'], 'Linux armv8l', 'android']);
      expect(h.js('[innerWidth, innerHeight, devicePixelRatio, window === globalThis]'),
          [390, 844, 3, true]);
      expect(h.js('nativax.platform'), 'android');
    });

    test('matchMedia evaluates and notifies changes', () {
      h.js('''
        globalThis.changes = [];
        const dark = matchMedia("(prefers-color-scheme: dark)");
        globalThis.wide = matchMedia("(min-width: 600px)");
        wide.addEventListener("change", (e) => changes.push(["wide", e.matches]));
        dark.addEventListener("change", (e) => changes.push(["dark", e.matches]));
        globalThis.initial = [dark.matches, wide.matches];
        window.addEventListener("resize", () => changes.push(["resize", innerWidth]));
      ''');
      expect(h.js('initial'), [true, false]);
      h.environment.media = const MediaContext(width: 800, height: 600, prefersDark: false);
      h.bindings.environmentChanged();
      expect(h.js('changes'), [
        ['resize', 800],
        // Lists are notified in creation order.
        ['dark', false],
        ['wide', true],
      ]);
      expect(h.js('wide.matches'), true);
    });

    test('theme API and change event; setMode goes to the host', () {
      expect(h.js('[nativax.theme.brightness, nativax.theme.colors.primary]'), ['dark', '#6750a4ff']);
      h.js('globalThis.themes = []; window.addEventListener("nativax:themechange", (e) => themes.push(e.brightness));');
      h.environment.theme = const ThemeSnapshot(brightness: 'light');
      h.bindings.environmentChanged();
      expect(h.js('themes'), ['light']);
      expect(h.js('nativax.theme.setMode("dark")'), true);
      expect(h.environment.themeRequests, [ThemeModeRequest.dark]);
      expect(h.js('try { nativax.theme.setMode("purple") } catch (e) { e.name }'), 'TypeError');
    });

    test('languagechange', () {
      h.js('globalThis.lang = null; window.addEventListener("languagechange", () => lang = navigator.language)');
      h.environment.languages = ['fr-FR'];
      h.bindings.environmentChanged();
      expect(h.js('lang'), 'fr-FR');
    });

    test('localStorage with quota', () {
      h.js('localStorage.setItem("k", "v"); localStorage.other = "w";');
      expect(h.js('[localStorage.getItem("k"), localStorage.other, localStorage.length, localStorage.getItem("zz")]'),
          ['v', 'w', 2, null]);
      expect(h.js('try { localStorage.setItem("big", "x".repeat(100)) } catch (e) { e.name }'),
          'QuotaExceededError');
      h.js('localStorage.removeItem("k"); delete localStorage.other');
      expect(h.js('localStorage.length'), 0);
    });

    test('Dart <-> JS messaging: nativax.invoke and postMessage', () {
      h.bindings.registerHandler('sum', (args) => (args[0] as num) + (args[1] as num));
      expect(h.js('nativax.invoke("sum", 2, 3)'), 5);
      expect(h.js('try { nativax.invoke("nope") } catch (e) { e.message }'), 'no handler named "nope"');
      h.js('globalThis.msgs = []; nativax.addEventListener("message", (e) => msgs.push(e.data))');
      h.bindings.postMessage({'hello': 'js'});
      expect(h.js('msgs'), [
        {'hello': 'js'},
      ]);
    });
  });

  group('lifecycle', () {
    test('dispose releases listeners and wrappers', () {
      h = Harness('<div id=a></div>');
      h.js('for (let i = 0; i < 50; i++) { const d = document.createElement("div");'
          'd.addEventListener("click", () => {}); document.body.appendChild(d); }');
      expect(h.bindings.liveListeners, 50);
      h.bindings.dispose();
      expect(h.bindings.liveListeners, 0);
      expect(h.bindings.registeredTargets, 0);
    });

    test('wrappers of unreachable nodes are released', () {
      h = Harness('');
      h.js('globalThis.keep = []; for (let i = 0; i < 2000; i++) keep.push(document.createElement("span"));');
      expect(h.bindings.registeredTargets, greaterThan(2000));
      h.js('keep = null');
      h.engine.collectGarbage();
      h.js('0'); // drains FinalizationRegistry jobs
      expect(h.bindings.registeredTargets, lessThan(100));
      // Nodes still in the tree get a fresh id when touched again.
      h.js('document.body.appendChild(document.createElement("i"))');
      h.engine.collectGarbage();
      h.js('0');
      expect(h.js('document.querySelector("i").localName'), 'i');
    });
  });
}
