#!/usr/bin/env bash
# Export EF / 5D Mark III hybrid print STLs into stls/EFhybrid/
#   ./export_efhybrid.sh [part ...]
exec "$(cd "$(dirname "$0")/.." && pwd)/export_stls.sh" --efhybrid "$@"
