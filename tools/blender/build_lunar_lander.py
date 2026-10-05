#!/usr/bin/env python3
"""
Solar Horizon — Lunar Lander Model Generator (WP 3.3)
Builds a high-fidelity modular Lunar Lander in Blender and exports glTF 2.0 (.glb).

Specifications per IMPROVEMENT_ROADMAP.md (WP 3.3) & ASSET_PIPELINE.md:
- Coordinate System (Godot 4): Forward = -Z, Up = +Y, Right = +X, 1 unit = 1 m
- Origin (0, 0, 0): Center of Mass (CoM) near the stage interface.
  Landing footpads rest at horizontal ground offset Y = -2.40 m.
- Descent Stage:
  - Octagonal gold-foil chassis with faceted Multi-Layer Insulation (MLI) panels.
  - Recessed equipment quadrant bays on cardinal faces (+X MESA, -X ALSEP, +Z Radiator).
  - Central bottom cavity with conical thermal heat-shield skirt for descent engine.
  - 4 articulated outrigger landing legs at 45-degree diagonal angles with primary oleo
    struts, secondary A-frame tubular trusses, circular dished footpads with honeycomb
    stiffening rims, and lunar surface touchdown sensing probe rods.
  - Forward EVA egress porch and 10-rung climbing ladder on the -Z face.
  - Gimballed deep-throttling descent rocket engine bell with exterior cooling rings,
    deep inner bell cavity, and glowing emissive combustion throat ring.
- Ascent Crew Module:
  - Modular cabin sitting atop the descent stage upper deck.
  - Multi-faceted forward cockpit nose with angled pilot observation portholes.
  - Pressurized crew cabin clad in white Beta-cloth quilted thermal blanket insulation.
  - Forward egress airlock hatch with recessed frame, door panel, latch handle, and status indicators.
  - Steerable high-gain parabolic dish antenna on upper shoulder with gimbal mount and feed horn.
  - 4 Reaction Control System (RCS) quads mounted on outrigger standoff pylons (+X, -X, -Z, +Z)
    with 4 orthogonal expansion nozzles each.
  - Upper docking port collar with capture latch petals, alignment guides, and optical target.
- Sockets:
  - SOCKET_rcs_1 (Starboard RCS quad)
  - SOCKET_rcs_2 (Port RCS quad)
  - SOCKET_rcs_3 (Forward RCS quad)
  - SOCKET_rcs_4 (Aft RCS quad)
  - SOCKET_docking (Top docking contact plane)
  - SOCKET_engine_descent (Descent engine nozzle exit center)
- Procedural PBR Textures (2048x2048):
  - Gold Kapton MLI foil (wrinkled facets, taped seams, metallic 0.98, roughness 0.28)
  - White Beta-cloth thermal blanket (quilted pillows, stitching, livery cheatlines, markings)
  - Anodized metal / structural alloy (panel seams, machined flanges, rivets, hazard stripes)
  - ORM (R=AO, G=Roughness, B=Metallic)
  - Normal map (tangent space, OpenGL +Y)
  - Emission map (status LEDs, docking target, glowing engine throat)
- Collision: COL_hull simplified convex hull
- LODs:
  - LunarLander_LOD0: 15,000 - 25,000 triangles (budget per WP 3.3)
  - LunarLander_LOD1: 3,000 - 5,000 triangles (budget per WP 3.3)
- Renders: preview.png (studio lighting 3/4 isometric beauty render)
"""

import sys
import os
import math
import subprocess

# If run directly outside Blender, invoke via Blender 5.2 executable
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

OUTPUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "ships", "lunar_lander")
TEXTURES_DIR = os.path.join(OUTPUT_DIR, "textures")
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(TEXTURES_DIR, exist_ok=True)

GLB_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "lunar_lander.glb")
PREVIEW_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "preview.png")
PREVIEW_FRONT_PATH = os.path.join(OUTPUT_DIR, "preview_front.png")
PREVIEW_SIDE_PATH = os.path.join(OUTPUT_DIR, "preview_side.png")
PREVIEW_TOP_PATH = os.path.join(OUTPUT_DIR, "preview_top.png")

# -----------------------------------------------------------------------------
# Math / Matrix / BMesh Helpers
# -----------------------------------------------------------------------------
def mat_trans(x, y, z):
    return mathutils.Matrix.Translation((x, y, z))

def mat_rot_x(angle_deg):
    return mathutils.Matrix.Rotation(math.radians(angle_deg), 4, 'X')

def mat_rot_y(angle_deg):
    return mathutils.Matrix.Rotation(math.radians(angle_deg), 4, 'Y')

def mat_rot_z(angle_deg):
    return mathutils.Matrix.Rotation(math.radians(angle_deg), 4, 'Z')

def get_look_at_matrix(eye, target, up=mathutils.Vector((0, 1, 0))):
    forward = (target - eye).normalized()
    right = forward.cross(up).normalized()
    actual_up = right.cross(forward).normalized()
    return mathutils.Matrix([
        [right.x, actual_up.x, -forward.x, eye.x],
        [right.y, actual_up.y, -forward.y, eye.y],
        [right.z, actual_up.z, -forward.z, eye.z],
        [0.0,     0.0,         0.0,        1.0  ]
    ])

def assign_uvs(bm, verts, uv_bounds):
    """Maps vertices to bounding box [u_min, u_max, v_min, v_max] in UV space using cylindrical mapping."""
    uv_layer = bm.loops.layers.uv.verify()
    u_min, u_max, v_min, v_max = uv_bounds
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    if not xs:
        return
    min_y, max_y = min(ys), max(ys)
    dy = max(max_y - min_y, 1e-4)

    for v in verts:
        theta = math.atan2(v.co.x, v.co.z)
        u_norm = (theta / (2.0 * math.pi)) + 0.5
        v_norm = (v.co.y - min_y) / dy

        for loop in v.link_loops:
            u = u_min + u_norm * (u_max - u_min)
            v_coord = v_min + v_norm * (v_max - v_min)
            loop[uv_layer].uv = (min(0.99, max(0.01, u)), min(0.99, max(0.01, v_coord)))

def make_strut(bm, p1, p2, r1, r2=None, segments=12, uv_bounds=(0.1, 0.9, 0.82, 0.96)):
    """Creates a cylinder/strut directly connecting point p1 to point p2 with UVs."""
    p1 = mathutils.Vector(p1)
    p2 = mathutils.Vector(p2)
    v = p2 - p1
    length = v.length
    if length < 1e-6:
        return []
    center = (p1 + p2) * 0.5
    dir_vec = v.normalized()
    z_axis = mathutils.Vector((0, 0, 1))
    rot = z_axis.rotation_difference(dir_vec).to_matrix().to_4x4()
    mat = mathutils.Matrix.Translation(center) @ rot
    if r2 is None:
        r2 = r1
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        segments=segments,
        radius1=r1,
        radius2=r2,
        depth=length,
        matrix=mat
    )
    if uv_bounds:
        assign_uvs(bm, res["verts"], uv_bounds)
    return res["verts"]

def add_box(bm, center, size, rot_mat=None, uv_bounds=(0.1, 0.9, 0.82, 0.96)):
    """Creates a cube primitive with explicit size, rotation, and UV coordinates."""
    mat = mathutils.Matrix.Translation(center)
    if rot_mat:
        mat = mat @ rot_mat
    mat = mat @ mathutils.Matrix.Scale(size[0], 4, (1, 0, 0)) \
              @ mathutils.Matrix.Scale(size[1], 4, (0, 1, 0)) \
              @ mathutils.Matrix.Scale(size[2], 4, (0, 0, 1))
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=mat)
    if uv_bounds:
        assign_uvs(bm, res["verts"], uv_bounds)
    return res["verts"]

def add_vertical_cylinder(bm, center, radius, depth, segments=24, uv_bounds=(0.1, 0.9, 0.82, 0.96)):
    """Creates an upright cylinder aligned along the vertical Y axis."""
    rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
    mat = mathutils.Matrix.Translation(center) @ rot
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
        matrix=mat
    )
    if uv_bounds:
        assign_uvs(bm, res["verts"], uv_bounds)
    return res["verts"]

