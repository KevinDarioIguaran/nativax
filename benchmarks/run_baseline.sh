#!/usr/bin/env bash
# Reproducible baseline capture. Requires the runtime to be built.
# Usage: benchmarks/run_baseline.sh [app-dir]   (default: examples/counter)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${NATIVAX_BUILD_DIR:-$ROOT/build}"
APP="${1:-$ROOT/examples/counter}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/benchmarks/results/measure-$STAMP.json"

if [ ! -x "$BUILD/nativax-runtime" ]; then
  echo "runtime not built: $BUILD/nativax-runtime" >&2
  exit 1
fi

{
  printf '{\n  "date": "%s",\n  "app": "%s",\n  "headless": [' "$(date -Iseconds)" "$APP"
  for i in 1 2 3; do
    [ "$i" -gt 1 ] && printf ','
    "$BUILD/nativax-runtime" --headless --root "$APP" --frames 60 --mem 2>/dev/null | tail -1
  done
  printf '],\n  "windowed": ['
  if [ -n "${DISPLAY:-}" ]; then
    for i in 1 2 3; do
      [ "$i" -gt 1 ] && printf ','
      timeout 60 "$BUILD/nativax-runtime" --root "$APP" --frames 120 --mem 2>/dev/null | tail -1
    done
  fi
  printf '],\n  "render_bench": '
  "$BUILD/nativax_bench" --w 1024 --h 768 --iters 20 --cards 6 --text 40
  printf '}\n'
} > "$OUT"

echo "wrote $OUT"
