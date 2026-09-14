#!/usr/bin/env bash
# Export shifted-DX hybrid print STLs into stls/hybrid_shift/
#   ./export_hybrid_shift.sh [part ...]
exec "$(cd "$(dirname "$0")" && pwd)/export_stls.sh" --hybrid-shift "$@"
