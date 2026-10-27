import 'dart:async';

import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

void main() {
  late JscEngine engine;

  setUp(() => engine = JscEngine());
  tearDown(() => engine.dispose());

  group('evaluation', () {
    test('expressions, functions, arrow functions, objects, arrays', () {
      expect(engine.evaluate('1 + 2 * 3'), 7);
      expect(engine.evaluate('const sq = (x) => x * x; sq(12)'), 144);
      expect(engine.evaluate('function f(a, b) { return a + b } f("a", "b")'),
          'ab');
      expect(engine.evaluate('({a: [1, 2, {b: true}], c: null})'), {
        'a': [
          1,
          2,
          {'b': true},
        ],
        'c': null,
      });
      expect(engine.evaluate('let s = 0; for (let i = 0; i < 10; i++) '
          '{ if (i % 2) s += i; } s'), 25);
    });

    test('state persists across evaluations', () {
      engine.evaluate('globalThis.counter = 40');
      engine.evaluate('counter += 2');
      expect(engine.evaluate('counter'), 42);
    });

    test('undefined and functions decode to null', () {
      expect(engine.evaluate('undefined'), isNull);
      expect(engine.evaluate('(function () {})'), isNull);
    });

    test('unicode round trip', () {
      expect(engine.evaluate('"ñandú — 漢字 — 🎉".length'), 15);
      expect(engine.evaluate('"שלום" + " " + "ñ"'), 'שלום ñ');
    });

    test('syntax errors are reported, not hidden', () {
      expect(
        () => engine.evaluate('let = ;'),
        throwsA(isA<JavaScriptException>()
            .having((e) => e.name, 'name', 'SyntaxError')),
      );
    });

    test('thrown errors carry name, message and stack', () {
      expect(
        () => engine.evaluate('function boom() { throw new TypeError("bad") }'
            ' boom()'),
        throwsA(isA<JavaScriptException>()
            .having((e) => e.name, 'name', 'TypeError')
            .having((e) => e.message, 'message', 'bad')
            .having((e) => e.stack, 'stack', contains('boom'))),
      );
    });

    test('non-Error throw values are reported', () {
      expect(
        () => engine.evaluate('throw 42'),
        throwsA(isA<JavaScriptException>()
            .having((e) => e.message, 'message', '42')),
      );
    });

    test('try/catch inside script works', () {
      expect(engine.evaluate('try { null.x } catch (e) { e.name }'),
          'TypeError');
    });

    test('callGlobal passes JSON arguments', () {
      engine.evaluate('globalThis.add = ({a, b}) => a + b');
      expect(engine.callGlobal('add', {'a': 2, 'b': 3}), 5);
      expect(() => engine.callGlobal('missing'),
          throwsA(isA<JavaScriptException>()));
    });
  });

  group('promises', () {
    test('microtasks are drained after each entry', () {
      engine.evaluate('globalThis.log = [];'
          'Promise.resolve(1).then((v) => log.push(v));'
          'log.push(0);');
      expect(engine.evaluate('log'), [0, 1]);
    });

    test('async/await resolves within one entry', () {
      engine.evaluate('globalThis.out = null;'
          '(async () => { const v = await Promise.resolve(5);'
          ' out = v * 2; })();');
      expect(engine.evaluate('out'), 10);
    });
  });

  group('host functions', () {
    test('script calls Dart synchronously with JSON values', () {
      engine.registerHostFunction('sum', (args) {
        return (args.cast<num>()).fold<num>(0, (a, b) => a + b);
      });
      expect(engine.evaluate('__nx.host("sum", 1, 2, 3.5)'), 6.5);
    });

    test('host errors become typed script exceptions', () {
      engine.registerHostFunction('fail', (args) {
        throw JavaScriptHostError('RangeError', 'out of range');
      });
      expect(
        engine.evaluate('try { __nx.host("fail") } catch (e) '
            '{ e instanceof RangeError && e.message }'),
        'out of range',
      );
    });

    test('custom error names are preserved', () {
      engine.registerHostFunction('nf', (args) {
        throw JavaScriptHostError('NotFoundError', 'gone');
      });
      expect(engine.evaluate('try { __nx.host("nf") } catch (e) { e.name }'),
          'NotFoundError');
    });

    test('unexpected Dart exceptions do not leak details', () {
      Object? seen;
      engine.onHostError = (e, _) => seen = e;
      engine.registerHostFunction('crash', (args) => throw StateError('secret'));
      final message = engine.evaluate(
          'try { __nx.host("crash") } catch (e) { e.message }');
      expect(message, 'internal host error');
      expect(seen, isA<StateError>());
    });

    test('unknown host functions throw TypeError', () {
      expect(engine.evaluate('try { __nx.host("nope") } catch (e) { e.name }'),
          'TypeError');
    });

    test('raw bridge is not reachable from script', () {
      expect(engine.evaluate('typeof __nx_host'), 'undefined');
      expect(engine.evaluate('Object.isFrozen(__nx)'), true);
    });

    test('re-entrant calls: script -> Dart -> script', () {
      engine.evaluate('globalThis.double = (x) => x * 2');
      engine.registerHostFunction('viaScript', (args) {
        return engine.callGlobal('double', args[0]);
      });
      expect(engine.evaluate('__nx.host("viaScript", 21)'), 42);
    }, skip: 'JSC C API is not re-entrant from host callbacks');
  });

  group('limits', () {
    test('infinite loops are interrupted by the execution budget', () {
      final e = JscEngine(const JavaScriptEngineConfig(
        executionBudget: Duration(milliseconds: 100),
      ));
      addTearDown(e.dispose);
      final sw = Stopwatch()..start();
      expect(() => e.evaluate('while (true) {}'),
          throwsA(isA<JavaScriptTimeoutException>()));
      expect(sw.elapsedMilliseconds, lessThan(2000));
      // The interruption cannot be swallowed by try/catch.
      expect(() => e.evaluate('try { while (true) {} } catch (_) {} "x"'),
          throwsA(isA<JavaScriptTimeoutException>()));
      // The engine stays usable afterwards.
      expect(e.evaluate('1 + 1'), 2);
    }, skip: 'JSC C API has no execution-time interrupt hook');

    test('unbounded recursion raises RangeError instead of crashing', () {
      expect(
        () => engine.evaluate('function r() { return r() + 1 } r()'),
        throwsA(isA<JavaScriptException>()
            .having((e) => e.name, 'name', 'RangeError')),
      );
      expect(engine.evaluate('2 + 2'), 4);
    });

    test('memory limit is enforced', () {
      final e = JscEngine(const JavaScriptEngineConfig(
        memoryLimitBytes: 8 * 1024 * 1024,
      ));
      addTearDown(e.dispose);
      expect(
        () => e.evaluate('const a = []; while (true) a.push(new Array(1e5).fill(1));'),
        throwsA(isA<JavaScriptException>()),
      );
    }, skip: 'JSC C API has no memory limit hook');

    test('microtask loops are bounded', () {
      final e = JscEngine(const JavaScriptEngineConfig(
        executionBudget: Duration(milliseconds: 200),
      ));
      addTearDown(e.dispose);
      expect(
        () => e.evaluate('const loop = () => Promise.resolve().then(loop); loop();'),
        throwsA(isA<JavaScriptException>()),
      );
    }, skip: 'JSC C API has no execution-time interrupt hook');
  });

  group('lifecycle', () {
    test('contexts are isolated', () {
      final other = JscEngine();
      addTearDown(other.dispose);
      engine.evaluate('globalThis.secret = 1');
      expect(other.evaluate('typeof secret'), 'undefined');
    });

    test('disposed engine rejects calls', () {
      final e = JscEngine()..dispose();
      expect(() => e.evaluate('1'),
          throwsA(isA<JavaScriptEngineStateException>()));
      e.dispose(); // idempotent
    });

    test('many create/dispose cycles do not fail', () {
      for (var i = 0; i < 200; i++) {
        final e = JscEngine();
        e.evaluate('const x = new Array(1000).fill("x").join("")');
        e.dispose();
      }
    });
  });

  group('console', () {
    test('forwards formatted messages', () {
      final messages = <ConsoleMessage>[];
      installConsole(engine, messages.add);
      engine.evaluate('console.log("a", 1, {b: 2}); console.error(new Error("x"))');
      expect(messages.map((m) => m.toString()),
          ['[log] a 1 {"b":2}', '[error] Error: x']);
    });
  });

  group('timers', () {
    test('setTimeout runs later without blocking and in delay order', () async {
      final timers = TimerHost(engine);
      addTearDown(timers.dispose);
      engine.evaluate('globalThis.order = [];'
          'setTimeout(() => order.push("b"), 20);'
          'setTimeout((x) => order.push(x), 0, "a");'
          'order.push("sync");');
      expect(engine.evaluate('order'), ['sync']);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(engine.evaluate('order'), ['sync', 'a', 'b']);
    });

    test('clearTimeout cancels; setInterval repeats until cleared', () async {
      final timers = TimerHost(engine);
      addTearDown(timers.dispose);
      engine.evaluate('globalThis.n = 0; globalThis.fired = false;'
          'const t = setTimeout(() => fired = true, 5); clearTimeout(t);'
          'const i = setInterval(() => { if (++n === 3) clearInterval(i); }, 5);');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.evaluate('[n, fired]'), [3, false]);
      expect(timers.activeTimers, 0);
    });

    test('timer callback errors are reported, not swallowed', () async {
      final errors = <JavaScriptException>[];
      final timers = TimerHost(engine, onError: errors.add);
      addTearDown(timers.dispose);
      engine.evaluate('setTimeout(() => { throw new Error("late") }, 0)');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errors.single.message, 'late');
    });

    test('active timer count is limited', () {
      final timers = TimerHost(engine,
          limits: const TimerLimits(maxActiveTimers: 3));
      addTearDown(timers.dispose);
      expect(
        engine.evaluate('try { for (let i = 0; i < 5; i++) setTimeout(() => {}, 1000);'
            ' "no" } catch (e) { e.name }'),
        'RangeError',
      );
    });

    test('promise-based sleep with async/await', () async {
      final timers = TimerHost(engine);
      addTearDown(timers.dispose);
      engine.evaluate('globalThis.done = false;'
          'const sleep = (ms) => new Promise((r) => setTimeout(r, ms));'
          '(async () => { await sleep(10); done = true; })();');
      expect(engine.evaluate('done'), false);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(engine.evaluate('done'), true);
    });
  });
}
