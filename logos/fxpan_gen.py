#!/usr/bin/env python
"""FXPAN logo generator: web SVG plus colour-separated STL parts.

Geometry is authored in reference-image pixel space (x right, y down) and
mapped to millimetres so the finished mark is 145 mm wide including the
outline, per the FXPAN technical schema.

Outputs (all in this directory):
    fxpan.svg                  transparent, web-embeddable
    fxpan_fx_gold.stl          FX monogram + sweep
    fxpan_pan_white.stl        PAN lettering
    fxpan_outline_red.stl      offset outline
    fxpan_backer_optional.stl  flat carrier plate (holds the loose islands)

The three coloured parts share one origin and never interpenetrate, so a
slicer can load them as a single multi-material object.
"""

from pathlib import Path

import cadquery as cq
from shapely.geometry import MultiPolygon, Polygon
from shapely.ops import unary_union

HERE = Path(__file__).resolve().parent

# --- physical parameters -------------------------------------------------
MARK_WIDTH_MM = 140.0   # gold silhouette width; +outline lands on 145 mm
RELIEF_MM = 3.0         # height of every coloured part
OUTLINE_GAP_MM = 2.2    # silhouette -> outline centreline
OUTLINE_WIDTH_MM = 0.8
BACKER_MM = 2.0
BACKER_MARGIN_MM = 4.0

# Fill the F's counters before offsetting so the outline reads as one frame
# around the mark, the way the reference render draws it, instead of threading
# into every notch.
OUTLINE_FRAME_ONLY = True

MITRE = dict(join_style="mitre", mitre_limit=24)

# --- reference-space anchors --------------------------------------------
PX_X0, PX_X1 = 175.0, 889.0   # silhouette extents in the reference image
PX_Y0 = 436.0                 # F stem bottom-left, used as the y datum
SCALE = MARK_WIDTH_MM / (PX_X1 - PX_X0)


def cubic(p0, p1, p2, p3, step=2.0):
    """Flatten a cubic bezier to a polyline, excluding the start point."""
    span = sum(
        abs(complex(*b) - complex(*a))
        for a, b in zip((p0, p1, p2), (p1, p2, p3))
    )
    n = max(8, int(span / step))
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        out.append(
            (
                u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0],
                u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1],
            )
        )
    return out


# --- F monogram ----------------------------------------------------------
# Every chamfer runs at the mark's single design angle, dy/dx = 1.5.
F_RING = [
    (175, 82),    # top left
    (490, 82),    # top bar point
    (450, 142),   # chamfered bar end
    (235, 142),
    (235, 193),
    (310, 193),   # middle bar point
    (274, 247),   # chamfered bar end
    (235, 247),
    (235, 346),
    (175, 436),   # stem foot
]
# The F with its counters closed off by a single diagonal, so the outline
# frames the mark instead of threading around the bars. Outer edges (left,
# top, bar chamfer, stem foot) are the real ones; only the right side is
# bridged, and that bridge is swallowed by the X in the union.
F_ENVELOPE = [(175, 82), (490, 82), (450, 142), (235, 346), (175, 436)]

# --- X strokes and sweep -------------------------------------------------
# Vertices of the diamond where the two X strokes cross.
X_TOP = (429.8, 198.1)
X_RIGHT = (466.3, 252.0)
X_BOTTOM = (426.8, 310.5)
X_LEFT = (390.3, 256.5)

SWEEP_TOP = ((466.0, 252.0), (566.7, 350.2), (478.3, 387.1), (889.0, 389.0))
SWEEP_TIP = ((889.0, 389.0), (896.0, 390.0), (896.0, 394.0), (886.0, 395.0))
SWEEP_BOT = ((886.0, 395.0), (490.3, 419.7), (537.6, 405.0), (426.8, 310.5))

X_RING = (
    [
        (319, 151),   # upper-left arm tip, tucked under the F's top bar
        (398, 151),
        X_TOP,
        (509, 81),    # upper-right arm tip
        (582, 81),
        X_RIGHT,      # the sweep leaves the diamond here
    ]
    + cubic(*SWEEP_TOP)
    + cubic(*SWEEP_TIP, step=1.0)
    + cubic(*SWEEP_BOT)
    + [
        (365, 402),   # lower-left leg foot
        (292, 402),
        X_LEFT,
    ]
)

# --- PAN lettering -------------------------------------------------------
P_OUTER = (
    [(547, 221), (629, 221)]
    + cubic((629, 221), (639, 221), (646, 230), (646, 246.5))
    + cubic((646, 246.5), (646, 263), (639, 272), (629, 272))
    + [(561, 272), (561, 305), (547, 305)]
)
P_COUNTER = (
    [(561, 232), (625, 232)]
    + cubic((625, 232), (632, 232), (632, 239), (632, 247))
    + cubic((632, 247), (632, 255), (632, 262), (625, 262))
    + [(561, 262)]
)
A_OUTER = [
    (641, 305), (688, 221), (711, 221), (758, 305),
    (742, 305), (732, 286), (667, 286), (657, 305),
]
A_COUNTER = [(699.5, 236), (721, 274), (678, 274)]
N_OUTER = [
    (774, 221), (793, 221), (871, 286), (871, 221), (886, 221),
    (886, 305), (867, 305), (789, 243), (789, 305), (774, 305),
]


