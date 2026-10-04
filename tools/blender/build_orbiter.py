#!/usr/bin/env python3
"""
Solar Horizon — Hero Orbiter Model Generator
Builds a high-fidelity space-shuttle-like orbiter model in Blender and exports glTF 2.0 (.glb).

Specifications:
- Dimensions: ~14.2 m long, 13.8 m wingspan, forward = -Z in Godot, 1 unit = 1 m
- Fuselage with bevelled panels and thermal protection system (TPS) tiles
- Cockpit glazing with multi-pane windows and interior console
- Delta wings with aerofoil section, bevelled elevons, and wingtip fences
- Vertical tail fin with split rudder / speed brake
- Twin rear rocket engine bells with gimbal mounts and nozzle flare
- Sockets:
    SOCKET_engine_L, SOCKET_engine_R
    SOCKET_nav_port, SOCKET_nav_stbd
    SOCKET_rcs_nose_pitch_up, SOCKET_rcs_nose_pitch_down, SOCKET_rcs_nose_yaw_port, SOCKET_rcs_nose_yaw_stbd
    SOCKET_rcs_tail_port, SOCKET_rcs_tail_stbd, SOCKET_rcs_tail_up
    SOCKET_cockpit_cam, SOCKET_chase_cam
- Deployable landing gear (3 legs: 1 nose, 2 main) with 1s animation 'gear_deploy'
- Collision mesh named COL_hull
- PBR materials: mat_hull (with procedural textures), mat_glass, mat_engine, mat_emissive
- LOD0 (<= 50k tris) and LOD1 (<= 8k tris)
- Render preview PNG saved to assets/models/ships/orbiter/preview.png
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
    """Generates procedural PBR texture maps and saves them as PNG files."""
    print(f"Generating {size}x{size} procedural PBR textures...")
    
    y_coords, x_coords = np.mgrid[0:size, 0:size]
    u = x_coords / float(size)
    v = y_coords / float(size)

    # 1.1 ALBEDO MAP
    albedo = np.zeros((size, size, 4), dtype=np.float32)
    albedo[:, :, 0] = 0.88
    albedo[:, :, 1] = 0.89
    albedo[:, :, 2] = 0.90
    albedo[:, :, 3] = 1.0

    # Thermal blanket fine weave pattern
    weave = (np.sin(u * 512.0 * math.pi) * np.sin(v * 512.0 * math.pi)) * 0.02
    albedo[:, :, 0] += weave
    albedo[:, :, 1] += weave
    albedo[:, :, 2] += weave

    # Belly Thermal Protection System (TPS) Black Tiles (bottom 45% of UV map)
    tps_mask = (v < 0.45)
    albedo[tps_mask, 0] = 0.11
    albedo[tps_mask, 1] = 0.12
    albedo[tps_mask, 2] = 0.13

    # TPS Tile grout grid
    tile_grid_x = (x_coords % 32 == 0) | (x_coords % 32 == 31)
    tile_grid_y = (y_coords % 32 == 0) | (y_coords % 32 == 31)
    tile_grout = (tile_grid_x | tile_grid_y) & tps_mask
    albedo[tile_grout, 0] = 0.05
    albedo[tile_grout, 1] = 0.05
    albedo[tile_grout, 2] = 0.06

    # Reinforced Carbon-Carbon (RCC) leading edges / nose cap zone
    rcc_mask = (u > 0.42) & (u < 0.58) & (v > 0.45) & (v < 0.58)
    albedo[rcc_mask, 0] = 0.20
    albedo[rcc_mask, 1] = 0.21
    albedo[rcc_mask, 2] = 0.22

    # High-vis markings & Solar Horizon mission stripes
    stripe_mask_1 = (u > 0.15) & (u < 0.18) & (v > 0.55) & (v < 0.92)
    stripe_mask_2 = (u > 0.82) & (u < 0.85) & (v > 0.55) & (v < 0.92)
    stripe_mask = stripe_mask_1 | stripe_mask_2
    albedo[stripe_mask, 0] = 0.85
    albedo[stripe_mask, 1] = 0.45
    albedo[stripe_mask, 2] = 0.10

    # Panel seams across upper hull
    seam_x = (x_coords % 128 == 0) & (~tps_mask)
    seam_y = (y_coords % 128 == 0) & (~tps_mask)
    seams = seam_x | seam_y
    albedo[seams, 0] = 0.45
    albedo[seams, 1] = 0.46
    albedo[seams, 2] = 0.48

    albedo = np.clip(albedo, 0.0, 1.0)

    # 1.2 ORM MAP (Red = AO, Green = Roughness, Blue = Metallic)
    orm = np.zeros((size, size, 4), dtype=np.float32)
    orm[:, :, 0] = 1.0   # AO
    orm[:, :, 1] = 0.55  # Roughness
    orm[:, :, 2] = 0.03  # Metallic
    orm[:, :, 3] = 1.0

    orm[tps_mask, 1] = 0.78
    orm[tps_mask, 2] = 0.01

    orm[tile_grout, 0] = 0.65
    orm[tile_grout, 1] = 0.92

    orm[rcc_mask, 1] = 0.62
    orm[rcc_mask, 2] = 0.08

    orm[seams, 0] = 0.40
    orm[seams, 1] = 0.85

    # 1.3 NORMAL MAP
    normal = np.zeros((size, size, 4), dtype=np.float32)
    normal[:, :, 0] = 0.5
    normal[:, :, 1] = 0.5
    normal[:, :, 2] = 1.0
    normal[:, :, 3] = 1.0

    seam_edge_x1 = ((x_coords + 1) % 128 == 0) & (~tps_mask)
    seam_edge_x2 = ((x_coords - 1) % 128 == 0) & (~tps_mask)
    normal[seam_edge_x1, 0] = 0.62
    normal[seam_edge_x2, 0] = 0.38

    seam_edge_y1 = ((y_coords + 1) % 128 == 0) & (~tps_mask)
    seam_edge_y2 = ((y_coords - 1) % 128 == 0) & (~tps_mask)
    normal[seam_edge_y1, 1] = 0.62
    normal[seam_edge_y2, 1] = 0.38

    # 1.4 EMISSION MAP
    emission = np.zeros((size, size, 4), dtype=np.float32)
    emission[:, :, 3] = 1.0

    strip_emiss_1 = (u > 0.16) & (u < 0.17) & (v > 0.60) & (v < 0.64)
    strip_emiss_2 = (u > 0.83) & (u < 0.84) & (v > 0.60) & (v < 0.64)
    strip_emiss = strip_emiss_1 | strip_emiss_2
    emission[strip_emiss, 0] = 0.2
    emission[strip_emiss, 1] = 0.9
    emission[strip_emiss, 2] = 1.0

    maps = {
        "orbiter_hull_albedo.png": albedo,
        "orbiter_hull_orm.png": orm,
        "orbiter_hull_normal.png": normal,
        "orbiter_hull_emission.png": emission,
    }

    tex_paths = {}
    for filename, data in maps.items():
        path = os.path.join(tex_dir, filename)
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
    """Sets up the 4 canonical PBR materials: mat_hull, mat_glass, mat_engine, mat_emissive."""
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

    # 2.2 mat_glass (Cockpit glazing)
    mat_glass = bpy.data.materials.new("mat_glass")
    bsdf_glass = mat_glass.node_tree.nodes.get("Principled BSDF")
    bsdf_glass.inputs["Base Color"].default_value = (0.04, 0.07, 0.12, 1.0)
    bsdf_glass.inputs["Metallic"].default_value = 0.90
    bsdf_glass.inputs["Roughness"].default_value = 0.05
    if "Specular IOR Level" in bsdf_glass.inputs:
        bsdf_glass.inputs["Specular IOR Level"].default_value = 1.0
    materials["mat_glass"] = mat_glass

    # 2.3 mat_engine (Inconel / titanium engine bell alloy)
    mat_engine = bpy.data.materials.new("mat_engine")
    bsdf_eng = mat_engine.node_tree.nodes.get("Principled BSDF")
    bsdf_eng.inputs["Base Color"].default_value = (0.22, 0.22, 0.25, 1.0)
    bsdf_eng.inputs["Metallic"].default_value = 0.92
    bsdf_eng.inputs["Roughness"].default_value = 0.28
    materials["mat_engine"] = mat_engine

    # 2.4 mat_emissive (Cockpit displays, strobe & marker lights)
    mat_emissive = bpy.data.materials.new("mat_emissive")
    bsdf_em = mat_emissive.node_tree.nodes.get("Principled BSDF")
    bsdf_em.inputs["Base Color"].default_value = (0.1, 0.8, 1.0, 1.0)
    bsdf_em.inputs["Emission Color"].default_value = (0.1, 0.8, 1.0, 1.0)
    bsdf_em.inputs["Emission Strength"].default_value = 8.0
    materials["mat_emissive"] = mat_emissive

    return materials

# -----------------------------------------------------------------------------
# 3. Geometry Building Functions (Hand-Modelled Spaceplane Parts)
# -----------------------------------------------------------------------------
def assign_mat(obj, mat):
    if len(obj.data.materials) == 0:
        obj.data.materials.append(mat)
    else:
        obj.data.materials[0] = mat

def apply_smart_uv(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')

def build_fuselage(materials):
    """Builds the main aerodynamic fuselage with nose ogive, payload bay, and OMS shoulders."""
    bm = bmesh.new()

    sections = [
        (-6.40,  0.10, 0.20, 0.18, 0.18),
        (-6.25,  0.11, 0.40, 0.32, 0.28),
        (-6.00,  0.13, 0.68, 0.50, 0.42),
        (-5.60,  0.17, 0.95, 0.72, 0.55),
        (-5.10,  0.23, 1.22, 0.92, 0.65),
        (-4.60,  0.32, 1.45, 1.15, 0.72),
        (-4.10,  0.42, 1.58, 1.28, 0.76),
        (-3.60,  0.40, 1.68, 1.28, 0.78),
        (-3.00,  0.38, 1.72, 1.26, 0.78),
        (-1.50,  0.35, 1.75, 1.25, 0.78),
        ( 0.00,  0.35, 1.75, 1.25, 0.78),
        ( 1.50,  0.35, 1.75, 1.25, 0.78),
        ( 3.00,  0.35, 1.76, 1.25, 0.78),
        ( 4.50,  0.35, 1.80, 1.28, 0.80),
        ( 5.50,  0.32, 1.88, 1.34, 0.82),
        ( 6.30,  0.28, 1.90, 1.35, 0.82),
        ( 6.80,  0.24, 1.84, 1.28, 0.80),
        ( 7.10,  0.20, 1.75, 1.20, 0.75),
    ]

    num_radial = 40
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

    nose_apex = bm.verts.new((0.0, 0.10, -6.45))
    for i in range(num_radial):
        i_next = (i + 1) % num_radial
        bm.faces.new((nose_apex, rings[0][i_next], rings[0][i]))

    aft_center = bm.verts.new((0.0, 0.20, 7.10))
    for i in range(num_radial):
        i_next = (i + 1) % num_radial
        bm.faces.new((aft_center, rings[-1][i], rings[-1][i_next]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    
    mesh = bpy.data.meshes.new("FuselageMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Fuselage", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])
    apply_smart_uv(obj)

    mod_bev = obj.modifiers.new("Bevel", "BEVEL")
    mod_bev.width = 0.04
    mod_bev.segments = 2
    mod_bev.limit_method = "ANGLE"
    mod_bev.angle_limit = math.radians(35)

    return obj

def build_cockpit_glazing(materials):
    """Builds multi-faceted cockpit canopy windows and frames."""
    bm = bmesh.new()

    v_fwd_L = [
        bm.verts.new((-0.15, 1.48, -4.10)),
        bm.verts.new((-0.95, 1.35, -4.12)),
        bm.verts.new((-1.05, 1.05, -4.75)),
        bm.verts.new((-0.15, 1.10, -4.78)),
    ]
    bm.faces.new(v_fwd_L)

    v_fwd_R = [
        bm.verts.new((0.15, 1.48, -4.10)),
        bm.verts.new((0.15, 1.10, -4.78)),
        bm.verts.new((1.05, 1.05, -4.75)),
        bm.verts.new((0.95, 1.35, -4.12)),
    ]
    bm.faces.new(v_fwd_R)

    v_side_L = [
        bm.verts.new((-0.98, 1.35, -4.10)),
        bm.verts.new((-1.35, 1.15, -3.45)),
        bm.verts.new((-1.42, 0.95, -3.50)),
        bm.verts.new((-1.07, 1.02, -4.70)),
    ]
    bm.faces.new(v_side_L)

    v_side_R = [
        bm.verts.new((0.98, 1.35, -4.10)),
        bm.verts.new((1.07, 1.02, -4.70)),
        bm.verts.new((1.42, 0.95, -3.50)),
        bm.verts.new((1.35, 1.15, -3.45)),
    ]
    bm.faces.new(v_side_R)

    v_top_L = [
        bm.verts.new((-0.18, 1.62, -3.85)),
        bm.verts.new((-0.80, 1.55, -3.88)),
        bm.verts.new((-0.85, 1.42, -4.20)),
        bm.verts.new((-0.18, 1.52, -4.18)),
    ]
    bm.faces.new(v_top_L)

    v_top_R = [
        bm.verts.new((0.18, 1.62, -3.85)),
        bm.verts.new((0.18, 1.52, -4.18)),
        bm.verts.new((0.85, 1.42, -4.20)),
        bm.verts.new((0.80, 1.55, -3.88)),
    ]
    bm.faces.new(v_top_R)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.solidify(bm, geom=bm.faces, thickness=0.03)

    mesh = bpy.data.meshes.new("CockpitGlazingMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("CockpitGlazing", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_glass"])

    bm_dash = bmesh.new()
    bmesh.ops.create_cube(bm_dash, size=1.0)
    bmesh.ops.scale(bm_dash, vec=(1.6, 0.45, 0.7), verts=bm_dash.verts)
    bmesh.ops.translate(bm_dash, vec=(0.0, 0.85, -4.1), verts=bm_dash.verts)
    mesh_dash = bpy.data.meshes.new("CockpitDashMesh")
    bm_dash.to_mesh(mesh_dash)
    bm_dash.free()

    obj_dash = bpy.data.objects.new("CockpitDashboard", mesh_dash)
    bpy.context.scene.collection.objects.link(obj_dash)
    assign_mat(obj_dash, materials["mat_emissive"])

    return obj, obj_dash

def build_delta_wings(materials):
    """Builds double-delta wings spanning 13.8 m with cambered aerofoil, elevons, and wingtip fences."""
    bm = bmesh.new()

    stations = [
        (1.70, -1.80,  5.80,  0.08, 0.38),
        (2.30, -1.30,  5.75,  0.09, 0.35),
        (3.10, -0.60,  5.65,  0.10, 0.32),
        (4.00,  0.30,  5.45,  0.11, 0.28),
        (4.90,  1.20,  5.25,  0.12, 0.24),
        (5.70,  2.00,  5.00,  0.13, 0.20),
        (6.40,  2.50,  4.75,  0.14, 0.16),
        (6.90,  2.80,  4.60,  0.15, 0.14),
    ]

    for is_port in [False, True]:
        sign = -1.0 if is_port else 1.0
        wing_rings = []
        for x_span, le_z, te_z, y_cam, thick in stations:
            x = sign * x_span
            chord = te_z - le_z
            chord_pts = 24
            profile_upper = []
            profile_lower = []
            for p in range(chord_pts):
                t = p / float(chord_pts - 1)
                z = le_z + t * chord
                h = 4.0 * t * (1.0 - t) * thick
                y_up = y_cam + h * 0.65
                y_dn = y_cam - h * 0.35
                profile_upper.append(bm.verts.new((x, y_up, z)))
                profile_lower.append(bm.verts.new((x, y_dn, z)))

            wing_rings.append((profile_upper, profile_lower))

        for s in range(len(stations) - 1):
            up0, dn0 = wing_rings[s]
            up1, dn1 = wing_rings[s + 1]
            n_pts = len(up0)

            for i in range(n_pts - 1):
                if not is_port:
                    bm.faces.new((up0[i], up1[i], up1[i + 1], up0[i + 1]))
                else:
                    bm.faces.new((up0[i], up0[i + 1], up1[i + 1], up1[i]))

            for i in range(n_pts - 1):
                if not is_port:
                    bm.faces.new((dn0[i], dn0[i + 1], dn1[i + 1], dn1[i]))
                else:
                    bm.faces.new((dn0[i], dn1[i], dn1[i + 1], dn0[i + 1]))

            if not is_port:
                bm.faces.new((dn0[0], up0[0], up1[0], dn1[0]))
            else:
                bm.faces.new((dn0[0], dn1[0], up1[0], up0[0]))

            if not is_port:
                bm.faces.new((up0[-1], dn0[-1], dn1[-1], up1[-1]))
            else:
                bm.faces.new((up0[-1], up1[-1], dn1[-1], dn0[-1]))

        tip_up, tip_dn = wing_rings[-1]
        tip_x = sign * 6.90
        fence_up = []
        for v in tip_up:
            fence_up.append(bm.verts.new((tip_x, v.co.y + 0.35, v.co.z)))
        for i in range(len(tip_up) - 1):
            if not is_port:
                bm.faces.new((tip_up[i], tip_up[i + 1], fence_up[i + 1], fence_up[i]))
            else:
                bm.faces.new((tip_up[i], fence_up[i], fence_up[i + 1], tip_up[i + 1]))

    # Bevelled Elevons
    for sign in [-1.0, 1.0]:
        for elevon_span in [(2.2, 4.2), (4.5, 6.5)]:
            x_in, x_out = elevon_span
            z_hinge = 5.0
            z_te = 5.8
            el_verts = [
                bm.verts.new((sign * x_in,  0.12, z_hinge)),
                bm.verts.new((sign * x_out, 0.15, z_hinge)),
                bm.verts.new((sign * x_out, 0.14, z_te)),
                bm.verts.new((sign * x_in,  0.10, z_te)),
            ]
            f = bm.faces.new(el_verts)
            bmesh.ops.solidify(bm, geom=[f], thickness=0.08)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("DeltaWingsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("DeltaWings", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])
    apply_smart_uv(obj)

    return obj

def build_vertical_tail_fin(materials):
    """Builds the vertical tail fin and rudder along dorsal centerline."""
    bm = bmesh.new()

    fin_stations = [
        (1.20, 3.60, 7.10, 0.35),
        (1.65, 4.05, 7.05, 0.30),
        (2.10, 4.50, 6.98, 0.25),
        (2.55, 4.95, 6.90, 0.20),
        (3.00, 5.40, 6.80, 0.15),
        (3.45, 5.80, 6.65, 0.10),
    ]

    fin_rings = []
    for y, le_z, te_z, thick in fin_stations:
        chord = te_z - le_z
        chord_pts = 18
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

        for i in range(n - 1):
            bm.faces.new((s0[i], s0[i + 1], s1[i + 1], s1[i]))

        bm.faces.new((p0[0], s0[0], s1[0], p1[0]))
        bm.faces.new((s0[-1], p0[-1], p1[-1], s1[-1]))

    tip_p, tip_s = fin_rings[-1]
    for i in range(len(tip_p) - 1):
        bm.faces.new((tip_p[i], tip_p[i + 1], tip_s[i + 1], tip_s[i]))

    rudder_f = [
        bm.verts.new((-0.06, 1.35, 6.30)),
        bm.verts.new((-0.04, 3.35, 6.10)),
        bm.verts.new(( 0.04, 3.35, 6.10)),
        bm.verts.new(( 0.06, 1.35, 6.30)),
    ]
    bm.faces.new(rudder_f)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("TailFinMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("TailFin", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])
    apply_smart_uv(obj)

    return obj

def build_engine_bells(materials):
    """Builds twin main propulsion rocket engine bells at the rear bulkhead."""
    bm = bmesh.new()

    engine_positions = [-0.85, 0.85]
    rings_count = 24
    sectors = 36

    for ex in engine_positions:
        ey = -0.10
        bmesh.ops.create_cone(
            bm,
            cap_ends=True,
            cap_tris=False,
            segments=sectors,
            radius1=0.38,
            radius2=0.35,
            depth=0.25,
            matrix=mat_trans(ex, ey, 6.95)
        )

        bell_rings = []
        for r_i in range(rings_count + 1):
            t = r_i / float(rings_count)
            z = 7.00 + t * 1.20
            radius = 0.28 + 0.44 * (t ** 0.75)
            
            ring_v = []
            for s in range(sectors):
                th = (s / float(sectors)) * 2.0 * math.pi
                x = ex + radius * math.cos(th)
                y = ey + radius * math.sin(th)
                ring_v.append(bm.verts.new((x, y, z)))
            bell_rings.append(ring_v)

        for r_i in range(rings_count):
            for s in range(sectors):
                s_next = (s + 1) % sectors
                v0 = bell_rings[r_i][s]
                v1 = bell_rings[r_i][s_next]
                v2 = bell_rings[r_i + 1][s_next]
                v3 = bell_rings[r_i + 1][s]
                bm.faces.new((v0, v1, v2, v3))

        for ring_z in [7.35, 7.75, 8.10]:
            t_ring = (ring_z - 7.00) / 1.20
            r_ring = 0.28 + 0.44 * (t_ring ** 0.75)
            torus_v = []
            for s in range(sectors):
                th = (s / float(sectors)) * 2.0 * math.pi
                x = ex + (r_ring + 0.04) * math.cos(th)
                y = ey + (r_ring + 0.04) * math.sin(th)
                torus_v.append(bm.verts.new((x, y, ring_z)))
            for s in range(sectors):
                s_next = (s + 1) % sectors
                v0 = torus_v[s]
                v1 = torus_v[s_next]
                v2 = bm.verts.new((torus_v[s_next].co.x, torus_v[s_next].co.y, ring_z + 0.04))
                v3 = bm.verts.new((torus_v[s].co.x, torus_v[s].co.y, ring_z + 0.04))
                bm.faces.new((v0, v1, v2, v3))

        dome_apex = bm.verts.new((ex, ey, 7.02))
        for s in range(sectors):
            s_next = (s + 1) % sectors
            bm.faces.new((dome_apex, bell_rings[0][s], bell_rings[0][s_next]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("EngineBellsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("EngineBells", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_engine"])
    apply_smart_uv(obj)

    return obj

def build_rcs_blisters(materials):
    """Builds reaction control system (RCS) thruster pods on nose and aft shoulders."""
    bm = bmesh.new()

    for sign in [-1.0, 1.0]:
        px = sign * 0.95
        py = 0.10
        pz = -4.80
        bmesh.ops.create_cube(bm, size=0.35)
        last_verts = bm.verts[-8:]
        bmesh.ops.scale(bm, vec=(0.7, 0.9, 1.2), verts=last_verts)
        bmesh.ops.translate(bm, vec=(px, py, pz), verts=last_verts)

    for sign in [-1.0, 1.0]:
        px = sign * 1.35
        py = 0.45
        pz = 6.60
        bmesh.ops.create_cube(bm, size=0.55)
        last_verts = bm.verts[-8:]
        bmesh.ops.scale(bm, vec=(0.8, 0.9, 1.5), verts=last_verts)
        bmesh.ops.translate(bm, vec=(px, py, pz), verts=last_verts)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("RCSPodsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("RCSPods", mesh)
    bpy.context.scene.collection.objects.link(obj)
    assign_mat(obj, materials["mat_hull"])

    return obj

# -----------------------------------------------------------------------------
# 4. Deployable Landing Gear (3 Legs) & 1-Second Animation
# -----------------------------------------------------------------------------
def build_landing_gear(materials):
    """
    Builds 3 deployable landing gear legs in bone-local coordinates:
    - 1 Nose gear at (0, -0.25, -4.20)
    - 2 Main gears at (±2.40, -0.15, 2.00)
    Sets up an Armature with 1-second 'gear_deploy' animation (30 frames at 30 fps).
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
    nose_bone.tail = (0.0, -1.60, -4.20)
    nose_bone.parent = root_bone

    main_l_bone = arm_data.edit_bones.new("gear_main_L")
    main_l_bone.head = (-2.40, -0.15, 2.00)
    main_l_bone.tail = (-2.40, -1.60, 2.00)
    main_l_bone.parent = root_bone

    main_r_bone = arm_data.edit_bones.new("gear_main_R")
    main_r_bone.head = (2.40, -0.15, 2.00)
    main_r_bone.tail = (2.40, -1.60, 2.00)
    main_r_bone.parent = root_bone

    bpy.ops.object.mode_set(mode='OBJECT')

    gear_objects = []

    # 1. Nose Gear Mesh (authored in bone-local space)
    bm_n = bmesh.new()
    # Strut along Y from 0 to -1.35
    bmesh.ops.create_cone(
        bm_n,
        cap_ends=True,
        segments=20,
        radius1=0.07,
        radius2=0.07,
        depth=1.35,
        matrix=mat_cyl_y(0.0, -0.675, 0.0)
    )
    # Axle along X at Y = -1.35
    bmesh.ops.create_cone(
        bm_n,
        cap_ends=True,
        segments=16,
        radius1=0.04,
        radius2=0.04,
        depth=0.48,
        matrix=mat_cyl_x(0.0, -1.35, 0.0)
    )
    # Twin nose wheels
    for side in [-0.18, 0.18]:
        bmesh.ops.create_cone(
            bm_n,
            cap_ends=True,
            segments=28,
            radius1=0.35,
            radius2=0.35,
            depth=0.14,
            matrix=mat_cyl_x(side, -1.35, 0.0)
        )
    mesh_n = bpy.data.meshes.new("NoseGearMesh")
    bm_n.to_mesh(mesh_n)
    bm_n.free()
    obj_nose = bpy.data.objects.new("GearLeg_Nose", mesh_n)
    bpy.context.scene.collection.objects.link(obj_nose)
    assign_mat(obj_nose, materials["mat_engine"])
    gear_objects.append((obj_nose, "gear_nose"))

    # 2. Main Gear Left Mesh (bone-local space)
    bm_ml = bmesh.new()
    bmesh.ops.create_cone(
        bm_ml,
        cap_ends=True,
        segments=24,
        radius1=0.10,
        radius2=0.10,
        depth=1.45,
        matrix=mat_cyl_y(0.0, -0.725, 0.0)
    )
    bmesh.ops.create_cone(
        bm_ml,
        cap_ends=True,
        segments=18,
        radius1=0.05,
        radius2=0.05,
        depth=0.55,
        matrix=mat_cyl_x(0.0, -1.45, 0.0)
    )
    for side in [-0.22, 0.22]:
        bmesh.ops.create_cone(
            bm_ml,
            cap_ends=True,
            segments=32,
            radius1=0.45,
            radius2=0.45,
            depth=0.18,
            matrix=mat_cyl_x(side, -1.45, 0.0)
        )
    mesh_ml = bpy.data.meshes.new("MainGearLMesh")
    bm_ml.to_mesh(mesh_ml)
    bm_ml.free()
    obj_main_l = bpy.data.objects.new("GearLeg_Main_L", mesh_ml)
    bpy.context.scene.collection.objects.link(obj_main_l)
    assign_mat(obj_main_l, materials["mat_engine"])
    gear_objects.append((obj_main_l, "gear_main_L"))

    # 3. Main Gear Right Mesh (bone-local space)
    bm_mr = bmesh.new()
    bmesh.ops.create_cone(
        bm_mr,
        cap_ends=True,
        segments=24,
        radius1=0.10,
        radius2=0.10,
        depth=1.45,
        matrix=mat_cyl_y(0.0, -0.725, 0.0)
    )
    bmesh.ops.create_cone(
        bm_mr,
        cap_ends=True,
        segments=18,
        radius1=0.05,
        radius2=0.05,
        depth=0.55,
        matrix=mat_cyl_x(0.0, -1.45, 0.0)
    )
    for side in [-0.22, 0.22]:
        bmesh.ops.create_cone(
            bm_mr,
            cap_ends=True,
            segments=32,
            radius1=0.45,
            radius2=0.45,
            depth=0.18,
            matrix=mat_cyl_x(side, -1.45, 0.0)
        )
    mesh_mr = bpy.data.meshes.new("MainGearRMesh")
    bm_mr.to_mesh(mesh_mr)
    bm_mr.free()
    obj_main_r = bpy.data.objects.new("GearLeg_Main_R", mesh_mr)
    bpy.context.scene.collection.objects.link(obj_main_r)
    assign_mat(obj_main_r, materials["mat_engine"])
    gear_objects.append((obj_main_r, "gear_main_R"))

    # Bind gear meshes to armature bones
    for obj, bone_name in gear_objects:
        obj.parent = arm_obj
        obj.parent_type = 'BONE'
        obj.parent_bone = bone_name

    # Keyframed animation 'gear_deploy' (30 frames = 1.0 second at 30 fps)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode='POSE')

    pose_nose = arm_obj.pose.bones["gear_nose"]
    pose_l = arm_obj.pose.bones["gear_main_L"]
    pose_r = arm_obj.pose.bones["gear_main_R"]

    for p in [pose_nose, pose_l, pose_r]:
        p.rotation_mode = 'XYZ'

    # Frame 1: Retracted inside bays
    pose_nose.rotation_euler = (math.radians(95), 0, 0)
    pose_nose.keyframe_insert(data_path="rotation_euler", frame=1)

    pose_l.rotation_euler = (0, 0, math.radians(90))
    pose_l.keyframe_insert(data_path="rotation_euler", frame=1)

    pose_r.rotation_euler = (0, 0, math.radians(-90))
    pose_r.keyframe_insert(data_path="rotation_euler", frame=1)

    # Frame 30: Deployed vertically
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
    """Builds all attachment sockets as empties for plumes, RCS, nav lights, and cameras."""
    sockets = [
        # Main Propulsion Engine Nozzles
        ("SOCKET_engine_L", (-0.85, -0.10,  8.20)),
        ("SOCKET_engine_R", ( 0.85, -0.10,  8.20)),

        # Wingtip Navigation Lights (Port Red / Starboard Green)
        ("SOCKET_nav_port", (-6.90,  0.15,  2.80)),
        ("SOCKET_nav_stbd", ( 6.90,  0.15,  2.80)),

        # Reaction Control System (RCS) Nozzles
        ("SOCKET_rcs_nose_pitch_up",   ( 0.00,  0.65, -4.80)),
        ("SOCKET_rcs_nose_pitch_down", ( 0.00, -0.65, -4.80)),
        ("SOCKET_rcs_nose_yaw_port",   (-0.95,  0.10, -4.80)),
        ("SOCKET_rcs_nose_yaw_stbd",   ( 0.95,  0.10, -4.80)),

        ("SOCKET_rcs_tail_port", (-1.35,  0.45,  6.80)),
        ("SOCKET_rcs_tail_stbd", ( 1.35,  0.45,  6.80)),
        ("SOCKET_rcs_tail_up",   ( 0.00,  1.40,  6.80)),

        # Camera & Cockpit Eye Points
        ("SOCKET_cockpit_cam", (0.00, 0.95, -3.80)),
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
        # Nose
        (0.0, 0.10, -6.40),
        # Cockpit brow & apex
        (0.0, 1.35, -4.10),
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
        ( 6.90, 0.15, 2.80),
        ( 6.90, 0.15, 4.60),
        (-6.90, 0.15, 2.80),
        (-6.90, 0.15, 4.60),
        # Trailing edge root
        ( 1.85, 0.10, 5.80),
        (-1.85, 0.10, 5.80),
        # Tail fin top
        (0.0, 3.45, 5.80),
        (0.0, 3.45, 6.70),
        # Aft bulkhead corners
        (-1.75, 1.20, 7.10),
        ( 1.75, 1.20, 7.10),
        (-1.75, -0.60, 7.10),
        ( 1.75, -0.60, 7.10),
        # Engine bells envelope
        (-0.85, -0.10, 8.20),
        ( 0.85, -0.10, 8.20),
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
    # Hide from preview render so it doesn't obstruct visual model
    obj.hide_render = True

    return obj

# -----------------------------------------------------------------------------
# 7. LOD Generation
# -----------------------------------------------------------------------------
def build_lods(hull_components):
    """
    Combines hull components into Orbiter_LOD0 and creates a decimated Orbiter_LOD1.
    """
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
    print(f"Orbiter_LOD0 triangle count: {lod0_tris} (budget <= 50,000)")

    bpy.ops.object.select_all(action='DESELECT')
    lod0_obj.select_set(True)
    bpy.context.view_layer.objects.active = lod0_obj
    bpy.ops.object.duplicate()
    lod1_obj = bpy.context.active_object
    lod1_obj.name = "Orbiter_LOD1"
    lod1_obj.data.name = "Orbiter_LOD1_Mesh"

    ratio = min(0.25, 7500.0 / max(1.0, float(lod0_tris)))
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
# 8. Render Preview PNG
# -----------------------------------------------------------------------------
def render_preview(output_path):
    """Sets up studio camera and lighting, rendering preview.png."""
    scene = bpy.context.scene
    scene.frame_set(30)

    eye = mathutils.Vector((-16.0, 11.0, -15.0))
    target = mathutils.Vector((0.0, 0.4, 0.2))
    up = mathutils.Vector((0.0, 1.0, 0.0))
    mat = get_look_at_matrix(eye, target, up)

    cam_data = bpy.data.cameras.new("PreviewCamera")
    cam_data.lens = 45.0
    cam_obj = bpy.data.objects.new("PreviewCamera", cam_data)
    cam_obj.matrix_world = mat
    bpy.context.scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    # Key Point Light (Upper-Front-Left)
    p1_data = bpy.data.lights.new("KeyLight", type='POINT')
    p1_data.energy = 35000.0
    p1_data.color = (1.0, 0.95, 0.90)
    p1 = bpy.data.objects.new("KeyLight", p1_data)
    p1.location = (-12.0, 14.0, -14.0)
    bpy.context.scene.collection.objects.link(p1)

    # Fill Point Light (Upper-Front-Right)
    p2_data = bpy.data.lights.new("FillLight", type='POINT')
    p2_data.energy = 15000.0
    p2_data.color = (0.6, 0.75, 1.0)
    p2 = bpy.data.objects.new("FillLight", p2_data)
    p2.location = (14.0, 10.0, -8.0)
    bpy.context.scene.collection.objects.link(p2)

    # Rim Point Light (Upper-Rear)
    p3_data = bpy.data.lights.new("RimLight", type='POINT')
    p3_data.energy = 25000.0
    p3_data.color = (0.9, 0.95, 1.0)
    p3 = bpy.data.objects.new("RimLight", p3_data)
    p3.location = (0.0, 10.0, 14.0)
    bpy.context.scene.collection.objects.link(p3)

    scene.render.filepath = os.path.abspath(output_path)
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

    print(f"Rendering preview image to {output_path}...")
    bpy.ops.render.render(write_still=True)
    print(f"Preview render saved successfully: {os.path.exists(output_path)}")

    for temp_obj in [cam_obj, p1, p2, p3]:
        bpy.data.objects.remove(temp_obj, do_unlink=True)

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
def main():
    print("=== Building Solar Horizon Hero Orbiter ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # 1. Generate textures
    tex_paths = generate_procedural_textures(TEXTURES_DIR, size=2048)

    # 2. Setup materials
    materials = setup_materials(tex_paths)

    # 3. Build geometry components
    print("Hand-modelling orbiter components...")
    fuselage = build_fuselage(materials)
    cockpit_glass, cockpit_dash = build_cockpit_glazing(materials)
    wings = build_delta_wings(materials)
    tail_fin = build_vertical_tail_fin(materials)
    engine_bells = build_engine_bells(materials)
    rcs_blisters = build_rcs_blisters(materials)

    hull_components = [
        fuselage,
        cockpit_glass,
        cockpit_dash,
        wings,
        tail_fin,
        engine_bells,
        rcs_blisters
    ]

    # 4. Build deployable landing gear & animation
    print("Building deployable landing gear and rigging animation...")
    gear_armature, gear_legs = build_landing_gear(materials)

    # 5. Build sockets
    print("Creating attachment sockets...")
    sockets = build_sockets()

    # 6. Build collision hull
    print("Building collision mesh COL_hull...")
    col_hull = build_collision_mesh()

    # 7. Render preview image (gear deployed)
    render_preview(PREVIEW_OUTPUT_PATH)

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
    if os.path.exists(PREVIEW_OUTPUT_PATH):
        print(f"Preview Output: {PREVIEW_OUTPUT_PATH} ({os.path.getsize(PREVIEW_OUTPUT_PATH):,} bytes)")

if __name__ == "__main__":
    main()
