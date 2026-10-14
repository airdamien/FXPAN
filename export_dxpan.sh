#!/usr/bin/env bash
# Export DXPAN 65. Fork of the FXPAN OpenSCAD body; STLs go to stls/dxpan/.
#
#   ./export_dxpan.sh [part ...]
exec "$(cd "$(dirname "$0")" && pwd)/export_stls.sh" --dxpan "$@"
