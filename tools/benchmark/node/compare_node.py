#!/usr/bin/env python3
"""Compare NativaX js_steady.* results with the Node/V8 steady-state run.

Usage:
  python3 tools/benchmark/node/compare_node.py NATIVAX.json V8.json

Both inputs are the JSON emitted by tools/benchmark and steady_bench.mjs.
The printed ratio is NativaX time / V8 time; >1 means NativaX is slower.
The geometric mean is the aggregate ratio over the same benchmark set.
"""

import json
import math
import sys


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    native = load(sys.argv[1])
    v8 = load(sys.argv[2])
    n = {r["name"]: r for r in native["results"]}
    v = {r["name"]: r for r in v8["results"]}
    names = [name for name in v if name in n]
    if not names:
        raise SystemExit("no matching js_steady.* cases")

    print("| Benchmark | NativaX ms | V8 ms | ratio | checksum |")
    print("|---|---:|---:|---:|---|")
    logs = []
    for name in names:
        a = float(n[name]["medianMs"])
        b = float(v[name]["medianMs"])
        ratio = a / b if b else float("inf")
        logs.append(math.log(ratio))
        same = "ok" if n[name].get("checksum") == v[name].get("checksum") else "MISMATCH"
        print(f"| `{name}` | {a:.3f} | {b:.3f} | {ratio:.2f}x | {same} |")

    geomean = math.exp(sum(logs) / len(logs))
    print()
    print(f"Geometric mean NativaX/V8: **{geomean:.2f}x**")
    print(f"Equivalent geometric speedup needed for parity: {geomean:.2f}x")
    print(f"Speedup needed to be 7x faster than V8: {geomean * 7:.1f}x")


if __name__ == "__main__":
    main()