def poly(outer, *holes):
    """Shapely polygon from reference pixels, converted to millimetres."""
    def mm(ring):
        return [((x - PX_X0) * SCALE, (PX_Y0 - y) * SCALE) for x, y in ring]

    return Polygon(mm(outer), [mm(h) for h in holes])


def parts_of(shape):
    return shape.geoms if isinstance(shape, MultiPolygon) else [shape]


def build():
    gold = unary_union([poly(F_RING), poly(X_RING)])
    pan = unary_union([
        poly(P_OUTER, P_COUNTER), poly(A_OUTER, A_COUNTER), poly(N_OUTER)
    ])

    source = gold
    if OUTLINE_FRAME_ONLY:
        source = unary_union([poly(F_ENVELOPE), poly(X_RING)])
    half = OUTLINE_WIDTH_MM / 2
    outline = source.buffer(OUTLINE_GAP_MM + half, **MITRE).difference(
        source.buffer(OUTLINE_GAP_MM - half, **MITRE)
    )
    # Tight notches pinch off specks that would print as loose chips.
    outline = unary_union([p for p in parts_of(outline) if p.area > 20.0])
    return gold, pan, outline


def prism(shape, height=RELIEF_MM, base=0.0):
    """Extrude a shapely polygon (or multipolygon) into a CadQuery solid."""
    solid = None
    for p in parts_of(shape):
        piece = (
            cq.Workplane("XY", origin=(0, 0, base))
            .polyline(list(p.exterior.coords)[:-1]).close().extrude(height)
        )
        for hole in p.interiors:
            piece = piece.cut(
                cq.Workplane("XY", origin=(0, 0, base))
                .polyline(list(hole.coords)[:-1]).close().extrude(height)
            )
        solid = piece if solid is None else solid.union(piece)
    return solid


SVG_TEMPLATE = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" \
width="{w:.2f}mm" height="{h:.2f}mm" role="img" aria-labelledby="fxpan-title">
  <title id="fxpan-title">FXPAN</title>
  <defs>
    <linearGradient id="fxpan-gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#E7CC72"/>
      <stop offset="0.45" stop-color="#C9A227"/>
      <stop offset="1" stop-color="#8E6C14"/>
    </linearGradient>
    <linearGradient id="fxpan-steel" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#C6C9CC"/>
    </linearGradient>
  </defs>
  <path d="{outline}" fill="#A81A1F" fill-rule="evenodd"/>
  <path d="{gold}" fill="url(#fxpan-gold)" fill-rule="evenodd"/>
  <path d="{pan}" fill="url(#fxpan-steel)" fill-rule="evenodd"/>
</svg>
"""


def svg_path(shape, oy):
    out = []
    for p in parts_of(shape):
        for ring in [p.exterior, *p.interiors]:
            pts = " L ".join(
                f"{x:.3f},{oy - y:.3f}" for x, y in list(ring.coords)[:-1]
            )
            out.append(f"M {pts} Z")
    return " ".join(out)


def main():
    gold, pan, outline = build()
    art = unary_union([outline, pan])
    x0, y0, x1, y1 = art.bounds
    m = BACKER_MARGIN_MM
    plate = (
        cq.Workplane("XY")
        .center((x0 + x1) / 2, (y0 + y1) / 2)
        .rect(x1 - x0 + 2 * m, y1 - y0 + 2 * m)
        .extrude(-BACKER_MM)
        .edges("|Z")
        .fillet(6.0)
    )

    solids = {
        "fxpan_fx_gold.stl": prism(gold),
        "fxpan_pan_white.stl": prism(pan),
        "fxpan_outline_red.stl": prism(outline),
        "fxpan_backer_optional.stl": plate,
    }
    for name, shape in solids.items():
        cq.exporters.export(
            shape, str(HERE / name), tolerance=0.02, angularTolerance=0.1
        )
        bb = shape.val().BoundingBox()
        print(
            f"wrote {name:30s} {bb.xlen:6.1f} x {bb.ylen:5.1f} x {bb.zlen:4.1f} mm"
            f"  islands={len(shape.solids().vals())}"
            f"  vol={shape.val().Volume():8.1f} mm3"
        )

    # Coloured parts must not interpenetrate or a multi-material slice fights.
    named = [("fx_gold", gold), ("pan_white", pan), ("outline_red", outline)]
    for i, (na, a) in enumerate(named):
        for nb, b in named[i + 1:]:
            if a.intersection(b).area > 1e-9:
                print(f"  WARNING: {na} overlaps {nb}")

    svg = SVG_TEMPLATE.format(
        vb=f"{x0:.3f} 0 {x1 - x0:.3f} {y1 - y0:.3f}",
        w=x1 - x0,
        h=y1 - y0,
        outline=svg_path(outline, y1),
        gold=svg_path(gold, y1),
        pan=svg_path(pan, y1),
    )
    (HERE / "fxpan.svg").write_text(svg)
    print(f"wrote fxpan.svg                 {x1 - x0:6.1f} x {y1 - y0:5.1f} mm")


if __name__ == "__main__":
    main()
