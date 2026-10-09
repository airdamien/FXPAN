#!/usr/bin/env bash
# Export hybrid print STLs into stls/hybrid/
#   ./export_hybrid.sh [part ...]
exec "$(cd "$(dirname "$0")/.." && pwd)/export_stls.sh" --hybrid "$@"
