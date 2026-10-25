#!/usr/bin/env bash
# Render a Markdown report to HTML and open it (preview, not source).
#
#   tools/preview_report.sh
#   tools/preview_report.sh progress/reports/perf-latest.md
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
file="${1:-progress/reports/nativa-quality-latest.md}"
if [[ ! -f "$file" ]]; then
  echo "no existe: $file" >&2
  exit 2
fi
python3 tools/render_report.py "$file" --open
