#!/usr/bin/env python3
"""
Solar Horizon — Lunar Surface Rover Model Generator (WP 3.4)
Builds a high-fidelity modular Apollo/Artemis-style Lunar Surface Rover in Blender
and exports glTF 2.0 (.glb) along with procedural PBR textures and studio preview renders.

Specifications per WP 3.4 & ASSET_PIPELINE.md:
- Dimensions: ~3.5m length, 2.1m width, forward = -Z, 1 unit = 1 m
- Coordinate System (Godot 4): Forward = -Z, Up = +Y, Right = +X
- Origin (0, 0, 0): Nominal Center of Mass (CoM)
  Wheel bottom contact plane rests at horizontal ground offset Y = -0.55 m.
- Tubular chassis spaceframe with roll bars, bumpers, and double-wishbone suspension wishbones.
- Dual astronaut bucket seats with contoured backrests (PLSS backpack recess) and central control yoke / stick.
- High-gain parabolic dish antenna on steerable front mast, optical camera sensor turret.
- Rear cargo equipment bay with rack, tool boxes, sample containers, and core drill tools.
- 4 wire-mesh / chevron-tread lunar wheels (independent objects / submeshes: Wheel_FL, Wheel_FR, Wheel_RL, Wheel_RR)
  with gold/silver planetary gear hubs and dust mudguards.
- Empties/Sockets:
  - SOCKET_headlight_L, SOCKET_headlight_R
  - SOCKET_cargo
  - SOCKET_seat_driver, SOCKET_seat_passenger
  - SOCKET_wheel_FL, SOCKET_wheel_FR, SOCKET_wheel_RL, SOCKET_wheel_RR
  - SOCKET_antenna, SOCKET_cam, SOCKET_chase_cam
- Collision mesh COL_chassis (simplified convex hull)
- Procedural PBR materials:
  - Kapton gold foil (Zone 1)
  - Beta cloth white (Zone 2)
  - Chassis matte dark gray (Zone 3)
  - Wheel titanium mesh & chevron tread (Zone 4)
- LODs:
  - Rover_LOD0: 10,000 - 18,000 triangles
  - Rover_LOD1: 2,000 - 4,000 triangles
- Renders:
  - preview.png (3/4 isometric beauty render)
  - preview_front.png (front view)
  - preview_side.png (side profile)
  - preview_top.png (top-down view)
"""

import sys
import os
import math
import subprocess

# Self-bootstrap outside Blender: invoke via Blender 5.2 / 4.x
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

OUTPUT_DIR = os.path.join(PROJECT_ROOT, "assets", "models", "vehicles", "rover")
TEXTURES_DIR = os.path.join(OUTPUT_DIR, "textures")
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(TEXTURES_DIR, exist_ok=True)

GLB_OUTPUT_PATH = os.path.join(OUTPUT_DIR, "rover.glb")
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

def assign_uvs(bm, verts, uv_bounds, mapping='cylindrical'):
    """Maps vertices to UV bounds [u_min, u_max, v_min, v_max]."""
    uv_layer = bm.loops.layers.uv.verify()
    u_min, u_max, v_min, v_max = uv_bounds
    if not verts:
        return
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    min_z, max_z = min(zs), max(zs)
    dx = max(max_x - min_x, 1e-4)
    dy = max(max_y - min_y, 1e-4)
    dz = max(max_z - min_z, 1e-4)
    cx = (min_x + max_x) * 0.5
    cz = (min_z + max_z) * 0.5

    for v in verts:
        if mapping == 'cylindrical':
            theta = math.atan2(v.co.x - cx, v.co.z - cz)
            u_norm = (theta / (2.0 * math.pi)) + 0.5
            v_norm = (v.co.y - min_y) / dy
        elif mapping == 'cylindrical_x':
            theta = math.atan2(v.co.y - min_y - dy*0.5, v.co.z - cz)
            u_norm = (theta / (2.0 * math.pi)) + 0.5
            v_norm = (v.co.x - min_x) / dx
        elif mapping == 'planar_xz':
            u_norm = (v.co.x - min_x) / dx
            v_norm = (v.co.z - min_z) / dz
        elif mapping == 'planar_xy':
            u_norm = (v.co.x - min_x) / dx
            v_norm = (v.co.y - min_y) / dy
        else: # box / general
            u_norm = ((v.co.x - min_x) + (v.co.z - min_z)) / (dx + dz)
            v_norm = (v.co.y - min_y) / dy

        u_norm = max(0.0, min(1.0, u_norm))
        v_norm = max(0.0, min(1.0, v_norm))

        for loop in v.link_loops:
            u = u_min + u_norm * (u_max - u_min)
            v_coord = v_min + v_norm * (v_max - v_min)
            loop[uv_layer].uv = (min(0.99, max(0.01, u)), min(0.99, max(0.01, v_coord)))

def make_strut(bm, p1, p2, r1, r2=None, segments=12, uv_bounds=(0.1, 0.9, 0.52, 0.73)):
    """Creates a cylinder/strut connecting p1 to p2 with UVs."""
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
        assign_uvs(bm, res["verts"], uv_bounds, mapping='cylindrical')
    return res["verts"]

def add_box(bm, center, size, rot_mat=None, uv_bounds=(0.1, 0.9, 0.52, 0.73), mapping='box'):
    """Creates a box primitive with center, size, rotation, and UV coordinates."""
    mat = mathutils.Matrix.Translation(center)
    if rot_mat:
        mat = mat @ rot_mat
    mat = mat @ mathutils.Matrix.Scale(size[0], 4, (1, 0, 0)) \
              @ mathutils.Matrix.Scale(size[1], 4, (0, 1, 0)) \
              @ mathutils.Matrix.Scale(size[2], 4, (0, 0, 1))
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=mat)
    if uv_bounds:
        assign_uvs(bm, res["verts"], uv_bounds, mapping=mapping)
    return res["verts"]

def add_cylinder(bm, center, radius, depth, axis='Y', segments=16, uv_bounds=(0.1, 0.9, 0.52, 0.73)):
    """Creates a cylinder aligned with specified axis ('X', 'Y', 'Z')."""
    if axis == 'Y':
        rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'X')
        mapping = 'cylindrical'
    elif axis == 'X':
        rot = mathutils.Matrix.Rotation(math.radians(90), 4, 'Y')
        mapping = 'cylindrical_x'
    else: # 'Z'
        rot = mathutils.Matrix.Identity(4)
        mapping = 'cylindrical'

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
        assign_uvs(bm, res["verts"], uv_bounds, mapping=mapping)
    return res["verts"]

def add_paraboloid(bm, center, radius, depth, rot_mat=None, segments=24, rings=10, uv_bounds=(0.1, 0.9, 0.76, 0.98)):
    """Creates a dish reflector paraboloid with front surface and rear shell."""
    verts = []
    # Generate concentric rings of vertices
    grid_verts = []
    for r_idx in range(rings + 1):
        r_frac = r_idx / float(rings)
        r = radius * r_frac
        z = (r_frac ** 2) * depth
        ring = []
        for s_idx in range(segments):
            angle = 2.0 * math.pi * (s_idx / float(segments))
            x = r * math.cos(angle)
            y = r * math.sin(angle)
            ring.append((x, y, z))
        grid_verts.append(ring)

    # Transform and build front bowl
    mesh_front_verts = []
    transform_mat = mathutils.Matrix.Translation(center)
    if rot_mat:
        transform_mat = transform_mat @ rot_mat

    created_bverts = []
    for ring in grid_verts:
        b_ring = []
        for pt in ring:
            world_p = transform_mat @ mathutils.Vector(pt)
            v = bm.verts.new(world_p)
            b_ring.append(v)
            created_bverts.append(v)
        mesh_front_verts.append(b_ring)

    # Faces between rings
    for r_idx in range(rings):
        r0 = mesh_front_verts[r_idx]
        r1 = mesh_front_verts[r_idx + 1]
        for s_idx in range(segments):
            s_next = (s_idx + 1) % segments
            if r_idx == 0:
                bm.faces.new([r0[s_idx], r1[s_idx], r1[s_next]])
            else:
                bm.faces.new([r0[s_idx], r1[s_idx], r1[s_next], r0[s_next]])

    if uv_bounds:
        assign_uvs(bm, created_bverts, uv_bounds, mapping='cylindrical')
    return created_bverts

