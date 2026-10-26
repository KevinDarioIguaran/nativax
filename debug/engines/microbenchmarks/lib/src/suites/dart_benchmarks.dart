import 'dart:convert';

import '../model.dart';

/// Native Dart reference workloads. They are useful for context ("how fast is
/// the same shape of work in Dart?"), but they are not an apples-to-apples
/// replacement for the JS engine: the runtime, optimizer and allocation
/// behavior differ.
List<BenchmarkCase> dartBenchmarks() => [
      BenchmarkCase(
        name: 'dart.arithmetic',
        category: 'dart',
        operations: 1000000,
        notes: 'Native Dart reference; same loop shape as js.arithmetic.',
        body: () {
          var sum = 0;
          for (var i = 0; i < 1000000; i++) {
            sum = (sum + i * 3 + (i % 7)) | 0;
          }
          return sum;
        },
      ),
      BenchmarkCase(
        name: 'dart.function_calls',
        category: 'dart',
        operations: 500000,
        body: () {
          int add(int a, int b) => a + b;
          var sum = 0;
          for (var i = 0; i < 500000; i++) {
            sum = add(sum, i);
          }
          return sum;
        },
      ),
      BenchmarkCase(
        name: 'dart.objects_properties',
        category: 'dart',
        operations: 300000,
        body: () {
          final proto = _Proto();
          var sum = 0;
          for (var i = 0; i < 300000; i++) {
            final o = _Value(proto, i);
            sum += o.get();
          }
          return sum;
        },
      ),
      BenchmarkCase(
        name: 'dart.arrays',
        category: 'dart',
        operations: 200000,
        body: () {
          final a = <int>[];
          var sum = 0;
          for (var i = 0; i < 200000; i++) {
            a.add(i);
            sum += a[i];
          }
          return sum + a.length;
        },
      ),
      BenchmarkCase(
        name: 'dart.strings',
        category: 'dart',
        operations: 150000,
        body: () {
          const s = 'abcdefghij';
          var sum = 0;
          for (var i = 0; i < 150000; i++) {
            sum += s.codeUnitAt(i % 10) + s.substring(1, 5).length;
          }
          return sum;
        },
      ),
      BenchmarkCase(
        name: 'dart.recursion',
        category: 'dart',
        operations: 1,
        unit: 'run',
        expected: 46368,
        body: () {
          int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);
          return fib(24);
        },
      ),
      BenchmarkCase(
        name: 'dart.json_parse',
        category: 'dart',
        operations: 5000,
        body: () {
          final text = jsonEncode(List.generate(
              20, (i) => {'id': i, 'name': 'item$i', 'ok': true}));
          var sum = 0;
          for (var i = 0; i < 5000; i++) {
            final value = jsonDecode(text) as List;
            sum += ((value[0] as Map)['id'] as int) + value.length;
          }
          return sum;
        },
      ),
      BenchmarkCase(
        name: 'dart.json_stringify',
        category: 'dart',
        operations: 5000,
        body: () {
          const value = {
            'id': 1,
            'name': 'item',
            'ok': true,
            'nested': {'a': 1, 'b': 2},
          };
          var sum = 0;
          for (var i = 0; i < 5000; i++) {
            sum += jsonEncode(value).length;
          }
          return sum;
        },
      ),
      BenchmarkCase(
        name: 'dart.object_churn',
        category: 'dart',
        operations: 120000,
        body: () {
          var sum = 0;
          for (var i = 0; i < 120000; i++) {
            final o = _Churn(i, i + 1, 'x$i');
            sum += o.a + o.b + o.c.length;
          }
          return sum;
        },
      ),
    ];

class _Proto {
  int value = 0;
  int get() => value;
}

class _Value {
  _Value(this.proto, this.value);
  final _Proto proto;
  final int value;
  int get() => proto.value = value;
}

class _Churn {
  const _Churn(this.a, this.b, this.c);
  final int a;
  final int b;
  final String c;
}
