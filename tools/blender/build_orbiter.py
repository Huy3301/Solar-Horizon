#!/usr/bin/env python3
"""
Solar Horizon — Hero Orbiter Model Generator (High-Fidelity Polish Pass)
Builds a high-fidelity spaceplane hero orbiter in Blender and exports glTF 2.0 (.glb).

Specifications & Enhancements (WP 3.2 Polish Pass):
- Dimensions: ~14.2 m long, 13.8 m wingspan, forward = -Z in Godot, 1 unit = 1 m
- Watertight aerodynamic fuselage with seamless nose ogive and reinforced carbon-carbon (RCC) nose cap
- Cockpit canopy with flush beveled black tile frames, 6 recessed windshield & side panes (mat_glass),
  and interior flight deck console with illuminated MFD instruments (mat_emissive)
- Double-delta wings with wing root fillet / strake leading edge extension, cambered aerofoil,
  wingtip fences, and bevelled split elevons with underside actuator fairings
- Streamlined twin OMS pods flanking dorsal tail with OMS nozzles and RCS arrays
- Dorsal vertical tail fin with split rudder / speed brake and RCC leading edge
- Ventral aerodynamic body flap with beveled heat-shield underside protecting engine nozzles
- Twin main rocket engine bells with gimbal mounts, cooling pipe rings, deep inner bell cavity,
  and radiant glowing emissive combustion throat rings (mat_emissive)
- Deployable landing gear (nose gear + twin main gear) with oleo struts, torque link scissors,
  axles, metallic alloy hubs, and dark vulcanized rubber tires (mat_tire),
  rigged and keyframed in 1-second 'gear_deploy' animation (frame 30 = deployed)
- Procedural 2048x2048 PBR texture maps (Albedo, ORM, Normal, Emission):
  - Black high-temperature ceramic tiles (HRSI) on entire belly, wing undersides, and body flap
    with individual tile micro-variation, grout grid, and beveled tile normal mapping
  - Off-white thermal blanket panels (AFRSI) on upper hull with quilt weave micro-texture
  - Distinct payload bay doors with longitudinal centerline split seam and transverse segment seams
  - High-visibility aerospace livery (Solar Horizon orange cheatlines, cyan pinstripes, markings)
  - Dark RCC leading edges on nose, wing strakes, and vertical fin
- Sockets:
    SOCKET_engine_L, SOCKET_engine_R
    SOCKET_nav_port, SOCKET_nav_stbd
    SOCKET_rcs_nose_pitch_up, SOCKET_rcs_nose_pitch_down, SOCKET_rcs_nose_yaw_port, SOCKET_rcs_nose_yaw_stbd
    SOCKET_rcs_tail_port, SOCKET_rcs_tail_stbd, SOCKET_rcs_tail_up
    SOCKET_cockpit_cam, SOCKET_chase_cam
- Collision mesh: COL_hull (simplified convex hull)
- LODs:
    LOD0: ~25,000 - 40,000 tris
    LOD1: <= 8,000 tris
- Multi-angle studio preview renders: preview_front.png, preview_side.png, preview_top.png, preview.png
"""

import sys
import os
import math
import subprocess

# If run directly outside Blender, invoke via Blender executable
try:
    import bpy
    import bmesh
    import mathutils
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False

if not IN_BLENDER:
    blender_candidates = [
        r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
        r"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe",
        r"C:\Program Files\Blender Foundation\Blender 4.0\blender.exe",
        "blender",
    ]
    blender_bin = None
    for c in blender_candidates:
        if os.path.exists(c):
            blender_bin = c
            break

    if not blender_bin:
        import shutil
        blender_bin = shutil.which("blender")

    if not blender_bin:
        print("ERROR: Blender executable not found. Please install Blender or add it to PATH.")
        sys.exit(1)

    print(f"Launching Blender: {blender_bin}")
    script_path = os.path.abspath(__file__)
    cmd = [blender_bin, "--background", "--python", script_path]
    res = subprocess.run(cmd)
    sys.exit(res.returncode)

import numpy as np

# -----------------------------------------------------------------------------
# Configuration & Output Paths
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))

OUTPUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "ships", "orbiter")
TEXTURES_DIR = os.path.join(OUTPUT_DIR, "textures")
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(TEXTURES_DIR, exist_ok=True)

GLB_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "orbiter.glb")
PREVIEW_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "preview.png")
PREVIEW_FRONT_PATH = os.path.join(OUTPUT_DIR, "preview_front.png")
PREVIEW_SIDE_PATH = os.path.join(OUTPUT_DIR, "preview_side.png")
PREVIEW_TOP_PATH = os.path.join(OUTPUT_DIR, "preview_top.png")

# -----------------------------------------------------------------------------
# Math / Matrix Helpers for BMesh Primitives
# -----------------------------------------------------------------------------
def mat_trans(x, y, z):
    """Returns a translation matrix."""
    return mathutils.Matrix.Translation((x, y, z))

def mat_cyl_y(x, y, z):
    """Returns a transformation matrix aligning a Z-cylinder along the Y axis."""
    rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
    return mathutils.Matrix.Translation((x, y, z)) @ rot

def mat_cyl_x(x, y, z):
    """Returns a transformation matrix aligning a Z-cylinder along the X axis."""
    rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'Y')
    return mathutils.Matrix.Translation((x, y, z)) @ rot

def get_look_at_matrix(eye, target, up=mathutils.Vector((0, 1, 0))):
    """Computes a camera transformation matrix looking at target with specified up vector."""
    forward = (target - eye).normalized()
    right = forward.cross(up).normalized()
    actual_up = right.cross(forward).normalized()
    mat = mathutils.Matrix([
        [right.x, actual_up.x, -forward.x, eye.x],
        [right.y, actual_up.y, -forward.y, eye.y],
        [right.z, actual_up.z, -forward.z, eye.z],
        [0.0,     0.0,         0.0,        1.0  ]
    ])
    return mat

