import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_dom/nativa_dom.dart';
import 'package:nativa_dom_bindings/nativa_dom_bindings.dart';
import 'package:nativa_html/nativa_html.dart';
import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

/// A fake network that answers from a map and records requests.
class FakeNetwork implements NativaXNetwork {
  final requests = <NetworkRequest>[];

  @override
  Future<NetworkResponse> fetch(NetworkRequest r) async {
    requests.add(r);
    if (r.url.host == 'down.test') throw const NetworkDenied('blocked');
    final body = jsonEncode({'method': r.method, 'path': r.url.path, 'body': r.body == null ? null : utf8.decode(r.body!)});
    return NetworkResponse(
      status: 200,
      statusText: 'OK',
      headers: [('content-type', 'application/json'), ('x-test', '1')],
      body: Uint8List.fromList(utf8.encode(body)),
      url: r.url,
    );
  }

  @override
  Future<NetworkSocket> connect(Uri url, List<String> protocols) async => _EchoSocket();
}

class _EchoSocket implements NetworkSocket {
  final _c = StreamController<Object>();
  @override
  Stream<Object> get messages => _c.stream;
  @override
  String get protocol => '';
  @override
  void send(Object data) => _c.add(data is String ? 'echo:$data' : data);
  @override
  Future<void> close([int? code, String? reason]) async {
    closeCode = code ?? 1000;
    closeReason = reason ?? '';
    await _c.close();
  }

  @override
  int? closeCode;
  @override
  String? closeReason;
}

class WebHarness {
  WebHarness(String html, {String css = '', String url = 'https://app.test/index.html', NativaXNetwork? network}) {
    document = HtmlParser().parseDocument(html).value;
    styles = StyleEngine(document: document, media: const MediaContext(width: 800, height: 600))
      ..authorSheets = [StyleSheet.parse(css)];
    document.addMutationListener(styles.handleMutation);
    engine = QuickJsEngine();
    installConsole(engine, logs.add);
    timers = TimerHost(engine, onError: errors.add);
    bindings = DomBindings(
      engine: engine,
      document: document,
      environment: StaticEnvironment(localStorage: MemoryStorage()),
      onScriptError: errors.add,
      styleEngine: styles,
      documentUrl: url,
      network: network ?? const DeniedNetwork(),
    )..install();
  }

  late final Document document;
  late final StyleEngine styles;
  late final QuickJsEngine engine;
  late final TimerHost timers;
  late final DomBindings bindings;
  final logs = <ConsoleMessage>[];
  final errors = <Object>[];

  Object? js(String src) => engine.evaluate(src);

  /// Runs [src] (which must set `globalThis.out`), lets timers and
  /// microtasks run, then returns `out`.
  Future<Object?> async(String src, {int ms = 60}) async {
    engine.evaluate('globalThis.out = undefined; $src');
    for (var i = 0; i < ms ~/ 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      engine.drainMicrotasks();
    }
    return engine.evaluate('globalThis.out');
  }

  void dispose() {
    timers.dispose();
    bindings.dispose();
    engine.dispose();
  }
}