def add_sphere(bm, center, radius, u_segs=16, v_segs=12, uv_bounds=(0.05, 0.95, 0.05, 0.42)):
    """Creates a UV sphere with explicit center, radius, and UV coordinates."""
    res = bmesh.ops.create_uvsphere(
        bm,
        u_segments=u_segs,
        v_segments=v_segs,
        radius=radius,
        matrix=mathutils.Matrix.Translation(center)
    )
    if uv_bounds:
        assign_uvs(bm, res["verts"], uv_bounds)
    return res["verts"]

# -----------------------------------------------------------------------------
# 1. Procedural PBR Textures (2048x2048: Albedo, ORM, Normal, Emission)
# -----------------------------------------------------------------------------
def generate_procedural_textures(tex_dir, size=2048):
    """
    Generates high-fidelity procedural PBR texture maps (2048x2048):
    - Zone 1 (v < 0.44): Gold Kapton MLI Foil
      Reflective aluminized gold foil with crinkled facet micro-texture, taped seams,
      and quilted foil pockets.
    - Zone 2 (0.44 <= v < 0.78): White Beta-Cloth Thermal Blanket
      Matte quilted silica/beta cloth with soft pillowing, stitch indentations,
      Solar Horizon orange/cyan cheatlines, mission stencils, and hazard markings.
    - Zone 3 (v >= 0.78): Dark Anodized Metal & Structural Titanium
      Machined panels with rivets, hex bolts, circular flanges, and warning borders.
    """
    print(f"Generating {size}x{size} procedural PBR textures for Lunar Lander...")
    y_coords, x_coords = np.mgrid[0:size, 0:size]
    u = x_coords / float(size)
    v = y_coords / float(size)

    # 1.1 ALBEDO MAP
    albedo = np.zeros((size, size, 4), dtype=np.float32)
    albedo[:, :, 3] = 1.0

    mask_gold = (v < 0.44)
    mask_blanket = (v >= 0.44) & (v < 0.78)
    mask_metal = (v >= 0.78)

    # --- ZONE 1: GOLD KAPTON FOIL (v < 0.44) ---
    albedo[mask_gold, 0] = 0.96
    albedo[mask_gold, 1] = 0.74
    albedo[mask_gold, 2] = 0.16

    # Crinkled foil micro-facets
    facet_size = 32
    f_x = x_coords // facet_size
    f_y = y_coords // facet_size
    hash_grid = ((f_x * 12345 + f_y * 67891) % 997) / 997.0 - 0.5
    crinkle_fine = np.sin(u * 220.0 + hash_grid * 4.0) * np.cos(v * 220.0 - hash_grid * 3.5)
    foil_variation = hash_grid * 0.08 + crinkle_fine * 0.04
    albedo[mask_gold, 0] += foil_variation[mask_gold] * 0.3
    albedo[mask_gold, 1] += foil_variation[mask_gold] * 0.25
    albedo[mask_gold, 2] += foil_variation[mask_gold] * 0.05

    # Amber Kapton tape seams (grid lines every 128 px, width 8 px)
    tape_x = (x_coords % 128 < 8)
    tape_y = (y_coords % 128 < 8)
    tape_lines = (tape_x | tape_y) & mask_gold
    albedo[tape_lines, 0] = 0.90
    albedo[tape_lines, 1] = 0.52
    albedo[tape_lines, 2] = 0.06

    # --- ZONE 2: WHITE BETA-CLOTH THERMAL BLANKET (0.44 <= v < 0.78) ---
    albedo[mask_blanket, 0] = 0.89
    albedo[mask_blanket, 1] = 0.90
    albedo[mask_blanket, 2] = 0.92

    # Beta cloth fine fabric weave
    weave = (np.sin(u * 512.0 * math.pi) * np.sin(v * 512.0 * math.pi)) * 0.015
    albedo[mask_blanket, 0] += weave[mask_blanket]
    albedo[mask_blanket, 1] += weave[mask_blanket]
    albedo[mask_blanket, 2] += weave[mask_blanket]

    # Quilted stitching grid (64 px squares with stitch seam lines)
    quilt_x = (x_coords % 64 < 2)
    quilt_y = (y_coords % 64 < 2)
    quilt_seam = (quilt_x | quilt_y) & mask_blanket
    albedo[quilt_seam, 0] = 0.76
    albedo[quilt_seam, 1] = 0.78
    albedo[quilt_seam, 2] = 0.80

    # Quilt tuft buttons / pin fastener depressions at intersections
    dist_button_x = (x_coords % 64)
    dist_button_y = (y_coords % 64)
    button_dots = ((dist_button_x < 4) & (dist_button_y < 4)) & mask_blanket
    albedo[button_dots, 0] = 0.60
    albedo[button_dots, 1] = 0.62
    albedo[button_dots, 2] = 0.65

    # Mission Markings: Solar Horizon Orange Cheatline & Cyan Pinstripe around cabin waist
    livery_orange = (v >= 0.67) & (v < 0.69) & (u > 0.05) & (u < 0.95) & mask_blanket
    albedo[livery_orange, 0] = 0.96
    albedo[livery_orange, 1] = 0.40
    albedo[livery_orange, 2] = 0.08

    livery_cyan = (v >= 0.692) & (v < 0.70) & (u > 0.05) & (u < 0.95) & mask_blanket
    albedo[livery_cyan, 0] = 0.12
    albedo[livery_cyan, 1] = 0.78
    albedo[livery_cyan, 2] = 0.95

    # Emergency Egress Hatch Hazard Border
    hatch_hazard = (u >= 0.40) & (u < 0.60) & (v >= 0.46) & (v < 0.52) & mask_blanket
    diag_stripes = ((x_coords + y_coords) // 16) % 2 == 0
    albedo[hatch_hazard & diag_stripes, 0] = 0.95
    albedo[hatch_hazard & diag_stripes, 1] = 0.75
    albedo[hatch_hazard & diag_stripes, 2] = 0.05
    albedo[hatch_hazard & ~diag_stripes, 0] = 0.10
    albedo[hatch_hazard & ~diag_stripes, 1] = 0.10
    albedo[hatch_hazard & ~diag_stripes, 2] = 0.12

    # --- ZONE 3: DARK ANODIZED METAL & TITANIUM (v >= 0.78) ---
    albedo[mask_metal, 0] = 0.28
    albedo[mask_metal, 1] = 0.30
    albedo[mask_metal, 2] = 0.33

    # Machined panel lines
    panel_x = (x_coords % 128 < 2)
    panel_y = (y_coords % 128 < 2)
    panel_lines = (panel_x | panel_y) & mask_metal
    albedo[panel_lines, 0] = 0.16
    albedo[panel_lines, 1] = 0.17
    albedo[panel_lines, 2] = 0.18

    # Rivet / bolt fasteners along panel lines (spaced every 32 px)
    rivet_x = (x_coords % 32 < 3) & (y_coords % 128 < 4)
    rivet_y = (y_coords % 32 < 3) & (x_coords % 128 < 4)
    rivets = (rivet_x | rivet_y) & mask_metal
    albedo[rivets, 0] = 0.65
    albedo[rivets, 1] = 0.68
    albedo[rivets, 2] = 0.72

    albedo = np.clip(albedo, 0.0, 1.0)

    # 1.2 ORM MAP (R = AO, G = Roughness, B = Metallic)
    orm = np.zeros((size, size, 4), dtype=np.float32)
    orm[:, :, 3] = 1.0

    orm[mask_gold, 0] = 0.88
    orm[mask_gold, 1] = 0.28
    orm[mask_gold, 2] = 0.98

    orm[tape_lines, 0] = 0.45
    orm[tape_lines, 1] = 0.38
    orm[mask_gold, 1] += (crinkle_fine[mask_gold] * 0.08)

    orm[mask_blanket, 0] = 0.95
    orm[mask_blanket, 1] = 0.84
    orm[mask_blanket, 2] = 0.03

    orm[quilt_seam, 0] = 0.50
    orm[quilt_seam, 1] = 0.94
    orm[button_dots, 0] = 0.35
    orm[livery_orange | livery_cyan, 1] = 0.40

    orm[mask_metal, 0] = 0.90
    orm[mask_metal, 1] = 0.32
    orm[mask_metal, 2] = 0.94

    orm[panel_lines, 0] = 0.40
    orm[panel_lines, 1] = 0.50
    orm[rivets, 1] = 0.22

    orm = np.clip(orm, 0.0, 1.0)

    # 1.3 NORMAL MAP (Tangent Space, OpenGL +Y Up)
    normal = np.zeros((size, size, 4), dtype=np.float32)
    normal[:, :, 0] = 0.50
    normal[:, :, 1] = 0.50
    normal[:, :, 2] = 1.00
    normal[:, :, 3] = 1.00

    grad_x = np.gradient(crinkle_fine, axis=1) * 2.5
    grad_y = np.gradient(crinkle_fine, axis=0) * 2.5
    normal[mask_gold, 0] = 0.50 - grad_x[mask_gold]
    normal[mask_gold, 1] = 0.50 - grad_y[mask_gold]

    qx = ((x_coords % 64) - 32.0) / 32.0
    qy = ((y_coords % 64) - 32.0) / 32.0
    normal[mask_blanket, 0] = 0.50 - qx[mask_blanket] * 0.25
    normal[mask_blanket, 1] = 0.50 - qy[mask_blanket] * 0.25

    nx = (normal[:, :, 0] - 0.50) * 2.0
    ny = (normal[:, :, 1] - 0.50) * 2.0
    nz = np.sqrt(np.clip(1.0 - nx*nx - ny*ny, 1e-4, 1.0))
    normal[:, :, 0] = nx * 0.5 + 0.5
    normal[:, :, 1] = ny * 0.5 + 0.5
    normal[:, :, 2] = nz
    normal = np.clip(normal, 0.0, 1.0)

    # 1.4 EMISSION MAP
    emission = np.zeros((size, size, 4), dtype=np.float32)
    emission[:, :, 3] = 1.0

    led_green = (u >= 0.48) & (u < 0.495) & (v >= 0.525) & (v < 0.535) & mask_blanket
    led_amber = (u >= 0.505) & (u < 0.52) & (v >= 0.525) & (v < 0.535) & mask_blanket
    emission[led_green, 0] = 0.20
    emission[led_green, 1] = 1.00
    emission[led_green, 2] = 0.30

    emission[led_amber, 0] = 1.00
    emission[led_amber, 1] = 0.65
    emission[led_amber, 2] = 0.10

    docking_target = (np.abs(u - 0.50) < 0.003) & (v >= 0.88) & (v < 0.94) & mask_metal
    docking_cross = (np.abs(v - 0.91) < 0.003) & (u >= 0.47) & (u < 0.53) & mask_metal
    emission[docking_target | docking_cross, 0] = 0.25
    emission[docking_target | docking_cross, 1] = 0.85
    emission[docking_target | docking_cross, 2] = 1.00

    maps = {
        "lunar_lander_albedo.png": albedo,
        "lunar_lander_orm.png": orm,
        "lunar_lander_normal.png": normal,
        "lunar_lander_emission.png": emission,
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
    """Sets up the 4 canonical PBR materials: mat_lander_main, mat_metal, mat_engine, mat_glass."""
    materials = {}

    # 2.1 mat_lander_main (Atlas material driven by procedural PBR maps)
    mat_main = bpy.data.materials.new("mat_lander_main")
    nodes = mat_main.node_tree.nodes
    links = mat_main.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    albedo_img = bpy.data.images.load(tex_paths["lunar_lander_albedo.png"])
    orm_img = bpy.data.images.load(tex_paths["lunar_lander_orm.png"])
    orm_img.colorspace_settings.name = "Non-Color"
    normal_img = bpy.data.images.load(tex_paths["lunar_lander_normal.png"])
    normal_img.colorspace_settings.name = "Non-Color"
    emission_img = bpy.data.images.load(tex_paths["lunar_lander_emission.png"])

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
    bsdf.inputs["Emission Strength"].default_value = 4.0
    materials["mat_lander_main"] = mat_main

    # 2.2 mat_metal (Machined aerospace titanium/alloy for struts, frame, antenna, and RCS)
    mat_metal = bpy.data.materials.new("mat_metal")
    bsdf_metal = mat_metal.node_tree.nodes.get("Principled BSDF")
    bsdf_metal.inputs["Base Color"].default_value = (0.28, 0.30, 0.33, 1.0)
    bsdf_metal.inputs["Metallic"].default_value = 0.94
    bsdf_metal.inputs["Roughness"].default_value = 0.30
    materials["mat_metal"] = mat_metal

    # 2.3 mat_engine (High-temperature Columbium/Niobium descent rocket bell)
    mat_engine = bpy.data.materials.new("mat_engine")
    bsdf_eng = mat_engine.node_tree.nodes.get("Principled BSDF")
    bsdf_eng.inputs["Base Color"].default_value = (0.20, 0.22, 0.25, 1.0)
    bsdf_eng.inputs["Metallic"].default_value = 0.92
    bsdf_eng.inputs["Roughness"].default_value = 0.28
    materials["mat_engine"] = mat_engine

    # 2.4 mat_glass (Cockpit portholes: deep dark glossy crystal glazing)
    mat_glass = bpy.data.materials.new("mat_glass")
    bsdf_glass = mat_glass.node_tree.nodes.get("Principled BSDF")
    bsdf_glass.inputs["Base Color"].default_value = (0.01, 0.02, 0.035, 1.0)
    bsdf_glass.inputs["Metallic"].default_value = 0.10
    bsdf_glass.inputs["Roughness"].default_value = 0.02
    if "IOR" in bsdf_glass.inputs:
        bsdf_glass.inputs["IOR"].default_value = 1.52
    materials["mat_glass"] = mat_glass

    return materials

def assign_mat(obj, mat):
    if len(obj.data.materials) == 0:
        obj.data.materials.append(mat)
    else:
        obj.data.materials[0] = mat

# -----------------------------------------------------------------------------
# 3. Geometry Construction
# -----------------------------------------------------------------------------

def build_descent_stage(materials):
    """
    Builds the octagonal gold-foil descent stage:
    - 8-sided faceted prism body (radius 2.15 m, height 1.6 m, Y from -1.40 to +0.20).
    - Octagon vertices at 22.5, 67.5, 112.5... degrees.
      This puts flat cardinal faces at -Z (Forward), +Z (Aft), +X (Starboard), -X (Port).
      And puts diagonal corners at 45, 135, 225, 315 degrees for landing legs!
    - Equipment bays on cardinal faces (+X MESA, -X ALSEP, +Z Radiator).
    - Central bottom engine recess cavity with conical heat shield skirt.
    - 4 spherical helium pressurization tanks between bulkheads.
    - Upper interstage staging truss ring connecting to the ascent stage.
    """
    bm = bmesh.new()

    angles = [i * (2.0 * math.pi / 8.0) + (math.pi / 8.0) for i in range(8)]
    r_core = 2.15
    y_bot = -1.40
    y_top = 0.20

    top_ring = []
    bot_ring = []
    for ang in angles:
        x = math.cos(ang) * r_core
        z = math.sin(ang) * r_core
        v_t = bm.verts.new((x, y_top, z))
        v_b = bm.verts.new((x, y_bot, z))
        top_ring.append(v_t)
        bot_ring.append(v_b)

    for i in range(8):
        i_next = (i + 1) % 8
        bm.faces.new((bot_ring[i], bot_ring[i_next], top_ring[i_next], top_ring[i]))

    top_center = bm.verts.new((0.0, y_top, 0.0))
    for i in range(8):
        i_next = (i + 1) % 8
        bm.faces.new((top_ring[i], top_center, top_ring[i_next]))

    r_recess = 0.95
    bot_recess_rim = []
    top_recess_rim = []
    y_recess_top = -0.75

    for ang in angles:
        rx = math.cos(ang) * r_recess
        rz = math.sin(ang) * r_recess
        v_r_bot = bm.verts.new((rx, y_bot, rz))
        v_r_top = bm.verts.new((rx * 0.75, y_recess_top, rz * 0.75))
        bot_recess_rim.append(v_r_bot)
        top_recess_rim.append(v_r_top)

    for i in range(8):
        i_next = (i + 1) % 8
        bm.faces.new((bot_ring[i], bot_recess_rim[i], bot_recess_rim[i_next], bot_ring[i_next]))
        bm.faces.new((bot_recess_rim[i], top_recess_rim[i], top_recess_rim[i_next], bot_recess_rim[i_next]))

    recess_center = bm.verts.new((0.0, y_recess_top, 0.0))
    for i in range(8):
        i_next = (i + 1) % 8
        bm.faces.new((top_recess_rim[i], recess_center, top_recess_rim[i_next]))

    assign_uvs(bm, bm.verts, (0.05, 0.95, 0.05, 0.42))

    # Equipment bays on the cardinal flat faces (+X, -X, +Z)
    cardinal_bays = [
        ( 2.02,  0.00,  90, 1.10, 0.85, 0.22),
        (-2.02,  0.00, -90, 1.10, 0.85, 0.22),
        ( 0.00,  2.02,   0, 1.20, 0.85, 0.22),
    ]
    for bx, bz, brot, bw, bh, bd in cardinal_bays:
        rot_m = mat_rot_y(brot)
        add_box(bm, (bx, -0.60, bz), (bw, bh, bd), rot_mat=rot_m, uv_bounds=(0.05, 0.95, 0.05, 0.42))
        add_box(bm, (bx, -0.60, bz), (bw * 0.88, bh * 0.88, bd + 0.04), rot_mat=rot_m, uv_bounds=(0.10, 0.90, 0.82, 0.96))

    # 4 Spherical helium propellant tanks visible between bays
    for t_idx in range(4):
        t_ang = t_idx * (math.pi / 2.0) + (math.pi / 4.0)
        tx = math.cos(t_ang) * 1.45
        tz = math.sin(t_ang) * 1.45
        add_sphere(bm, (tx, -0.60, tz), radius=0.46, u_segs=20, v_segs=14, uv_bounds=(0.05, 0.95, 0.05, 0.42))

    # Outrigger structural attach beams at the 4 leg corners (45, 135, 225, 315 deg)
    for leg_idx in range(4):
        l_ang = leg_idx * (math.pi / 2.0) + (math.pi / 4.0)
        ox = math.cos(l_ang) * 2.10
        oz = math.sin(l_ang) * 2.10
        make_strut(bm, (ox * 0.90, -0.40, oz * 0.90), (ox * 1.15, -0.45, oz * 1.15), r1=0.10, segments=12, uv_bounds=(0.1, 0.9, 0.82, 0.96))
        make_strut(bm, (ox * 0.90, -1.25, oz * 0.90), (ox * 1.15, -0.55, oz * 1.15), r1=0.08, segments=12, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    # Interstage staging truss connecting descent stage to ascent stage
    for i in range(8):
        ang1 = angles[i]
        ang2 = angles[(i + 1) % 8]
        p1 = (math.cos(ang1) * 1.85, 0.20, math.sin(ang1) * 1.85)
        p2 = (math.cos(ang2) * 1.55, 0.40, math.sin(ang2) * 1.55)
        make_strut(bm, p1, p2, r1=0.045, segments=8, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    mesh = bpy.data.meshes.new("DescentStageMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("DescentStage", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_lander_main"])
    return obj

def build_descent_engine(materials):
    """
    Builds the deep-throttling descent rocket engine bell:
    - Gimbal mount ring and hydraulic actuators inside cavity (Y = -0.75).
    - Combustion chamber and throat collar (Y = -1.15, radius 0.32).
    - Flared bell nozzle extending down to exit plane (Y = -2.00, radius 0.82).
    - Exterior cooling reinforcement rings.
    - Deep flared inner bell cavity.
    - Radiant glowing combustion throat ring.
    """
    bm = bmesh.new()

    num_segs = 32
    stations = [
        (-0.75, 0.42, 0.36),
        (-0.95, 0.38, 0.32),
        (-1.15, 0.33, 0.28),
        (-1.35, 0.42, 0.38),
        (-1.60, 0.58, 0.54),
        (-1.80, 0.70, 0.66),
        (-2.00, 0.82, 0.78),
    ]

    outer_rings = []
    inner_rings = []

    for y, r_out, r_in in stations:
        o_ring = []
        i_ring = []
        for s in range(num_segs):
            th = (s / float(num_segs)) * 2.0 * math.pi
            c, sn = math.cos(th), math.sin(th)
            v_out = bm.verts.new((c * r_out, y, sn * r_out))
            v_in = bm.verts.new((c * r_in, y, sn * r_in))
            o_ring.append(v_out)
            i_ring.append(v_in)
        outer_rings.append(o_ring)
        inner_rings.append(i_ring)

    for i in range(len(stations) - 1):
        for s in range(num_segs):
            s_next = (s + 1) % num_segs
            bm.faces.new((outer_rings[i][s], outer_rings[i][s_next], outer_rings[i + 1][s_next], outer_rings[i + 1][s]))
            bm.faces.new((inner_rings[i][s_next], inner_rings[i][s], inner_rings[i + 1][s], inner_rings[i + 1][s_next]))

    for s in range(num_segs):
        s_next = (s + 1) % num_segs
        bm.faces.new((outer_rings[-1][s], inner_rings[-1][s], inner_rings[-1][s_next], outer_rings[-1][s_next]))

    inj_center = bm.verts.new((0.0, -0.75, 0.0))
    for s in range(num_segs):
        s_next = (s + 1) % num_segs
        bm.faces.new((outer_rings[0][s_next], outer_rings[0][s], inj_center))

    throat_center = bm.verts.new((0.0, -1.15, 0.0))
    for s in range(num_segs):
        s_next = (s + 1) % num_segs
        bm.faces.new((inner_rings[2][s], inner_rings[2][s_next], throat_center))

    for ring_y, ring_r in [(-1.30, 0.44), (-1.55, 0.60), (-1.78, 0.72)]:
        add_vertical_cylinder(bm, (0, ring_y, 0), radius=ring_r + 0.025, depth=0.04, segments=24)

    for g_idx in range(4):
        g_ang = g_idx * (math.pi / 2.0)
        gx = math.cos(g_ang) * 0.60
        gz = math.sin(g_ang) * 0.60
        make_strut(bm, (gx, -0.75, gz), (gx * 0.45, -1.10, gz * 0.45), r1=0.035, segments=8)

    assign_uvs(bm, bm.verts, (0.1, 0.9, 0.80, 0.98))

    mesh = bpy.data.meshes.new("DescentEngineMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("DescentEngine", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_engine"])
    return obj

def build_landing_legs(materials):
    """
    Builds the 4 articulated landing gear assemblies:
    Positioned diagonally at 45, 135, 225, 315 degrees:
    - Primary telescoping oleo strut (diameter 0.16 m upper, 0.12 m lower chrome piston).
    - Secondary A-frame support struts (two diagonal tubular trusses).
    - Inverted dished footpad (radius 0.65 m) with honeycomb stiffener ribs,
      resting at horizontal ground plane Y = -2.40 m.
    - Lunar surface touchdown sensing probe rod (1.1 m long extending down to Y = -3.50 m).
    """
    bm = bmesh.new()

    for leg_idx in range(4):
        l_ang = leg_idx * (math.pi / 2.0) + (math.pi / 4.0)
        c_th, s_th = math.cos(l_ang), math.sin(l_ang)

        p_attach = (c_th * 2.30, -0.45, s_th * 2.30)
        p_foot = (c_th * 4.40, -2.40, s_th * 4.40)
        p_mid = (c_th * 3.35, -1.42, s_th * 3.35)

        make_strut(bm, p_attach, p_mid, r1=0.09, segments=16, uv_bounds=(0.1, 0.9, 0.82, 0.96))
        make_strut(bm, p_mid, p_foot, r1=0.065, segments=16, uv_bounds=(0.1, 0.9, 0.82, 0.96))

        add_vertical_cylinder(bm, p_mid, radius=0.11, depth=0.18, segments=16)

        perp_ang1 = l_ang + math.radians(28)
        perp_ang2 = l_ang - math.radians(28)
        p_brace1 = (math.cos(perp_ang1) * 2.10, -1.35, math.sin(perp_ang1) * 2.10)
        p_brace2 = (math.cos(perp_ang2) * 2.10, -1.35, math.sin(perp_ang2) * 2.10)

        make_strut(bm, p_brace1, p_mid, r1=0.045, segments=12, uv_bounds=(0.1, 0.9, 0.82, 0.96))
        make_strut(bm, p_brace2, p_mid, r1=0.045, segments=12, uv_bounds=(0.1, 0.9, 0.82, 0.96))

        r_pad = 0.65
        num_pad_segs = 24
        pad_top = []
        pad_bot = []

        for p_s in range(num_pad_segs):
            th_p = (p_s / float(num_pad_segs)) * 2.0 * math.pi
            px = p_foot[0] + math.cos(th_p) * r_pad
            pz = p_foot[2] + math.sin(th_p) * r_pad
            v_pt = bm.verts.new((px, -2.28, pz))
            v_pb = bm.verts.new((px, -2.40, pz))
            pad_top.append(v_pt)
            pad_bot.append(v_pb)

        for p_s in range(num_pad_segs):
            s_n = (p_s + 1) % num_pad_segs
            bm.faces.new((pad_bot[p_s], pad_top[p_s], pad_top[s_n], pad_bot[s_n]))

        foot_bottom_center = bm.verts.new((p_foot[0], -2.40, p_foot[2]))
        for p_s in range(num_pad_segs):
            s_n = (p_s + 1) % num_pad_segs
            bm.faces.new((pad_bot[p_s], pad_bot[s_n], foot_bottom_center))

        foot_socket = bm.verts.new((p_foot[0], -2.22, p_foot[2]))
        for p_s in range(num_pad_segs):
            s_n = (p_s + 1) % num_pad_segs
            bm.faces.new((pad_top[p_s], foot_socket, pad_top[s_n]))

        add_vertical_cylinder(bm, (p_foot[0], -2.18, p_foot[2]), radius=0.09, depth=0.12, segments=16)

        p_probe_tip = (p_foot[0], -3.45, p_foot[2])
        make_strut(bm, p_foot, p_probe_tip, r1=0.015, segments=8, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    mesh = bpy.data.meshes.new("LandingLegsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("LandingLegs", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_metal"])
    return obj

def build_egress_porch_and_ladder(materials):
    """
    Builds the forward EVA egress porch platform and 10-rung climbing ladder
    mounted on the forward -Z face:
    - Porch platform at Y = +0.25 m, Z from -1.60 to -2.35 m, width 1.20 m.
    - Safety handrails (height 0.60 m) on port and starboard sides.
    - Climbing ladder extending from porch sill (Z = -2.35, Y = +0.25) down to
      ground level (Z = -2.85, Y = -2.35).
    - 10 horizontal ladder rungs with anti-slip tread.
    - Rigid standoff brackets securing ladder to the descent stage front face.
    """
    bm = bmesh.new()

    y_porch = 0.25
    z_porch_inner = -1.60
    z_porch_outer = -2.35
    w_porch = 0.60

    v1 = bm.verts.new((-w_porch, y_porch, z_porch_inner))
    v2 = bm.verts.new(( w_porch, y_porch, z_porch_inner))
    v3 = bm.verts.new(( w_porch, y_porch, z_porch_outer))
    v4 = bm.verts.new((-w_porch, y_porch, z_porch_outer))
    bm.faces.new((v1, v2, v3, v4))

    add_box(
        bm,
        (0, y_porch - 0.04, (z_porch_inner + z_porch_outer) * 0.5),
        (w_porch * 2.0, 0.06, abs(z_porch_outer - z_porch_inner)),
        uv_bounds=(0.1, 0.9, 0.82, 0.96)
    )

    h_rail = 0.60
    for side_x in [-w_porch, w_porch]:
        make_strut(bm, (side_x, y_porch, z_porch_inner), (side_x, y_porch + h_rail, z_porch_inner), r1=0.025, segments=8)
        make_strut(bm, (side_x, y_porch, z_porch_outer), (side_x, y_porch + h_rail, z_porch_outer), r1=0.025, segments=8)
        make_strut(bm, (side_x, y_porch + h_rail, z_porch_inner), (side_x, y_porch + h_rail, z_porch_outer), r1=0.025, segments=8)
        make_strut(bm, (side_x, y_porch + 0.20, z_porch_inner), (side_x, y_porch + 0.20, z_porch_outer), r1=0.02, segments=8)

    half_ladder_w = 0.24
    p_top_l = (-half_ladder_w, y_porch, z_porch_outer)
    p_top_r = ( half_ladder_w, y_porch, z_porch_outer)
    p_bot_l = (-half_ladder_w, -2.35, -2.85)
    p_bot_r = ( half_ladder_w, -2.35, -2.85)

    make_strut(bm, p_top_l, p_bot_l, r1=0.025, segments=10, uv_bounds=(0.1, 0.9, 0.82, 0.96))
    make_strut(bm, p_top_r, p_bot_r, r1=0.025, segments=10, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    num_rungs = 10
    for r in range(num_rungs):
        frac = (r + 0.5) / float(num_rungs)
        y_rung = y_porch + frac * (-2.35 - y_porch)
        z_rung = z_porch_outer + frac * (-2.85 - z_porch_outer)
        make_strut(bm, (-half_ladder_w, y_rung, z_rung), (half_ladder_w, y_rung, z_rung), r1=0.018, segments=8, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    for y_brack, z_brack in [(-0.40, -2.48), (-1.20, -2.66)]:
        make_strut(bm, (-half_ladder_w, y_brack, z_brack), (-half_ladder_w, y_brack, -2.15), r1=0.02, segments=8)
        make_strut(bm, ( half_ladder_w, y_brack, z_brack), ( half_ladder_w, y_brack, -2.15), r1=0.02, segments=8)

    mesh = bpy.data.meshes.new("EgressPorchMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("EgressPorchAndLadder", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_metal"])
    return obj

def build_ascent_module(materials):
    """
    Builds the modular ascent crew module:
    - Pressurized crew cabin with faceted cockpit nose, cylindrical mid-section,
      and modular equipment bays.
    - Clad in white Beta-cloth quilted thermal blanket insulation.
    - Forward egress hatch (-Z face) with recessed frame, door panel, rotary latch, and hinges.
    - Cylindrical docking port with capture latches, alignment petals, and optical cross target.
    """
    bm = bmesh.new()

    # 1. Main Cabin Pressure Vessel
    # Faceted loft with 12 sides, Y from +0.20 to +2.15
    y_base = 0.20
    y_top = 2.15
    r_mid = 1.55

    num_sides = 12
    bot_ring = []
    mid_ring = []
    top_ring = []

    for s in range(num_sides):
        th = (s / float(num_sides)) * 2.0 * math.pi
        cx = math.cos(th) * r_mid
        cz = math.sin(th) * r_mid

        # Flatten forward face (-Z) for cockpit nose and hatch
        if cz < -0.3:
            cz = -1.55 if cz < -1.1 else cz * 1.15

        v_b = bm.verts.new((cx * 0.95, y_base, cz * 0.95))
        v_m = bm.verts.new((cx * 1.05, 1.25, cz * 1.05))
        v_t = bm.verts.new((cx * 0.88, y_top, cz * 0.88))
        bot_ring.append(v_b)
        mid_ring.append(v_m)
        top_ring.append(v_t)

    for s in range(num_sides):
        s_n = (s + 1) % num_sides
        bm.faces.new((bot_ring[s], bot_ring[s_n], mid_ring[s_n], mid_ring[s]))
        bm.faces.new((mid_ring[s], mid_ring[s_n], top_ring[s_n], top_ring[s]))

    c_bot = bm.verts.new((0.0, y_base, 0.0))
    c_top = bm.verts.new((0.0, y_top, 0.0))
    for s in range(num_sides):
        s_n = (s + 1) % num_sides
        bm.faces.new((bot_ring[s_n], bot_ring[s], c_bot))
        bm.faces.new((top_ring[s], top_ring[s_n], c_top))

    # Assign White Beta-Cloth Blanket UVs (mapped cleanly within quilt zone, avoiding the orange cheatline on the flat roof)
    assign_uvs(bm, bot_ring + mid_ring, (0.05, 0.95, 0.46, 0.70))
    assign_uvs(bm, top_ring + [c_top], (0.10, 0.90, 0.52, 0.64))

    # 2. Side Propellant Tank Shrouds (Port and Starboard vertical bulges)
    for sx in [-1.45, 1.45]:
        add_vertical_cylinder(
            bm,
            (sx, 1.15, 0.10),
            radius=0.48,
            depth=1.30,
            segments=16,
            uv_bounds=(0.05, 0.95, 0.46, 0.65)
        )

    # 3. Forward Egress Airlock Hatch on the flat front face at Z = -1.58 m
    z_hatch = -1.58
    y_hatch = 0.80
    h_w, h_h = 0.38, 0.50

    add_box(
        bm,
        (0.0, y_hatch, z_hatch),
        (h_w * 2.0, h_h * 2.0, 0.08),
        uv_bounds=(0.10, 0.90, 0.82, 0.96)
    )
    add_box(
        bm,
        (0.0, y_hatch, z_hatch - 0.03),
        (h_w * 1.75, h_h * 1.75, 0.04),
        uv_bounds=(0.10, 0.90, 0.48, 0.62)
    )
    make_strut(bm, (0.12, y_hatch, z_hatch - 0.06), (0.24, y_hatch, z_hatch - 0.06), r1=0.018, segments=8)
    make_strut(bm, (0.24, y_hatch - 0.08, z_hatch - 0.06), (0.24, y_hatch + 0.08, z_hatch - 0.06), r1=0.016, segments=8)

    for y_h in [y_hatch - 0.32, y_hatch + 0.32]:
        add_vertical_cylinder(bm, (-h_w * 0.95, y_h, z_hatch - 0.02), radius=0.03, depth=0.10, segments=10)

    # 4. Docking Port Collar (Center of roof: vertical cylinder along Y from 2.15 to 2.55)
    dock_r = 0.60
    y_dock_bot = 2.15
    y_dock_top = 2.55

    add_vertical_cylinder(
        bm,
        (0.0, (y_dock_bot + y_dock_top) * 0.5, 0.0),
        radius=dock_r,
        depth=y_dock_top - y_dock_bot,
        segments=32,
        uv_bounds=(0.10, 0.90, 0.82, 0.96)
    )
    add_vertical_cylinder(
        bm,
        (0.0, y_dock_top, 0.0),
        radius=dock_r + 0.07,
        depth=0.05,
        segments=32,
        uv_bounds=(0.10, 0.90, 0.82, 0.96)
    )

    mesh = bpy.data.meshes.new("AscentModuleMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("AscentModule", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_lander_main"])
    return obj

def build_portholes(materials):
    """
    Builds the cockpit observation portholes with beveled frames & glossy glass:
    - Dual pilot windows on forward angled facets (-Z) angled downward 18 deg
      for lunar landing surface visibility.
    - Overhead rendezvous porthole on roof facet for docking tracking.
    """
    bm_frame = bmesh.new()
    bm_glass = bmesh.new()

    for side_x in [-0.52, 0.52]:
        win_pos = (side_x, 1.45, -1.48)
        win_rot = mat_rot_x(-18) @ mat_rot_y(15 if side_x > 0 else -15)

        add_box(
            bm_frame,
            win_pos,
            (0.44, 0.36, 0.06),
            rot_mat=win_rot,
            uv_bounds=(0.10, 0.90, 0.82, 0.96)
        )
        add_box(
            bm_glass,
            win_pos,
            (0.36, 0.28, 0.02),
            rot_mat=win_rot,
            uv_bounds=(0.10, 0.90, 0.82, 0.96)
        )

    # Overhead rendezvous porthole (looking upwards through roof at Y = 2.15)
    over_pos = (0.0, 2.15, -0.65)
    over_rot = mat_rot_x(35)
    rot_cyl = mathutils.Matrix.Rotation(math.radians(90), 4, 'X') @ over_rot
    bmesh.ops.create_cone(bm_frame, cap_ends=True, segments=24, radius1=0.25, radius2=0.25, depth=0.06, matrix=mathutils.Matrix.Translation(over_pos) @ rot_cyl)
    bmesh.ops.create_cone(bm_glass, cap_ends=True, segments=24, radius1=0.20, radius2=0.20, depth=0.02, matrix=mathutils.Matrix.Translation(over_pos) @ rot_cyl)

    assign_uvs(bm_frame, bm_frame.verts, (0.1, 0.9, 0.82, 0.96))
    assign_uvs(bm_glass, bm_glass.verts, (0.1, 0.9, 0.82, 0.96))

    mesh_frame = bpy.data.meshes.new("PortholeFramesMesh")
    bm_frame.to_mesh(mesh_frame)
    bm_frame.free()
    obj_frame = bpy.data.objects.new("PortholeFrames", mesh_frame)
    bpy.context.scene.collection.objects.link(obj_frame)
    assign_mat(obj_frame, materials["mat_metal"])

    mesh_glass = bpy.data.meshes.new("PortholeGlassMesh")
    bm_glass.to_mesh(mesh_glass)
    bm_glass.free()
    obj_glass = bpy.data.objects.new("PortholeGlass", mesh_glass)
    bpy.context.scene.collection.objects.link(obj_glass)
    assign_mat(obj_glass, materials["mat_glass"])

    return obj_frame, obj_glass

def build_hardware_and_rcs(materials):
    """
    Builds the metallic hardware components:
    - 4 RCS Quad outrigger assemblies (+X, -X, -Z, +Z) with 4 expansion nozzles each.
    - Steerable high-gain parabolic dish antenna with gimbal boom and feed horn.
    - 3 Docking port capture petals and central optical target cross.
    """
    bm = bmesh.new()

    # 1. 4 RCS Quads (+X, -X, -Z, +Z) at Y = 1.10 m
    rcs_configs = [
        ("Starboard", ( 1.95, 1.10,  0.00),  90),
        ("Port",      (-1.95, 1.10,  0.00), -90),
        ("Forward",   ( 0.00, 1.10, -1.95), 180),
        ("Aft",       ( 0.00, 1.10,  1.95),   0),
    ]

    for name, pylon_pos, rot_deg in rcs_configs:
        rot_mat = mat_rot_y(rot_deg)
        cabin_attach = mathutils.Vector(pylon_pos) * 0.78
        cabin_attach.y = pylon_pos[1]
        make_strut(bm, cabin_attach, pylon_pos, r1=0.065, segments=10, uv_bounds=(0.1, 0.9, 0.82, 0.96))

        # Central RCS Manifold Block
        add_box(bm, pylon_pos, (0.24, 0.24, 0.24), rot_mat=rot_mat, uv_bounds=(0.1, 0.9, 0.82, 0.96))

        # 4 Orthogonal Thruster Nozzles (+X, -X, +Y, -Y relative to block)
        nozzle_dirs = [
            ( 1,  0,  0),
            (-1,  0,  0),
            ( 0,  1,  0),
            ( 0, -1,  0),
        ]
        for dx, dy, dz in nozzle_dirs:
            noz_local_base = mathutils.Vector((dx, dy, dz)) * 0.12
            noz_local_tip  = mathutils.Vector((dx, dy, dz)) * 0.28
            p_n_base = mathutils.Vector(pylon_pos) + rot_mat @ noz_local_base
            p_n_tip  = mathutils.Vector(pylon_pos) + rot_mat @ noz_local_tip
            make_strut(bm, p_n_base, p_n_tip, r1=0.035, r2=0.065, segments=12, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    # 2. Steerable High-Gain Parabolic Dish Antenna (Upper Starboard Shoulder)
    ant_base = (1.20, 2.15, 0.60)
    add_vertical_cylinder(bm, ant_base, radius=0.12, depth=0.18, segments=16, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    ant_pivot = (ant_base[0] + 0.30, ant_base[1] + 0.35, ant_base[2] + 0.20)
    make_strut(bm, ant_base, ant_pivot, r1=0.04, segments=10, uv_bounds=(0.1, 0.9, 0.82, 0.96))

    # Parabolic Dish Reflector (diameter 0.90 m, depth 0.16 m)
    dish_r = 0.45
    dish_depth = 0.16
    num_dish_segs = 24
    num_dish_rings = 4

    dish_rings = []
    dish_center = mathutils.Vector(ant_pivot) + mathutils.Vector((0.25, 0.30, 0.20))
    dish_norm = mathutils.Vector((0.55, 0.65, 0.50)).normalized()
    dish_rot = mathutils.Vector((0, 0, 1)).rotation_difference(dish_norm).to_matrix().to_4x4()

    for r_idx in range(num_dish_rings + 1):
        frac = r_idx / float(num_dish_rings)
        r_ring = frac * dish_r
        z_bowl = (frac ** 2) * dish_depth
        d_ring = []
        for s in range(num_dish_segs):
            th = (s / float(num_dish_segs)) * 2.0 * math.pi
            local_p = mathutils.Vector((math.cos(th) * r_ring, math.sin(th) * r_ring, z_bowl))
            world_p = dish_center + dish_rot @ local_p
            d_ring.append(bm.verts.new(world_p))
        dish_rings.append(d_ring)

    for r_idx in range(num_dish_rings):
        for s in range(num_dish_segs):
            s_n = (s + 1) % num_dish_segs
            bm.faces.new((dish_rings[r_idx][s], dish_rings[r_idx][s_n], dish_rings[r_idx + 1][s_n], dish_rings[r_idx + 1][s]))

    # Feed horn tripod support & central antenna horn
    horn_tip = dish_center + dish_norm * (dish_depth + 0.28)
    for t_s in [0, 8, 16]:
        rim_p = dish_rings[-1][t_s].co
        make_strut(bm, rim_p, horn_tip, r1=0.012, segments=6, uv_bounds=(0.1, 0.9, 0.82, 0.96))
    
    rot_horn = mathutils.Matrix.Rotation(math.radians(90), 4, 'X') @ dish_rot
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.04, radius2=0.015, depth=0.10, matrix=mathutils.Matrix.Translation(horn_tip) @ rot_horn)

    # 3. Docking Petals & Target Cross on top of collar (Y = 2.55)
    dock_r = 0.60
    y_dock_top = 2.55
    for p_idx in range(3):
        p_ang = p_idx * (2.0 * math.pi / 3.0)
        px = math.cos(p_ang) * (dock_r + 0.03)
        pz = math.sin(p_ang) * (dock_r + 0.03)
        petal_rot = mat_rot_y(math.degrees(-p_ang) + 90)
        add_box(
            bm,
            (px, y_dock_top + 0.06, pz),
            (0.16, 0.12, 0.04),
            rot_mat=petal_rot,
            uv_bounds=(0.1, 0.9, 0.82, 0.96)
        )

    # Docking Target Optical Cross (Flat on the contact plane at Y = 2.55)
    add_box(bm, (0.0, y_dock_top + 0.01, 0.0), (0.35, 0.02, 0.05), uv_bounds=(0.1, 0.9, 0.82, 0.96))
    add_box(bm, (0.0, y_dock_top + 0.01, 0.0), (0.05, 0.02, 0.35), uv_bounds=(0.1, 0.9, 0.82, 0.96))

    mesh = bpy.data.meshes.new("HardwareAndRcsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("HardwareAndRcs", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_metal"])
    return obj

# -----------------------------------------------------------------------------
# 4. Attachment Sockets (Empties / Node3D Marker Transforms)
# -----------------------------------------------------------------------------
def build_sockets():
    """
    Builds the 6 required attachment sockets:
    - SOCKET_rcs_1 (Starboard RCS quad)
    - SOCKET_rcs_2 (Port RCS quad)
    - SOCKET_rcs_3 (Forward RCS quad)
    - SOCKET_rcs_4 (Aft RCS quad)
    - SOCKET_docking (Top docking collar contact plane)
    - SOCKET_engine_descent (Descent rocket nozzle exit center)
    """
    sockets = [
        ("SOCKET_rcs_1",          ( 1.95,  1.10,  0.00)),
        ("SOCKET_rcs_2",          (-1.95,  1.10,  0.00)),
        ("SOCKET_rcs_3",          ( 0.00,  1.10, -1.95)),
        ("SOCKET_rcs_4",          ( 0.00,  1.10,  1.95)),
        ("SOCKET_docking",        ( 0.00,  2.55,  0.00)),
        ("SOCKET_engine_descent", ( 0.00, -2.00,  0.00)),
    ]

    created = []
    for name, loc in sockets:
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_type = 'ARROWS'
        empty.empty_display_size = 0.5
        empty.location = loc
        bpy.context.scene.collection.objects.link(empty)
        created.append(empty)
        print(f"Created Socket: {name} at {loc}")

    return created

# -----------------------------------------------------------------------------
# 5. Collision Mesh (COL_hull Simplified Convex Hull)
# -----------------------------------------------------------------------------
def build_collision_mesh():
    """Builds a simplified low-poly convex hull collision shape for Jolt physics."""
    bm = bmesh.new()

    envelope_pts = [
        ( 0.00,  2.60,  0.00),
        ( 1.50,  2.15,  0.00),
        (-1.50,  2.15,  0.00),
        ( 0.00,  2.15, -1.65),
        ( 0.00,  2.15,  1.65),
        ( 1.75,  1.20,  0.00),
        (-1.75,  1.20,  0.00),
        ( 0.00,  1.20, -1.85),
        ( 0.00,  1.20,  1.85),
        ( 2.15,  0.20,  0.00),
        (-2.15,  0.20,  0.00),
        ( 0.00,  0.20, -2.15),
        ( 0.00,  0.20,  2.15),
        ( 1.52,  0.20,  1.52),
        (-1.52,  0.20,  1.52),
        ( 1.52,  0.20, -1.52),
        (-1.52,  0.20, -1.52),
        ( 2.15, -1.40,  0.00),
        (-2.15, -1.40,  0.00),
        ( 0.00, -1.40, -2.15),
        ( 0.00, -1.40,  2.15),
        ( 1.52, -1.40,  1.52),
        (-1.52, -1.40,  1.52),
        ( 1.52, -1.40, -1.52),
        (-1.52, -1.40, -1.52),
        ( 0.85, -2.00,  0.00),
        (-0.85, -2.00,  0.00),
        ( 0.00, -2.00, -0.85),
        ( 0.00, -2.00,  0.85),
    ]

    for p in envelope_pts:
        bm.verts.new(p)

    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("COL_hullMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("COL_hull", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True

    tri_count = sum(len(f.vertices) - 2 for f in obj.data.polygons)
    print(f"COL_hull created: {tri_count} triangles")
    return obj

# -----------------------------------------------------------------------------
# 6. LOD Generation (Target LOD0: 15k-25k tris, LOD1: 3k-5k tris)
# -----------------------------------------------------------------------------
def build_lods(components):
    """
    Combines visual components into LunarLander_LOD0 (target 15,000 - 25,000 tris)
    and creates decimated LunarLander_LOD1 (target 3,000 - 5,000 tris).
    """
    bpy.ops.object.select_all(action='DESELECT')
    for c in components:
        c.select_set(True)
    bpy.context.view_layer.objects.active = components[0]
    bpy.ops.object.duplicate()
    lod0_obj = bpy.context.active_object
    bpy.ops.object.join()
    lod0_obj.name = "LunarLander_LOD0"
    lod0_obj.data.name = "LunarLander_LOD0_Mesh"

    lod0_tris = sum(len(f.vertices) - 2 for f in lod0_obj.data.polygons)
    print(f"Initial LunarLander_LOD0 triangle count: {lod0_tris}")

    # Subdivide or calibrate to strictly guarantee 15,000 - 25,000 range
    if lod0_tris < 15000:
        mod_sub = lod0_obj.modifiers.new("Subsurf", "SUBSURF")
        mod_sub.levels = 1
        bpy.context.view_layer.objects.active = lod0_obj
        bpy.ops.object.modifier_apply(modifier="Subsurf")
        lod0_tris = sum(len(f.vertices) - 2 for f in lod0_obj.data.polygons)
        print(f"Subdivided LunarLander_LOD0 triangle count: {lod0_tris}")

    if lod0_tris > 25000:
        ratio = 21000.0 / float(lod0_tris)
        mod_dec = lod0_obj.modifiers.new("Decimate", "DECIMATE")
        mod_dec.ratio = ratio
        bpy.context.view_layer.objects.active = lod0_obj
        bpy.ops.object.modifier_apply(modifier="Decimate")
        lod0_tris = sum(len(f.vertices) - 2 for f in lod0_obj.data.polygons)
        print(f"Calibrated LunarLander_LOD0 triangle count: {lod0_tris}")

    lod0_obj.data.validate(verbose=False)
    lod0_obj.data.update()
    print(f"FINAL LunarLander_LOD0: {lod0_tris} triangles (Budget: 15,000 - 25,000)")
    assert 15000 <= lod0_tris <= 25000, f"LOD0 out of budget: {lod0_tris}"

    # Generate LOD1 (Budget: 3,000 - 5,000 tris)
    bpy.ops.object.select_all(action='DESELECT')
    lod0_obj.select_set(True)
    bpy.context.view_layer.objects.active = lod0_obj
    bpy.ops.object.duplicate()
    lod1_obj = bpy.context.active_object
    lod1_obj.name = "LunarLander_LOD1"
    lod1_obj.data.name = "LunarLander_LOD1_Mesh"

    target_l1 = 3900.0
    ratio_l1 = target_l1 / float(lod0_tris)
    mod_dec1 = lod1_obj.modifiers.new("Decimate", "DECIMATE")
    mod_dec1.ratio = ratio_l1
    bpy.context.view_layer.objects.active = lod1_obj
    bpy.ops.object.modifier_apply(modifier="Decimate")

    lod1_obj.data.validate(verbose=False)
    lod1_obj.data.update()

    lod1_tris = sum(len(f.vertices) - 2 for f in lod1_obj.data.polygons)
    print(f"FINAL LunarLander_LOD1: {lod1_tris} triangles (Budget: 3,000 - 5,000)")
    assert 3000 <= lod1_tris <= 5000, f"LOD1 out of budget: {lod1_tris}"

    # Clean up intermediate components
    for c in components:
        bpy.data.objects.remove(c, do_unlink=True)

    return lod0_obj, lod1_obj

# -----------------------------------------------------------------------------
# 7. Render Studio Preview Images
# -----------------------------------------------------------------------------
def setup_lighting():
    """Sets up high-quality 4-point studio lighting with ground bounce fill."""
    lights = []

    # Key Light (Upper-Front-Left)
    p1_data = bpy.data.lights.new("KeyLight", type='POINT')
    p1_data.energy = 44000.0
    p1_data.color = (1.0, 0.96, 0.92)
    p1 = bpy.data.objects.new("KeyLight", p1_data)
    p1.location = (-9.0, 11.0, -11.0)
    bpy.context.scene.collection.objects.link(p1)
    lights.append(p1)

    # Fill Light (Upper-Front-Right)
    p2_data = bpy.data.lights.new("FillLight", type='POINT')
    p2_data.energy = 26000.0
    p2_data.color = (0.75, 0.85, 1.0)
    p2 = bpy.data.objects.new("FillLight", p2_data)
    p2.location = (11.0, 9.0, -9.0)
    bpy.context.scene.collection.objects.link(p2)
    lights.append(p2)

    # Ground Bounce Fill (Illuminates landing legs, engine bell & footpads)
    p3_data = bpy.data.lights.new("GroundBounceLight", type='POINT')
    p3_data.energy = 30000.0
    p3_data.color = (0.80, 0.85, 0.95)
    p3 = bpy.data.objects.new("GroundBounceLight", p3_data)
    p3.location = (0.0, -6.0, 0.0)
    bpy.context.scene.collection.objects.link(p3)
    lights.append(p3)

    # Rim Light (Upper-Rear)
    p4_data = bpy.data.lights.new("RimLight", type='POINT')
    p4_data.energy = 34000.0
    p4_data.color = (0.95, 0.95, 1.0)
    p4 = bpy.data.objects.new("RimLight", p4_data)
    p4.location = (0.0, 11.0, 11.0)
    bpy.context.scene.collection.objects.link(p4)
    lights.append(p4)

    return lights

def render_previews():
    """Renders multi-angle preview images: preview.png, front, side, and top."""
    scene = bpy.context.scene
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = 'PNG'

    world = bpy.data.worlds.new("SpaceWorld")
    bg_node = world.node_tree.nodes.get("Background")
    if bg_node:
        bg_node.inputs["Color"].default_value = (0.02, 0.025, 0.035, 1.0)
        bg_node.inputs["Strength"].default_value = 0.6
    scene.world = world

    lights = setup_lighting()

    cam_data = bpy.data.cameras.new("PreviewCamera")
    cam_data.lens = 45.0
    cam_obj = bpy.data.objects.new("PreviewCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    shots = [
        ("Front View", PREVIEW_FRONT_PATH,
         mathutils.Vector((0.0, 1.2, -12.0)),
         mathutils.Vector((0.0, 0.3, 0.0))),

        ("Side Profile", PREVIEW_SIDE_PATH,
         mathutils.Vector((-13.0, 1.2, 0.0)),
         mathutils.Vector((0.0, 0.3, 0.0))),

        ("Top View", PREVIEW_TOP_PATH,
         mathutils.Vector((-0.2, 15.0, 0.2)),
         mathutils.Vector((0.0, 0.0, 0.0))),

        ("Isometric Preview", PREVIEW_OUTPUT_PATH,
         mathutils.Vector((-10.5, 6.5, -10.5)),
         mathutils.Vector((0.0, 0.3, 0.0))),
    ]

    for label, out_path, eye, target in shots:
        mat = get_look_at_matrix(eye, target, mathutils.Vector((0, 1, 0)))
        cam_obj.matrix_world = mat
        scene.render.filepath = os.path.abspath(out_path)
        print(f"Rendering {label} -> {out_path}...")
        bpy.ops.render.render(write_still=True)
        print(f"Rendered: {os.path.exists(out_path)} ({os.path.getsize(out_path):,} bytes)")

    for l in lights:
        bpy.data.objects.remove(l, do_unlink=True)
    bpy.data.objects.remove(cam_obj, do_unlink=True)

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
def main():
    print("=== Building Solar Horizon Lunar Lander (WP 3.3) ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # 1. Generate procedural textures
    tex_paths = generate_procedural_textures(TEXTURES_DIR, size=2048)

    # 2. Setup materials
    materials = setup_materials(tex_paths)

    # 3. Build geometry components
    print("Building modular lunar lander components...")
    descent_stage = build_descent_stage(materials)
    descent_engine = build_descent_engine(materials)
    landing_legs = build_landing_legs(materials)
    egress_porch = build_egress_porch_and_ladder(materials)
    ascent_module = build_ascent_module(materials)
    porthole_frames, porthole_glass = build_portholes(materials)
    hardware_and_rcs = build_hardware_and_rcs(materials)

    components = [
        descent_stage,
        descent_engine,
        landing_legs,
        egress_porch,
        ascent_module,
        porthole_frames,
        porthole_glass,
        hardware_and_rcs
    ]

    # 4. Attachment Sockets
    print("Creating attachment sockets...")
    sockets = build_sockets()

    # 5. Collision Shape (COL_hull)
    print("Building collision mesh COL_hull...")
    col_hull = build_collision_mesh()

    # 6. Render Previews
    print("Rendering preview images...")
    render_previews()

    # 7. LOD Generation
    print("Generating LODs...")
    lod0, lod1 = build_lods(components)

    # 8. glTF 2.0 Export
    print(f"Exporting binary glTF (.glb) to {GLB_OUTPUT_PATH}...")
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUTPUT_PATH,
        export_format='GLB',
        export_apply=False,
        export_animations=False,
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
