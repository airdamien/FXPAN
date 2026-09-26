# ISCO clamps

Printed (or CNC) collars that hang the ISCO Ultra-Star HD Cinemascope
attachment on the taking lens. There are three variants:

| Clamp | Taking lens | STL | SendCutSend STEP |
| --- | --- | --- | --- |
| **M62** | EL-Nikkor 180/5.6N (external M62 on the front barrel) | [`isco_clamp.stl`](../../stls/isco/isco_clamp.stl) | [`sendcutsend/isco_clamp.step`](sendcutsend/isco_clamp.step) |
| **Nikkor-W** | Nikkor-W 180/5.6 in Copal No. 1 (Ø73 barrel land) | [`isco_clamp_nw.stl`](../../stls/isco/isco_clamp_nw.stl) | [`sendcutsend/isco_clamp_nw.step`](sendcutsend/isco_clamp_nw.step) |
| **EF 100L** | Canon EF 100mm f/2.8L Macro IS USM (female 67 mm filter) | [`isco_clamp_ef100.stl`](../../stls/isco/isco_clamp_ef100.stl) | — |

Parts list and fasteners: [`bom.md`](bom.md).

Source: [`isco_mount.scad`](isco_mount.scad). Preview in
[`WATCH_ME.scad`](WATCH_ME.scad) — set `PART` to **M62 clamp**,
**Nikkor-W clamp**, **Nikkor-W + ISCO**, **EF 100L clamp**,
**EF 100L + ISCO**, or **Full assembly section**.

## What each clamp does

Both clamps grip the ISCO attachment on its **Ø70.6 mm rear tube**, not on
the Ø67 rear thread. A shoulder inside the front pocket stops that face.
The Ø67 thread sits in a deeper pocket on the lens side of the shoulder and
cannot reach the taking lens.

### M62 clamp (`isco_clamp`)

One piece for the EL-Nikkor:

1. **Female M62×1** (9 mm engagement) screws onto the lens's external
   front thread and seats on the Ø76 shoulder behind it. The bore through
   the seat flange is the same **Ø62** as the thread, so there is no
   smaller step for the male to bottom on.
2. **Split collar** (ID 71 mm) closes on the ISCO's Ø70.6 land.
3. **Two M3 screws** through the ears pinch the ISCO collar only — the slot
   does not cut the M62 thread.

### EF 100L clamp (`isco_clamp_ef100`)

Male **M67×0.75**, 3.5 mm, screws into the Canon's filter thread and
seats on the front rim. Hood ET-73 comes off first. A **Ø64** barrel
carries the thread; the light hole through it is **Ø56**. The ISCO collar in front is the same pocket as the
M62 clamp. Four M3×4×5 inserts, two screws on the ISCO collar.

### Nikkor-W clamp (`isco_clamp_nw`)

One piece for the Nikkor-W 180/5.6:

1. **Rear collar** (ID 73.4 mm) grips the Ø73 barrel land. A **0.9 mm lip**
   drops into the 1.1 mm groove at the shutter junction so the clamp cannot
   slide along the barrel.
2. **M67 filter bore** stays open through the front flange so the taking
   beam is not blocked.
3. **Front collar** (same ISCO pocket as the M62 clamp) grips the Ø70.6
   land and stops the attachment shoulder.
4. **Four M3 screws** — two on the lens collar, two on the ISCO collar.

The W clamp is longer (~64 mm vs ~38 mm) because the ISCO pocket sits
forward of the Nikkor-W's front rim, not on the lens thread.

## Assembly

### EL-Nikkor + ISCO

```
[180 barrel] ← M62 female ← [isco_clamp] → ISCO Ø70.6 land ← [attachment]
```

1. Thread the clamp's M62 female onto the 180's external front thread until
   the back face seats on the Ø76 shoulder.
2. Slide the ISCO attachment in from the front. The Ø67 rear thread nests
   in the pocket; the Ø70.6 face stops on the shoulder.
3. Rotate the attachment for horizontal (theatre focus is forgiving).
4. Tighten both M3 screws into the heat-set inserts.

### Nikkor-W + ISCO

```
[Nikkor-W Ø73 land] ← rear collar ← [isco_clamp_nw] → ISCO Ø70.6 ← [attachment]
```

1. Seat the clamp on the Ø73 land with the lip in the groove
   (`z = NW_SHUTTER + NW_GROOVE` in the model).
2. Tighten the two **rear** M3 screws (lens collar).
3. Install the ISCO attachment as above.
4. Tighten the two **front** M3 screws (ISCO collar).

Preview with `PART = "nw"` in `WATCH_ME.scad`.

## Print

| Part | Orientation | Notes |
| --- | --- | --- |
| `isco_clamp` | M62 bore vertical, ears up | **M3 × 4 × 5 mm** inserts press in from the **+Y** ear face. The clamp bore is **through**; screw heads sit on the −Y face. |
| `isco_clamp_nw` | Lens end down, ears up | Same insert and through-bore rule. The lip goes toward the lens. |

**Material:** PETG, ABS, or PCTG. Not PLA — you are pinching a kilo of
glass on a split collar.

**Infill:** 40%+ on the collar walls; the ears see the screw load.

**Threads:** the STLs model M62 as a helix for preview. A real printed M62
female is unreliable at this scale — chase the bore or use the metal STEP
from SendCutSend and tap M62×1 yourself.

## CNC (SendCutSend)

Upload the STEP from [`sendcutsend/`](sendcutsend/). Bores are plain
cylinders (no helix). Regenerate the Nikkor-W file after model changes:

```bash
/tmp/cqvenv/bin/python openscad/isco/sendcutsend/export_nw_clamp.py
```

The EL clamp STEP was exported the same way (see git history). Instant
quotes on SendCutSend are for flat sheet; these parts change thickness, so
expect a custom quote.

| Part | Bounding box | Volume |
| --- | --- | ---: |
| `isco_clamp.step` | 115 × 84 × 38 mm | ~45 cm³ |
| `isco_clamp_nw.step` | 117 × 84 × 64 mm | ~100 cm³ |

## Bench stand

[`isco_stand.stl`](../../stls/isco/isco_stand.stl) is optional — a cradle
under the Ø90 ISCO barrel at **70 mm** axis height (FXPAN optical axis).
One **1/4-20 × 6.4 mm** heat-set insert in the foot, opening downward.
Preview with `PART = "stand"` or **Full assembly**.

## FXPAN body

On the FXPAN 65 chassis, preview the EL stack with `PART = "isco"` in
[`../fxpan/WATCH_ME.scad`](../fxpan/WATCH_ME.scad). The Nikkor-W stack uses
the helicoid nose on the stem, not this clamp on the taking lens — the W
clamp is for bench testing or a fixed lensboard mount outside the body.

## Export

```bash
./export_stls.sh --isco isco_clamp isco_clamp_nw isco_stand
```
