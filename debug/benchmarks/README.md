# debug/benchmarks

Per-run results for the three benchmark engines, plus tracked baselines.

```text
debug/benchmarks/<area>/<run_id>/
    <result>.json        run results
    <result>.jsonl       per-batch samples (leaks only)
    <result>.md          human report
    manifest.json        validated run manifest (schema 1.0)
```

`<run_id>` is `<UTC ISO basic>Z[-<git short sha>][-N]`, so lexical order is
chronological. `debug/manifest` writes the manifest; the schema is
`debug/logic/schemas/run-manifest.schema.json`, shared with
`debug/logic/storage.py` and the dashboard archive format.

| Area | Engine | Output |
|---|---|---|
| JS/bridge/DOM/style microbenchmarks | `debug/engines/microbenchmarks` | `debug/benchmarks/microbench/<run_id>/` |
| Leaks/lifecycle | `debug/engines/memory` | `debug/benchmarks/leaks/<run_id>/` |
| Security/host APIs | `debug/engines/security` | `debug/benchmarks/security/<run_id>/` |

Directories are created without overwriting. `--out DIR` makes an engine write
to an explicit directory (and still emit its manifest).

Run directories are **gitignored**. Tracked evidence is limited to:

- `baselines/`: small profiles cited by reports;
- `game-player-phase0/`: phase-0 presentation evidence.

## Run

```bash
cd debug/engines/microbenchmarks
dart run bin/benchmark.dart run --warmup 3 --rounds 15

cd debug/engines/memory
dart run bin/leaks.dart run --profile quick

cd debug/engines/security
dart run bin/security.dart run
```

## Inspect and compare

```bash
ls -1 debug/benchmarks/microbench
python3 debug/run.py runs --area security
python3 debug/run.py context runs --area microbench

cd debug/engines/microbenchmarks
dart run bin/benchmark.dart compare \
  --baseline debug/benchmarks/microbench/<run-a>/bench-*.json \
  --current debug/benchmarks/microbench/<run-b>/bench-*.json
```

Check the manifest before quoting a result. A run directory without its
manifest is incomplete. `progress/reports/*-latest.md` are convenience copies
and may lag the immutable run directory.

See [`../../docs/benchmarks.md`](../../docs/benchmarks.md) for how to read the
numbers, and [`../README.md`](../README.md) for the overall diagnostics layout.
