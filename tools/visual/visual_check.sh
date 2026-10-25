#!/usr/bin/env bash
# Convenience wrapper: run the headless visual judge from anywhere.
#   tools/visual/visual_check.sh --suite 50projects50days
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
exec dart run tools/visual/bin/visual_check.dart "$@"
