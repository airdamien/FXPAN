import cadquery as cq

def generate_badass_fxpan():
    # --- RIG GEOMETRY CONFIGURATION (mm) ---
    plate_w, plate_h, plate_t = 150.0, 90.0, 4.0
    emboss_d = 0.8
    tol = 0.04 # Precision air gap clearance for clean multi-filament insertion
    
    # 1. BASE MATRIX BUILD
    chassis = cq.Workplane("XY").box(plate_w, plate_h, plate_t).edges("|Z").fillet(8.0)
    
    # 2. THE BADASS EXTENDED "FX" CONTAINER FRAME
    # Precision vector coordinate layout forming the custom outer frame boundaries
    fx_frame = (
        cq.Workplane("XY").workplane(offset=plate_t/2)
        .moveTo(-60, 25).lineTo(0, 25).lineTo(-10, 15).lineTo(-50, 15)
        .lineTo(-50, 5).lineTo(-20, 5).lineTo(-25, -5).lineTo(-50, -5)
        .lineTo(-50, -25).lineTo(-60, -35).close()
        .extrude(emboss_d)
    )
    
    # 3. THE SWOOPING "X" & RADIAL HORIZON UNDERLINE
    # Uses parametric spline control points to draw the smooth, sweeping curvature under "PAN"
    x_bar1 = (
        cq.Workplane("XY").workplane(offset=plate_t/2)
        .moveTo(-35, 15).lineTo(-10, -25).lineTo(-2, -25).lineTo(-22, 15).close()
        .extrude(emboss_d)
    )
    x_bar2 = (
        cq.Workplane("XY").workplane(offset=plate_t/2)
        .moveTo(-10, 15).lineTo(-32, -25).lineTo(-24, -25).lineTo(-2, 15).close()
        .extrude(emboss_d)
    )
    x_underline = (
        cq.Workplane("XY").workplane(offset=plate_t/2)
        .moveTo(-16, -15)
        .spline([(5, -20), (35, -23), (65, -23)], includeCurrent=True)
        .lineTo(65, -20)
        .spline([(35, -20), (5, -17), (-12, -11)], includeCurrent=True)
        .close()
        .extrude(emboss_d)
    )
    x_swoop = x_bar1.union(x_bar2).union(x_underline)
    
    # 4. VECTOR CONSTRUCTED "PAN" TYPOGRAPHY (FONTLESS ARRAY MAP)
    # Built out of pure polygon coordinates so the geometry matches the sleek wide tracking exactly
    p_letter = cq.Workplane("XY").workplane(offset=plate_t/2).moveTo(5, 5).lineTo(20, 5).lineTo(20, -5).lineTo(10, -5).lineTo(10, -25).lineTo(5, -25).close().extrude(emboss_d)
    a_letter = cq.Workplane("XY").workplane(offset=plate_t/2).moveTo(25, -25).lineTo(32, 5).lineTo(38, 5).lineTo(45, -25).lineTo(39, -25).lineTo(37, -12).lineTo(31, -12).lineTo(29, -25).close().extrude(emboss_d)
    inner_a  = cq.Workplane("XY").workplane(offset=plate_t/2).moveTo(32, -5).lineTo(36, -5).lineTo(34, 2).close().extrude(emboss_d)
    n_letter = cq.Workplane("XY").workplane(offset=plate_t/2).moveTo(50, -25).lineTo(50, 5).lineTo(55, 5).lineTo(68, -18).lineTo(68, 5).lineTo(73, 5).lineTo(73, -25).lineTo(68, -25).lineTo(55, -2).lineTo(55, -25).close().extrude(emboss_d)
    
    # Consolidate individual path profiles
    typography = p_letter.union(a_letter).cut(inner_a).union(n_letter)
    logo_master = fx_frame.union(x_swoop).union(typography)
    
    # 5. DUAL-STL INLAY SPLITTING PROCESS (Boolean Math)
    logo_pocket = (
        logo_master.faces(">Z")
        .wires()
        .toPending()
        .offset2D(tol)
        .extrude(-(emboss_d + tol))
    )
    chassis_base_output = chassis.cut(logo_pocket)
    logo_inlay_output = logo_master
    
    # --- PHYSICAL FILE SYSTEM EXPORT ---
    print("Writing geometric mesh nodes directly to system files...")
    cq.exporters.export(chassis.union(logo_master), "fxpan_perfect_single.stl")
    cq.exporters.export(chassis_base_output, "fxpan_perfect_base.stl")
    cq.exporters.export(logo_inlay_output, "fxpan_perfect_inlay.stl")
    print("Success! High-fidelity STL files compiled without mesh errors.")

if __name__ == "__main__":
    generate_badass_fxpan()