# -----------------------------------------------------------------------------
# 1. Procedural PBR Texture Generation (NumPy -> PNG)
# -----------------------------------------------------------------------------
def generate_procedural_textures(tex_dir, size=2048):
    """
    Generates high-fidelity procedural PBR texture maps (2048x2048):
    - Albedo: Crisp black HRSI ceramic tiles on belly, dark RCC leading edges,
      black cockpit tile frame, off-white quilted thermal blankets on upper hull,
      distinct payload bay door centerline & segment seams, orange & cyan livery.
    - ORM: Ambient Occlusion, Roughness (semi-matte glazed tiles, rough grout,
      matte blankets, polished metals), Metallic channels.
    - Normal: Raised 3D bevelled tiles, recessed door seams, quilted weave relief.
    - Emission: Glowing cockpit flight instruments, nav lights, and warning indicators.
    """
    print(f"Generating {size}x{size} procedural PBR textures...")
    
    y_coords, x_coords = np.mgrid[0:size, 0:size]
    u = x_coords / float(size)
    v = y_coords / float(size)

    # 1.1 ALBEDO MAP
    albedo = np.zeros((size, size, 4), dtype=np.float32)
    albedo[:, :, 3] = 1.0

    # Upper Hull: Off-white thermal blanket (AFRSI) base
    albedo[:, :, 0] = 0.88
    albedo[:, :, 1] = 0.89
    albedo[:, :, 2] = 0.90

    # Quilted thermal blanket fine weave pattern
    weave = (np.sin(u * 256.0 * math.pi) * np.sin(v * 256.0 * math.pi)) * 0.015
    albedo[:, :, 0] += weave
    albedo[:, :, 1] += weave
    albedo[:, :, 2] += weave

    # -------------------------------------------------------------------------
    # Belly / Underside: Black Ceramic Thermal Protection System (TPS) Tiles
    # Covers v in [0.0, 0.48]
    # -------------------------------------------------------------------------
    tps_mask = (v < 0.48)
    albedo[tps_mask, 0] = 0.09
    albedo[tps_mask, 1] = 0.095
    albedo[tps_mask, 2] = 0.105

    # High-density ceramic tile grid (tile size 24 px ~ 15 cm scale)
    tile_size = 24
    tile_ix = x_coords // tile_size
    tile_iy = y_coords // tile_size
    tile_hash = ((tile_ix * 31337 + tile_iy * 7919) % 1000) / 1000.0 - 0.5
    albedo[tps_mask, 0] += tile_hash[tps_mask] * 0.02
    albedo[tps_mask, 1] += tile_hash[tps_mask] * 0.02
    albedo[tps_mask, 2] += tile_hash[tps_mask] * 0.02

    # Tile grout lines (2 px wide grout between ceramic tiles)
    tile_grout_x = (x_coords % tile_size < 2)
    tile_grout_y = (y_coords % tile_size < 2)
    tile_grout = (tile_grout_x | tile_grout_y) & tps_mask
    albedo[tile_grout, 0] = 0.035
    albedo[tile_grout, 1] = 0.038
    albedo[tile_grout, 2] = 0.042

    # Reinforced Carbon-Carbon (RCC) leading edges / nose cap
    rcc_nose = (u > 0.38) & (u < 0.62) & (v > 0.01) & (v < 0.14)
    rcc_wing_l = (u < 0.14) & (v < 0.46)
    rcc_wing_r = (u > 0.86) & (v < 0.46)
    rcc_mask = (rcc_nose | rcc_wing_l | rcc_wing_r) & tps_mask
    albedo[rcc_mask, 0] = 0.18
    albedo[rcc_mask, 1] = 0.19
    albedo[rcc_mask, 2] = 0.20

    # -------------------------------------------------------------------------
    # Upper Hull: Payload Bay Doors, Seams & Markings (v >= 0.48)
    # -------------------------------------------------------------------------
    upper_mask = ~tps_mask

    # Dark RCC Nose Cap on upper apex (z < -5.8)
    nose_cap_upper = (u > 0.42) & (u < 0.58) & (v > 0.53) & (v < 0.56)
    albedo[nose_cap_upper, 0] = 0.18
    albedo[nose_cap_upper, 1] = 0.19
    albedo[nose_cap_upper, 2] = 0.20

    # Cockpit Black Ceramic Tile Frame ("Raccoon Eyes" surround around windows)
    cockpit_tile = (u > 0.38) & (u < 0.62) & (v > 0.56) & (v < 0.635)
    albedo[cockpit_tile, 0] = 0.09
    albedo[cockpit_tile, 1] = 0.095
    albedo[cockpit_tile, 2] = 0.105
    cockpit_grout = cockpit_tile & (tile_grout_x | tile_grout_y)
    albedo[cockpit_grout, 0] = 0.035
    albedo[cockpit_grout, 1] = 0.038
    albedo[cockpit_grout, 2] = 0.042

    # Wing leading edge RCC dark composite bands on upper wing
    wing_rcc_l = (u < 0.15) & (v > 0.55) & (v < 0.88)
    wing_rcc_r = (u > 0.85) & (v > 0.55) & (v < 0.88)
    wing_rcc = wing_rcc_l | wing_rcc_r
    albedo[wing_rcc, 0] = 0.18
    albedo[wing_rcc, 1] = 0.19
    albedo[wing_rcc, 2] = 0.20

    # Payload Bay Door Centerline Split Line (dark recessed seam at u = 0.50)
    bay_centerline = (np.abs(u - 0.50) < 0.003) & (v > 0.64) & (v < 0.90)
    albedo[bay_centerline, 0] = 0.20
    albedo[bay_centerline, 1] = 0.21
    albedo[bay_centerline, 2] = 0.23

    # Payload Bay Door Transverse Segmentation Seams (4 segments along length)
    bay_transverse = np.zeros((size, size), dtype=bool)
    for v_split in [0.70, 0.77, 0.84]:
        line = (np.abs(v - v_split) < 0.0025) & (u > 0.36) & (u < 0.64)
        bay_transverse |= line
    albedo[bay_transverse, 0] = 0.20
    albedo[bay_transverse, 1] = 0.21
    albedo[bay_transverse, 2] = 0.23

    # Payload Bay Door Shoulder Hinge Seams (u = 0.36 and u = 0.64)
    bay_hinge_l = (np.abs(u - 0.36) < 0.003) & (v > 0.64) & (v < 0.90)
    bay_hinge_r = (np.abs(u - 0.64) < 0.003) & (v > 0.64) & (v < 0.90)
    bay_hinges = bay_hinge_l | bay_hinge_r
    albedo[bay_hinges, 0] = 0.30
    albedo[bay_hinges, 1] = 0.31
    albedo[bay_hinges, 2] = 0.33

    # Upper hull structural panel seams
    panel_seam_x = (x_coords % 128 < 2) & upper_mask & (~cockpit_tile)
    panel_seam_y = (y_coords % 128 < 2) & upper_mask & (~cockpit_tile)
    panel_seams = panel_seam_x | panel_seam_y
    albedo[panel_seams, 0] = 0.55
    albedo[panel_seams, 1] = 0.56
    albedo[panel_seams, 2] = 0.58

    # Aerospace High-Visibility Markings & Solar Horizon Mission Stripes
    stripe_wing_l = (u > 0.17) & (u < 0.22) & (v > 0.66) & (v < 0.86)
    stripe_wing_r = (u > 0.78) & (u < 0.83) & (v > 0.66) & (v < 0.86)
    orange_stripes = stripe_wing_l | stripe_wing_r
    albedo[orange_stripes, 0] = 0.92
    albedo[orange_stripes, 1] = 0.42
    albedo[orange_stripes, 2] = 0.08

    # Accent cyan pinstripes
    pinstripe_l = (u > 0.225) & (u < 0.235) & (v > 0.66) & (v < 0.86)
    pinstripe_r = (u > 0.765) & (u < 0.775) & (v > 0.66) & (v < 0.86)
    cyan_stripes = pinstripe_l | pinstripe_r
    albedo[cyan_stripes, 0] = 0.10
    albedo[cyan_stripes, 1] = 0.75
    albedo[cyan_stripes, 2] = 0.90

    # Forward fuselage side cheatlines
    cheatline_l = (u > 0.33) & (u < 0.35) & (v > 0.54) & (v < 0.62)
    cheatline_r = (u > 0.65) & (u < 0.67) & (v > 0.54) & (v < 0.62)
    albedo[cheatline_l | cheatline_r, 0] = 0.92
    albedo[cheatline_l | cheatline_r, 1] = 0.42
    albedo[cheatline_l | cheatline_r, 2] = 0.08

    # Port crew hatch outline & warning border
    hatch_border = (u > 0.32) & (u < 0.35) & (v > 0.58) & (v < 0.61)
    hatch_inner = (u > 0.325) & (u < 0.345) & (v > 0.585) & (v < 0.605)
    albedo[hatch_border, 0] = 0.85
    albedo[hatch_border, 1] = 0.72
    albedo[hatch_border, 2] = 0.12
    albedo[hatch_inner, 0] = 0.75
    albedo[hatch_inner, 1] = 0.76
    albedo[hatch_inner, 2] = 0.78

    albedo = np.clip(albedo, 0.0, 1.0)

    # 1.2 ORM MAP (Red = AO, Green = Roughness, Blue = Metallic)
    orm = np.zeros((size, size, 4), dtype=np.float32)
    orm[:, :, 0] = 1.0   # Default AO
    orm[:, :, 1] = 0.76  # Default Roughness (matte thermal blanket)
    orm[:, :, 2] = 0.02  # Default Metallic (non-metal)
    orm[:, :, 3] = 1.0

    # Black TPS tiles: semi-matte ceramic glaze with tile roughness variance
    orm[tps_mask, 1] = 0.62 + tile_hash[tps_mask] * 0.10
    orm[tps_mask, 2] = 0.02

    # Tile grout: rough porous silica
    orm[tile_grout, 0] = 0.55
    orm[tile_grout, 1] = 0.94
    orm[tile_grout, 2] = 0.01

    # RCC leading edges: hard composite
    orm[rcc_mask | nose_cap_upper | wing_rcc, 1] = 0.54
    orm[rcc_mask | nose_cap_upper | wing_rcc, 2] = 0.08

    # Cockpit black tiles
    orm[cockpit_tile, 1] = 0.58
    orm[cockpit_grout, 0] = 0.55
    orm[cockpit_grout, 1] = 0.94

    # Payload bay door seams: deep AO shadows
    orm[bay_centerline, 0] = 0.25
    orm[bay_centerline, 1] = 0.35
    orm[bay_centerline, 2] = 0.80

    orm[bay_transverse, 0] = 0.30
    orm[bay_transverse, 1] = 0.40
    orm[bay_transverse, 2] = 0.75

    orm[bay_hinges, 0] = 0.35
    orm[bay_hinges, 1] = 0.30
    orm[bay_hinges, 2] = 0.85

    orm[panel_seams, 0] = 0.45
    orm[panel_seams, 1] = 0.85

    # Glossy paint markings
    orm[orange_stripes | cyan_stripes, 1] = 0.42

    orm = np.clip(orm, 0.0, 1.0)

    # 1.3 NORMAL MAP (Tangent-space: Red = X, Green = Y, Blue = Z)
    normal = np.zeros((size, size, 4), dtype=np.float32)
    normal[:, :, 0] = 0.5
    normal[:, :, 1] = 0.5
    normal[:, :, 2] = 1.0
    normal[:, :, 3] = 1.0

    tile_active = tps_mask | cockpit_tile
    tile_left = (x_coords % tile_size == 2) & tile_active
    tile_right = (x_coords % tile_size == tile_size - 1) & tile_active
    tile_down = (y_coords % tile_size == 2) & tile_active
    tile_up = (y_coords % tile_size == tile_size - 1) & tile_active

    normal[tile_left, 0] = 0.64
    normal[tile_right, 0] = 0.36
    normal[tile_down, 1] = 0.64
    normal[tile_up, 1] = 0.36

    # Payload bay door recessed centerline groove
    bay_edge_l = (np.abs(u - 0.497) < 0.0015) & (v > 0.64) & (v < 0.90)
    bay_edge_r = (np.abs(u - 0.503) < 0.0015) & (v > 0.64) & (v < 0.90)
    normal[bay_edge_l, 0] = 0.70
    normal[bay_edge_r, 0] = 0.30

    # Panel seams normal perturbations
    seam_edge_x1 = (x_coords % 128 == 1) & upper_mask & (~cockpit_tile)
    seam_edge_x2 = (x_coords % 128 == 127) & upper_mask & (~cockpit_tile)
    normal[seam_edge_x1, 0] = 0.60
    normal[seam_edge_x2, 0] = 0.40

    seam_edge_y1 = (y_coords % 128 == 1) & upper_mask & (~cockpit_tile)
    seam_edge_y2 = (y_coords % 128 == 127) & upper_mask & (~cockpit_tile)
    normal[seam_edge_y1, 1] = 0.60
    normal[seam_edge_y2, 1] = 0.40

    normal = np.clip(normal, 0.0, 1.0)

    # 1.4 EMISSION MAP
    emission = np.zeros((size, size, 4), dtype=np.float32)
    emission[:, :, 3] = 1.0

    # Wingtip navigation lights
    nav_port = (u > 0.08) & (u < 0.09) & (v > 0.85) & (v < 0.87)
    nav_stbd = (u > 0.91) & (u < 0.92) & (v > 0.85) & (v < 0.87)
    emission[nav_port, 0] = 1.0   # Port Red
    emission[nav_stbd, 1] = 1.0   # Starboard Green

    maps = {
        "orbiter_hull_albedo.png": albedo,
        "orbiter_hull_orm.png": orm,
        "orbiter_hull_normal.png": normal,
        "orbiter_hull_emission.png": emission,
    }

    tex_paths = {}
    for filename, data in maps.items():
        path = os.path.join(tex_dir, filename)
        img = bpy.data.images.get(filename)
        if not img or img.size[0] != size or img.size[1] != size:
            if img:
                bpy.data.images.remove(img)
            img = bpy.data.images.new(filename, width=size, height=size)
        img.pixels.foreach_set(data.flatten())
        img.save_render(path)
        img.pack()
        tex_paths[filename] = path
        print(f"Saved texture: {path}")

    return tex_paths

