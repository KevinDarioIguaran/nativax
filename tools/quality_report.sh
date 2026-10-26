#!/usr/bin/env bash
# Runs both quality suites end to end and prints the report locations.
#
#   tools/quality_report.sh              # 51 visual + 245 performance + app idle
#   tools/quality_report.sh --all-visual # 300 visual + performance + app idle
#   tools/quality_report.sh --gui        # ... and open the Tkinter dashboard
#
# FAIL/INVALID pages and scenarios are expected findings, not a script error;
# the suites still write their JSON/Markdown reports.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

visual_args=(--suite 50projects50days)
gui=0
for arg in "$@"; do
  case "$arg" in
    --all-visual) visual_args=(--all --catalog .visual/catalog.json) ;;
    --gui) gui=1 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

echo "=== visual fidelity (${visual_args[*]}) ==="
dart run debug/engines/visual_comparison/bin/visual_check.dart \
  "${visual_args[@]}" \
  --out .visual/latest || true

echo
echo "=== performance (245 scenarios + app idle) ==="
dart run debug/engines/performance/bin/perf.dart run \
  --app-idle \
  --out .perf/latest || true

echo
echo "=== recommendations ==="
python3 tools/recommend.py --out progress/reports/recommendations-latest.md || true

echo
echo "Reports:"
echo "  .visual/latest/report.md            visual summary"
echo "  .visual/latest/results.json         visual table"
echo "  .perf/latest/report.md              performance summary"
echo "  .perf/latest/results.json           performance table"
echo "  .perf/latest/app-idle.json          real app idle"
echo "  .perf/latest/charts/*.svg           charts"
echo "  progress/reports/nativa-quality-latest.md  consolidated report"
echo "  progress/reports/recommendations-latest.md  automatic recommendations"

if [[ "$gui" == "1" ]]; then
  python3 debug/engines/performance/gui/perf_gui.py
fi
