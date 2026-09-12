#!/usr/bin/env bash
# Export E-mount / α7 hybrid print STLs into stls/Ehybrid/
#   ./export_ehybrid.sh [part ...]
exec "$(cd "$(dirname "$0")" && pwd)/export_stls.sh" --ehybrid "$@"