void main() {
  late WebHarness h;
  tearDown(() => h.dispose());

  test('encoding, base64, structuredClone, crypto', () {
    h = WebHarness('<p>x</p>');
    expect(h.js('Array.from(new TextEncoder().encode("añ€😀"))'), [97, 195, 177, 226, 130, 172, 240, 159, 152, 128]);
    expect(h.js('new TextDecoder().decode(new TextEncoder().encode("añ€😀"))'), 'añ€😀');
    expect(h.js('[btoa("hola"), atob("aG9sYQ==")]'), ['aG9sYQ==', 'hola']);
    expect(h.js('(() => { const o = {a: [1, {b: 2}], d: new Date(0), m: new Map([[1, 2]])}; o.self = o;'
        ' const c = structuredClone(o); return [c.a[1].b, c.d.getTime(), c.m.get(1), c.self === c, c !== o]; })()'),
        [2, 0, 2, true, true]);
    expect(h.js('(() => { try { structuredClone(() => 1); } catch (e) { return e.name; } })()'), 'DataCloneError');
    expect(h.js('/^[0-9a-f-]{36}\$/.test(crypto.randomUUID()) && crypto.getRandomValues(new Uint8Array(8)).length'), 8);
  });

  test('Intl formatting without ICU', () {
    h = WebHarness('<p>x</p>');
    expect(h.js('new Intl.NumberFormat("en-US").format(1234567.891)'), '1,234,567.891');
    expect(h.js('new Intl.NumberFormat("es-CO").format(1234567.5)'), '1.234.567,5');
    expect(h.js('new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"}).format(12.5)'), r'$12.50');
    expect(h.js('new Intl.NumberFormat("en", {style: "percent"}).format(0.25)'), '25%');
    expect(h.js('new Intl.DateTimeFormat("en-US", {timeZone: "UTC"}).format(new Date(Date.UTC(2024, 0, 5)))'), '1/5/2024');
    expect(h.js('new Intl.DateTimeFormat("es", {timeZone: "UTC", dateStyle: "long"}).format(new Date(Date.UTC(2024, 0, 5)))'),
        '5 de enero de 2024');
    expect(h.js('new Intl.RelativeTimeFormat("es", {numeric: "auto"}).format(-1, "day")'), 'ayer');
    expect(h.js('new Intl.RelativeTimeFormat("en").format(3, "hours")'), 'in 3 hours');
    expect(h.js('new Intl.ListFormat("en").format(["a", "b", "c"])'), 'a, b, and c');
    expect(h.js('(1234.5).toLocaleString("en-US")'), '1,234.5');
  });

  test('location, hash navigation, :target and history', () async {
    h = WebHarness('<p id=a>a</p><p id=b>b</p><a id=link href="#b">b</a>', css: ':target { color: red }');
    expect(h.js('[location.href, location.origin, location.pathname, location.hash]'),
        ['https://app.test/index.html', 'https://app.test', '/index.html', '']);
    expect(h.js('document.getElementById("link").hash'), '#b');
    expect(h.js('document.getElementById("link").href'), 'https://app.test/index.html#b');
    final out = await h.async('addEventListener("hashchange", e => { out = [e.oldURL, e.newURL, location.hash]; });'
        'document.getElementById("link").click();');
    expect(out, ['https://app.test/index.html', 'https://app.test/index.html#b', '#b']);
    expect(h.styles.styleOf(h.document.getElementById('b')!).color, const CssColor(0xffff0000));
    h.js('history.pushState({n: 1}, "", "/other?x=1")');
    expect(h.js('[location.pathname, location.search, history.state.n, history.length]'), ['/other', '?x=1', 1, 3]);
    final popped = await h.async('addEventListener("popstate", e => { out = [e.state && e.state.n, location.pathname]; }); history.back();');
    expect(popped, [null, '/index.html']);
  });

  test('forms: validity, FormData, elements, requestSubmit', () {
    h = WebHarness('<form id=f><input name=email type=email required>'
        '<input name=n type=number min=1 max=3 value=5><input type=checkbox name=c value=yes checked>'
        '<select name=s multiple><option selected>A</option><option>B</option><option selected>C</option></select>'
        '<button>go</button></form>');
    expect(h.js('const f = document.getElementById("f"); [f.elements.length, f.elements.email.type, f.elements.namedItem("n").value]'),
        [5, 'email', '5']);
    expect(h.js('[f.elements.email.validity.valueMissing, f.elements.n.validity.rangeOverflow, f.checkValidity()]'),
        [true, true, false]);
    expect(h.js('f.elements.email.validationMessage'), 'Please fill out this field.');
    h.js('f.elements.email.value = "x@y.co"; f.elements.n.value = "2";');
    expect(h.js('f.checkValidity()'), true);
    h.js('f.elements.email.setCustomValidity("nope")');
    expect(h.js('[f.elements.email.validity.customError, f.elements.email.validationMessage, f.reportValidity()]'),
        [true, 'nope', false]);
    h.js('f.elements.email.setCustomValidity("")');
    expect(h.js('[...new FormData(f)].map(([k, v]) => k + "=" + v)'), ['email=x@y.co', 'n=2', 'c=yes', 's=A', 's=C']);
    expect(h.js('let sub = 0; f.addEventListener("submit", e => { sub++; e.preventDefault(); }); f.requestSubmit(); sub'), 1);
    expect(h.js('[f.elements.s.selectedOptions.length, f.elements.s.options[1].selected]'), [2, false]);
  });

  test('getComputedStyle and CSS.supports', () {
    h = WebHarness('<div id=d class=x>t</div>',
        css: '.x { color: #ff0000; padding: 4px 2px; display: grid; --brand: blue } .x::after { content: "!" }');
    expect(h.js('const cs = getComputedStyle(document.getElementById("d")); [cs.color, cs.paddingTop, cs.getPropertyValue("padding-left"), cs.display, cs.getPropertyValue("--brand")]'),
        ['rgb(255, 0, 0)', '4px', '2px', 'grid', 'blue']);
    expect(h.js('getComputedStyle(document.getElementById("d"), "::after").content'), '"!"');
    expect(h.js('[CSS.supports("display", "grid"), CSS.supports("display", "bogus"), CSS.supports("(gap: 1rem) and (display: flex)"), CSS.supports("selector(:has(a))")]'),
        [true, false, true, true]);
    expect(h.js('CSS.escape("1a b")'), r'\31 a\ b');
  });

  test('MutationObserver delivers records in a microtask', () async {
    h = WebHarness('<ul id=l><li>1</li></ul>');
    final out = await h.async('const l = document.getElementById("l");'
        'new MutationObserver((rs) => { out = rs.map(r => r.type + ":" + (r.attributeName || r.addedNodes.length) + ":" + (r.oldValue ?? "")); })'
        '.observe(l, {childList: true, attributes: true, attributeOldValue: true, subtree: true});'
        'l.setAttribute("data-x", "1"); l.setAttribute("data-x", "2"); l.appendChild(document.createElement("li"));');
    expect(out, ['attributes:data-x:', 'attributes:data-x:1', 'childList:1:']);
  });

  test('fetch, XMLHttpRequest and WebSocket go through the network policy', () async {
    final net = FakeNetwork();
    h = WebHarness('<p>x</p>', network: net);
    final res = await h.async('fetch("/api/items", {method: "POST", body: JSON.stringify({a: 1}), headers: {"X-A": "b"}})'
        '.then(r => r.json().then(j => { out = [r.ok, r.status, r.headers.get("x-test"), j.method, j.path, j.body]; }));');
    expect(res, [true, 200, '1', 'POST', '/api/items', '{"a":1}']);
    expect(net.requests.single.url.toString(), 'https://app.test/api/items');
    expect(net.requests.single.headers, contains(('x-a', 'b')));
    final failed = await h.async('fetch("https://down.test/x").then(() => { out = "resolved"; }, e => { out = e.name; });');
    expect(failed, 'TypeError');
    final aborted = await h.async('const c = new AbortController(); fetch("/slow", {signal: c.signal}).catch(e => { out = e.name; }); c.abort();');
    expect(aborted, 'AbortError');
    final xhr = await h.async('const x = new XMLHttpRequest(); x.open("GET", "/x"); x.responseType = "json";'
        'x.onload = () => { out = [x.status, x.response.path, x.getResponseHeader("content-type")]; }; x.send();');
    expect(xhr, [200, '/x', 'application/json']);
    final ws = await h.async('const w = new WebSocket("wss://echo.test"); w.onopen = () => w.send("hi");'
        'w.onmessage = (e) => { out = [w.readyState, e.data]; w.close(); };');
    expect(ws, [1, 'echo:hi']);
  });

  test('fetch is denied by default', () async {
    h = WebHarness('<p>x</p>');
    expect(await h.async('fetch("/x").catch(e => { out = e.message; });'), startsWith('Failed to fetch'));
    expect(await h.async('fetch("data:text/plain,hola%20mundo").then(r => r.text()).then(t => { out = t; });'), 'hola mundo');
  });

  test('Blob, FileReader and object URLs', () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async('const b = new Blob(["hola ", new Uint8Array([109, 117, 110, 100, 111])], {type: "text/plain"});'
        'const r = new FileReader(); r.onload = () => b.text().then(t => fetch(URL.createObjectURL(b)).then(x => x.text())'
        '.then(t2 => { out = [b.size, b.type, r.result, t, t2]; })); r.readAsDataURL(b);');
    expect(out, [10, 'text/plain', 'data:text/plain;base64,aG9sYSBtdW5kbw==', 'hola mundo', 'hola mundo']);
  });

  test('IndexedDB stores, indexes and cursors', () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async('''
      const req = indexedDB.open("db", 1);
      req.onupgradeneeded = () => {
        const store = req.result.createObjectStore("people", { keyPath: "id", autoIncrement: true });
        store.createIndex("byAge", "age");
      };
      req.onsuccess = () => {
        const db = req.result;
        const tx = db.transaction("people", "readwrite");
        const s = tx.objectStore("people");
        s.add({ name: "Ana", age: 30 }); s.add({ name: "Luis", age: 25 }); s.put({ id: 9, name: "Eva", age: 41 });
        tx.oncomplete = () => {
          const r = db.transaction("people").objectStore("people");
          const names = [];
          r.index("byAge").openCursor(IDBKeyRange.lowerBound(26)).onsuccess = (e) => {
            const c = e.target.result;
            if (c) { names.push(c.value.name); c.continue(); return; }
            r.count().onsuccess = (ev) => { out = [db.version, [...db.objectStoreNames], names, ev.target.result]; };
          };
        };
      };
    ''', ms: 200);
    expect(out, [1, ['people'], ['Ana', 'Eva'], 3]);
  });

  test('IndexedDB abort restores the records changed by the transaction',
      () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async('''
      const req = indexedDB.open("abortdb", 1);
      req.onupgradeneeded = () => req.result.createObjectStore("items", { autoIncrement: true });
      req.onsuccess = () => {
        const db = req.result;
        const seed = db.transaction("items", "readwrite").objectStore("items");
        seed.add("one"); seed.add("two");
        seed.transaction.oncomplete = () => {
          const tx = db.transaction("items", "readwrite");
          const store = tx.objectStore("items");
          const put = store.put("changed", 1);
          put.onsuccess = () => tx.abort();
          tx.onabort = () => {
            const read = db.transaction("items").objectStore("items");
            read.getAll().onsuccess = (e) => { out = e.target.result; };
          };
        };
      };
    ''', ms: 200);
    expect(out, ['one', 'two']);
  });

  test('custom elements upgrade and lifecycle callbacks', () async {
    h = WebHarness('<x-greet name="Ana"></x-greet>');
    final out = await h.async('''
      const log = [];
      class XGreet extends HTMLElement {
        static observedAttributes = ["name"];
        connectedCallback() { log.push("connected"); this.textContent = "Hola " + this.getAttribute("name"); }
        attributeChangedCallback(n, o, v) { log.push(n + ":" + o + ">" + v); }
      }
      customElements.define("x-greet", XGreet);
      const el = document.querySelector("x-greet");
      el.setAttribute("name", "Eva");
      const made = document.createElement("x-greet");
      document.body.appendChild(made);
      setTimeout(() => { out = [el instanceof XGreet, el.textContent, log, made instanceof XGreet]; }, 10);
    ''');
    expect(out, [true, 'Hola Ana', ['name:null>Ana', 'connected', 'name:Ana>Eva', 'connected'], true]);
  });

  test('event classes, script targets and error reporting', () {
    h = WebHarness('<button id=b>b</button>');
    expect(h.js('const ev = new KeyboardEvent("keydown", {key: "Enter", ctrlKey: true}); [ev.key, ev.ctrlKey, ev.code, ev instanceof UIEvent]'),
        ['Enter', true, '', true]);
    expect(h.js('const t = new EventTarget(); let n = 0; const f = () => n++; t.addEventListener("x", f); t.addEventListener("x", f);'
        't.addEventListener("y", () => n += 10, {once: true}); t.dispatchEvent(new Event("x")); t.dispatchEvent(new Event("y")); t.dispatchEvent(new Event("y")); n'), 11);
    expect(h.js('const ac = new AbortController(); let m = 0; const tt = new EventTarget(); tt.addEventListener("z", () => m++, {signal: ac.signal});'
        'ac.abort(); tt.dispatchEvent(new Event("z")); [m, ac.signal.aborted, ac.signal.reason.name]'), [0, true, 'AbortError']);
    expect(h.js('document.getElementById("b") instanceof HTMLButtonElement && document.body instanceof HTMLBodyElement'), true);
    expect(h.js('let got = null; addEventListener("error", (e) => { got = e.message; }); const t2 = new EventTarget();'
        't2.addEventListener("boom", () => { throw new Error("kaput"); }); t2.dispatchEvent(new Event("boom")); got'), 'kaput');
  });

  test('dedicated workers run in their own engine', () async {
    h = WebHarness('<p>x</p>');
    final out = await h.async('const u = URL.createObjectURL(new Blob(["onmessage=e=>{let s=0;for(let i=0;i<e.data;i++)s+=i;postMessage(s)}"], {type: "text/javascript"}));'
        'const w = new Worker(u); w.onmessage = (e) => { out = [e.data, typeof window.onmessage]; w.terminate(); }; w.postMessage(1000);', ms: 150);
    expect(out, [499500, 'object']);
    final err = await h.async('const w2 = new Worker(URL.createObjectURL(new Blob(["throw new Error(\\"bad\\")"])));'
        'w2.onerror = (e) => { out = e.message; };', ms: 150);
    expect(err, contains('bad'));
  });
  test('CSSOM: styleSheets, insertRule and rule.style edit the style text', () {
    final h = WebHarness('<style>div { color: red; }</style><div id="a">x</div>');
    addTearDown(h.dispose);
    expect(h.js('document.styleSheets.length'), 1);
    expect(h.js('document.styleSheets[0].cssRules.length'), 1);
    expect(h.js('document.styleSheets[0].cssRules[0].selectorText'), 'div');
    expect(h.js('document.styleSheets[0].cssRules[0].style.getPropertyValue("color")'), 'red');
    h.js('document.styleSheets[0].cssRules[0].style.color = "blue"');
    expect(h.document.querySelector('style')!.textContent, contains('color: blue'));
    h.js('document.styleSheets[0].insertRule("p.x { color: green; }", 0)');
    expect(h.js('document.styleSheets[0].cssRules.length'), 2);
    expect(h.js('document.styleSheets[0].cssRules[0].selectorText'), 'p.x');
    h.js('document.styleSheets[0].deleteRule(0)');
    expect(h.js('document.styleSheets[0].cssRules.length'), 1);
  });

}
