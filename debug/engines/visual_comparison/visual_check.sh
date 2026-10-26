#!/usr/bin/env bash
# Convenience wrapper: run the headless visual judge from anywhere.
#   debug/engines/visual_comparison/visual_check.sh --suite 50projects50days
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"
exec dart run debug/engines/visual_comparison/bin/visual_check.dart "$@"