# -----------------------------------------------------------------------------
# 1. Procedural PBR Textures (2048x2048: Albedo, ORM, Normal, Emission)
# -----------------------------------------------------------------------------
def generate_procedural_textures(tex_dir, size=2048):
    """
    Generates high-fidelity procedural PBR texture atlas maps (2048x2048):
    - Zone 1 (0.00 <= v < 0.25): Kapton Gold MLI Foil
      Wrinkled foil micro-texture, taped seams, metallic 0.98, roughness 0.26
    - Zone 2 (0.25 <= v < 0.50): White Beta-Cloth Thermal Blanket
      Quilted stitching squares, Solar Horizon orange/cyan livery stripes, hazard diagonals
    - Zone 3 (0.50 <= v < 0.75): Chassis Matte Dark Gray Powder-Coated Metal
      Powder-coat micro-grit, panel lines, weld seams, hex bolts
    - Zone 4 (0.75 <= v <= 1.00): Wheel Titanium Wire Mesh & Chevron Tread
      Diamond wire-mesh weave, titanium chevron traction cleats, metallic 0.94
    """
    print(f"Generating {size}x{size} procedural PBR textures for Lunar Rover...")
    y_coords, x_coords = np.mgrid[0:size, 0:size]
    u = x_coords / float(size)
    v = y_coords / float(size)

    # 1.1 ALBEDO MAP
    albedo = np.zeros((size, size, 4), dtype=np.float32)
    albedo[:, :, 3] = 1.0

    mask_kapton = (v < 0.25)
    mask_beta   = (v >= 0.25) & (v < 0.50)
    mask_chassis = (v >= 0.50) & (v < 0.75)
    mask_wheel  = (v >= 0.75)

    # --- ZONE 1: KAPTON GOLD MLI FOIL (v < 0.25) ---
    albedo[mask_kapton, 0] = 0.96
    albedo[mask_kapton, 1] = 0.74
    albedo[mask_kapton, 2] = 0.16

    # Crinkled foil micro-facets
    facet_size = 32
    f_x = x_coords // facet_size
    f_y = y_coords // facet_size
    hash_grid = ((f_x * 12345 + f_y * 67891) % 997) / 997.0 - 0.5
    crinkle_fine = np.sin(u * 220.0 + hash_grid * 4.0) * np.cos(v * 220.0 - hash_grid * 3.5)
    foil_variation = hash_grid * 0.08 + crinkle_fine * 0.04
    albedo[mask_kapton, 0] += foil_variation[mask_kapton] * 0.3
    albedo[mask_kapton, 1] += foil_variation[mask_kapton] * 0.25
    albedo[mask_kapton, 2] += foil_variation[mask_kapton] * 0.05

    # Amber Kapton tape seams (grid lines every 128 px, width 8 px)
    tape_x = (x_coords % 128 < 8)
    tape_y = (y_coords % 128 < 8)
    tape_lines = (tape_x | tape_y) & mask_kapton
    albedo[tape_lines, 0] = 0.90
    albedo[tape_lines, 1] = 0.52
    albedo[tape_lines, 2] = 0.06

    # --- ZONE 2: WHITE BETA-CLOTH THERMAL BLANKET (0.25 <= v < 0.50) ---
    albedo[mask_beta, 0] = 0.89
    albedo[mask_beta, 1] = 0.90
    albedo[mask_beta, 2] = 0.92

    # Beta cloth fine fabric weave
    weave = (np.sin(u * 512.0 * math.pi) * np.sin(v * 512.0 * math.pi)) * 0.015
    albedo[mask_beta, 0] += weave[mask_beta]
    albedo[mask_beta, 1] += weave[mask_beta]
    albedo[mask_beta, 2] += weave[mask_beta]

    # Quilted stitching grid (64 px squares with stitch seam lines)
    quilt_x = (x_coords % 64 < 2)
    quilt_y = (y_coords % 64 < 2)
    quilt_seam = (quilt_x | quilt_y) & mask_beta
    albedo[quilt_seam, 0] = 0.76
    albedo[quilt_seam, 1] = 0.78
    albedo[quilt_seam, 2] = 0.80

    # Quilt tuft buttons / pin fastener depressions at intersections
    dist_button_x = (x_coords % 64)
    dist_button_y = (y_coords % 64)
    button_dots = ((dist_button_x < 4) & (dist_button_y < 4)) & mask_beta
    albedo[button_dots, 0] = 0.60
    albedo[button_dots, 1] = 0.62
    albedo[button_dots, 2] = 0.65

    # Livery Stripes: Solar Horizon Orange Cheatline & Cyan Pinstripe
    livery_orange = (v >= 0.44) & (v < 0.46) & (u > 0.05) & (u < 0.95) & mask_beta
    albedo[livery_orange, 0] = 0.96
    albedo[livery_orange, 1] = 0.40
    albedo[livery_orange, 2] = 0.08

    livery_cyan = (v >= 0.465) & (v < 0.475) & (u > 0.05) & (u < 0.95) & mask_beta
    albedo[livery_cyan, 0] = 0.12
    albedo[livery_cyan, 1] = 0.78
    albedo[livery_cyan, 2] = 0.95

    # Hazard Diagonal Caution Stripes (Equipment Bay & Fender flaps)
    hazard_zone = (u >= 0.40) & (u < 0.60) & (v >= 0.28) & (v < 0.34) & mask_beta
    diag_stripes = ((x_coords + y_coords) // 16) % 2 == 0
    albedo[hazard_zone & diag_stripes, 0] = 0.95
    albedo[hazard_zone & diag_stripes, 1] = 0.75
    albedo[hazard_zone & diag_stripes, 2] = 0.05
    albedo[hazard_zone & ~diag_stripes, 0] = 0.10
    albedo[hazard_zone & ~diag_stripes, 1] = 0.10
    albedo[hazard_zone & ~diag_stripes, 2] = 0.12

    # --- ZONE 3: CHASSIS MATTE DARK GRAY METAL (0.50 <= v < 0.75) ---
    albedo[mask_chassis, 0] = 0.20
    albedo[mask_chassis, 1] = 0.21
    albedo[mask_chassis, 2] = 0.23

    # Structural panel lines
    panel_x = (x_coords % 128 < 2)
    panel_y = (y_coords % 128 < 2)
    panel_lines = (panel_x | panel_y) & mask_chassis
    albedo[panel_lines, 0] = 0.12
    albedo[panel_lines, 1] = 0.13
    albedo[panel_lines, 2] = 0.14

    # Hex bolts / rivets along chassis frame seams (spaced every 32 px)
    rivet_x = (x_coords % 32 < 3) & (y_coords % 128 < 4)
    rivet_y = (y_coords % 32 < 3) & (x_coords % 128 < 4)
    rivets = (rivet_x | rivet_y) & mask_chassis
    albedo[rivets, 0] = 0.55
    albedo[rivets, 1] = 0.58
    albedo[rivets, 2] = 0.62

    # --- ZONE 4: WHEEL TITANIUM WIRE MESH & CHEVRON TREAD (v >= 0.75) ---
    albedo[mask_wheel, 0] = 0.62
    albedo[mask_wheel, 1] = 0.64
    albedo[mask_wheel, 2] = 0.67

    # Diamond woven wire mesh pattern
    diag_mesh_1 = (x_coords + y_coords) % 16 < 3
    diag_mesh_2 = (x_coords - y_coords) % 16 < 3
    wire_weave = (diag_mesh_1 | diag_mesh_2) & mask_wheel
    albedo[wire_weave, 0] = 0.78
    albedo[wire_weave, 1] = 0.80
    albedo[wire_weave, 2] = 0.83
    mesh_openings = (~wire_weave) & mask_wheel
    albedo[mesh_openings, 0] = 0.35
    albedo[mesh_openings, 1] = 0.36
    albedo[mesh_openings, 2] = 0.38

    # Titanium Chevron Traction Tread Cleat pattern (V-shaped tread strips)
    chevron_x = (x_coords % 128)
    chevron_v = (y_coords % 64)
    chevron_dist = np.abs(chevron_x - 64) - (chevron_v * 1.0)
    chevron_cleat = (np.abs(chevron_dist) < 6) & (v >= 0.88) & mask_wheel
    albedo[chevron_cleat, 0] = 0.85
    albedo[chevron_cleat, 1] = 0.87
    albedo[chevron_cleat, 2] = 0.90

    albedo = np.clip(albedo, 0.0, 1.0)

    # 1.2 ORM MAP (R = AO, G = Roughness, B = Metallic)
    orm = np.zeros((size, size, 4), dtype=np.float32)
    orm[:, :, 3] = 1.0

    # Zone 1: Kapton Gold Foil
    orm[mask_kapton, 0] = 0.90 # AO
    orm[mask_kapton, 1] = 0.26 # Roughness
    orm[mask_kapton, 2] = 0.98 # Metallic
    orm[tape_lines, 0] = 0.50
    orm[tape_lines, 1] = 0.38
    orm[mask_kapton, 1] += (crinkle_fine[mask_kapton] * 0.08)

    # Zone 2: White Beta Cloth
    orm[mask_beta, 0] = 0.92 # AO
    orm[mask_beta, 1] = 0.85 # Roughness
    orm[mask_beta, 2] = 0.02 # Metallic (dielectric)
    orm[quilt_seam, 0] = 0.52
    orm[quilt_seam, 1] = 0.95
    orm[button_dots, 0] = 0.35
    orm[livery_orange | livery_cyan, 1] = 0.40

    # Zone 3: Chassis Matte Dark Gray
    orm[mask_chassis, 0] = 0.88 # AO
    orm[mask_chassis, 1] = 0.55 # Roughness
    orm[mask_chassis, 2] = 0.78 # Metallic
    orm[panel_lines, 0] = 0.40
    orm[panel_lines, 1] = 0.65
    orm[rivets, 1] = 0.25

    # Zone 4: Wheel Titanium Mesh & Tread
    orm[mask_wheel, 0] = 0.85 # AO
    orm[mask_wheel, 1] = 0.32 # Roughness
    orm[mask_wheel, 2] = 0.94 # Metallic
    orm[wire_weave, 1] = 0.28
    orm[mesh_openings, 0] = 0.40
    orm[mesh_openings, 1] = 0.55
    orm[chevron_cleat, 1] = 0.22

    orm = np.clip(orm, 0.0, 1.0)

    # 1.3 NORMAL MAP (Tangent-space OpenGL: R=X, G=Y, B=Z)
    normal = np.zeros((size, size, 4), dtype=np.float32)
    normal[:, :, 0] = 0.5 # Normal X flat
    normal[:, :, 1] = 0.5 # Normal Y flat
    normal[:, :, 2] = 1.0 # Normal Z up
    normal[:, :, 3] = 1.0

    # Zone 1: Crinkled foil normal relief
    nx_foil = np.gradient(foil_variation, axis=1) * 6.0
    ny_foil = np.gradient(foil_variation, axis=0) * 6.0
    normal[mask_kapton, 0] = 0.5 + nx_foil[mask_kapton]
    normal[mask_kapton, 1] = 0.5 - ny_foil[mask_kapton]

    # Zone 2: Quilted pillow relief and seams
    quilt_pillow = np.sin((x_coords % 64) / 64.0 * math.pi) * np.sin((y_coords % 64) / 64.0 * math.pi)
    nx_quilt = np.gradient(quilt_pillow, axis=1) * 3.5
    ny_quilt = np.gradient(quilt_pillow, axis=0) * 3.5
    normal[mask_beta, 0] = 0.5 + nx_quilt[mask_beta]
    normal[mask_beta, 1] = 0.5 - ny_quilt[mask_beta]

    # Zone 3: Panel seam bevels and rivets
    rivet_bump = np.zeros((size, size), dtype=np.float32)
    rivet_bump[rivets] = 0.6
    nx_rivet = np.gradient(rivet_bump, axis=1) * 4.0
    ny_rivet = np.gradient(rivet_bump, axis=0) * 4.0
    normal[mask_chassis, 0] = 0.5 + nx_rivet[mask_chassis]
    normal[mask_chassis, 1] = 0.5 - ny_rivet[mask_chassis]

    # Zone 4: Wire mesh weave and chevron tread cleat ridges
    cleat_bump = np.zeros((size, size), dtype=np.float32)
    cleat_bump[chevron_cleat] = 0.8
    cleat_bump[wire_weave] = 0.25
    nx_cleat = np.gradient(cleat_bump, axis=1) * 5.0
    ny_cleat = np.gradient(cleat_bump, axis=0) * 5.0
    normal[mask_wheel, 0] = 0.5 + nx_cleat[mask_wheel]
    normal[mask_wheel, 1] = 0.5 - ny_cleat[mask_wheel]

    # Re-normalize normal vector
    nz = np.sqrt(np.clip(1.0 - (normal[:, :, 0] - 0.5)**2 * 4.0 - (normal[:, :, 1] - 0.5)**2 * 4.0, 0.01, 1.0))
    normal[:, :, 2] = nz * 0.5 + 0.5
    normal = np.clip(normal, 0.0, 1.0)

    # 1.4 EMISSION MAP (LED headlights, instruments, status markers)
    emission = np.zeros((size, size, 4), dtype=np.float32)
    emission[:, :, 3] = 1.0

    # Headlight reflectors / lens bulbs (Zone 3, designated headlight patch)
    headlight_glow = (u >= 0.80) & (u < 0.95) & (v >= 0.52) & (v < 0.58)
    emission[headlight_glow, 0] = 1.0
    emission[headlight_glow, 1] = 0.98
    emission[headlight_glow, 2] = 0.90

    # Center console dashboard MFD telemetry display (Zone 3)
    dash_mfd = (u >= 0.45) & (u < 0.55) & (v >= 0.60) & (v < 0.68)
    dash_scanlines = (y_coords % 8 < 2) & dash_mfd
    emission[dash_scanlines, 0] = 0.10
    emission[dash_scanlines, 1] = 0.92
    emission[dash_scanlines, 2] = 0.75

    # Instrument status warning indicators
    dash_leds = (u >= 0.46) & (u < 0.48) & (v >= 0.69) & (v < 0.71)
    emission[dash_leds, 0] = 1.0
    emission[dash_leds, 1] = 0.35
    emission[dash_leds, 2] = 0.05

    # Rear safety taillights
    taillight_glow = (u >= 0.85) & (u < 0.95) & (v >= 0.62) & (v < 0.66)
    emission[taillight_glow, 0] = 1.0
    emission[taillight_glow, 1] = 0.05
    emission[taillight_glow, 2] = 0.05

    # Save texture maps
    maps = {
        "rover_albedo.png": albedo,
        "rover_orm.png": orm,
        "rover_normal.png": normal,
        "rover_emission.png": emission,
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
    """Sets up the PBR materials: mat_rover_main, mat_glass, mat_emissive."""
    materials = {}

    # 2.1 mat_rover_main (Atlas material driven by procedural PBR maps)
    mat_main = bpy.data.materials.new("mat_rover_main")
    mat_main.use_nodes = True
    nodes = mat_main.node_tree.nodes
    links = mat_main.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    albedo_img = bpy.data.images.load(tex_paths["rover_albedo.png"])
    orm_img = bpy.data.images.load(tex_paths["rover_orm.png"])
    orm_img.colorspace_settings.name = "Non-Color"
    normal_img = bpy.data.images.load(tex_paths["rover_normal.png"])
    normal_img.colorspace_settings.name = "Non-Color"
    emission_img = bpy.data.images.load(tex_paths["rover_emission.png"])

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
    materials["mat_rover_main"] = mat_main

    # 2.2 mat_glass (Camera lenses, dial faces)
    mat_glass = bpy.data.materials.new("mat_glass")
    mat_glass.use_nodes = True
    bsdf_glass = mat_glass.node_tree.nodes.get("Principled BSDF")
    bsdf_glass.inputs["Base Color"].default_value = (0.85, 0.92, 0.98, 1.0)
    bsdf_glass.inputs["Roughness"].default_value = 0.05
    bsdf_glass.inputs["Transmission Weight"].default_value = 0.92
    bsdf_glass.inputs["IOR"].default_value = 1.52
    materials["mat_glass"] = mat_glass

    # 2.3 mat_emissive (Headlights & high-intensity indicators)
    mat_emissive = bpy.data.materials.new("mat_emissive")
    mat_emissive.use_nodes = True
    bsdf_emissive = mat_emissive.node_tree.nodes.get("Principled BSDF")
    bsdf_emissive.inputs["Base Color"].default_value = (1.0, 0.98, 0.90, 1.0)
    bsdf_emissive.inputs["Emission Color"].default_value = (1.0, 0.98, 0.90, 1.0)
    bsdf_emissive.inputs["Emission Strength"].default_value = 6.0
    materials["mat_emissive"] = mat_emissive

    return materials

# -----------------------------------------------------------------------------
# 3. Component Builders
# -----------------------------------------------------------------------------

def build_chassis_and_suspension(materials):
    """
    Builds the tubular spaceframe chassis, roll bars, floorboard,
    undercarriage battery enclosure, and 4-corner double-wishbone suspension.
    """
    bm = bmesh.new()

    # UV bounds shortcuts
    uv_chassis = (0.05, 0.95, 0.52, 0.73)
    uv_kapton  = (0.05, 0.95, 0.02, 0.23)
    uv_floor   = (0.05, 0.95, 0.55, 0.70)

    # 3.1 Main Ladder Perimeter Rails
    # Left & Right outer rails (X = +/-0.65m)
    r_tube = 0.024
    for sign in [-1.0, 1.0]:
        x = sign * 0.65
        # Lower longitudinal rail (Z: -1.65 to +1.65)
        make_strut(bm, (x, 0.00, -1.65), (x, 0.00,  1.65), r_tube, uv_bounds=uv_chassis)
        # Upper side rail (Z: -1.30 to +1.30, Y = 0.22)
        make_strut(bm, (x, 0.22, -1.30), (x, 0.22,  1.30), r_tube, uv_bounds=uv_chassis)
        # Vertical riser struts between lower and upper rails
        for z_riser in [-1.30, -0.65, 0.00, 0.65, 1.30]:
            make_strut(bm, (x, 0.00, z_riser), (x, 0.22, z_riser), r_tube * 0.9, uv_bounds=uv_chassis)
        # Diagonal truss struts along side frame
        make_strut(bm, (x, 0.00, -1.30), (x, 0.22, -0.65), r_tube * 0.8, uv_bounds=uv_chassis)
        make_strut(bm, (x, 0.00,  0.65), (x, 0.22,  1.30), r_tube * 0.8, uv_bounds=uv_chassis)

    # 3.2 Transverse Crossmembers connecting Left & Right rails
    cross_zs = [-1.65, -1.25, -0.75, -0.20, 0.35, 0.85, 1.25, 1.65]
    for z_c in cross_zs:
        make_strut(bm, (-0.65, 0.00, z_c), (0.65, 0.00, z_c), r_tube, uv_bounds=uv_chassis)

    # Upper crossmembers across crew bay and cargo deck
    for z_c in [-1.30, 0.00, 0.85, 1.30]:
        make_strut(bm, (-0.65, 0.22, z_c), (0.65, 0.22, z_c), r_tube * 0.9, uv_bounds=uv_chassis)

    # 3.3 Central Spine Rails (X = +/-0.20m)
    for sign in [-1.0, 1.0]:
        x = sign * 0.20
        make_strut(bm, (x, -0.02, -1.55), (x, -0.02, 1.55), r_tube * 0.9, uv_bounds=uv_chassis)

    # 3.4 Front Bumper & Nudge Bar
    # Swept front bumper bow (Z = -1.75m)
    make_strut(bm, (-0.75, 0.08, -1.75), ( 0.75, 0.08, -1.75), r_tube * 1.1, uv_bounds=uv_chassis)
    make_strut(bm, (-0.75, 0.24, -1.68), ( 0.75, 0.24, -1.68), r_tube * 0.9, uv_bounds=uv_chassis)
    make_strut(bm, (-0.65, 0.00, -1.65), (-0.75, 0.08, -1.75), r_tube, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.65, 0.00, -1.65), ( 0.75, 0.08, -1.75), r_tube, uv_bounds=uv_chassis)
    make_strut(bm, (-0.75, 0.08, -1.75), (-0.75, 0.24, -1.68), r_tube * 0.9, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.75, 0.08, -1.75), ( 0.75, 0.24, -1.68), r_tube * 0.9, uv_bounds=uv_chassis)

    # Tow Shackles / Tie-down loops on front bumper
    for sign in [-1.0, 1.0]:
        add_cylinder(bm, (sign * 0.45, 0.08, -1.77), 0.035, 0.015, axis='Z', segments=12, uv_bounds=uv_chassis)

    # 3.5 Rear Bumper & Hitch Bar (Z = +1.75m)
    make_strut(bm, (-0.75, 0.12, 1.75), ( 0.75, 0.12, 1.75), r_tube * 1.1, uv_bounds=uv_chassis)
    make_strut(bm, (-0.65, 0.00, 1.65), (-0.75, 0.12, 1.75), r_tube, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.65, 0.00, 1.65), ( 0.75, 0.12, 1.75), r_tube, uv_bounds=uv_chassis)

    # 3.6 Floorboard Deck & Heel Rests
    # Crew compartment floor pan (Z: -0.80 to +0.35, Y = -0.02)
    add_box(bm, (0.0, -0.02, -0.22), (1.24, 0.025, 1.10), uv_bounds=uv_floor)
    # Angled front footwell ramp (Z: -0.95 to -0.80)
    add_box(bm, (0.0, 0.03, -0.88), (1.24, 0.02, 0.16),
            rot_mat=mat_rot_x(-25), uv_bounds=uv_floor)

    # 3.7 Underside Battery & Avionics Thermal Enclosure (Kapton Gold MLI)
    add_box(bm, (0.0, -0.16, -0.25), (1.10, 0.22, 1.30), uv_bounds=uv_kapton)

    # 3.8 Roll Cage / Overhead Safety Roll Bars
    # Main B-Pillar Roll Hoop (Z = 0.05m, Y up to 1.15m)
    make_strut(bm, (-0.65, 0.22, 0.05), (-0.65, 1.10, 0.05), r_tube * 1.1, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.65, 0.22, 0.05), ( 0.65, 1.10, 0.05), r_tube * 1.1, uv_bounds=uv_chassis)
    make_strut(bm, (-0.65, 1.10, 0.05), ( 0.65, 1.10, 0.05), r_tube * 1.1, uv_bounds=uv_chassis)

    # Front A-Pillar Roll Struts (sloping from brow down to chassis)
    make_strut(bm, (-0.65, 1.05, -0.65), (-0.65, 0.22, -1.05), r_tube, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.65, 1.05, -0.65), ( 0.65, 0.22, -1.05), r_tube, uv_bounds=uv_chassis)
    # Front overhead brow bar
    make_strut(bm, (-0.65, 1.05, -0.65), ( 0.65, 1.05, -0.65), r_tube, uv_bounds=uv_chassis)
    # Longitudinal top roof bars connecting A-hoop and B-hoop
    make_strut(bm, (-0.65, 1.05, -0.65), (-0.65, 1.10, 0.05), r_tube, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.65, 1.05, -0.65), ( 0.65, 1.10, 0.05), r_tube, uv_bounds=uv_chassis)

    # Rear diagonal support struts down to cargo deck
    make_strut(bm, (-0.65, 1.10, 0.05), (-0.65, 0.22, 0.95), r_tube, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.65, 1.10, 0.05), ( 0.65, 0.22, 0.95), r_tube, uv_bounds=uv_chassis)

    # Roll bar crew grab handles
    for sign in [-1.0, 1.0]:
        x = sign * 0.68
        make_strut(bm, (x, 0.85, -0.20), (x, 0.65, -0.20), 0.012, uv_bounds=uv_chassis)
        make_strut(bm, (x, 0.85, -0.20), (sign * 0.65, 0.85, -0.20), 0.012, uv_bounds=uv_chassis)
        make_strut(bm, (x, 0.65, -0.20), (sign * 0.65, 0.65, -0.20), 0.012, uv_bounds=uv_chassis)

    # 3.9 4-Corner Independent Suspension Wishbones & Shocks
    wheel_positions = [
        ("FL", -0.92, -0.15, -1.15),
        ("FR",  0.92, -0.15, -1.15),
        ("RL", -0.92, -0.15,  1.15),
        ("RR",  0.92, -0.15,  1.15),
    ]

    r_arm = 0.016
    for name, wx, wy, wz in wheel_positions:
        sign_x = -1.0 if wx < 0 else 1.0
        chassis_x = sign_x * 0.65
        knuckle_x = wx - sign_x * 0.06

        # Lower Wishbone A-arm (2 tubular legs meeting at knuckle)
        p_chassis_l1 = (chassis_x, -0.10, wz - 0.16)
        p_chassis_l2 = (chassis_x, -0.10, wz + 0.16)
        p_knuckle_low = (knuckle_x, wy - 0.08, wz)
        make_strut(bm, p_chassis_l1, p_knuckle_low, r_arm, uv_bounds=uv_chassis)
        make_strut(bm, p_chassis_l2, p_knuckle_low, r_arm, uv_bounds=uv_chassis)

        # Upper Wishbone A-arm
        p_chassis_u1 = (chassis_x, 0.08, wz - 0.12)
        p_chassis_u2 = (chassis_x, 0.08, wz + 0.12)
        p_knuckle_up  = (knuckle_x, wy + 0.10, wz)
        make_strut(bm, p_chassis_u1, p_knuckle_up, r_arm, uv_bounds=uv_chassis)
        make_strut(bm, p_chassis_u2, p_knuckle_up, r_arm, uv_bounds=uv_chassis)

        # Steering Knuckle / Spindle Upright
        make_strut(bm, p_knuckle_low, p_knuckle_up, r_tube * 1.3, uv_bounds=uv_chassis)

        # Coilover Spring / Damper Shock Strut
        p_shock_mount_chassis = (chassis_x, 0.18, wz)
        p_shock_mount_lower   = (knuckle_x + sign_x * -0.05, wy - 0.06, wz)
        # Damper body
        make_strut(bm, p_shock_mount_chassis, p_shock_mount_lower, 0.022, uv_bounds=uv_chassis)
        # Outer helical coil spring rings
        shock_mid = ((p_shock_mount_chassis[0] + p_shock_mount_lower[0]) * 0.5,
                     (p_shock_mount_chassis[1] + p_shock_mount_lower[1]) * 0.5,
                     wz)
        add_cylinder(bm, shock_mid, 0.034, 0.18, axis='Y', segments=12, uv_bounds=uv_chassis)

        # Drive Motor Housing (electric in-wheel traction motor)
        add_cylinder(bm, (wx - sign_x * 0.04, wy, wz), 0.085, 0.12, axis='X', segments=16, uv_bounds=uv_chassis)

    mesh = bpy.data.meshes.new("ChassisMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Chassis", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["mat_rover_main"])
    return obj

