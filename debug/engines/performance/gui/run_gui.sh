#!/usr/bin/env bash
# Launches the NativaX quality dashboard without a terminal after this point.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$root"
exec python3 debug/engines/performance/gui/perf_gui.py "$@"
