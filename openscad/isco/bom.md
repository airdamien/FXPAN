# Bill of materials — ISCO clamps

Hardware for the printed (or CNC) collars in
[`isco_mount.scad`](isco_mount.scad). Assembly notes:
[`clamps.md`](clamps.md).

You need **one** taking-lens clamp (M62, Nikkor-W, or EF 100L) plus the ISCO
attachment itself. The bench stand is optional.

## Taking lens (pick one path)

| Qty | Item | Clamp | Why | Link |
| --- | --- | --- | --- | --- |
| 1 | **EL-Nikkor 180 mm f/5.6N** | M62 | External **M62×1** on the front barrel, Ø76 shoulder behind the thread. | [eBay EL-Nikkor 180](https://www.ebay.com/sch/i.html?_nkw=el-nikkor+180mm+f%2F5.6) |
| *or* 1 | **Nikkor-W 180 mm f/5.6** (Copal No. 1) | Nikkor-W | **Ø73** barrel land, **1.1 mm** groove at the shutter, **M67×0.75** filter. FFD **178.8 mm** on the FXPAN helicoid stack. | [eBay Nikkor-W 180](https://www.ebay.com/sch/i.html?_nkw=nikkor-w+180mm+f%2F5.6) |
| *or* 1 | **Canon EF 100mm f/2.8L Macro IS USM** | EF 100L | Female **67 mm** filter. Max Ø77.7 × 123 mm. Hood **ET-73** comes off. | [Canon EF 100L Macro](https://www.usa.canon.com/shop/p/ef-100mm-f-2-8l-macro-is-usm) |

## ISCO attachment

| Qty | Item | Why | Link |
| --- | --- | --- | --- |
| 1 | **ISCO Ultra-Star HD Cinemascope attachment** | 2× afocal front piece from the HD Plus turret. **Ø70.6 mm** rear tube, **Ø67 mm** rear thread (US turret — caliper yours). | (bought) |

Caliper the rear tube before you trust the clamp ID. RafCamera lists
**71 mm** clamps for this batch; the model uses **71.0 mm** ID on the ISCO
collar and **73.4 mm** on the Nikkor-W land.

## Clamp body (pick one)

| Qty | Item | Why | Link |
| --- | --- | --- | --- |
| 1 | **`isco_clamp`** | EL-Nikkor path. ~115 × 84 × 38 mm. | Print [`stls/isco/isco_clamp.stl`](../../stls/isco/isco_clamp.stl) or CNC [`sendcutsend/isco_clamp.step`](sendcutsend/isco_clamp.step) |
| *or* 1 | **`isco_clamp_nw`** | Nikkor-W path. ~117 × 84 × 64 mm, dual collar. | Print [`stls/isco/isco_clamp_nw.stl`](../../stls/isco/isco_clamp_nw.stl) or CNC [`sendcutsend/isco_clamp_nw.step`](sendcutsend/isco_clamp_nw.step) |
| *or* 1 | **`isco_clamp_ef100`** | EF 100L path. Male M67×0.75 into the filter, ISCO collar in front. | Print [`stls/isco/isco_clamp_ef100.stl`](../../stls/isco/isco_clamp_ef100.stl) |

**Print:** PETG, ABS, or PCTG, 40%+ infill, ears up, inserts from the top
face. See [`clamps.md`](clamps.md).

**CNC:** STEP bores are plain cylinders — tap **M62×1** on the EL clamp
yourself if you cut metal.

## Fasteners

| Qty | Item | M62 | W | EF | Why | Link |
| --- | --- | ---: | ---: | --- | --- |
| — | **M3 heat-set insert, 4 mm × 5 mm** | 4 | 8 | 4 | Ø4 × 5 mm long. Press into the +Y ear face; the bore is through for the screw. (6×5 and 8×5 are too wide for the 16 mm ears.) | [M3 heat-set inserts](https://www.amazon.com/s?k=M3+heat+set+insert) |
| — | **M3 × 12–14 mm socket cap** | 4 | 8 | 4 | Close the split collars — ISCO only on the M62 and EF clamps; lens + ISCO on the W. | [M3 screw kit](https://www.amazon.com/s?k=M3+socket+head+cap+screw+assortment) |

## Bench stand (optional)

| Qty | Item | Why | Link |
| --- | --- | --- | --- |
| 1 | **`isco_stand`** | Cradle under the Ø90 barrel at 70 mm axis height. | [`stls/isco/isco_stand.stl`](../../stls/isco/isco_stand.stl) · [`sendcutsend/isco_stand.step`](sendcutsend/isco_stand.step) |
| 1 | **1/4-20 heat-set insert, 6.4 mm** (Ø8.1 well) | Tripod foot, same as the FXPAN chassis. | [CNC Kitchen 1/4-20×6.4](https://cnckitchenus.store/products/heat-set-insert-1-4-20x6-4-camera-thread-short-version-20-pieces) |
| 1 | **1/4-20 tripod screw** | Into the foot insert. | [1/4-20 camera screw](https://www.amazon.com/s?k=1%2F4-20+camera+screw) |

## Not on this clamp

| Item | Why |
| --- | --- |
| RafCamera 71 mm → M77 collar | Bought adapter path for the EL-180 when you are **not** printing this clamp. See [`../fxpan/bom.md`](../fxpan/bom.md). |
| M62 helicoid / FXPAN stem | In-body focus for the Nikkor-W — separate from this bench clamp. |
| 1/4-20 chassis support for the ISCO mass | On the FXPAN body, hang the kilo off the **chassis** insert, not the printed stem boss. |

## Export

```bash
./export_stls.sh --isco isco_clamp isco_clamp_nw isco_stand
```
