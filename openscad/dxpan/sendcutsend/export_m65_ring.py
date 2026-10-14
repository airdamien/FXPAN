#!/usr/bin/env python3
"""SendCutSend solid for the flangeless M65×1 to M62×1 ring.

The threads are the part. Both are modeled, right-hand, ISO basic profile
(crest flat P/8, root flat P/4, 60°). No tap-drill blank.

  Outside  M65×1 male, 8 mm, major 65
  Inside   M62×1 female, 8 mm, major 62

The sleeve sits in the helicoid's female. The lens flange stops on the
helicoid face, so the finished ring adds 0 mm. Stock between the M65 root
and the M62 major is about 1 mm, which is the whole reason this is metal.
"""

from math import sqrt
from pathlib import Path

import cadquery as cq

OUT = Path(__file__).resolve().parent

P = 1.0
L = 8.0
H = P * sqrt(3) / 2
TOOTH = 5 * H / 8
BITE = 0.15


def trap(r0, z0, r1, z1):
    return (
        cq.Workplane("XZ")
        .moveTo(r0, -z0)
        .lineTo(r1, -z1)
        .lineTo(r1, z1)
        .lineTo(r0, z0)
        .close()
        .val()
    )


def helical(wire, radius):
    path = cq.Wire.makeHelix(P, L + 4, radius, center=(0, 0, -2))
    swept = cq.Solid.sweep(wire, [], path, makeSolid=True, isFrenet=True)
    return swept.intersect(cq.Solid.makeCylinder(40, L)).Solids()[0]


r_crest = 65 / 2
r_root = r_crest - TOOTH
external = helical(
    trap(r_root - BITE, 0.75 * P / 2, r_crest, (P / 8) / 2),
    r_root,
)

r_major = 62 / 2
r_minor = r_major - TOOTH
# Air between the internal crests: wide at the bore, narrow at the major.
internal_groove = helical(
    trap(r_minor - BITE, (7 * P / 8) / 2, r_major + 0.05, (P / 4) / 2),
    r_minor,
)

core = cq.Solid.makeCylinder(r_root, L).cut(cq.Solid.makeCylinder(r_minor, L))
part = core.fuse(external).cut(internal_groove)

bb = part.BoundingBox()
path = OUT / "m65_m62_flangeless.step"
cq.exporters.export(part, str(path))
print(
    f"m65_m62_flangeless  valid={part.isValid()}  solids={len(part.Solids())}  "
    f"size {bb.xlen:.1f} x {bb.ylen:.1f} x {bb.zlen:.1f} mm  "
    f"vol {part.Volume() / 1000:.2f} cm3  ->  {path}"
)
