#!/usr/bin/env bash
# Runs the same scenarios under several Docker CPU/RAM limits and summarizes
# the comparison. Results land in debug/artifacts/perf/container/matrix.{json,md}.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
only="${ONLY:-js.arrays|dom.rows-create-1k|scroll.2d-tiles}"
configs=(
  "desktop 2 2g"
  "mobile 1 1g"
  "low 0.5 768m"
)

for spec in "${configs[@]}"; do
  read -r name cpus memory <<<"$spec"
  echo
  echo "=== container: $name (cpus=$cpus memory=$memory) ==="
  "$root/debug/engines/performance/container/run.sh" \
    --cpus "$cpus" --memory "$memory" --name "$name" --only "$only" || true
done

python3 "$root/debug/engines/performance/container/summarize.py"
