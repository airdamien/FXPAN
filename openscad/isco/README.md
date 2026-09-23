# EL-Nikkor 180/5.6N

Measured model of the 180 mm f/5.6N on the bench. The section drawing supplied
the barrel and the optical stations. This copy has no lip around the mount
thread, and the rear barrel is longer than the sheet.

Open [`WATCH_ME.scad`](WATCH_ME.scad). The solid other files should include is
[`el_nikkor_180n.scad`](el_nikkor_180n.scad). The exported envelope is
[`../../stls/isco/el_nikkor_180n.stl`](../../stls/isco/el_nikkor_180n.stl).

Origin is the seating face, the back of the Ø76 body where the M62 thread
starts. +Z is the front of the lens. −Z runs through the thread toward the
focal plane.

## Envelope

| | mm | |
| --- | ---: | --- |
| Barrel | 76 | straight down to the mount thread |
| Rear barrel | 60 | continues through the mount thread |
| Mount thread | M62×1 × 8 | starts at the seating face |
| Past the thread | 9.2 | this lens, Ø60 |
| Rear tip | −17.2 | 8 + 9.2 behind the seating face |
| Front rim | 53.1 | 10 + 37.1 + 6 ahead of the seating face |
| Overall | 70.3 | front rim to rear tip |
| Filter thread | M62×1 × 5 | outer end of the 10 mm front ring |

The sheet draws an 88 mm flange and a 78 mm shoulder around the mount thread.
This lens does not have that lip. The Ø76 body ends at the thread, and that
face is what seats.

The sheet's rear tip is 9.5 mm behind that face, which would leave only 1.5 mm
of barrel past an 8 mm thread. On this lens the Ø60 barrel extends **9.2 mm
past the threads**. Anything it screws into has to stay at least 60 mm clear
for that whole 9.2 mm. The FXPAN infinity stem uses a 61.2 mm bore there
(`EL180_BARREL`).

M58×0.75 is the retaining-ring thread at both cells. Ø65, a 4.3 mm step, and
six radial holes are on the sheet with no station and no hole diameter, so
they are not in the solid.

## Register

The focal length is 180 mm. The flange focal distance on the sheet is
**158.5 mm**. With the flange seated, the focal plane is at z = −158.5, and
the rear principal point is 21.5 mm in front of the flange.

The stations agree with each other:

- Back focus 152.7 puts the rear vertex 5.8 mm behind the flange.
- Vertex spacing 57.1 puts the front vertex at z = 51.3.
- The front rim is at 53.1, so the glass starts 1.8 mm behind the rim.
- Entrance pupil Ø31, 30.1 mm behind the front vertex.
- Exit pupil Ø32.4, 29.4 mm ahead of the rear vertex.
- H to H' is 0.3 mm.

`SHOW_GLASS` draws those stations. They are not part of the STL.

The FXPAN path is still built on 180 mm from flange to sensor. Seating this
lens on that stem does not land infinity at 158.5.
