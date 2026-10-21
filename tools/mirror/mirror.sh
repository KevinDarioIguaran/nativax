#!/usr/bin/env bash
# Renders the same page in Chrome (reference only, never shipped) and in
# NativaX, then compares element boxes and saves both screenshots.
#
#   tools/mirror/mirror.sh <page-dir> <out-dir> [width] [height] [setup-js] [scheme]
#
# <page-dir> must contain index.html. [setup-js] runs after load in both
# engines (for example "showSec('css')"). [scheme] is light (default) or dark.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
page="$(cd "$1" && pwd)"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
width="${3:-800}"
height="${4:-1600}"
setup="${5:-}"
scheme="${6:-light}"
chrome="${CHROME:-google-chrome}"

# --- Chrome reference -------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$page/." "$work/"
cp "$root/tools/mirror/measure.js" "$work/__mirror_measure.js"
cat > "$work/__mirror_run.js" <<EOF
addEventListener('load', () => setTimeout(() => {
  try { ${setup} } catch (e) { console.error(e); }
  setTimeout(() => {
    const p = document.createElement('pre');
    p.id = '__mirror';
    p.textContent = __mirrorMeasure();
    document.documentElement.appendChild(p);
  }, 300);
}, 200));
EOF
python3 - "$work/index.html" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
tag = '<script src="__mirror_measure.js"></script><script src="__mirror_run.js"></script>'
i = s.lower().rfind('</body>')
s = s[:i] + tag + s[i:] if i >= 0 else s + tag
open(p, 'w', encoding='utf-8').write(s)
PY
pref=1
[ "$scheme" = dark ] && pref=0
"$chrome" --headless=new --disable-gpu --hide-scrollbars --blink-settings=preferredColorScheme=$pref \
  --window-size="$width,$height" --virtual-time-budget=4000 --dump-dom "file://$work/index.html" 2>/dev/null \
  | python3 -c "import sys,re,html; m=re.search(r'<pre id=\"__mirror\">(.*?)</pre>', sys.stdin.read(), re.S); print(html.unescape(m.group(1)) if m else '{}')" \
  > "$out/chrome.json"
"$chrome" --headless=new --disable-gpu --hide-scrollbars --blink-settings=preferredColorScheme=$pref \
  --window-size="$width,$height" --virtual-time-budget=4000 --screenshot="$out/chrome.png" \
  "file://$work/index.html" 2>/dev/null >/dev/null

# --- NativaX ------------------------------------------------------------------
probe="$(cat "$root/tools/mirror/measure.js")"
(cd "$root/examples/web-challenge" && \
  NATIVAX_SHOT="$out/nativax.png" NATIVAX_SHOT_DIR="$page" \
  NATIVAX_SHOT_WIDTH="$width" NATIVAX_SHOT_HEIGHT="$height" \
  NATIVAX_SHOT_SCHEME="$scheme" \
  NATIVAX_SHOT_JS="$probe
${setup}" NATIVAX_SHOT_DUMP="__mirrorMeasure()" \
  flutter test test/screenshot_test.dart 2>&1) \
  | sed -n 's/^DUMP: //p' > "$out/nativax.json"

dart run "$root/tools/mirror/compare.dart" "$out/chrome.json" "$out/nativax.json"
