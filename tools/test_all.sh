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

echo "=== debug harness ==="
# Offscreen harnesses used by the debug engines; their tests are env-gated
# and skip here, so this checks that the package builds and analyzes.
(cd "$root/debug/harness" && flutter analyze && flutter test)

echo "=== conformance analyze ==="
(cd "$root/debug/engines/compatibility" && dart analyze)

echo "=== run manifest tests ==="
(cd "$root/debug/manifest" && dart test)

echo "=== run manifest analyze ==="
(cd "$root/debug/manifest" && dart analyze)

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
(cd "$root" && python3 -m py_compile debug/engines/quality_gate/quality_gate.py debug/scripts/render_report.py debug/engines/recommendations/recommend.py tools/run_video_contract.py debug/logic/history/history.py debug/logic/storage.py debug/logic/json_validate.py debug/logic/context.py debug/logic/ia_audit.py debug/logic/test_docs_links.py debug/run.py tools/test_architecture.py tools/check_docs.py tools/test_check_docs.py debug/engines/performance/gui/perf_gui.py debug/engines/performance/container/summarize.py debug/engines/bug_detection/audit.py debug/engines/bug_detection/gui/app.py debug/app/main.py debug/logic/catalog.py debug/logic/workspaces.py debug/logic/compare_runs.py && python3 debug/engines/recommendations/test_recommend.py && python3 tools/test_video_manifest.py && python3 debug/logic/history/test_history.py && python3 debug/logic/test_storage.py && python3 debug/logic/test_context.py && python3 debug/logic/test_output_schemas.py && python3 debug/logic/test_docs_links.py && python3 tools/test_architecture.py && python3 tools/test_check_docs.py && python3 debug/engines/bug_detection/test_audit.py && python3 debug/engines/bug_detection/gui/test_gui.py && python3 debug/engines/quality_gate/test_quality_gate.py && python3 debug/engines/performance/gui/test_perf_gui.py && python3 debug/logic/test_compare_runs.py && python3 debug/tests/ui/test_app.py)
