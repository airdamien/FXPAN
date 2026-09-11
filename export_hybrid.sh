#!/usr/bin/env bash
# Export hybrid print STLs into stls/hybrid/
#   ./export_hybrid.sh [part ...]
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
scad=$root/openscad/hybrid/WATCH_ME.scad
out=$root/stls/hybrid
parts=(chassis stem arm_r arm_t lid hybrid_tray shims elnikkor_adapter)
if [[ $# -gt 0 ]]; then
    parts=("$@")
fi

if [[ -n "${OPENSCAD:-}" && -x "$OPENSCAD" ]]; then
    osc=$OPENSCAD
elif [[ -x /Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD ]]; then
    osc=/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD
elif command -v openscad >/dev/null; then
    osc=$(command -v openscad)
else
    echo "OpenSCAD not found. Set OPENSCAD or install the app." >&2
    exit 1
fi

mkdir -p "$out"

for part in "${parts[@]}"; do
    dest=$out/$part.stl
    echo "export $part -> $dest"
    "$osc" -o "$dest" --export-format binstl -D "PART=\"$part\"" "$scad"
done

echo "done. print chassis floor-down; tubes cookie-down."
echo "$out"
