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
(cd "$root/tools/conformance" && dart analyze)

echo "=== benchmark tests ==="
(cd "$root/tools/benchmark" && dart test)

echo "=== benchmark analyze ==="
(cd "$root/tools/benchmark" && dart analyze)

echo "=== leak tests ==="
(cd "$root/tools/leaks" && dart test)

echo "=== leak analyze ==="
(cd "$root/tools/leaks" && dart analyze)

echo "=== security tests ==="
(cd "$root/tools/security" && dart test)

echo "=== security analyze ==="
(cd "$root/tools/security" && dart analyze)