# -----------------------------------------------------------------------------
# 2. Material Setup (PBR Shaders)
# -----------------------------------------------------------------------------
def setup_materials(tex_paths):
    """Sets up the canonical PBR materials: mat_hull, mat_glass, mat_engine, mat_emissive, mat_tire."""
    materials = {}

    # 2.1 mat_hull
    mat_hull = bpy.data.materials.new("mat_hull")
    nodes = mat_hull.node_tree.nodes
    links = mat_hull.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    albedo_img = bpy.data.images.load(tex_paths["orbiter_hull_albedo.png"])
    orm_img = bpy.data.images.load(tex_paths["orbiter_hull_orm.png"])
    orm_img.colorspace_settings.name = "Non-Color"
    normal_img = bpy.data.images.load(tex_paths["orbiter_hull_normal.png"])
    normal_img.colorspace_settings.name = "Non-Color"
    emission_img = bpy.data.images.load(tex_paths["orbiter_hull_emission.png"])

    tex_albedo = nodes.new("ShaderNodeTexImage")
    tex_albedo.image = albedo_img
    links.new(tex_albedo.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nodes.new("ShaderNodeTexImage")
    tex_orm.image = orm_img
    sep_color = nodes.new("ShaderNodeSeparateColor")
    links.new(tex_orm.outputs["Color"], sep_color.inputs["Color"])
    links.new(sep_color.outputs["Green"], bsdf.inputs["Roughness"])
    links.new(sep_color.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_normal = nodes.new("ShaderNodeTexImage")
    tex_normal.image = normal_img
    norm_map = nodes.new("ShaderNodeNormalMap")
    norm_map.inputs["Strength"].default_value = 1.0
    links.new(tex_normal.outputs["Color"], norm_map.inputs["Color"])
    links.new(norm_map.outputs["Normal"], bsdf.inputs["Normal"])

    tex_emission = nodes.new("ShaderNodeTexImage")
    tex_emission.image = emission_img
    links.new(tex_emission.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 3.0
    materials["mat_hull"] = mat_hull

    # 2.2 mat_glass (Cockpit glazing: deep glossy crystal glass)
    mat_glass = bpy.data.materials.new("mat_glass")
    bsdf_glass = mat_glass.node_tree.nodes.get("Principled BSDF")
    bsdf_glass.inputs["Base Color"].default_value = (0.012, 0.025, 0.045, 1.0)
    bsdf_glass.inputs["Metallic"].default_value = 0.15
    bsdf_glass.inputs["Roughness"].default_value = 0.02
    if "IOR" in bsdf_glass.inputs:
        bsdf_glass.inputs["IOR"].default_value = 1.52
    if "Specular IOR Level" in bsdf_glass.inputs:
        bsdf_glass.inputs["Specular IOR Level"].default_value = 1.0
    materials["mat_glass"] = mat_glass

    # 2.3 mat_engine (Inconel / titanium rocket bells & gear struts)
    mat_engine = bpy.data.materials.new("mat_engine")
    bsdf_eng = mat_engine.node_tree.nodes.get("Principled BSDF")
    bsdf_eng.inputs["Base Color"].default_value = (0.24, 0.25, 0.28, 1.0)
    bsdf_eng.inputs["Metallic"].default_value = 0.92
    bsdf_eng.inputs["Roughness"].default_value = 0.30
    materials["mat_engine"] = mat_engine

    # 2.4 mat_emissive (Hot rocket throat combustion rings)
    mat_emissive = bpy.data.materials.new("mat_emissive")
    bsdf_em = mat_emissive.node_tree.nodes.get("Principled BSDF")
    bsdf_em.inputs["Base Color"].default_value = (1.0, 0.60, 0.20, 1.0)
    bsdf_em.inputs["Emission Color"].default_value = (1.0, 0.55, 0.15, 1.0)
    bsdf_em.inputs["Emission Strength"].default_value = 14.0
    materials["mat_emissive"] = mat_emissive

    # 2.5 mat_tire (Matte black vulcanized landing gear tire rubber)
    mat_tire = bpy.data.materials.new("mat_tire")
    bsdf_tire = mat_tire.node_tree.nodes.get("Principled BSDF")
    bsdf_tire.inputs["Base Color"].default_value = (0.05, 0.05, 0.06, 1.0)
    bsdf_tire.inputs["Metallic"].default_value = 0.0
    bsdf_tire.inputs["Roughness"].default_value = 0.85
    materials["mat_tire"] = mat_tire

    return materials

# -----------------------------------------------------------------------------
# 3. Geometry Building Functions (Hand-Modelled Spaceplane Parts)
# -----------------------------------------------------------------------------
def assign_mat(obj, mat):
    if len(obj.data.materials) == 0:
        obj.data.materials.append(mat)
    else:
        obj.data.materials[0] = mat

def assign_deterministic_uvs(bm, is_belly_fn=None, is_wing=False):
    """
    Assigns continuous, distortion-free UV coordinates across orbiter components:
    - Underside (belly) loops map to V in [0.06, 0.46], U in [0.06, 0.94]
    - Upper hull loops map to V in [0.54, 0.94], U in [0.06, 0.94]
    Centerline X=0 maps directly to U=0.50.
    """
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        f_norm = face.normal
        for loop in face.loops:
            co = loop.vert.co
            x, y, z = co.x, co.y, co.z
            
            if is_wing:
                u = 0.50 + (x / 7.2) * 0.42
            else:
                u = 0.50 + (x / 4.2) * 0.44
            u = max(0.02, min(0.98, u))

            z_norm = (z + 6.5) / 14.0
            z_norm = max(0.0, min(1.0, z_norm))

            is_belly = False
            if is_belly_fn:
                is_belly = is_belly_fn(co, f_norm)
            else:
                is_belly = (f_norm.y < -0.15) or (y < 0.10 and f_norm.y <= 0.05)

            if is_belly:
                v = 0.05 + z_norm * 0.40
            else:
                v = 0.53 + z_norm * 0.41

            loop[uv_layer].uv = (u, v)

def build_fuselage(materials):
    """
    Builds the main aerodynamic fuselage with nose ogive, payload bay, and OMS shoulders.
    Uses 64 radial divisions x 28 cross-sections for high-fidelity, watertight geometry.
    """
    bm = bmesh.new()

    sections = [
        # (z, cy, hw, th, bd)
        (-6.45,  0.10, 0.08, 0.08, 0.08),  # Nose apex
        (-6.30,  0.11, 0.35, 0.28, 0.24),  # Nose cap
        (-6.00,  0.13, 0.68, 0.50, 0.40),  # Forward nose
        (-5.60,  0.17, 0.96, 0.72, 0.52),  # Forward RCS zone
        (-5.10,  0.23, 1.22, 0.92, 0.62),  # Pre-canopy
        (-4.75,  0.30, 1.40, 1.08, 0.70),  # Windshield lower sill
        (-4.40,  0.36, 1.54, 1.22, 0.74),  # Mid windshield
        (-4.05,  0.42, 1.62, 1.30, 0.76),  # Cockpit brow apex
        (-3.50,  0.40, 1.68, 1.28, 0.78),  # Forward cargo bulkhead
        (-2.20,  0.36, 1.74, 1.26, 0.78),  # Payload bay
        (-1.00,  0.35, 1.76, 1.25, 0.78),
        ( 0.20,  0.35, 1.76, 1.25, 0.78),
        ( 1.40,  0.35, 1.76, 1.25, 0.78),
        ( 2.60,  0.35, 1.77, 1.25, 0.78),
        ( 3.80,  0.35, 1.80, 1.26, 0.80),
        ( 4.80,  0.34, 1.84, 1.30, 0.82),  # OMS pod shoulders
        ( 5.60,  0.31, 1.88, 1.33, 0.82),
        ( 6.30,  0.28, 1.90, 1.34, 0.82),
        ( 6.80,  0.24, 1.84, 1.28, 0.80),
        ( 7.10,  0.20, 1.75, 1.20, 0.75),  # Aft bulkhead
    ]

    num_radial = 64
    rings = []

    for z, cy, hw, th, bd in sections:
        ring_verts = []
        for i in range(num_radial):
            th_angle = (i / float(num_radial)) * 2.0 * math.pi
            c_a = math.cos(th_angle)
            s_a = math.sin(th_angle)

            x = c_a * hw
            if s_a >= 0:
                y = cy + s_a * th
            else:
                flat_factor = 0.85 + 0.15 * (c_a ** 2)
                y = cy + s_a * bd * flat_factor

            v = bm.verts.new((x, y, z))
            ring_verts.append(v)
        rings.append(ring_verts)

    for r in range(len(rings) - 1):
        for i in range(num_radial):
            i_next = (i + 1) % num_radial
            v0 = rings[r][i]
            v1 = rings[r][i_next]
            v2 = rings[r + 1][i_next]
            v3 = rings[r + 1][i]
            bm.faces.new((v0, v1, v2, v3))

    nose_apex = bm.verts.new((0.0, 0.10, -6.50))
    for i in range(num_radial):
        i_next = (i + 1) % num_radial
        bm.faces.new((nose_apex, rings[0][i_next], rings[0][i]))

    aft_center = bm.verts.new((0.0, 0.20, 7.10))
    for i in range(num_radial):
        i_next = (i + 1) % num_radial
        bm.faces.new((aft_center, rings[-1][i], rings[-1][i_next]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    assign_deterministic_uvs(bm)

    mesh = bpy.data.meshes.new("FuselageMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Fuselage", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])

    mod_bev = obj.modifiers.new("Bevel", "BEVEL")
    mod_bev.width = 0.03
    mod_bev.segments = 2
    mod_bev.limit_method = "ANGLE"
    mod_bev.angle_limit = math.radians(35)

    return obj

def build_cockpit_glazing(materials):
    """
    Builds the iconic cockpit canopy window frame structure and multi-pane glazing:
    - 6 recessed window panes (2 front windshields, 2 side, 2 overhead)
    - Black thermal tile window frames ('raccoon eyes' frame) with beveled mullions
    - Interior flight deck dashboard console with glowing MFD avionics screens
    """
    bm_glass = bmesh.new()

    # Accurate Shuttle cockpit window panes sitting flush in the cabin brow
    # Pane 1 & 2: Forward Windshields (Left & Right)
    v_fwd_L = [
        bm_glass.verts.new((-0.06, 1.68, -4.10)),
        bm_glass.verts.new((-0.74, 1.64, -4.12)),
        bm_glass.verts.new((-0.76, 1.40, -4.70)),
        bm_glass.verts.new((-0.06, 1.42, -4.72)),
    ]
    bm_glass.faces.new(v_fwd_L)

    v_fwd_R = [
        bm_glass.verts.new((0.06, 1.68, -4.10)),
        bm_glass.verts.new((0.06, 1.42, -4.72)),
        bm_glass.verts.new((0.76, 1.40, -4.70)),
        bm_glass.verts.new((0.74, 1.64, -4.12)),
    ]
    bm_glass.faces.new(v_fwd_R)

    # Pane 3 & 4: Side Windows (Left & Right)
    v_side_L = [
        bm_glass.verts.new((-0.76, 1.64, -4.12)),
        bm_glass.verts.new((-1.10, 1.55, -4.10)),
        bm_glass.verts.new((-1.14, 1.35, -4.45)),
        bm_glass.verts.new((-0.78, 1.38, -4.68)),
    ]
    bm_glass.faces.new(v_side_L)

    v_side_R = [
        bm_glass.verts.new((0.76, 1.64, -4.12)),
        bm_glass.verts.new((0.78, 1.38, -4.68)),
        bm_glass.verts.new((1.14, 1.35, -4.45)),
        bm_glass.verts.new((1.10, 1.55, -4.10)),
    ]
    bm_glass.faces.new(v_side_R)

    # Pane 5 & 6: Overhead Eyebrow Windows
    v_top_L = [
        bm_glass.verts.new((-0.08, 1.73, -3.70)),
        bm_glass.verts.new((-0.64, 1.72, -3.70)),
        bm_glass.verts.new((-0.66, 1.68, -4.08)),
        bm_glass.verts.new((-0.08, 1.70, -4.08)),
    ]
    bm_glass.faces.new(v_top_L)

    v_top_R = [
        bm_glass.verts.new((0.08, 1.73, -3.70)),
        bm_glass.verts.new((0.08, 1.70, -4.08)),
        bm_glass.verts.new((0.66, 1.68, -4.08)),
        bm_glass.verts.new((0.64, 1.72, -3.70)),
    ]
    bm_glass.faces.new(v_top_R)

    bmesh.ops.recalc_face_normals(bm_glass, faces=bm_glass.faces)
    bmesh.ops.solidify(bm_glass, geom=bm_glass.faces, thickness=0.015)

    mesh_glass = bpy.data.meshes.new("CockpitGlazingMesh")
    bm_glass.to_mesh(mesh_glass)
    bm_glass.free()

    obj_glass = bpy.data.objects.new("CockpitGlazing", mesh_glass)
    bpy.context.scene.collection.objects.link(obj_glass)
    assign_mat(obj_glass, materials["mat_glass"])

    # Cockpit Window Frame Mullions (Flush Black Ceramic Tile Frame)
    bm_frame = bmesh.new()

    # Center pillar divider between left & right windshields
    res_cp = bmesh.ops.create_cube(bm_frame, size=1.0)
    cp_verts = res_cp['verts']
    bmesh.ops.scale(bm_frame, vec=(0.12, 0.03, 0.68), verts=cp_verts)
    bmesh.ops.rotate(bm_frame, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.radians(-38), 3, 'X'), verts=cp_verts)
    bmesh.ops.translate(bm_frame, vec=(0.0, 1.55, -4.41), verts=cp_verts)

    # Left & Right A-Pillars
    for sign in [-1.0, 1.0]:
        res_ap = bmesh.ops.create_cube(bm_frame, size=1.0)
        ap_verts = res_ap['verts']
        bmesh.ops.scale(bm_frame, vec=(0.10, 0.03, 0.68), verts=ap_verts)
        bmesh.ops.rotate(bm_frame, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.radians(-38), 3, 'X'), verts=ap_verts)
        bmesh.ops.translate(bm_frame, vec=(sign * 0.77, 1.52, -4.41), verts=ap_verts)

    # Brow sill across top of windshield
    res_bs = bmesh.ops.create_cube(bm_frame, size=1.0)
    bmesh.ops.scale(bm_frame, vec=(1.60, 0.03, 0.08), verts=res_bs['verts'])
    bmesh.ops.translate(bm_frame, vec=(0.0, 1.69, -4.10), verts=res_bs['verts'])

    # Lower sill across bottom of windshield
    res_ls = bmesh.ops.create_cube(bm_frame, size=1.0)
    bmesh.ops.scale(bm_frame, vec=(1.70, 0.03, 0.08), verts=res_ls['verts'])
    bmesh.ops.translate(bm_frame, vec=(0.0, 1.41, -4.71), verts=res_ls['verts'])

    bmesh.ops.recalc_face_normals(bm_frame, faces=bm_frame.faces)
    
    # Assign black tile UV region (V < 0.45) so the frame is authentic black ceramic
    uv_f = bm_frame.loops.layers.uv.verify()
    for face in bm_frame.faces:
        for loop in face.loops:
            loop[uv_f].uv = (0.50 + loop.vert.co.x * 0.15, 0.18)

    mesh_frame = bpy.data.meshes.new("CockpitFrameMesh")
    bm_frame.to_mesh(mesh_frame)
    bm_frame.free()

    obj_frame = bpy.data.objects.new("CockpitFrame", mesh_frame)
    bpy.context.scene.collection.objects.link(obj_frame)
    assign_mat(obj_frame, materials["mat_hull"])

    # Interior Flight Deck Dashboard Console with Glowing MFD Displays
    bm_dash = bmesh.new()
    res_dash = bmesh.ops.create_cube(bm_dash, size=1.0)
    dash_v = res_dash['verts']
    bmesh.ops.scale(bm_dash, vec=(1.50, 0.35, 0.60), verts=dash_v)
    bmesh.ops.rotate(bm_dash, cent=(0, 0, 0), matrix=mathutils.Matrix.Rotation(math.radians(25), 3, 'X'), verts=dash_v)
    bmesh.ops.translate(bm_dash, vec=(0.0, 1.25, -4.25), verts=dash_v)

    mesh_dash = bpy.data.meshes.new("CockpitDashMesh")
    bm_dash.to_mesh(mesh_dash)
    bm_dash.free()

    obj_dash = bpy.data.objects.new("CockpitDashboard", mesh_dash)
    bpy.context.scene.collection.objects.link(obj_dash)
    assign_mat(obj_dash, materials["mat_emissive"])

    return obj_glass, obj_frame, obj_dash

def build_delta_wings(materials):
    """
    Builds double-delta wings spanning 13.8 m with:
    - Aerodynamic wing root fillet / leading edge extension (strake)
    - Cambered aerofoil section with blunt RCC leading edge
    - Wingtip fences
    - Split elevons (inboard and outboard) with bevelled hinges and actuator fairings
    - Precise UV assignment: Dorsal = White Upper Blanket, Ventral = Black TPS Tiles
    """
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    stations = [
        # (x_span, le_z, te_z, y_cam, thick)
        (1.68, -2.20,  5.85,  0.10, 0.42),  # Wing root / strake origin
        (2.10, -1.20,  5.80,  0.10, 0.38),  # Strake forward taper
        (2.80,  0.20,  5.70,  0.11, 0.35),  # Strake mid
        (3.40,  1.40,  5.55,  0.12, 0.30),  # Double-delta kink
        (4.20,  2.10,  5.40,  0.13, 0.26),  # Main 45-deg outer wing leading edge
        (5.00,  2.80,  5.20,  0.14, 0.22),
        (5.80,  3.50,  5.00,  0.14, 0.18),
        (6.40,  4.00,  4.80,  0.15, 0.15),
        (6.90,  4.40,  4.65,  0.15, 0.12),  # Wingtip
    ]

    for is_port in [False, True]:
        sign = -1.0 if is_port else 1.0
        wing_rings = []
        for x_span, le_z, te_z, y_cam, thick in stations:
            x = sign * x_span
            chord = te_z - le_z
            chord_pts = 32
            profile_upper = []
            profile_lower = []
            for p in range(chord_pts):
                t = p / float(chord_pts - 1)
                z = le_z + t * chord
                h = 4.0 * t * (1.0 - t) * thick
                y_up = y_cam + h * 0.70
                y_dn = y_cam - h * 0.30
                profile_upper.append(bm.verts.new((x, y_up, z)))
                profile_lower.append(bm.verts.new((x, y_dn, z)))

            wing_rings.append((profile_upper, profile_lower))

        for s in range(len(stations) - 1):
            up0, dn0 = wing_rings[s]
            up1, dn1 = wing_rings[s + 1]
            n_pts = len(up0)

            # Dorsal (Upper) skin faces: correctly oriented facing +Y
            for i in range(n_pts - 1):
                if not is_port:
                    f = bm.faces.new((up0[i], up0[i + 1], up1[i + 1], up1[i]))
                else:
                    f = bm.faces.new((up0[i], up1[i], up1[i + 1], up0[i + 1]))
                # Assign Upper Hull UV (V in [0.55, 0.95])
                for loop in f.loops:
                    co = loop.vert.co
                    u = max(0.04, min(0.96, 0.50 + (co.x / 7.2) * 0.42))
                    v = 0.55 + ((co.z - 1.0) / 6.0) * 0.38
                    loop[uv_layer].uv = (u, max(0.52, min(0.96, v)))

            # Ventral (Lower) skin faces: correctly oriented facing -Y
            for i in range(n_pts - 1):
                if not is_port:
                    f = bm.faces.new((dn0[i], dn1[i], dn1[i + 1], dn0[i + 1]))
                else:
                    f = bm.faces.new((dn0[i], dn0[i + 1], dn1[i + 1], dn1[i]))
                # Assign Belly TPS Tile UV (V in [0.06, 0.46])
                for loop in f.loops:
                    co = loop.vert.co
                    u = max(0.04, min(0.96, 0.50 + (co.x / 7.2) * 0.42))
                    v = 0.06 + ((co.z - 1.0) / 6.0) * 0.38
                    loop[uv_layer].uv = (u, max(0.04, min(0.48, v)))

            # Leading edge blunt cap
            if not is_port:
                f_le = bm.faces.new((dn0[0], up0[0], up1[0], dn1[0]))
                f_te = bm.faces.new((up0[-1], dn0[-1], dn1[-1], up1[-1]))
            else:
                f_le = bm.faces.new((dn0[0], dn1[0], up1[0], up0[0]))
                f_te = bm.faces.new((up0[-1], up1[-1], dn1[-1], dn0[-1]))

            for loop in f_le.loops:
                co = loop.vert.co
                u = max(0.04, min(0.96, 0.50 + (co.x / 7.2) * 0.42))
                loop[uv_layer].uv = (u, 0.10)
            for loop in f_te.loops:
                co = loop.vert.co
                u = max(0.04, min(0.96, 0.50 + (co.x / 7.2) * 0.42))
                loop[uv_layer].uv = (u, 0.45)

        # Wingtip vertical fences
        tip_up, tip_dn = wing_rings[-1]
        tip_x = sign * 6.90
        fence_up = []
        for v in tip_up:
            fence_up.append(bm.verts.new((tip_x, v.co.y + 0.38, v.co.z)))
        for i in range(len(tip_up) - 1):
            if not is_port:
                f = bm.faces.new((tip_up[i], fence_up[i], fence_up[i + 1], tip_up[i + 1]))
            else:
                f = bm.faces.new((tip_up[i], tip_up[i + 1], fence_up[i + 1], fence_up[i]))
            for loop in f.loops:
                u = 0.08 if is_port else 0.92
                loop[uv_layer].uv = (u, 0.85)

    # Split Elevons: Inboard and Outboard control surfaces on both wings
    for sign in [-1.0, 1.0]:
        for elevon_span in [(1.9, 4.0, 5.15, 5.85), (4.3, 6.7, 4.50, 5.20)]:
            x_in, x_out, z_hinge, z_te = elevon_span
            el_verts = [
                bm.verts.new((sign * x_in,  0.14, z_hinge)),
                bm.verts.new((sign * x_out, 0.17, z_hinge)),
                bm.verts.new((sign * x_out, 0.15, z_te)),
                bm.verts.new((sign * x_in,  0.12, z_te)),
            ]
            f = bm.faces.new(el_verts)
            bmesh.ops.solidify(bm, geom=[f], thickness=0.09)

            # Aerodynamic horizontal actuator blister fairings under elevon hinge
            mid_x = sign * (x_in + x_out) * 0.5
            res_blist = bmesh.ops.create_cone(
                bm,
                cap_ends=True,
                segments=14,
                radius1=0.07,
                radius2=0.03,
                depth=0.55,
                matrix=mat_trans(mid_x, 0.02, z_hinge + 0.10)
            )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("DeltaWingsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("DeltaWings", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])

    mod_bev = obj.modifiers.new("Bevel", "BEVEL")
    mod_bev.width = 0.02
    mod_bev.segments = 2
    mod_bev.limit_method = "ANGLE"
    mod_bev.angle_limit = math.radians(35)

    return obj

def build_oms_pods(materials):
    """
    Builds streamlined twin Orbital Maneuvering System (OMS) pods
    flanking the vertical tail fin on the aft shoulders.
    Each pod includes:
    - Teardrop aerodynamic housing
    - Aft OMS rocket engine nozzle
    - Aft RCS thruster block
    """
    bm = bmesh.new()

    for sign in [-1.0, 1.0]:
        px = sign * 1.45
        sections = [
            (4.20, 1.30, 0.15, 0.15),
            (4.80, 1.40, 0.38, 0.34),
            (5.60, 1.46, 0.46, 0.40),
            (6.40, 1.44, 0.46, 0.40),
            (7.10, 1.40, 0.42, 0.36),
        ]
        rings = []
        for z, py, rw, rh in sections:
            r_verts = []
            for s in range(24):
                th = (s / 24.0) * 2.0 * math.pi
                vx = px + math.cos(th) * rw
                vy = py + math.sin(th) * rh
                r_verts.append(bm.verts.new((vx, vy, z)))
            rings.append(r_verts)

        for r in range(len(rings) - 1):
            for s in range(24):
                s_next = (s + 1) % 24
                bm.faces.new((rings[r][s], rings[r][s_next], rings[r + 1][s_next], rings[r + 1][s]))

        f_apex = bm.verts.new((px, 1.30, 4.15))
        for s in range(24):
            s_next = (s + 1) % 24
            bm.faces.new((f_apex, rings[0][s_next], rings[0][s]))

        aft_apex = bm.verts.new((px, 1.40, 7.10))
        for s in range(24):
            s_next = (s + 1) % 24
            bm.faces.new((aft_apex, rings[-1][s], rings[-1][s_next]))

        # OMS engine nozzle protruding from pod aft bulkhead
        bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            segments=24,
            radius1=0.18,
            radius2=0.22,
            depth=0.45,
            matrix=mat_trans(px, 1.40, 7.30)
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    assign_deterministic_uvs(bm)

    mesh = bpy.data.meshes.new("OMSPodsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("OMSPods", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])

    return obj

def build_vertical_tail_fin(materials):
    """
    Builds the vertical tail fin and split rudder / speed brake along dorsal centerline.
    Includes:
    - Symmetrical aerofoil section with RCC leading edge cap
    - Recessed split rudder hinge line and twin clamshell split surfaces
    """
    bm = bmesh.new()

    fin_stations = [
        # (y, le_z, te_z, thick)
        (1.25, 3.50, 7.10, 0.38),
        (1.70, 3.95, 7.05, 0.32),
        (2.15, 4.40, 6.98, 0.27),
        (2.60, 4.85, 6.90, 0.22),
        (3.05, 5.30, 6.80, 0.17),
        (3.50, 5.75, 6.65, 0.12),
        (3.85, 6.10, 6.50, 0.08),  # Fin tip
    ]

    fin_rings = []
    for y, le_z, te_z, thick in fin_stations:
        chord = te_z - le_z
        chord_pts = 28
        side_port = []
        side_stbd = []
        for p in range(chord_pts):
            t = p / float(chord_pts - 1)
            z = le_z + t * chord
            h = 4.0 * t * (1.0 - t) * (thick / 2.0)
            side_port.append(bm.verts.new((-h, y, z)))
            side_stbd.append(bm.verts.new(( h, y, z)))
        fin_rings.append((side_port, side_stbd))

    for s in range(len(fin_stations) - 1):
        p0, s0 = fin_rings[s]
        p1, s1 = fin_rings[s + 1]
        n = len(p0)

        for i in range(n - 1):
            bm.faces.new((p0[i], p1[i], p1[i + 1], p0[i + 1]))
            bm.faces.new((s0[i], s0[i + 1], s1[i + 1], s1[i]))

        bm.faces.new((p0[0], s0[0], s1[0], p1[0]))
        bm.faces.new((s0[-1], p0[-1], p1[-1], s1[-1]))

    tip_p, tip_s = fin_rings[-1]
    for i in range(len(tip_p) - 1):
        bm.faces.new((tip_p[i], tip_p[i + 1], tip_s[i + 1], tip_s[i]))

    # Split Rudder / Speed Brake: Clamshell split surfaces along trailing edge
    for sign in [-1.0, 1.0]:
        rudder_verts = [
            bm.verts.new((sign * 0.02, 1.50, 6.40)),
            bm.verts.new((sign * 0.015, 3.60, 6.05)),
            bm.verts.new((sign * 0.04,  3.60, 6.45)),
            bm.verts.new((sign * 0.06,  1.50, 6.95)),
        ]
        f = bm.faces.new(rudder_verts)
        bmesh.ops.solidify(bm, geom=[f], thickness=sign * 0.03)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    assign_deterministic_uvs(bm)

    mesh = bpy.data.meshes.new("TailFinMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("TailFin", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])

    mod_bev = obj.modifiers.new("Bevel", "BEVEL")
    mod_bev.width = 0.02
    mod_bev.segments = 2
    mod_bev.limit_method = "ANGLE"
    mod_bev.angle_limit = math.radians(35)

    return obj

def build_body_flap(materials):
    """
    Builds the ventral aerodynamic body flap beneath the main rocket engines.
    Protects the engine nozzles during atmospheric re-entry and trims pitch.
    """
    bm = bmesh.new()

    x_span = 1.70
    z_hinge = 6.85
    z_tip = 8.15
    y_belly = -0.55
    thick = 0.14

    verts_top = [
        bm.verts.new((-x_span, y_belly, z_hinge)),
        bm.verts.new(( x_span, y_belly, z_hinge)),
        bm.verts.new(( x_span * 0.88, y_belly + 0.04, z_tip)),
        bm.verts.new((-x_span * 0.88, y_belly + 0.04, z_tip)),
    ]
    f = bm.faces.new(verts_top)
    bmesh.ops.solidify(bm, geom=[f], thickness=-thick)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    assign_deterministic_uvs(bm)

    mesh = bpy.data.meshes.new("BodyFlapMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("BodyFlap", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])

    return obj

def build_engine_bells(materials):
    """
    Builds twin main propulsion rocket engine bells at the rear bulkhead:
    - Gimbal mounts and universal ring
    - Exterior bell with cooling pipe rings
    - Deep flared inner bell cavity
    - Radiant glowing emissive combustion throat rings (mat_emissive)
    """
    bm_eng = bmesh.new()
    bm_emit = bmesh.new()

    engine_positions = [-0.88, 0.88]
    rings_count = 32
    sectors = 48

    for ex in engine_positions:
        ey = -0.05
        # Gimbal ring mount at aft bulkhead
        bmesh.ops.create_cone(
            bm_eng,
            cap_ends=True,
            cap_tris=False,
            segments=sectors,
            radius1=0.42,
            radius2=0.38,
            depth=0.25,
            matrix=mat_trans(ex, ey, 6.95)
        )

        # Flared rocket nozzle bell
        bell_rings = []
        for r_i in range(rings_count + 1):
            t = r_i / float(rings_count)
            z = 7.02 + t * 1.28
            radius = 0.30 + 0.42 * (t ** 0.75)
            
            ring_v = []
            for s in range(sectors):
                th = (s / float(sectors)) * 2.0 * math.pi
                x = ex + radius * math.cos(th)
                y = ey + radius * math.sin(th)
                ring_v.append(bm_eng.verts.new((x, y, z)))
            bell_rings.append(ring_v)

        for r_i in range(rings_count):
            for s in range(sectors):
                s_next = (s + 1) % sectors
                v0 = bell_rings[r_i][s]
                v1 = bell_rings[r_i][s_next]
                v2 = bell_rings[r_i + 1][s_next]
                v3 = bell_rings[r_i + 1][s]
                bm_eng.faces.new((v0, v1, v2, v3))

        # Circumferential cooling tube rings / stiffener bands on bell exterior
        for ring_z in [7.35, 7.65, 7.95, 8.22]:
            t_ring = (ring_z - 7.02) / 1.28
            r_ring = 0.30 + 0.42 * (t_ring ** 0.75)
            torus_v = []
            for s in range(sectors):
                th = (s / float(sectors)) * 2.0 * math.pi
                x = ex + (r_ring + 0.035) * math.cos(th)
                y = ey + (r_ring + 0.035) * math.sin(th)
                torus_v.append(bm_eng.verts.new((x, y, ring_z)))
            for s in range(sectors):
                s_next = (s + 1) % sectors
                v0 = torus_v[s]
                v1 = torus_v[s_next]
                v2 = bm_eng.verts.new((torus_v[s_next].co.x, torus_v[s_next].co.y, ring_z + 0.035))
                v3 = bm_eng.verts.new((torus_v[s].co.x, torus_v[s].co.y, ring_z + 0.035))
                bm_eng.faces.new((v0, v1, v2, v3))

        # Inner combustion chamber dome
        dome_apex = bm_eng.verts.new((ex, ey, 7.04))
        for s in range(sectors):
            s_next = (s + 1) % sectors
            bm_eng.faces.new((dome_apex, bell_rings[0][s], bell_rings[0][s_next]))

        # Luminous Emissive Hot Ring at combustion throat (radiant orange glow)
        throat_z = 7.18
        throat_r = 0.31
        ring_emit_v = []
        for s in range(sectors):
            th = (s / float(sectors)) * 2.0 * math.pi
            x = ex + throat_r * math.cos(th)
            y = ey + throat_r * math.sin(th)
            ring_emit_v.append(bm_emit.verts.new((x, y, throat_z)))
        for s in range(sectors):
            s_next = (s + 1) % sectors
            v0 = ring_emit_v[s]
            v1 = ring_emit_v[s_next]
            v2 = bm_emit.verts.new((ring_emit_v[s_next].co.x, ring_emit_v[s_next].co.y, throat_z + 0.08))
            v3 = bm_emit.verts.new((ring_emit_v[s].co.x, ring_emit_v[s].co.y, throat_z + 0.08))
            bm_emit.faces.new((v0, v1, v2, v3))

    bmesh.ops.recalc_face_normals(bm_eng, faces=bm_eng.faces)
    bmesh.ops.recalc_face_normals(bm_emit, faces=bm_emit.faces)

    mesh_eng = bpy.data.meshes.new("EngineBellsMesh")
    bm_eng.to_mesh(mesh_eng)
    bm_eng.free()
    obj_eng = bpy.data.objects.new("EngineBells", mesh_eng)
    bpy.context.scene.collection.objects.link(obj_eng)
    assign_mat(obj_eng, materials["mat_engine"])

    mesh_emit = bpy.data.meshes.new("EngineHotRingsMesh")
    bm_emit.to_mesh(mesh_emit)
    bm_emit.free()
    obj_emit = bpy.data.objects.new("EngineHotRings", mesh_emit)
    bpy.context.scene.collection.objects.link(obj_emit)
    assign_mat(obj_emit, materials["mat_emissive"])

    return obj_eng, obj_emit

def build_rcs_blisters(materials):
    """Builds reaction control system (RCS) thruster pods on nose and aft shoulders cleanly."""
    bm = bmesh.new()

    for sign in [-1.0, 1.0]:
        px = sign * 0.98
        py = 0.12
        pz = -4.80

        res_cube = bmesh.ops.create_cube(bm, size=0.40)
        c_verts = res_cube['verts']
        bmesh.ops.scale(bm, vec=(0.75, 0.95, 1.3), verts=c_verts)
        bmesh.ops.translate(bm, vec=(px, py, pz), verts=c_verts)

        for dy, dz in [(-0.08, -0.10), (0.08, -0.10), (0.0, 0.12)]:
            bmesh.ops.create_cone(
                bm,
                cap_ends=True,
                segments=12,
                radius1=0.04,
                radius2=0.03,
                depth=0.10,
                matrix=mat_trans(px + sign * 0.15, py + dy, pz + dz)
            )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    assign_deterministic_uvs(bm)

    mesh = bpy.data.meshes.new("RCSPodsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("RCSPods", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])

    return obj

# -----------------------------------------------------------------------------
# 4. Deployable Landing Gear (3 Assemblies) & 1-Second Rigged Animation
# -----------------------------------------------------------------------------
def build_landing_gear(materials):
    """
    Builds 3 deployable landing gear assemblies:
    - 1 Nose gear at (0, -0.25, -4.20)
    - 2 Main gears at (±2.30, -0.15, 2.00)
    Each assembly features:
    - Hydraulic oleo shock strut with chrome lower piston
    - Folding torque link scissor hinge
    - Axle with alloy wheel rims and vulcanized rubber tires (mat_tire)
    Sets up an Armature with 1-second 'gear_deploy' animation (30 frames at 30 fps),
    extending downwards when deployed (frame 30).
    """
    arm_data = bpy.data.armatures.new("GearArmature")
    arm_obj = bpy.data.objects.new("GearArmature", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)

    bpy.ops.object.mode_set(mode='EDIT')
    root_bone = arm_data.edit_bones.new("root")
    root_bone.head = (0, 0, 0)
    root_bone.tail = (0, 1, 0)

    nose_bone = arm_data.edit_bones.new("gear_nose")
    nose_bone.head = (0.0, -0.25, -4.20)
    nose_bone.tail = (0.0, -1.65, -4.20)
    nose_bone.parent = root_bone

    main_l_bone = arm_data.edit_bones.new("gear_main_L")
    main_l_bone.head = (-2.30, -0.15, 2.00)
    main_l_bone.tail = (-2.30, -1.70, 2.00)
    main_l_bone.parent = root_bone

    main_r_bone = arm_data.edit_bones.new("gear_main_R")
    main_r_bone.head = (2.30, -0.15, 2.00)
    main_r_bone.tail = (2.30, -1.70, 2.00)
    main_r_bone.parent = root_bone

    bpy.ops.object.mode_set(mode='OBJECT')

    gear_objects = []

    # 1. Nose Gear Mesh (bone-local space: head is at (0, 0, 0))
    bm_n = bmesh.new()
    bmesh.ops.create_cone(
        bm_n,
        cap_ends=True,
        segments=32,
        radius1=0.09,
        radius2=0.09,
        depth=0.75,
        matrix=mat_cyl_y(0.0, -0.375, 0.0)
    )
    bmesh.ops.create_cone(
        bm_n,
        cap_ends=True,
        segments=32,
        radius1=0.065,
        radius2=0.065,
        depth=0.70,
        matrix=mat_cyl_y(0.0, -0.95, 0.0)
    )
    res_sciss = bmesh.ops.create_cube(bm_n, size=1.0)
    bmesh.ops.scale(bm_n, vec=(0.04, 0.16, 0.08), verts=res_sciss['verts'])
    bmesh.ops.translate(bm_n, vec=(0.0, -0.70, 0.10), verts=res_sciss['verts'])

    bmesh.ops.create_cone(
        bm_n,
        cap_ends=True,
        segments=24,
        radius1=0.045,
        radius2=0.045,
        depth=0.52,
        matrix=mat_cyl_x(0.0, -1.40, 0.0)
    )
    tire_verts_n = set()
    for side in [-0.19, 0.19]:
        res_tire = bmesh.ops.create_cone(
            bm_n,
            cap_ends=True,
            segments=40,
            radius1=0.36,
            radius2=0.36,
            depth=0.15,
            matrix=mat_cyl_x(side, -1.40, 0.0)
        )
        tire_verts_n.update(res_tire['verts'])

        bmesh.ops.create_cone(
            bm_n,
            cap_ends=True,
            segments=32,
            radius1=0.20,
            radius2=0.20,
            depth=0.17,
            matrix=mat_cyl_x(side, -1.40, 0.0)
        )

    for f in bm_n.faces:
        f.material_index = 1 if all(v in tire_verts_n for v in f.verts) else 0

    mesh_n = bpy.data.meshes.new("NoseGearMesh")
    bm_n.to_mesh(mesh_n)
    bm_n.free()
    obj_nose = bpy.data.objects.new("GearLeg_Nose", mesh_n)
    bpy.context.scene.collection.objects.link(obj_nose)
    obj_nose.data.materials.append(materials["mat_engine"])
    obj_nose.data.materials.append(materials["mat_tire"])
    gear_objects.append((obj_nose, "gear_nose"))

    # 2. Main Gear Left Mesh (bone-local space)
    bm_ml = bmesh.new()
    bmesh.ops.create_cone(
        bm_ml,
        cap_ends=True,
        segments=36,
        radius1=0.12,
        radius2=0.12,
        depth=0.85,
        matrix=mat_cyl_y(0.0, -0.425, 0.0)
    )
    bmesh.ops.create_cone(
        bm_ml,
        cap_ends=True,
        segments=36,
        radius1=0.09,
        radius2=0.09,
        depth=0.75,
        matrix=mat_cyl_y(0.0, -1.05, 0.0)
    )
    res_ml_brace = bmesh.ops.create_cube(bm_ml, size=1.0)
    bmesh.ops.scale(bm_ml, vec=(0.06, 0.20, 0.10), verts=res_ml_brace['verts'])
    bmesh.ops.translate(bm_ml, vec=(-0.10, -0.75, 0.0), verts=res_ml_brace['verts'])

    bmesh.ops.create_cone(
        bm_ml,
        cap_ends=True,
        segments=28,
        radius1=0.06,
        radius2=0.06,
        depth=0.60,
        matrix=mat_cyl_x(0.0, -1.55, 0.0)
    )
    tire_verts_ml = set()
    for side in [-0.24, 0.24]:
        res_t = bmesh.ops.create_cone(
            bm_ml,
            cap_ends=True,
            segments=48,
            radius1=0.48,
            radius2=0.48,
            depth=0.20,
            matrix=mat_cyl_x(side, -1.55, 0.0)
        )
        tire_verts_ml.update(res_t['verts'])

        bmesh.ops.create_cone(
            bm_ml,
            cap_ends=True,
            segments=32,
            radius1=0.26,
            radius2=0.26,
            depth=0.22,
            matrix=mat_cyl_x(side, -1.55, 0.0)
        )

    for f in bm_ml.faces:
        f.material_index = 1 if all(v in tire_verts_ml for v in f.verts) else 0

    mesh_ml = bpy.data.meshes.new("MainGearLMesh")
    bm_ml.to_mesh(mesh_ml)
    bm_ml.free()
    obj_main_l = bpy.data.objects.new("GearLeg_Main_L", mesh_ml)
    bpy.context.scene.collection.objects.link(obj_main_l)
    obj_main_l.data.materials.append(materials["mat_engine"])
    obj_main_l.data.materials.append(materials["mat_tire"])
    gear_objects.append((obj_main_l, "gear_main_L"))

    # 3. Main Gear Right Mesh (bone-local space)
    bm_mr = bmesh.new()
    bmesh.ops.create_cone(
        bm_mr,
        cap_ends=True,
        segments=36,
        radius1=0.12,
        radius2=0.12,
        depth=0.85,
        matrix=mat_cyl_y(0.0, -0.425, 0.0)
    )
    bmesh.ops.create_cone(
        bm_mr,
        cap_ends=True,
        segments=36,
        radius1=0.09,
        radius2=0.09,
        depth=0.75,
        matrix=mat_cyl_y(0.0, -1.05, 0.0)
    )
    res_mr_brace = bmesh.ops.create_cube(bm_mr, size=1.0)
    bmesh.ops.scale(bm_mr, vec=(0.06, 0.20, 0.10), verts=res_mr_brace['verts'])
    bmesh.ops.translate(bm_mr, vec=(0.10, -0.75, 0.0), verts=res_mr_brace['verts'])

    bmesh.ops.create_cone(
        bm_mr,
        cap_ends=True,
        segments=28,
        radius1=0.06,
        radius2=0.06,
        depth=0.60,
        matrix=mat_cyl_x(0.0, -1.55, 0.0)
    )
    tire_verts_mr = set()
    for side in [-0.24, 0.24]:
        res_t = bmesh.ops.create_cone(
            bm_mr,
            cap_ends=True,
            segments=48,
            radius1=0.48,
            radius2=0.48,
            depth=0.20,
            matrix=mat_cyl_x(side, -1.55, 0.0)
        )
        tire_verts_mr.update(res_t['verts'])

        bmesh.ops.create_cone(
            bm_mr,
            cap_ends=True,
            segments=32,
            radius1=0.26,
            radius2=0.26,
            depth=0.22,
            matrix=mat_cyl_x(side, -1.55, 0.0)
        )

    for f in bm_mr.faces:
        f.material_index = 1 if all(v in tire_verts_mr for v in f.verts) else 0

    mesh_mr = bpy.data.meshes.new("MainGearRMesh")
    bm_mr.to_mesh(mesh_mr)
    bm_mr.free()
    obj_main_r = bpy.data.objects.new("GearLeg_Main_R", mesh_mr)
    bpy.context.scene.collection.objects.link(obj_main_r)
    obj_main_r.data.materials.append(materials["mat_engine"])
    obj_main_r.data.materials.append(materials["mat_tire"])
    gear_objects.append((obj_main_r, "gear_main_R"))

    # Bind gear meshes to armature bones
    for obj, bone_name in gear_objects:
        obj.parent = arm_obj
        obj.parent_type = 'BONE'
        obj.parent_bone = bone_name

    # Rig keyframed animation 'gear_deploy' (30 frames = 1.0 second at 30 fps)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='POSE')

    pose_nose = arm_obj.pose.bones["gear_nose"]
    pose_l = arm_obj.pose.bones["gear_main_L"]
    pose_r = arm_obj.pose.bones["gear_main_R"]

    for p in [pose_nose, pose_l, pose_r]:
        p.rotation_mode = 'XYZ'

    # Frame 1: Retracted inside belly bays
    pose_nose.rotation_euler = (math.radians(95), 0, 0)
    pose_nose.keyframe_insert(data_path="rotation_euler", frame=1)

    pose_l.rotation_euler = (0, 0, math.radians(90))
    pose_l.keyframe_insert(data_path="rotation_euler", frame=1)

    pose_r.rotation_euler = (0, 0, math.radians(-90))
    pose_r.keyframe_insert(data_path="rotation_euler", frame=1)

    # Frame 30: Fully deployed vertically and locked
    pose_nose.rotation_euler = (0, 0, 0)
    pose_nose.keyframe_insert(data_path="rotation_euler", frame=30)

    pose_l.rotation_euler = (0, 0, 0)
    pose_l.keyframe_insert(data_path="rotation_euler", frame=30)

    pose_r.rotation_euler = (0, 0, 0)
    pose_r.keyframe_insert(data_path="rotation_euler", frame=30)

    bpy.ops.object.mode_set(mode='OBJECT')

    if arm_obj.animation_data and arm_obj.animation_data.action:
        arm_obj.animation_data.action.name = "gear_deploy"

    return arm_obj, [obj_nose, obj_main_l, obj_main_r]

# -----------------------------------------------------------------------------
# 5. Sockets (Empties / Node3D Marker Attachment Points)
# -----------------------------------------------------------------------------
def build_sockets():
    """Builds all 11 attachment sockets as empties for plumes, RCS, nav lights, and cameras."""
    sockets = [
        # Main Propulsion Engine Nozzles
        ("SOCKET_engine_L", (-0.88, -0.05,  8.30)),
        ("SOCKET_engine_R", ( 0.88, -0.05,  8.30)),

        # Wingtip Navigation Lights (Port Red / Starboard Green)
        ("SOCKET_nav_port", (-6.90,  0.15,  4.40)),
        ("SOCKET_nav_stbd", ( 6.90,  0.15,  4.40)),

        # Reaction Control System (RCS) Nozzles
        ("SOCKET_rcs_nose_pitch_up",   ( 0.00,  0.65, -4.80)),
        ("SOCKET_rcs_nose_pitch_down", ( 0.00, -0.65, -4.80)),
        ("SOCKET_rcs_nose_yaw_port",   (-0.98,  0.12, -4.80)),
        ("SOCKET_rcs_nose_yaw_stbd",   ( 0.98,  0.12, -4.80)),

        ("SOCKET_rcs_tail_port", (-1.45,  1.40,  7.10)),
        ("SOCKET_rcs_tail_stbd", ( 1.45,  1.40,  7.10)),
        ("SOCKET_rcs_tail_up",   ( 0.00,  3.80,  6.50)),

        # Camera & Cockpit Eye Points
        ("SOCKET_cockpit_cam", (0.00, 1.25, -4.10)),
        ("SOCKET_chase_cam",   (0.00, 4.00, 18.00)),
    ]

    created = []
    for name, loc in sockets:
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_type = 'ARROWS'
        empty.empty_display_size = 0.5
        empty.location = loc
        bpy.context.scene.collection.objects.link(empty)
        created.append(empty)

    return created

# -----------------------------------------------------------------------------
# 6. Collision Mesh (COL_hull)
# -----------------------------------------------------------------------------
def build_collision_mesh():
    """Builds a simplified low-poly convex hull collision mesh for Jolt physics."""
    bm = bmesh.new()

    pts = [
        # Nose apex
        (0.0, 0.10, -6.50),
        # Cockpit brow
        (0.0, 1.40, -4.10),
        (-1.40, 0.20, -4.50),
        ( 1.40, 0.20, -4.50),
        # Belly nose
        (0.0, -0.65, -4.80),
        # Payload bay shoulders
        (-1.75, 1.25, -1.50),
        ( 1.75, 1.25, -1.50),
        (-1.75, 1.25,  4.50),
        ( 1.75, 1.25,  4.50),
        # Belly chine
        (-1.75, -0.65, -1.50),
        ( 1.75, -0.65, -1.50),
        (-1.80, -0.65,  4.50),
        ( 1.80, -0.65,  4.50),
        # Delta Wingtips (Starboard & Port)
        ( 6.90, 0.15, 4.40),
        ( 6.90, 0.15, 4.80),
        (-6.90, 0.15, 4.40),
        (-6.90, 0.15, 4.80),
        # Trailing edge root
        ( 1.85, 0.10, 5.85),
        (-1.85, 0.10, 5.85),
        # Tail fin top
        (0.0, 3.85, 6.10),
        (0.0, 3.85, 6.50),
        # Aft bulkhead corners
        (-1.75, 1.20, 7.10),
        ( 1.75, 1.20, 7.10),
        (-1.75, -0.60, 7.10),
        ( 1.75, -0.60, 7.10),
        # Engine bells envelope
        (-0.88, -0.05, 8.30),
        ( 0.88, -0.05, 8.30),
    ]

    for p in pts:
        bm.verts.new(p)

    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("COL_hullMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("COL_hull", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True

    return obj

# -----------------------------------------------------------------------------
# 7. LOD Generation (Target LOD0 ~25k - 40k tris, LOD1 <= 8k tris)
# -----------------------------------------------------------------------------
def build_lods(hull_components):
    """
    Combines hull components into Orbiter_LOD0 (target ~25k-40k tris)
    and creates a decimated Orbiter_LOD1 (<= 8k tris).
    """
    fuselage_obj = hull_components[0]
    mod_sub = fuselage_obj.modifiers.new("Subsurf", "SUBSURF")
    mod_sub.levels = 1
    mod_sub.render_levels = 1

    wings_obj = hull_components[4]
    mod_sub_w = wings_obj.modifiers.new("Subsurf", "SUBSURF")
    mod_sub_w.levels = 1
    mod_sub_w.render_levels = 1

    for c in hull_components:
        bpy.context.view_layer.objects.active = c
        for mod in list(c.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)

    bpy.ops.object.select_all(action='DESELECT')
    for c in hull_components:
        c.select_set(True)
    bpy.context.view_layer.objects.active = hull_components[0]
    bpy.ops.object.duplicate()
    lod0_obj = bpy.context.active_object
    bpy.ops.object.join()
    lod0_obj.name = "Orbiter_LOD0"
    lod0_obj.data.name = "Orbiter_LOD0_Mesh"

    lod0_tris = sum(len(f.vertices) - 2 for f in lod0_obj.data.polygons)
    print(f"Orbiter_LOD0 triangle count: {lod0_tris} (budget: ~25,000 - 40,000)")

    bpy.ops.object.select_all(action='DESELECT')
    lod0_obj.select_set(True)
    bpy.context.view_layer.objects.active = lod0_obj
    bpy.ops.object.duplicate()
    lod1_obj = bpy.context.active_object
    lod1_obj.name = "Orbiter_LOD1"
    lod1_obj.data.name = "Orbiter_LOD1_Mesh"

    target_l1 = 6800.0
    ratio = min(0.35, target_l1 / max(1.0, float(lod0_tris)))
    mod_dec = lod1_obj.modifiers.new("Decimate", "DECIMATE")
    mod_dec.ratio = ratio
    bpy.context.view_layer.objects.active = lod1_obj
    bpy.ops.object.modifier_apply(modifier="Decimate")

    lod1_tris = sum(len(f.vertices) - 2 for f in lod1_obj.data.polygons)
    print(f"Orbiter_LOD1 triangle count: {lod1_tris} (budget <= 8,000)")

    for c in hull_components:
        bpy.data.objects.remove(c, do_unlink=True)

    return lod0_obj, lod1_obj

# -----------------------------------------------------------------------------
# 8. Render Multi-Angle Preview Images
# -----------------------------------------------------------------------------
def setup_lighting():
    """Sets up high-quality 4-point studio lighting with ground bounce fill."""
    lights = []

    # Key Light (Upper-Front-Left)
    p1_data = bpy.data.lights.new("KeyLight", type='POINT')
    p1_data.energy = 48000.0
    p1_data.color = (1.0, 0.96, 0.92)
    p1 = bpy.data.objects.new("KeyLight", p1_data)
    p1.location = (-12.0, 14.0, -14.0)
    bpy.context.scene.collection.objects.link(p1)
    lights.append(p1)

    # Fill Light (Upper-Front-Right)
    p2_data = bpy.data.lights.new("FillLight", type='POINT')
    p2_data.energy = 26000.0
    p2_data.color = (0.75, 0.85, 1.0)
    p2 = bpy.data.objects.new("FillLight", p2_data)
    p2.location = (14.0, 10.0, -10.0)
    bpy.context.scene.collection.objects.link(p2)
    lights.append(p2)

    # Ground Bounce Fill (Illuminates deployed gear legs, wheels & belly tiles)
    p3_data = bpy.data.lights.new("GroundBounceLight", type='POINT')
    p3_data.energy = 30000.0
    p3_data.color = (0.80, 0.85, 0.95)
    p3 = bpy.data.objects.new("GroundBounceLight", p3_data)
    p3.location = (0.0, -8.0, 0.0)
    bpy.context.scene.collection.objects.link(p3)
    lights.append(p3)

    # Rim Light (Upper-Rear)
    p4_data = bpy.data.lights.new("RimLight", type='POINT')
    p4_data.energy = 36000.0
    p4_data.color = (0.95, 0.95, 1.0)
    p4 = bpy.data.objects.new("RimLight", p4_data)
    p4.location = (0.0, 12.0, 14.0)
    bpy.context.scene.collection.objects.link(p4)
    lights.append(p4)

    # Lateral Gear Fill Light (Illuminates gear struts & wheels in side view)
    p5_data = bpy.data.lights.new("GearSideFill", type='POINT')
    p5_data.energy = 28000.0
    p5_data.color = (0.85, 0.90, 1.0)
    p5 = bpy.data.objects.new("GearSideFill", p5_data)
    p5.location = (-16.0, -1.5, 0.0)
    bpy.context.scene.collection.objects.link(p5)
    lights.append(p5)

    return lights

def render_previews():
    """
    Renders 3 multi-angle preview images with deployed landing gear:
    - preview_front.png (Front three-quarter view showing nose, cockpit glass, gear legs)
    - preview_side.png (Side profile showing full fuselage, wings, elevons, gear)
    - preview_top.png (Top-down view showing double-delta wings, payload bay doors)
    - preview.png (Isometric view for backwards compatibility)
    """
    scene = bpy.context.scene
    scene.frame_set(30)  # Frame 30 = Landing gear fully deployed

    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = 'PNG'

    world = bpy.data.worlds.new("SpaceWorld")
    world.use_nodes = True
    bg_node = world.node_tree.nodes.get("Background")
    if bg_node:
        bg_node.inputs["Color"].default_value = (0.02, 0.025, 0.035, 1.0)
        bg_node.inputs["Strength"].default_value = 0.6
    scene.world = world

    lights = setup_lighting()

    cam_data = bpy.data.cameras.new("PreviewCamera")
    cam_data.lens = 42.0
    cam_obj = bpy.data.objects.new("PreviewCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    shots = [
        ("Front View", PREVIEW_FRONT_PATH,
         mathutils.Vector((-12.0, 5.0, -14.0)),
         mathutils.Vector((0.0, -0.2, -1.0))),

        ("Side Profile", PREVIEW_SIDE_PATH,
         mathutils.Vector((-18.0, 1.8, 0.5)),
         mathutils.Vector((0.0, 0.0, 0.5))),

        ("Top View", PREVIEW_TOP_PATH,
         mathutils.Vector((-0.5, 20.0, 1.0)),
         mathutils.Vector((0.0, 0.0, 0.5))),

        ("Isometric Preview", PREVIEW_OUTPUT_PATH,
         mathutils.Vector((-15.0, 9.5, -14.0)),
         mathutils.Vector((0.0, 0.2, 0.5))),
    ]

    for label, out_path, eye, target in shots:
        mat = get_look_at_matrix(eye, target, mathutils.Vector((0, 1, 0)))
        cam_obj.matrix_world = mat
        scene.render.filepath = os.path.abspath(out_path)
        print(f"Rendering {label} -> {out_path}...")
        bpy.ops.render.render(write_still=True)
        print(f"Rendered: {os.path.exists(out_path)} ({os.path.getsize(out_path):,} bytes)")

    # Clean up lighting and camera
    for l in lights:
        bpy.data.objects.remove(l, do_unlink=True)
    bpy.data.objects.remove(cam_obj, do_unlink=True)

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
def main():
    print("=== Building Solar Horizon Hero Orbiter (Polish Pass) ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # 1. Generate textures
    tex_paths = generate_procedural_textures(TEXTURES_DIR, size=2048)

    # 2. Setup materials
    materials = setup_materials(tex_paths)

    # 3. Build geometry components
    print("Hand-modelling high-fidelity orbiter components...")
    fuselage = build_fuselage(materials)
    cockpit_glass, cockpit_frame, cockpit_dash = build_cockpit_glazing(materials)
    wings = build_delta_wings(materials)
    oms_pods = build_oms_pods(materials)
    tail_fin = build_vertical_tail_fin(materials)
    body_flap = build_body_flap(materials)
    engine_bells, engine_hot_rings = build_engine_bells(materials)
    rcs_blisters = build_rcs_blisters(materials)

    hull_components = [
        fuselage,
        cockpit_glass,
        cockpit_frame,
        cockpit_dash,
        wings,
        oms_pods,
        tail_fin,
        body_flap,
        engine_bells,
        engine_hot_rings,
        rcs_blisters
    ]

    # 4. Build deployable landing gear & 1s animation
    print("Building deployable landing gear with struts and wheels...")
    gear_armature, gear_legs = build_landing_gear(materials)

    # 5. Build sockets
    print("Creating attachment sockets...")
    sockets = build_sockets()

    # 6. Build collision hull
    print("Building collision mesh COL_hull...")
    col_hull = build_collision_mesh()

    # 7. Render 3 multi-angle preview images (plus preview.png) with gear deployed
    print("Rendering multi-angle preview images...")
    render_previews()

    # 8. Build LOD0 and LOD1
    print("Generating LODs...")
    lod0, lod1 = build_lods(hull_components)

    # 9. glTF 2.0 Export
    print(f"Exporting binary glTF (.glb) to {GLB_OUTPUT_PATH}...")
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUTPUT_PATH,
        export_format='GLB',
        export_apply=False,
        export_animations=True,
        export_cameras=False,
        export_lights=False,
        export_extras=True,
    )

    print("=== Build Complete ===")
    if os.path.exists(GLB_OUTPUT_PATH):
        print(f"GLB Output: {GLB_OUTPUT_PATH} ({os.path.getsize(GLB_OUTPUT_PATH):,} bytes)")
    for p in [PREVIEW_OUTPUT_PATH, PREVIEW_FRONT_PATH, PREVIEW_SIDE_PATH, PREVIEW_TOP_PATH]:
        if os.path.exists(p):
            print(f"Preview Output: {p} ({os.path.getsize(p):,} bytes)")

if __name__ == "__main__":
    main()
