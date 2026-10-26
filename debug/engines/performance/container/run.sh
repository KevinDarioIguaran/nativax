#!/usr/bin/env bash
# Runs the performance suite inside a resource-limited Docker container.
#
#   debug/engines/performance/container/run.sh --cpus 1 --memory 1g --name low-end
#   debug/engines/performance/container/run.sh --cpus 2 --memory 2g --name desktop
#   debug/engines/performance/container/run.sh --only 'js.arrays' --cpus 0.5 --memory 1g
#
# The image is built once (Debian + Chromium + build tools). Flutter and the
# repository are mounted at their real host paths so package configs and the
# SDK cache keep working; no WebView is involved.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
image="${IMAGE:-nativa-perf:local}"
cpus="${CPUS:-2}"
memory="${MEMORY:-2g}"
name="${NAME:-custom}"
only="${ONLY:-js.arrays|dom.rows-create-1k|scroll.2d-tiles}"
summarize=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cpus) cpus="$2"; shift 2 ;;
    --memory) memory="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --only) only="$2"; shift 2 ;;
    --no-summary) summarize=0; shift ;;
    --build) docker build -t "$image" "$root/debug/engines/performance/container"; shift ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

# Keep the artifact directory safe for arbitrary user labels.
safe_name="$(printf '%s' "$name" | tr -cs 'A-Za-z0-9._-' '-')"
out="$root/.perf/container/$safe_name"
mkdir -p "$out"

if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "[container] building $image (one time) ..."
  docker build -t "$image" "$root/debug/engines/performance/container"
fi

# Mount at the host absolute paths: the workspace package_config and the
# Flutter SDK contain absolute paths. --network none keeps the run offline.
set +e
docker run --rm --init \
  --cpus "$cpus" \
  --memory "$memory" \
  --shm-size 1g \
  --network none \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e PUB_CACHE=/home/k3vin/.pub-cache \
  -e NATIVAX_PERF_NO_SANDBOX=1 \
  -e FLUTTER_SUPPRESS_ANALYTICS=true \
  -e CI=true \
  -v "$root:$root" \
  -v /usr/local/flutter:/usr/local/flutter \
  -v "$HOME/.pub-cache:/home/k3vin/.pub-cache" \
  -w "$root" \
  "$image" \
  bash -lc "export PATH=/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:\$PATH; \
    dart run debug/engines/performance/bin/perf.dart run --no-externals --chrome chromium \
      --only '$only' --out '$out'"
status=$?
set -e

cat > "$out/container.json" <<JSON
{
  "id": "$safe_name",
  "name": "$name",
  "label": "$name · $cpus CPU · $memory",
  "cpus": "$cpus",
  "memory": "$memory",
  "only": "$only",
  "image": "$image",
  "exit_code": $status,
  "generated_at": "$(date -Iseconds)"
}
JSON

if [[ "$summarize" == "1" ]]; then
  python3 "$root/debug/engines/performance/container/summarize.py" >/dev/null || true
fi

echo
echo "[container] name=$safe_name cpus=$cpus memory=$memory only='$only'"
echo "[container] results: $out/results.json"
echo "[container] report:  $out/report.md"
# A failing scenario is a valid result, not a runner error.
exit 0
