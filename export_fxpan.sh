#!/usr/bin/env bash
# Export FXPAN 65 — the clean-sheet FX panoramic body. Two D800 behind one
# EL-Nikkor 180/5.6N and a 75×75×1 50/50 plate; 64.80 mm stitch at 2.711:1.
# Shares nothing with hybrid_shift: the bore is wider (TUBE_ID 46 / F_BORE
# 43.5) so the 14.4 mm shift does not vignette. Every STL is stamped fxp_*.
#   ./export_fxpan.sh [part ...]     → stls/fxpan/
exec "$(cd "$(dirname "$0")" && pwd)/export_stls.sh" --fxpan "$@"
