import cadquery as cq
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _pocket_cutter(wp, dist, depth):
    """XY clearance around the inlay, extruded down from its top faces."""
    return (
        wp.faces(">Z")
        .wires()
        .toPending()
        .offset2D(dist)
        .extrude(-(depth + dist))
    )


def generate_fxpan_chassis():
    # --- RIG PARAMETERS (Millimeters) ---
    plate_width = 120.0
    plate_height = 100.0
    plate_thickness = 4.0
    corner_radius = 6.0
    emboss_depth = 0.8  # Perfect depth for 4 layers at 0.2mm layer height
    tolerance = 0.05    # High-precision fit clearance for dual STL slicing
    
    # 1. GENERATE BASE CHASSIS
    # Creates the rounded structural plate matching the D800 body prism style
    chassis = (
        cq.Workplane("XY")
        .box(plate_width, plate_height, plate_thickness)
        .edges("|Z")
        .fillet(corner_radius)
    )
    
    # 2. DEFINE LOGO GEOMETRY PATHS (Swooping X & Underline)
    # This creates the vector wireframe mapping out the typography anchors
    logo_wire = (
        cq.Workplane("XY")
        .workplane(offset=plate_thickness / 2) # Target top surface
        # --- The "F" Profile ---
        .moveTo(-45, 25).lineTo(-30, 25).lineTo(-30, 20).lineTo(-40, 20)
        .lineTo(-40, 12).lineTo(-32, 12).lineTo(-32, 7).lineTo(-40, 7)
        .lineTo(-40, -5).lineTo(-45, -5).close()
        # --- The Swooping "X" & Underline Flow ---
        .moveTo(-25, 25).lineTo(-18, 25).lineTo(-10, 10).lineTo(-2, 25).lineTo(5, 25)
        .lineTo(-5, 4)   # Central intersection node
        .lineTo(48, 4)   # Swoop extends right completely under "PAN" text zone
        .lineTo(48, 0)   # Line weight thickness of underline
        .lineTo(-7, 0)   # Return path tracking under the X
        .lineTo(-15, -5).lineTo(-22, -5).lineTo(-14, 6)
        .close()
    )
    
    # 3. TYPEFACE MASS BOUNDARIES ("PAN" Block Geometry)
    pan_text = (
        cq.Workplane("XY")
        .workplane(offset=plate_thickness / 2)
        .center(18, 12) # Precision offset above the swooping X extension line
        .text("PAN", fontsize=16, distance=emboss_depth, font="Arial", kind="bold")
    )
    
    # 4. TECH SPECS TEXT BLOCK DATA (65MP / 130MP Pipeline Layout)
    tech_text_native = (
        cq.Workplane("XY")
        .workplane(offset=plate_thickness / 2)
        .center(0, -15)
        .text("65MP NATIVE: 13248×4912", fontsize=6.5, distance=emboss_depth, font="Courier New", kind="bold")
    )
    
    tech_text_anamorphic = (
        cq.Workplane("XY")
        .workplane(offset=plate_thickness / 2)
        .center(0, -28)
        .text("130MP ANA 2╳: 26496×4912", fontsize=6.5, distance=emboss_depth, font="Courier New", kind="bold")
    )
    
    # Combine individual typographical elements into a single unified master vector group
    logo_profiles = logo_wire.extrude(emboss_depth)
    all_text_elements = logo_profiles.union(pan_text).union(tech_text_native).union(tech_text_anamorphic)
    
    # 5. ASSEMBLE OUTPUT A (Single Consolidated Solid Mesh)
    single_piece_rig = chassis.union(all_text_elements)
    
    # 6. ASSEMBLE OUTPUT B (Two-Part High-Precision Slicer Inlay System)
    # Drop the logo into the plate and cut a slightly larger XY pocket.
    logo_inlay_only = all_text_elements.translate((0, 0, -emboss_depth))
    chassis_with_pockets = chassis.cut(
        _pocket_cutter(logo_inlay_only, tolerance, emboss_depth)
    )

    # --- EXPORT STLs TO DISK ---
    print("Parsing structural manifold arrays... Exporting CAD models...")

    # Configuration 1: Standard Single Object File
    cq.exporters.export(single_piece_rig, str(HERE / "fxpan_single_piece.stl"))

    # Configuration 2: Separate multi-material files matching your exact build envelope
    cq.exporters.export(chassis_with_pockets, str(HERE / "fxpan_chassis_base.stl"))
    cq.exporters.export(logo_inlay_only, str(HERE / "fxpan_logo_inlay.stl"))
    
    print("Success! 'fxpan_single_piece.stl', 'fxpan_chassis_base.stl', and 'fxpan_logo_inlay.stl' are ready for your slicer.")

if __name__ == "__main__":
    generate_fxpan_chassis()