def build_cockpit_and_controls(materials):
    """
    Builds the dual astronaut bucket seats (with PLSS backpack channels),
    center control pedestal, T-handle joystick yoke, and instrument dashboard.
    """
    bm = bmesh.new()

    uv_beta    = (0.05, 0.95, 0.26, 0.48)
    uv_chassis = (0.05, 0.95, 0.52, 0.73)
    uv_kapton  = (0.05, 0.95, 0.02, 0.23)

    # 3.1 Dual Astronaut Bucket Seats
    seat_positions = [
        ("Driver",    -0.32, -0.15),
        ("Passenger",  0.32, -0.15),
    ]

    for name, sx, sz in seat_positions:
        # Seat tubular pedestal frame
        make_strut(bm, (sx - 0.18, 0.00, sz - 0.15), (sx - 0.18, 0.18, sz - 0.15), 0.016, uv_bounds=uv_chassis)
        make_strut(bm, (sx + 0.18, 0.00, sz - 0.15), (sx + 0.18, 0.18, sz - 0.15), 0.016, uv_bounds=uv_chassis)
        make_strut(bm, (sx - 0.18, 0.00, sz + 0.15), (sx - 0.18, 0.14, sz + 0.15), 0.016, uv_bounds=uv_chassis)
        make_strut(bm, (sx + 0.18, 0.00, sz + 0.15), (sx + 0.18, 0.14, sz + 0.15), 0.016, uv_bounds=uv_chassis)

        # Seat Cushion Pan (slanted back 6 degrees)
        add_box(bm, (sx, 0.18, sz), (0.46, 0.06, 0.42),
                rot_mat=mat_rot_x(6), uv_bounds=uv_beta)

        # Lateral thigh support bolsters
        for sign_b in [-1.0, 1.0]:
            bx = sx + sign_b * 0.21
            add_box(bm, (bx, 0.23, sz), (0.07, 0.08, 0.40),
                    rot_mat=mat_rot_x(6), uv_bounds=uv_beta)

        # Backrest (slanted back 18 degrees, height 0.65m)
        rot_back = mat_rot_x(18)
        # Left backrest section
        add_box(bm, (sx - 0.14, 0.50, sz + 0.12), (0.16, 0.62, 0.06),
                rot_mat=rot_back, uv_bounds=uv_beta)
        # Right backrest section
        add_box(bm, (sx + 0.14, 0.50, sz + 0.12), (0.16, 0.62, 0.06),
                rot_mat=rot_back, uv_bounds=uv_beta)
        # Recessed central channel for astronaut PLSS backpack
        add_box(bm, (sx, 0.48, sz + 0.15), (0.12, 0.58, 0.04),
                rot_mat=rot_back, uv_bounds=uv_chassis)

        # Crescent Headrest
        add_box(bm, (sx, 0.82, sz + 0.22), (0.32, 0.14, 0.07),
                rot_mat=rot_back, uv_bounds=uv_beta)

        # 4-Point Safety Restraint Harness Straps & Rotary Buckle
        # Shoulder straps
        add_box(bm, (sx - 0.10, 0.55, sz + 0.10), (0.05, 0.40, 0.015),
                rot_mat=rot_back, uv_bounds=uv_chassis)
        add_box(bm, (sx + 0.10, 0.55, sz + 0.10), (0.05, 0.40, 0.015),
                rot_mat=rot_back, uv_bounds=rot_back)
        # Central chest buckle disc
        add_cylinder(bm, (sx, 0.38, sz + 0.04), 0.035, 0.015, axis='Z', segments=12, uv_bounds=uv_chassis)

        # Footrest pedals on floorboard
        if name == "Driver":
            add_box(bm, (sx - 0.08, 0.06, -0.65), (0.07, 0.02, 0.12), rot_mat=mat_rot_x(-25), uv_bounds=uv_chassis)
            add_box(bm, (sx + 0.08, 0.06, -0.65), (0.07, 0.02, 0.12), rot_mat=mat_rot_x(-25), uv_bounds=uv_chassis)

    # 3.2 Center Control Pedestal & T-Handle Joystick Yoke
    # Pedestal column between seats (X = 0.0, Z = -0.32m)
    add_box(bm, (0.0, 0.20, -0.32), (0.16, 0.42, 0.22), uv_bounds=uv_chassis)

    # Control Yoke Shaft (tilted 20 degrees towards driver on port side)
    yoke_base = (0.0, 0.40, -0.30)
    yoke_grip = (-0.08, 0.58, -0.26)
    make_strut(bm, yoke_base, yoke_grip, 0.016, uv_bounds=uv_chassis)

    # T-Handle Crossbar Grip
    p_t1 = (-0.08 - 0.09, 0.58, -0.26)
    p_t2 = (-0.08 + 0.09, 0.58, -0.26)
    make_strut(bm, p_t1, p_t2, 0.018, uv_bounds=uv_chassis)
    # Thumb switch and trigger
    add_cylinder(bm, (-0.08, 0.59, -0.24), 0.012, 0.015, axis='Y', segments=8, uv_bounds=uv_chassis)

    # Handbrake Lever on Starboard side of console
    make_strut(bm, (0.09, 0.26, -0.36), (0.13, 0.48, -0.24), 0.012, uv_bounds=uv_chassis)
    add_cylinder(bm, (0.13, 0.48, -0.24), 0.018, 0.06, axis='Y', segments=10, uv_bounds=uv_chassis)

    # 3.3 Instrument Dashboard Console
    # Angled dashboard binnacle (Z = -0.50m, 45-degree slant)
    rot_dash = mat_rot_x(-45)
    add_box(bm, (0.0, 0.42, -0.50), (0.42, 0.22, 0.14), rot_mat=rot_dash, uv_bounds=uv_chassis)

    # Recessed MFD display bezel and screen
    add_box(bm, (0.0, 0.43, -0.51), (0.24, 0.14, 0.03), rot_mat=rot_dash, uv_bounds=uv_chassis)

    # Speedometer & Heading Gyro Dials
    add_cylinder(bm, (-0.14, 0.44, -0.48), 0.045, 0.02, axis='Y', segments=16, uv_bounds=uv_chassis)
    add_cylinder(bm, ( 0.14, 0.44, -0.48), 0.045, 0.02, axis='Y', segments=16, uv_bounds=uv_chassis)

    # Row of toggle switch guards & emergency stop button
    for sw_idx in range(5):
        sw_x = -0.12 + sw_idx * 0.06
        add_cylinder(bm, (sw_x, 0.36, -0.45), 0.006, 0.02, axis='Y', segments=8, uv_bounds=uv_chassis)

    # Big Red Emergency Stop Button
    add_cylinder(bm, (0.16, 0.36, -0.44), 0.022, 0.025, axis='Y', segments=12, uv_bounds=uv_chassis)

    mesh = bpy.data.meshes.new("CockpitMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Cockpit", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["mat_rover_main"])
    return obj

