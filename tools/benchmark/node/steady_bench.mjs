// Reproducible V8 steady-state reference for NativaX's js_steady.* cases.
//
// Each source is compiled once, then executed warmup + rounds times. This
// matches tools/benchmark's js_steady cases (compiled once, measured calls
// only) and intentionally excludes Node startup from the measured samples.
//
// Usage:
//   node tools/benchmark/node/steady_bench.mjs [output.json]
//
// The output shape is intentionally simple; compare_node.py reads both this
// file and the NativaX benchmark JSON.

import { performance } from 'node:perf_hooks';
import { writeFileSync } from 'node:fs';
import os from 'node:os';

const WARMUP = Number(process.env.BENCH_WARMUP ?? 8);
const ROUNDS = Number(process.env.BENCH_ROUNDS ?? 21);

const parseText = JSON.stringify(
  Array.from({ length: 20 }, (_, i) => ({ id: i, name: `item${i}`, ok: true })),
);

const cases = [
  ['js_steady.arithmetic', 1000000, `(() => {
    let sum = 0;
    for (let i = 0; i < 1000000; i++) sum = (sum + i * 3 + (i % 7)) | 0;
    return sum;
  })()`],
  ['js_steady.function_calls', 500000, `(() => {
    function add(a, b) { return a + b; }
    let sum = 0;
    for (let i = 0; i < 500000; i++) sum = add(sum, i);
    return sum;
  })()`],
  ['js_steady.objects_properties', 300000, `(() => {
    const proto = { get() { return this.value; } };
    let sum = 0;
    for (let i = 0; i < 300000; i++) {
      const o = Object.create(proto);
      o.value = i;
      sum += o.get();
    }
    return sum;
  })()`],
  ['js_steady.arrays', 200000, `(() => {
    const a = [];
    let sum = 0;
    for (let i = 0; i < 200000; i++) { a.push(i); sum += a[i]; }
    return sum + a.length;
  })()`],
  ['js_steady.strings', 150000, `(() => {
    const s = 'abcdefghij';
    let sum = 0;
    for (let i = 0; i < 150000; i++) sum += s.charCodeAt(i % 10) + s.slice(1, 5).length;
    return sum;
  })()`],
  ['js_steady.recursion', 1, `(() => {
    function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
    return fib(24);
  })()`],
  ['js_steady.json_parse', 5000, `(() => {
    const text = ${JSON.stringify(parseText)};
    let sum = 0;
    for (let i = 0; i < 5000; i++) {
      const value = JSON.parse(text);
      sum += value[0].id + value.length;
    }
    return sum;
  })()`],
  ['js_steady.json_stringify', 5000, `(() => {
    const value = { id: 1, name: 'item', ok: true, nested: { a: 1, b: 2 } };
    let sum = 0;
    for (let i = 0; i < 5000; i++) sum += JSON.stringify(value).length;
    return sum;
  })()`],
  ['js_steady.object_churn', 120000, `(() => {
    let sum = 0;
    for (let i = 0; i < 120000; i++) {
      const o = { a: i, b: i + 1, c: 'x' + i };
      sum += o.a + o.b + o.c.length;
    }
    return sum;
  })()`],
];

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2
    ? sorted[mid]
    : (sorted[mid - 1] + sorted[mid]) / 2;
};

const results = [];
for (const [name, operations, source] of cases) {
  const fn = new Function(`return (${source});`);
  let checksum;
  for (let i = 0; i < WARMUP; i++) checksum = fn();
  const samples = [];
  for (let i = 0; i < ROUNDS; i++) {
    const start = performance.now();
    const value = fn();
    samples.push(performance.now() - start);
    if (value !== checksum) throw new Error(`${name}: checksum changed`);
  }
  const sorted = [...samples].sort((a, b) => a - b);
  results.push({
    name,
    operations,
    samplesMs: samples,
    medianMs: median(samples),
    minMs: sorted[0],
    maxMs: sorted[sorted.length - 1],
    checksum,
  });
  console.log(`${name}\t${median(samples).toFixed(3)} ms\tchecksum ${checksum}`);
}

const report = {
  engine: 'V8',
  node: process.version,
  v8: process.versions.v8,
  os: `${os.platform()} ${os.release()} ${os.arch()}`,
  cpu: os.cpus()[0]?.model ?? 'unknown',
  warmup: WARMUP,
  rounds: ROUNDS,
  clock: 'node:perf_hooks performance.now()',
  mode: 'compiled-once steady state; startup excluded',
  results,
};

const out = process.argv[2];
if (out) writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`);
