#!/usr/bin/env bash
# Runs every test suite from its package directory. Native assets (QuickJS)
# are resolved per package, so `flutter test packages/...` from the root is not
# equivalent and must not be used in CI.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for pkg in nativa_js nativa_dom nativa_html nativa_css nativa_dom_bindings; do
  echo "=== $pkg ==="
  (cd "$root/packages/$pkg" && dart test)
done

for pkg in nativa_render nativax; do
  echo "=== $pkg ==="
  (cd "$root/packages/$pkg" && flutter test)
done

for ex in "$root"/examples/*/; do
  [ -f "$ex/pubspec.yaml" ] || continue
  # Some examples are runnable shells without their own test suite. Do not
  # fail the whole run just because `flutter test` has nothing to discover.
  [ -d "$ex/test" ] || continue
  echo "=== examples/$(basename "$ex") ==="
  (cd "$ex" && flutter test)
done

echo "=== conformance analyze ==="
(cd "$root/debug/engines/compatibility" && dart analyze)

echo "=== benchmark tests ==="
(cd "$root/debug/engines/microbenchmarks" && dart test)

echo "=== benchmark analyze ==="
(cd "$root/debug/engines/microbenchmarks" && dart analyze)

echo "=== leak tests ==="
(cd "$root/debug/engines/memory" && dart test)

echo "=== leak analyze ==="
(cd "$root/debug/engines/memory" && dart analyze)

echo "=== security tests ==="
(cd "$root/debug/engines/security" && dart test)

echo "=== security analyze ==="
(cd "$root/debug/engines/security" && dart analyze)

echo "=== visual tests ==="
(cd "$root/debug/engines/visual_comparison" && dart test)

echo "=== visual analyze ==="
(cd "$root/debug/engines/visual_comparison" && dart analyze)

echo "=== perf tests ==="
(cd "$root/debug/engines/performance" && dart test)

echo "=== perf analyze ==="
(cd "$root/debug/engines/performance" && dart analyze)

echo "=== python tooling syntax and recommendation tests ==="
(cd "$root" && python3 -m py_compile tools/quality_gate.py tools/render_report.py tools/recommend.py tools/run_video_contract.py tools/history.py tools/test_architecture.py debug/engines/performance/gui/perf_gui.py debug/engines/performance/container/summarize.py tools/audit/audit.py tools/audit/gui/app.py && python3 tools/test_recommend.py && python3 tools/test_video_manifest.py && python3 tools/test_history.py && python3 tools/test_architecture.py && python3 tools/audit/test_audit.py && python3 tools/audit/gui/test_gui.py)
