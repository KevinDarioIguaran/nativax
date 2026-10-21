#!/usr/bin/env bash
# Benchmark one NativaX game-player run with fixed geometry and JSONL metrics.
#
# Usage:
#   tools/bench_game_player.sh base_r1 [seconds]
#   NATIVAX_NO_BACKDROP=1 tools/bench_game_player.sh nobd_r1 [seconds]
#
# The player bundle must have been built in release mode. This script is
# measurement tooling: it never modifies the game bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/examples/game-player/build/linux/x64/release/bundle"
BIN="$BUNDLE/nativax_game_player"
LABEL="${1:?usage: $0 <label> [seconds]}"
SECONDS_TO_RUN="${2:-36}"
OUT_DIR="${NATIVAX_METRICS_DIR:-/tmp/opencode/nativax-metrics}"
OUT="$OUT_DIR/$LABEL.jsonl"
LOG="$OUT_DIR/$LABEL.log"
KWIN_HELPER="$OUT_DIR/activate_$LABEL.js"

if [[ ! -x "$BIN" ]]; then
  echo "error: missing $BIN; run flutter build linux --release" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT" "$LOG"
# The bracket keeps pkill from matching this script's own command line.
pkill -f '[n]ativax_game_player$' 2>/dev/null || true
sleep 2

{
  echo "date=$(date -Is)"
  echo "label=$LABEL"
  echo "seconds=$SECONDS_TO_RUN"
  echo "no_backdrop=${NATIVAX_NO_BACKDROP:-0}"
  echo "cpus=$(nproc)"
  echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
} | tee "$OUT_DIR/$LABEL.meta"

cd "$BUNDLE"
NATIVAX_FIXED_WINDOW=1 \
NATIVAX_AUTOSTART=1 \
NATIVAX_GAME_DPR=1.0 \
NATIVAX_METRICS=1 \
NATIVAX_METRICS_FILE="$OUT" \
NATIVAX_METRICS_LABEL="$LABEL" \
NATIVAX_NO_BACKDROP="${NATIVAX_NO_BACKDROP:-0}" \
setsid ./nativax_game_player >"$LOG" 2>&1 </dev/null &
APP_PID=$!
cd "$ROOT"

# Wait for the game's Start button to be clicked by the host autostart hook.
for _ in $(seq 1 40); do
  if grep -q 'autostart: dispatched DOM click' "$LOG" 2>/dev/null; then
    break
  fi
  sleep 1
done

cat >"$KWIN_HELPER" <<'EOF'
const windows = workspace.windowList();
for (const w of windows) {
  if (w.caption.indexOf("Three.js Multiplayer Starter") >= 0) {
    workspace.activeWindow = w;
  }
}
EOF
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.loadScript "$KWIN_HELPER" "activate_$LABEL" \
  >/dev/null 2>&1 || true
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.start >/dev/null 2>&1 || true

sleep "$SECONDS_TO_RUN"

kill -TERM "$APP_PID" 2>/dev/null || true
for _ in $(seq 1 10); do
  kill -0 "$APP_PID" 2>/dev/null || break
  sleep 0.5
done
kill -KILL "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

echo "metrics=$OUT"
wc -l "$OUT" 2>/dev/null || true
