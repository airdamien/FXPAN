# ISCO / EL-Nikkor 180/5.6N

Measured models for the taking lens and the ISCO Ultra-Star HD Cinemascope
attachment used on the FXPAN 65 anamorphic build.

Open [`WATCH_ME.scad`](WATCH_ME.scad). Solids to include elsewhere:

- [`el_nikkor_180n.scad`](el_nikkor_180n.scad)
- [`isco_ultrastar_attachment.scad`](isco_ultrastar_attachment.scad)

Exported envelopes live under [`../../stls/isco/`](../../stls/isco/).

## EL-Nikkor 180/5.6N

Origin is the seating face, the back of the Ø76 body where the M62 thread
starts. +Z is the front of the lens. −Z runs through the thread toward the
focal plane.

| | mm | |
| --- | ---: | --- |
| Barrel | 76 | straight down to the mount thread |
| Rear barrel | 60 | continues through the mount thread |
| Mount thread | M62×1 × 8 | starts at the seating face |
| Past the thread | 9.2 | this lens, Ø60 |
| Front rim | 53.1 | ahead of the seating face |

See the existing notes in this file's git history for register and optical
stations. `SHOW_GLASS` draws pupils and vertices; they are not in the STL.

## ISCO Ultra-Star HD Cinemascope attachment

2× afocal front adapter (the gold/orange cylinder from the HD Plus turret).
Origin is the **rear face** — the plane that faces the taking lens / clamp.
+Z is the front, toward the subject.

| | mm | source |
| --- | ---: | --- |
| Rear thread OD | **67.0** | measured |
| Rear tube OD | **70.6** | measured — US turret; RafCamera **71 mm** clamp |
| Front tube OD | 90.0 | KuSeRa / community — **caliper** |
| Input barrel | **90** | front, light in |
| Overall | **~165** | barrel rear face to front rim |
| Thread past the face | **5** | Ø67, measured; pitch not measured |
| Rear face to first step | **70** | the Ø70.6 clamp land |

The photos are a stepped barrel, not a cone: black Ø67 rear ring, long
Ø70.6 gold tube, two focus-scale collars, a knurl, then the front lip.
Those in-between diameters are read off the photos. Caliper them if a
clamp or a collar has to land on one.

Clamp onto the **70.6 mm rear tube**, not the thread (see
[`../fxpan/bom.md`](../fxpan/bom.md)).

### Still to measure

The `L_*` stack in `isco_ultrastar_attachment.scad` sums to `L_OAL`.
Replace a length or a diameter when you caliper that land.

### Stack preview

`PART=stack` puts the attachment rear face at the EL-180 front rim
(`z = 53.1`). Set `CLAMP_GAP` if a collar sits between them.

Export:

```bash
./export_stls.sh --isco el_nikkor_180n isco_ultrastar
```
