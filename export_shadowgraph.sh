#!/usr/bin/env bash
# Export same-image shadowgraph print STLs into stls/hybrid_shadowgraph/
#   ./export_shadowgraph.sh [part ...]
exec "$(cd "$(dirname "$0")" && pwd)/export_stls.sh" --shadowgraph "$@"
