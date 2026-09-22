#!/usr/bin/env python3
"""Export a dual-filament silkscreen plate for Bambu H2C (or any AMS).

Writes two aligned STLs into print/:
  board.stl  — FR-4 outline with holes (filament 1, e.g. green)
  silk.stl   — top silk only, widened and raised (filament 2, e.g. white)

Regenerate from the KiCad board:
  python3 export_print.py
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VENV_PY = ROOT.parent / "logos" / ".venv" / "bin" / "python3"
KICAD_CLI = Path("/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli")
PCB = ROOT / "kicad" / "gpio_trigger.kicad_pcb"
OUT = ROOT / "print"
SILK_THICKNESS = 0.40  # mm proud of the board top
SILK_SPREAD = 0.25  # mm outward buffer so thin strokes survive the slicer


def _ensure_geom_deps() -> None:
    try:
        import cadquery  # noqa: F401
        import shapely  # noqa: F401
    except ImportError:
        if VENV_PY.exists():
            os.execv(VENV_PY, [str(VENV_PY), str(Path(__file__).resolve())] + sys.argv[1:])
        raise SystemExit(
            "Need cadquery + shapely. Run: cd ../logos && python3 -m venv .venv && "
            ".venv/bin/pip install cadquery shapely"
        )


def _run_kicad_stl(out: Path, *flags: str) -> None:
    if not KICAD_CLI.exists():
        raise SystemExit(f"KiCad CLI not found at {KICAD_CLI}")
    cmd = [
        str(KICAD_CLI),
        "pcb",
        "export",
        "stl",
        "-o",
        str(out),
        *flags,
        str(PCB),
    ]
    subprocess.run(cmd, check=True)


def _read_tris(path: Path) -> list[tuple[tuple[float, float, float], ...]]:
    text = path.read_text(errors="ignore")
    if "vertex" not in text:
        text = path.read_bytes().decode("latin-1", errors="ignore")
    verts = [
        (float(m.group(1)), float(m.group(2)), float(m.group(3)))
        for m in re.finditer(
            r"vertex\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)", text
        )
    ]
    if len(verts) % 3:
        raise SystemExit(f"{path}: vertex count not divisible by 3")
    return [tuple(verts[i : i + 3]) for i in range(0, len(verts), 3)]


def _board_top_z(tris: list[tuple[tuple[float, float, float], ...]]) -> float:
    return max(p[2] for tri in tris for p in tri)


def _top_silk_caps(
    tris: list[tuple[tuple[float, float, float], ...]],
) -> list[tuple[tuple[float, float, float], ...]]:
    top_z = max(p[2] for tri in tris for p in tri)
    mid = (top_z + min(p[2] for tri in tris for p in tri)) / 2
    caps = [tri for tri in tris if all(p[2] >= mid for p in tri)]
    if not caps:
        raise SystemExit("no top silk triangles found")
    return caps


def _write_widened_silk_stl(
    caps: list[tuple[tuple[float, float, float], ...]], board_top: float, out: Path
) -> None:
    import cadquery as cq
    from shapely.geometry import Polygon
    from shapely.ops import unary_union

    merged = unary_union(
        [
            Polygon([(a[0], a[1]), (b[0], b[1]), (c[0], c[1])])
            for a, b, c in caps
        ]
    )
    widened = merged.buffer(SILK_SPREAD, join_style=2)

    def poly_solid(poly: Polygon) -> cq.Workplane:
        wp = cq.Workplane("XY").workplane(offset=board_top)
        outer = [(x, y) for x, y in poly.exterior.coords[:-1]]
        wp = wp.polyline(outer).close()
        for ring in poly.interiors:
            hole = [(x, y) for x, y in ring.coords[:-1]]
            wp = wp.polyline(hole).close()
        return wp.extrude(SILK_THICKNESS)

    geoms = [widened] if widened.geom_type == "Polygon" else list(widened.geoms)
    solids = [poly_solid(g) for g in geoms if not g.is_empty and g.area > 0.01]
    if not solids:
        raise SystemExit("widened silk is empty")

    result = solids[0]
    for solid in solids[1:]:
        result = result.union(solid)
    cq.exporters.export(result, str(out))


def main() -> None:
    _ensure_geom_deps()

    if not PCB.exists():
        raise SystemExit(f"missing {PCB} — run python3 gen_cad.py first")

    tmp = OUT / ".tmp"
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)

    board_raw = tmp / "board_raw.stl"
    silk_raw = tmp / "silk_raw.stl"
    _run_kicad_stl(board_raw, "--board-only", "--no-components")
    _run_kicad_stl(silk_raw, "--no-board-body", "--no-components", "--include-silkscreen")

    board_tris = _read_tris(board_raw)
    board_top = _board_top_z(board_tris)
    caps = _top_silk_caps(_read_tris(silk_raw))

    OUT.mkdir(exist_ok=True)
    board_out = OUT / "board.stl"
    silk_out = OUT / "silk.stl"
    shutil.copy2(board_raw, board_out)
    _write_widened_silk_stl(caps, board_top, silk_out)
    shutil.rmtree(tmp)

    readme = OUT / "README.md"
    readme.write_text(
        f"""# Dual-filament silkscreen plate (Bambu H2C)

Two STLs, same origin — load **both** into Bambu Studio:

| File | Filament | Notes |
|------|----------|--------|
| `board.stl` | 1 (e.g. matte green) | 1.6 mm PCB outline with holes |
| `silk.stl` | 2 (e.g. white) | Top silk, {SILK_SPREAD:.2f} mm wider + {SILK_THICKNESS:.1f} mm tall |

Silk is buffered outward before extrusion so thin text survives the slicer.

## Slicer

1. **Add** both STLs to one plate (they should align without moving).
2. Assign **filament 1** to `board.stl`, **filament 2** to `silk.stl`.
3. Print **face up** (silk on top). No supports needed.
4. Suggested: 0.2 mm layers, 0.4 mm nozzle, 3–4 top layers on the silk.
5. If Bambu still drops detail, turn off **filter out tiny areas** (or similar)
   in the slicer, or bump `SILK_SPREAD` in `export_print.py`.

Regenerate from KiCad: `python3 export_print.py`
"""
    )

    print(f"Wrote {board_out}")
    print(f"Wrote {silk_out} (spread {SILK_SPREAD} mm, height {SILK_THICKNESS} mm)")
    print(f"Wrote {readme}")


if __name__ == "__main__":
    main()