def build_mast_antenna_and_sensors(materials):
    """
    Builds the front mast, high-gain parabolic dish antenna with feed horn,
    optical camera sensor box with sun hood, and auxiliary omni antenna whip.
    """
    bm = bmesh.new()

    uv_dish    = (0.05, 0.95, 0.76, 0.98) # Titanium mesh reflector
    uv_kapton  = (0.05, 0.95, 0.02, 0.23) # Gold foil backing
    uv_chassis = (0.05, 0.95, 0.52, 0.73) # Metal mast
    uv_beta    = (0.05, 0.95, 0.26, 0.48) # Camera thermal blanket

    # 4.1 Forward Equipment Mast (X = -0.35m, Z = -1.50m)
    mast_base = (-0.35, 0.08, -1.50)
    mast_top  = (-0.35, 1.05, -1.48)
    make_strut(bm, mast_base, mast_top, 0.028, uv_bounds=uv_chassis)

    # Azimuth Slew Drive Collar & Elevation Yoke Knuckle
    add_cylinder(bm, (-0.35, 0.75, -1.48), 0.052, 0.12, axis='Y', segments=16, uv_bounds=uv_chassis)
    add_cylinder(bm, (-0.35, 1.05, -1.48), 0.045, 0.08, axis='X', segments=14, uv_bounds=uv_chassis)

    # Angled Extension Arm to Dish Hub (Y = 1.35m, Z = -1.42m)
    dish_center = (-0.35, 1.35, -1.42)
    make_strut(bm, mast_top, dish_center, 0.024, uv_bounds=uv_chassis)

    # 4.2 Parabolic Dish Reflector (Diameter 0.65m, depth 0.14m)
    # Tilted 25 degrees upward (+X rotation -25 deg) and 10 deg starboard
    rot_dish = mat_rot_y(10) @ mat_rot_x(-25)
    dish_radius = 0.325
    dish_depth  = 0.14
    add_paraboloid(bm, dish_center, dish_radius, dish_depth, rot_mat=rot_dish, segments=24, rings=8, uv_bounds=uv_dish)

    # Dish Rear Gold Foil Shell & Radial Stiffening Ribs
    add_box(bm, (dish_center[0], dish_center[1], dish_center[2] + 0.03), (0.24, 0.24, 0.04),
            rot_mat=rot_dish, uv_bounds=uv_kapton)
    for rib_idx in range(6):
        rib_ang = rib_idx * 60.0
        rib_rot = rot_dish @ mat_rot_z(rib_ang)
        p_rib_start = mathutils.Vector(dish_center)
        p_rib_end   = mathutils.Vector(dish_center) + rib_rot @ mathutils.Vector((0.0, dish_radius * 0.9, 0.04))
        make_strut(bm, p_rib_start, p_rib_end, 0.008, uv_bounds=uv_chassis)

    # Sub-Reflector Feed Horn Tripod & Focal Feed Element
    focal_pt = mathutils.Vector(dish_center) + rot_dish @ mathutils.Vector((0.0, 0.0, -0.28))
    for tripod_idx in range(3):
        t_ang = tripod_idx * 120.0
        p_rim = mathutils.Vector(dish_center) + rot_dish @ mathutils.Vector((
            dish_radius * 0.9 * math.cos(math.radians(t_ang)),
            dish_radius * 0.9 * math.sin(math.radians(t_ang)),
            dish_depth * 0.8
        ))
        make_strut(bm, p_rim, focal_pt, 0.006, uv_bounds=uv_chassis)

    # Feed horn cone at focal point
    add_cylinder(bm, focal_pt, 0.028, 0.04, axis='Z', segments=12, uv_bounds=uv_chassis)

    # 4.3 Color TV Camera / Optical Sensor Turret (X = +0.28m, Z = -1.55m)
    cam_base = (0.28, 0.12, -1.55)
    cam_top  = (0.28, 0.65, -1.55)
    make_strut(bm, cam_base, cam_top, 0.022, uv_bounds=uv_chassis)

    # Pan-Tilt Gimbal Base
    add_cylinder(bm, (0.28, 0.65, -1.55), 0.065, 0.05, axis='Y', segments=14, uv_bounds=uv_chassis)
    # Sensor Box (Beta cloth insulated with gold seams)
    add_box(bm, (0.28, 0.78, -1.55), (0.22, 0.18, 0.26), uv_bounds=uv_beta)

    # Sun Visor / Hood projecting forward
    add_box(bm, (0.28, 0.87, -1.70), (0.23, 0.02, 0.08), uv_bounds=uv_chassis)

    # Dual Stereo Camera Lens Barrels
    add_cylinder(bm, (0.23, 0.78, -1.69), 0.032, 0.04, axis='Z', segments=16, uv_bounds=uv_chassis)
    add_cylinder(bm, (0.33, 0.78, -1.69), 0.032, 0.04, axis='Z', segments=16, uv_bounds=uv_chassis)

    # Laser Rangefinder / Optical Tracker Center Aperture
    add_cylinder(bm, (0.28, 0.72, -1.69), 0.018, 0.03, axis='Z', segments=12, uv_bounds=uv_chassis)

    # Sensor box cooling radiator fins on top
    for fin_idx in range(4):
        fz = -1.62 + fin_idx * 0.05
        add_box(bm, (0.28, 0.89, fz), (0.18, 0.03, 0.008), uv_bounds=uv_chassis)

    # 4.4 Auxiliary Omni Whip Antenna
    omni_base = (-0.48, 0.12, -1.45)
    omni_top  = (-0.48, 1.85, -1.45)
    make_strut(bm, omni_base, omni_top, 0.008, 0.003, segments=8, uv_bounds=uv_chassis)
    # Tip ball
    add_cylinder(bm, omni_top, 0.015, 0.02, axis='Y', segments=8, uv_bounds=uv_chassis)

    mesh = bpy.data.meshes.new("AntennaAndSensorsMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("AntennaAndSensors", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["mat_rover_main"])
    return obj

def build_cargo_bay_and_tools(materials):
    """
    Builds the rear cargo utility deck, sealed sample return containers,
    equipment/avionics tool storage boxes, core drill tools, and auxiliary power module.
    """
    bm = bmesh.new()

    uv_chassis = (0.05, 0.95, 0.52, 0.73)
    uv_kapton  = (0.05, 0.95, 0.02, 0.23)
    uv_beta    = (0.05, 0.95, 0.26, 0.48)

    # 5.1 Cargo Platform Utility Deck & Perimeter Rail
    # Slotted cargo deck plate (Z: 0.55 to 1.65, Y = 0.14)
    add_box(bm, (0.0, 0.14, 1.10), (1.24, 0.025, 1.10), uv_bounds=uv_chassis)

    # Cargo Rack Railing (height Y = 0.36m)
    r_rail = 0.016
    # Left & Right top rails
    make_strut(bm, (-0.62, 0.36, 0.55), (-0.62, 0.36, 1.65), r_rail, uv_bounds=uv_chassis)
    make_strut(bm, ( 0.62, 0.36, 0.55), ( 0.62, 0.36, 1.65), r_rail, uv_bounds=uv_chassis)
    # Rear crossbar rail
    make_strut(bm, (-0.62, 0.36, 1.65), ( 0.62, 0.36, 1.65), r_rail, uv_bounds=uv_chassis)
    # Vertical stanchion posts
    for z_post in [0.55, 0.92, 1.28, 1.65]:
        make_strut(bm, (-0.62, 0.14, z_post), (-0.62, 0.36, z_post), r_rail, uv_bounds=uv_chassis)
        make_strut(bm, ( 0.62, 0.14, z_post), ( 0.62, 0.36, z_post), r_rail, uv_bounds=uv_chassis)

    # 5.2 Sealed Lunar Sample Return Containers (SRC)
    # Container 1 (Port side, cylindrical pressure vessel with latches)
    src_pos1 = (-0.32, 0.32, 0.85)
    add_cylinder(bm, src_pos1, 0.12, 0.32, axis='Y', segments=20, uv_bounds=uv_kapton)
    # Domed lid
    add_cylinder(bm, (src_pos1[0], src_pos1[1] + 0.17, src_pos1[2]), 0.125, 0.03, axis='Y', segments=20, uv_bounds=uv_chassis)
    # Top carry handle
    make_strut(bm, (src_pos1[0] - 0.06, src_pos1[1] + 0.19, src_pos1[2]),
                   (src_pos1[0] + 0.06, src_pos1[1] + 0.19, src_pos1[2]), 0.010, uv_bounds=uv_chassis)

    # Container 2 (Center-starboard)
    src_pos2 = (-0.02, 0.30, 0.90)
    add_cylinder(bm, src_pos2, 0.10, 0.28, axis='Y', segments=18, uv_bounds=uv_kapton)
    add_cylinder(bm, (src_pos2[0], src_pos2[1] + 0.15, src_pos2[2]), 0.105, 0.03, axis='Y', segments=18, uv_bounds=uv_chassis)

    # 5.3 Heavy-Duty Equipment & Tool Storage Box (Starboard rear)
    box_pos = (0.32, 0.28, 0.95)
    add_box(bm, box_pos, (0.36, 0.26, 0.48), uv_bounds=uv_chassis)
    # Box lid with seal lip
    add_box(bm, (box_pos[0], box_pos[1] + 0.14, box_pos[2]), (0.38, 0.03, 0.50), uv_bounds=uv_chassis)
    # Cooling radiator fins on box lid
    for bfin in range(5):
        bf_z = box_pos[2] - 0.18 + bfin * 0.09
        add_box(bm, (box_pos[0], box_pos[1] + 0.17, bf_z), (0.28, 0.03, 0.008), uv_bounds=uv_chassis)
    # Toggle draw latches
    add_box(bm, (box_pos[0] - 0.19, box_pos[1] + 0.06, box_pos[2] - 0.12), (0.015, 0.05, 0.03), uv_bounds=uv_chassis)
    add_box(bm, (box_pos[0] - 0.19, box_pos[1] + 0.06, box_pos[2] + 0.12), (0.015, 0.05, 0.03), uv_bounds=uv_chassis)

    # 5.4 Geological Sampling Tools Rack (Port side railing)
    # Core Drill Assembly (slender motor + long fluted tube)
    drill_start = (-0.56, 0.38, 0.65)
    drill_end   = (-0.56, 0.38, 1.45)
    make_strut(bm, drill_start, drill_end, 0.016, uv_bounds=uv_chassis)
    add_cylinder(bm, drill_start, 0.038, 0.12, axis='Z', segments=14, uv_bounds=uv_chassis)

    # Geology Rock Hammer
    make_strut(bm, (-0.46, 0.42, 0.70), (-0.46, 0.42, 1.10), 0.010, uv_bounds=uv_chassis)
    add_box(bm, (-0.46, 0.42, 0.70), (0.03, 0.04, 0.14), uv_bounds=uv_chassis)

    # Lunar Surface Sampling Scoop
    make_strut(bm, (-0.42, 0.38, 0.60), (-0.42, 0.38, 1.35), 0.012, uv_bounds=uv_chassis)
    add_box(bm, (-0.42, 0.38, 1.35), (0.08, 0.05, 0.09), uv_bounds=uv_chassis)

    # Regolith Tongs / Core Tube Clamp
    make_strut(bm, (-0.38, 0.40, 0.75), (-0.38, 0.40, 1.25), 0.008, uv_bounds=uv_chassis)

    # 5.5 Rear Power Module & Space Thermal Radiator (Z: 1.40 to 1.62)
    add_box(bm, (0.0, 0.26, 1.48), (0.80, 0.22, 0.26), uv_bounds=uv_beta)
    # Mirror radiator top surface
    add_box(bm, (0.0, 0.38, 1.48), (0.76, 0.015, 0.24), uv_bounds=uv_chassis)

    mesh = bpy.data.meshes.new("CargoBayMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("CargoBay", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["mat_rover_main"])
    return obj

def build_single_wheel(materials, name, wx, wy, wz):
    """
    Builds an independent lunar surface wheel object (Apollo/Artemis open-mesh style):
    - Cylindrical wire-mesh tire ring (radius 0.40m, width 0.24m)
    - 20 V-shaped chevron traction tread cleats arrayed around circumference
    - Spun titanium inner bump-stop drum ring
    - Anodized gold/silver central hub disc with 6 lightening cutouts & planetary gear casing
    - Arched dust mudguard / fender hovering over wheel with trailing beta-cloth mudflap
    - Vertex group named after wheel (Wheel_FL, Wheel_FR, etc.)
    """
    bm = bmesh.new()

    uv_wheel   = (0.05, 0.95, 0.76, 0.98) # Titanium mesh & chevron cleats
    uv_kapton  = (0.05, 0.95, 0.02, 0.23) # Gold hub cap
    uv_chassis = (0.05, 0.95, 0.52, 0.73) # Metal hub & fender
    uv_beta    = (0.05, 0.95, 0.26, 0.48) # Mudflap

    sign_x = -1.0 if wx < 0 else 1.0

    r_outer = 0.40
    r_inner = 0.27
    w_tire  = 0.24
    segments = 32

    # 6.1 Outer Woven Wire-Mesh Tire Barrel
    add_cylinder(bm, (wx, wy, wz), r_outer, w_tire, axis='X', segments=segments, uv_bounds=uv_wheel)

    # 6.2 Chevron Tread Traction Cleats around outer perimeter
    num_cleats = 20
    for c_idx in range(num_cleats):
        ang = (c_idx / float(num_cleats)) * 2.0 * math.pi
        c_y = wy + r_outer * math.cos(ang)
        c_z = wz + r_outer * math.sin(ang)

        # Angled V-shaped chevron strips: left wing and right wing
        rot_ang_x = math.atan2(math.sin(ang), math.cos(ang))
        # Wing 1
        p_c1_start = (wx - 0.10, c_y, c_z)
        p_c1_mid   = (wx, wy + (r_outer + 0.015) * math.cos(ang + 0.08), wz + (r_outer + 0.015) * math.sin(ang + 0.08))
        make_strut(bm, p_c1_start, p_c1_mid, 0.007, uv_bounds=uv_wheel)
        # Wing 2
        p_c2_end   = (wx + 0.10, c_y, c_z)
        make_strut(bm, p_c1_mid, p_c2_end, 0.007, uv_bounds=uv_wheel)

    # 6.3 Inner Concentric Titanium Bump-Stop Drum
    add_cylinder(bm, (wx, wy, wz), r_inner, w_tire * 0.75, axis='X', segments=20, uv_bounds=uv_chassis)

    # 6.4 Wheel Hub & Planetary Gear Reducer Housing
    outboard_x = wx + sign_x * (w_tire * 0.5 + 0.01)
    # Dished outboard hub disc
    add_cylinder(bm, (outboard_x, wy, wz), 0.22, 0.02, axis='X', segments=20, uv_bounds=uv_chassis)
    # 6 Circular Lightening Holes on hub disc
    for h_idx in range(6):
        h_ang = h_idx * (2.0 * math.pi / 6.0)
        hx = outboard_x + sign_x * 0.005
        hy = wy + 0.14 * math.cos(h_ang)
        hz = wz + 0.14 * math.sin(h_ang)
        add_cylinder(bm, (hx, hy, hz), 0.035, 0.025, axis='X', segments=10, uv_bounds=uv_chassis)

    # Gold Anodized Central Hub Cap
    add_cylinder(bm, (outboard_x + sign_x * 0.025, wy, wz), 0.085, 0.04, axis='X', segments=16, uv_bounds=uv_kapton)
    # 6 Lug Nuts around hub center
    for nut_idx in range(6):
        n_ang = nut_idx * (2.0 * math.pi / 6.0)
        ny = wy + 0.06 * math.cos(n_ang)
        nz = wz + 0.06 * math.sin(n_ang)
        add_cylinder(bm, (outboard_x + sign_x * 0.048, ny, nz), 0.010, 0.015, axis='X', segments=8, uv_bounds=uv_chassis)

    # 6.5 Arched Dust Mudguard / Fender & Flap
    fender_r = 0.46
    fender_w = 0.28
    # Arch over top of tire
    fender_pts = []
    # from -30 deg (forward) to +50 deg (rear)
    num_f_segs = 8
    for f_i in range(num_f_segs + 1):
        deg = -30.0 + f_i * (80.0 / num_f_segs)
        rad = math.radians(deg)
        fy = wy + fender_r * math.cos(rad)
        fz = wz + fender_r * math.sin(rad)
        fender_pts.append((fy, fz))

    for f_i in range(num_f_segs):
        p1_y, p1_z = fender_pts[f_i]
        p2_y, p2_z = fender_pts[f_i + 1]
        mid_y = (p1_y + p2_y) * 0.5
        mid_z = (p1_z + p2_z) * 0.5
        seg_len = math.sqrt((p2_y - p1_y)**2 + (p2_z - p1_z)**2)
        ang_seg = math.atan2(p2_z - p1_z, p2_y - p1_y)
        rot_seg = mat_rot_x(math.degrees(ang_seg))
        add_box(bm, (wx, mid_y, mid_z), (fender_w, 0.015, seg_len * 1.05), rot_mat=rot_seg, uv_bounds=uv_chassis)

    # Rear Flexible Mudflap at trailing edge of fender
    rear_fy, rear_fz = fender_pts[-1]
    add_box(bm, (wx, rear_fy - 0.08, rear_fz + 0.02), (fender_w * 0.95, 0.16, 0.012),
            rot_mat=mat_rot_x(15), uv_bounds=uv_beta)

    # Fender tubular mounting bracket to suspension upright
    make_strut(bm, (wx - sign_x * 0.08, wy + 0.10, wz), (wx, wy + fender_r - 0.02, wz), 0.014, uv_bounds=uv_chassis)

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["mat_rover_main"])

    # Create vertex group named after this wheel so it can be isolated as a submesh
    vg = obj.vertex_groups.new(name=name)
    all_indices = list(range(len(obj.data.vertices)))
    vg.add(all_indices, 1.0, 'REPLACE')

    return obj

def build_headlights_and_lighting(materials):
    """
    Builds the dual front high-output LED headlights with protective bezels
    and rear red safety position markers.
    """
    bm = bmesh.new()

    uv_chassis = (0.05, 0.95, 0.52, 0.73)

    # Left & Right Headlight Assemblies
    headlight_positions = [
        ("Left",  -0.55, 0.05, -1.68),
        ("Right",  0.55, 0.05, -1.68),
    ]

    for name, hx, hy, hz in headlight_positions:
        # Cylindrical lamp housing
        add_cylinder(bm, (hx, hy, hz), 0.065, 0.08, axis='Z', segments=16, uv_bounds=uv_chassis)
        # Mounting bracket to front bumper
        sign_h = -1.0 if hx < 0 else 1.0
        make_strut(bm, (sign_h * 0.65, 0.00, -1.65), (hx, hy, hz), 0.014, uv_bounds=uv_chassis)
        # Protective wire mesh guard ring
        add_cylinder(bm, (hx, hy, hz - 0.042), 0.068, 0.015, axis='Z', segments=16, uv_bounds=uv_chassis)
        # Headlight convex front bulb face
        add_cylinder(bm, (hx, hy, hz - 0.040), 0.058, 0.010, axis='Z', segments=16, uv_bounds=uv_chassis)

    # Rear Red Marker Lights on rear bumper corners
    for sign_r in [-1.0, 1.0]:
        rx = sign_r * 0.65
        add_cylinder(bm, (rx, 0.08, 1.70), 0.035, 0.03, axis='Z', segments=12, uv_bounds=uv_chassis)

    mesh = bpy.data.meshes.new("LightingMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Lighting", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(materials["mat_rover_main"])
    return obj

# -----------------------------------------------------------------------------
# 4. Attachment Sockets (Empties)
# -----------------------------------------------------------------------------
def build_sockets():
    """
    Creates glTF attachment sockets (Empties):
    - SOCKET_headlight_L, SOCKET_headlight_R
    - SOCKET_cargo
    - SOCKET_seat_driver, SOCKET_seat_passenger
    - SOCKET_wheel_FL, SOCKET_wheel_FR, SOCKET_wheel_RL, SOCKET_wheel_RR
    - SOCKET_antenna, SOCKET_cam, SOCKET_chase_cam
    """
    socket_defs = [
        ("SOCKET_headlight_L",    (-0.55, 0.05, -1.65), (0.0, 0.0, 0.0)),
        ("SOCKET_headlight_R",    ( 0.55, 0.05, -1.65), (0.0, 0.0, 0.0)),
        ("SOCKET_cargo",          ( 0.00, 0.35,  1.15), (0.0, 0.0, 0.0)),
        ("SOCKET_seat_driver",    (-0.32, 0.25, -0.15), (0.0, 0.0, 0.0)),
        ("SOCKET_seat_passenger", ( 0.32, 0.25, -0.15), (0.0, 0.0, 0.0)),
        ("SOCKET_wheel_FL",       (-0.92, -0.15, -1.15), (0.0, 0.0, 0.0)),
        ("SOCKET_wheel_FR",       ( 0.92, -0.15, -1.15), (0.0, 0.0, 0.0)),
        ("SOCKET_wheel_RL",       (-0.92, -0.15,  1.15), (0.0, 0.0, 0.0)),
        ("SOCKET_wheel_RR",       ( 0.92, -0.15,  1.15), (0.0, 0.0, 0.0)),
        ("SOCKET_antenna",        (-0.35, 1.45, -1.50), (0.0, 0.0, 0.0)),
        ("SOCKET_cam",            ( 0.28, 0.85, -1.55), (0.0, 0.0, 0.0)),
        ("SOCKET_chase_cam",      ( 0.00, 1.80,  3.80), (0.0, 0.0, 0.0)),
    ]

    sockets = []
    for name, loc, rot_deg in socket_defs:
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_type = 'ARROWS'
        empty.empty_display_size = 0.25
        empty.location = loc
        empty.rotation_euler = (math.radians(rot_deg[0]),
                                math.radians(rot_deg[1]),
                                math.radians(rot_deg[2]))
        bpy.context.scene.collection.objects.link(empty)
        sockets.append(empty)
        print(f"Created socket: {name} at {loc}")

    return sockets

# -----------------------------------------------------------------------------
# 5. Collision Shape (COL_chassis Convex Hull)
# -----------------------------------------------------------------------------
def build_collision_mesh():
    """
    Builds the simplified convex hull collision shape COL_chassis
    enveloping the chassis, roll bars, bumpers, and underside clearance.
    """
    bm = bmesh.new()

    envelope_pts = [
        # Front Bumper
        (-0.75, 0.10, -1.75),
        ( 0.75, 0.10, -1.75),
        (-0.55, 0.35, -1.65),
        ( 0.55, 0.35, -1.65),
        (-0.50, -0.20, -1.60),
        ( 0.50, -0.20, -1.60),

        # Rear Bumper & Rack
        (-0.75, 0.12, 1.75),
        ( 0.75, 0.12, 1.75),
        (-0.62, 0.40, 1.65),
        ( 0.62, 0.40, 1.65),
        (-0.50, -0.20, 1.60),
        ( 0.50, -0.20, 1.60),

        # Mid Chassis Sides
        (-0.70, 0.15, 0.00),
        ( 0.70, 0.15, 0.00),
        (-0.60, -0.25, 0.00),
        ( 0.60, -0.25, 0.00),

        # Roll Cage Top Hoops
        (-0.65, 1.15,  0.08),
        ( 0.65, 1.15,  0.08),
        (-0.65, 1.05, -0.65),
        ( 0.65, 1.05, -0.65),

        # Wheel suspension inboard clearance
        (-0.85, -0.15, -1.15),
        ( 0.85, -0.15, -1.15),
        (-0.85, -0.15,  1.15),
        ( 0.85, -0.15,  1.15),
    ]

    for p in envelope_pts:
        bm.verts.new(p)

    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("COL_chassisMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("COL_chassis", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True

    tri_count = sum(len(f.vertices) - 2 for f in obj.data.polygons)
    print(f"COL_chassis created: {tri_count} triangles")
    return obj

# -----------------------------------------------------------------------------
# 6. LOD Generation (Target LOD0: 10k-18k tris, LOD1: 2k-4k tris)
# -----------------------------------------------------------------------------
def build_lods(components):
    """
    Combines visual components into Rover_LOD0 (target 10,000 - 18,000 tris)
    and creates decimated Rover_LOD1 (target 2,000 - 4,000 tris).
    """
    bpy.ops.object.select_all(action='DESELECT')
    for c in components:
        c.select_set(True)
    bpy.context.view_layer.objects.active = components[0]
    bpy.ops.object.duplicate()
    lod0_obj = bpy.context.active_object
    bpy.ops.object.join()
    lod0_obj.name = "Rover_LOD0"
    lod0_obj.data.name = "Rover_LOD0_Mesh"

    lod0_tris = sum(len(f.vertices) - 2 for f in lod0_obj.data.polygons)
    print(f"Initial Rover_LOD0 triangle count: {lod0_tris}")

    # Subdivide or decimate to strictly guarantee 10,000 - 18,000 range
    if lod0_tris < 10000:
        mod_sub = lod0_obj.modifiers.new("Subsurf", "SUBSURF")
        mod_sub.levels = 1
        bpy.context.view_layer.objects.active = lod0_obj
        bpy.ops.object.modifier_apply(modifier="Subsurf")
        lod0_tris = sum(len(f.vertices) - 2 for f in lod0_obj.data.polygons)
        print(f"Subdivided Rover_LOD0 triangle count: {lod0_tris}")

    if lod0_tris > 18000:
        ratio = 15000.0 / float(lod0_tris)
        mod_dec = lod0_obj.modifiers.new("Decimate", "DECIMATE")
        mod_dec.ratio = ratio
        bpy.context.view_layer.objects.active = lod0_obj
        bpy.ops.object.modifier_apply(modifier="Decimate")
        lod0_tris = sum(len(f.vertices) - 2 for f in lod0_obj.data.polygons)
        print(f"Calibrated Rover_LOD0 triangle count: {lod0_tris}")

    lod0_obj.data.validate(verbose=False)
    lod0_obj.data.update()
    print(f"FINAL Rover_LOD0: {lod0_tris} triangles (Budget: 10,000 - 18,000)")
    assert 10000 <= lod0_tris <= 18000, f"LOD0 out of budget: {lod0_tris}"

    # Generate LOD1 (Budget: 2,000 - 4,000 tris)
    bpy.ops.object.select_all(action='DESELECT')
    lod0_obj.select_set(True)
    bpy.context.view_layer.objects.active = lod0_obj
    bpy.ops.object.duplicate()
    lod1_obj = bpy.context.active_object
    lod1_obj.name = "Rover_LOD1"
    lod1_obj.data.name = "Rover_LOD1_Mesh"

    target_l1 = 3000.0
    ratio_l1 = target_l1 / float(lod0_tris)
    mod_dec1 = lod1_obj.modifiers.new("Decimate", "DECIMATE")
    mod_dec1.ratio = ratio_l1
    bpy.context.view_layer.objects.active = lod1_obj
    bpy.ops.object.modifier_apply(modifier="Decimate")

    lod1_obj.data.validate(verbose=False)
    lod1_obj.data.update()

    lod1_tris = sum(len(f.vertices) - 2 for f in lod1_obj.data.polygons)
    print(f"FINAL Rover_LOD1: {lod1_tris} triangles (Budget: 2,000 - 4,000)")
    assert 2000 <= lod1_tris <= 4000, f"LOD1 out of budget: {lod1_tris}"

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
    p1_data.energy = 32000.0
    p1_data.color = (1.0, 0.96, 0.92)
    p1 = bpy.data.objects.new("KeyLight", p1_data)
    p1.location = (-6.0, 6.0, -7.0)
    bpy.context.scene.collection.objects.link(p1)
    lights.append(p1)

    # Fill Light (Upper-Front-Right)
    p2_data = bpy.data.lights.new("FillLight", type='POINT')
    p2_data.energy = 20000.0
    p2_data.color = (0.75, 0.85, 1.0)
    p2 = bpy.data.objects.new("FillLight", p2_data)
    p2.location = (7.0, 5.0, -5.0)
    bpy.context.scene.collection.objects.link(p2)
    lights.append(p2)

    # Ground Bounce Fill (Illuminates wheels, undercarriage, wishbones)
    p3_data = bpy.data.lights.new("GroundBounceLight", type='POINT')
    p3_data.energy = 22000.0
    p3_data.color = (0.80, 0.85, 0.95)
    p3 = bpy.data.objects.new("GroundBounceLight", p3_data)
    p3.location = (0.0, -4.0, 0.0)
    bpy.context.scene.collection.objects.link(p3)
    lights.append(p3)

    # Rim Light (Upper-Rear)
    p4_data = bpy.data.lights.new("RimLight", type='POINT')
    p4_data.energy = 26000.0
    p4_data.color = (0.95, 0.95, 1.0)
    p4 = bpy.data.objects.new("RimLight", p4_data)
    p4.location = (0.0, 7.0, 7.0)
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
    world.use_nodes = True
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
         mathutils.Vector((0.0, 0.8, -6.0)),
         mathutils.Vector((0.0, 0.2, 0.0))),

        ("Side Profile", PREVIEW_SIDE_PATH,
         mathutils.Vector((-6.5, 0.8, 0.0)),
         mathutils.Vector((0.0, 0.2, 0.0))),

        ("Top View", PREVIEW_TOP_PATH,
         mathutils.Vector((-0.1, 7.5, 0.1)),
         mathutils.Vector((0.0, 0.0, 0.0))),

        ("Isometric Preview", PREVIEW_OUTPUT_PATH,
         mathutils.Vector((-4.8, 3.2, -5.2)),
         mathutils.Vector((0.0, 0.2, 0.0))),
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
    print("=== Building Solar Horizon Lunar Surface Rover (WP 3.4) ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # 1. Generate procedural textures
    tex_paths = generate_procedural_textures(TEXTURES_DIR, size=2048)

    # 2. Setup materials
    materials = setup_materials(tex_paths)

    # 3. Build geometry components
    print("Building modular rover components...")
    chassis = build_chassis_and_suspension(materials)
    cockpit = build_cockpit_and_controls(materials)
    antenna = build_mast_antenna_and_sensors(materials)
    cargo   = build_cargo_bay_and_tools(materials)
    lights  = build_headlights_and_lighting(materials)

    # 4 independent lunar wheels
    wheel_fl = build_single_wheel(materials, "Wheel_FL", -0.92, -0.15, -1.15)
    wheel_fr = build_single_wheel(materials, "Wheel_FR",  0.92, -0.15, -1.15)
    wheel_rl = build_single_wheel(materials, "Wheel_RL", -0.92, -0.15,  1.15)
    wheel_rr = build_single_wheel(materials, "Wheel_RR",  0.92, -0.15,  1.15)

    components = [
        chassis,
        cockpit,
        antenna,
        cargo,
        lights,
        wheel_fl,
        wheel_fr,
        wheel_rl,
        wheel_rr,
    ]

    # 4. Attachment Sockets
    print("Creating attachment sockets...")
    sockets = build_sockets()

    # 5. Collision Shape (COL_chassis)
    print("Building collision mesh COL_chassis...")
    col_chassis = build_collision_mesh()

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
