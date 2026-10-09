#!/usr/bin/env bash
# Export FXPAN 65. Two D800s, a 50×75×1 plate, 64.80 mm stitch at 2.711:1.
# The built lens is the Nikkor-W (stem_m65, stem_nw_m65, arm_*_wl).
# Shares nothing with hybrid_shift: the bore is wider (TUBE_ID 46 / F_BORE
# 43.5) so the 14.4 mm shift does not vignette. Every STL is stamped fxp_*.
#   ./export_fxpan.sh [part ...]     → stls/fxpan/
exec "$(cd "$(dirname "$0")" && pwd)/export_stls.sh" --fxpan "$@"
