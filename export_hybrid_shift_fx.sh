#!/usr/bin/env bash
# Export shifted-FX (D800) parts that differ from the DX shift kit.
# Reuse stem, hybrid_tray, shims, monitor, and tools from hybrid_shift/.
#   ./export_hybrid_shift_fx.sh [part ...]
exec "$(cd "$(dirname "$0")" && pwd)/export_stls.sh" --hybrid-shift-fx "$@"
