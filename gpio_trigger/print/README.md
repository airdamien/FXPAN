# Dual-filament silkscreen plate (Bambu H2C)

Two STLs, same origin — load **both** into Bambu Studio:

| File | Filament | Notes |
|------|----------|--------|
| `board.stl` | 1 (e.g. matte green) | 1.6 mm PCB outline with holes |
| `silk.stl` | 2 (e.g. white) | Top silk, 0.25 mm wider + 0.4 mm tall |

Silk is buffered outward before extrusion so thin text survives the slicer.

## Slicer

1. **Add** both STLs to one plate (they should align without moving).
2. Assign **filament 1** to `board.stl`, **filament 2** to `silk.stl`.
3. Print **face up** (silk on top). No supports needed.
4. Suggested: 0.2 mm layers, 0.4 mm nozzle, 3–4 top layers on the silk.
5. If Bambu still drops detail, turn off **filter out tiny areas** (or similar)
   in the slicer, or bump `SILK_SPREAD` in `export_print.py`.

Regenerate from KiCad: `python3 export_print.py`
