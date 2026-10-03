import math
import os
import numpy as np

models_dir = "/working_dir/c_498f6079368ce6ce/solar_horizon_godot/assets/models"
os.makedirs(models_dir, exist_ok=True)

def write_obj_with_materials(filepath, vertices, faces, normals=None, uvs=None, name="Model"):
    with open(filepath, "w") as f:
        f.write(f"# Solar Horizon Hyper-Realistic 3D Asset: {name}\n")
        f.write(f"# Vertices: {len(vertices)}, Faces: {len(faces)}\n\n")
        
        for v in vertices:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        f.write("\n")
        
        if uvs is not None and len(uvs) == len(vertices):
            for uv in uvs:
                f.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
            f.write("\n")
            
        if normals is not None and len(normals) == len(vertices):
            for n in normals:
                f.write(f"vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}\n")
            f.write("\n")
            
        f.write(f"g {name}\n")
        f.write("s 1\n")
        has_vn = normals is not None and len(normals) == len(vertices)
        has_vt = uvs is not None and len(uvs) == len(vertices)
        
        for tri in faces:
            # tri can have material tag as 4th element or just 3 vertex indices
            v0, v1, v2 = tri[0] + 1, tri[1] + 1, tri[2] + 1
            if has_vn and has_vt:
                f.write(f"f {v0}/{v0}/{v0} {v1}/{v1}/{v1} {v2}/{v2}/{v2}\n")
            elif has_vn:
                f.write(f"f {v0}//{v0} {v1}//{v1} {v2}//{v2}\n")
            else:
                f.write(f"f {v0} {v1} {v2}\n")
                
    print(f"Generated {filepath}: {len(vertices)} verts, {len(faces)} faces.")

# -------------------------------------------------------------
# Primitive Generators with High Subdivision
# -------------------------------------------------------------
def make_cylinder(r, length, rings=16, sectors=36, axis='z', center=(0,0,0)):
    verts, faces = [], []
    cx, cy, cz = center
    for r_i in range(rings + 1):
        t = r_i / float(rings)
        pos = -length / 2.0 + t * length
        for s in range(sectors):
            th = (s / float(sectors)) * 2.0 * math.pi
            c_t, s_t = math.cos(th), math.sin(th)
            if axis == 'z':
                x, y, z = cx + r * c_t, cy + r * s_t, cz + pos
            elif axis == 'x':
                x, y, z = cx + pos, cy + r * c_t, cz + r * s_t
            else:
                x, y, z = cx + r * c_t, cy + pos, cz + r * s_t
            verts.append((x, y, z))
            
    for r_i in range(rings):
        for s in range(sectors):
            s_next = (s + 1) % sectors
            v00 = r_i * sectors + s
            v01 = r_i * sectors + s_next
            v10 = (r_i + 1) * sectors + s
            v11 = (r_i + 1) * sectors + s_next
            faces.append((v00, v10, v11))
            faces.append((v00, v11, v01))
            
    # Caps
    c0 = (cx, cy, cz - length/2.0) if axis == 'z' else ((cx - length/2.0, cy, cz) if axis == 'x' else (cx, cy - length/2.0, cz))
    c1 = (cx, cy, cz + length/2.0) if axis == 'z' else ((cx + length/2.0, cy, cz) if axis == 'x' else (cx, cy + length/2.0, cz))
    i_c0, i_c1 = len(verts), len(verts) + 1
    verts.extend([c0, c1])
    for s in range(sectors):
        s_next = (s + 1) % sectors
        faces.append((i_c0, s_next, s))
        top_curr = rings * sectors + s
        top_next = rings * sectors + s_next
        faces.append((i_c1, top_curr, top_next))
    return verts, faces

def make_box(size, center=(0,0,0)):
    sx, sy, sz = size[0]/2.0, size[1]/2.0, size[2]/2.0
    cx, cy, cz = center
    verts = [
        (cx - sx, cy - sy, cz - sz), (cx + sx, cy - sy, cz - sz),
        (cx + sx, cy + sy, cz - sz), (cx - sx, cy + sy, cz - sz),
        (cx - sx, cy - sy, cz + sz), (cx + sx, cy - sy, cz + sz),
        (cx + sx, cy + sy, cz + sz), (cx - sx, cy + sy, cz + sz),
    ]
    faces = [
        (0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7),
        (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5),
        (3, 7, 6), (3, 6, 2), (0, 1, 5), (0, 5, 4)
    ]
    return verts, faces

def make_torus(r_major, r_minor, segs_maj=48, segs_min=24, center=(0,0,0), axis='z'):
    verts, faces = [], []
    cx, cy, cz = center
    for i in range(segs_maj):
        phi = (i / float(segs_maj)) * 2.0 * math.pi
        cp, sp = math.cos(phi), math.sin(phi)
        for j in range(segs_min):
            theta = (j / float(segs_min)) * 2.0 * math.pi
            r_curr = r_major + r_minor * math.cos(theta)
            if axis == 'z':
                x = cx + r_curr * cp
                y = cy + r_curr * sp
                z = cz + r_minor * math.sin(theta)
            elif axis == 'y':
                x = cx + r_curr * cp
                y = cy + r_minor * math.sin(theta)
                z = cz + r_curr * sp
            else:
                x = cx + r_minor * math.sin(theta)
                y = cy + r_curr * cp
                z = cz + r_curr * sp
            verts.append((x, y, z))
            
    for i in range(segs_maj):
        i_next = (i + 1) % segs_maj
        for j in range(segs_min):
            j_next = (j + 1) % segs_min
            v00 = i * segs_min + j
            v01 = i * segs_min + j_next
            v10 = i_next * segs_min + j
            v11 = i_next * segs_min + j_next
            faces.append((v00, v10, v11))
            faces.append((v00, v11, v01))
    return verts, faces

def make_parabolic_dish(radius, depth, rings=12, sectors=32, center=(0,0,0), axis='z'):
    verts, faces = [], []
    cx, cy, cz = center
    verts.append(center) # vertex 0 is apex
    for r_i in range(1, rings + 1):
        t = r_i / float(rings)
        r_curr = radius * t
        z_curr = depth * (t**2)
        for s in range(sectors):
            th = (s / float(sectors)) * 2.0 * math.pi
            x = cx + r_curr * math.cos(th)
            y = cy + r_curr * math.sin(th)
            z = cz + z_curr
            verts.append((x, y, z))
            
    # Apex fan
    for s in range(sectors):
        s_next = (s + 1) % sectors
        faces.append((0, 1 + s, 1 + s_next))
        
    for r_i in range(1, rings):
        for s in range(sectors):
            s_next = (s + 1) % sectors
            v00 = 1 + (r_i - 1) * sectors + s
            v01 = 1 + (r_i - 1) * sectors + s_next
            v10 = 1 + r_i * sectors + s
            v11 = 1 + r_i * sectors + s_next
            faces.append((v00, v10, v11))
            faces.append((v00, v11, v01))
    return verts, faces

def merge_mesh_components(comp_list):
    all_v, all_f = [], []
    v_off = 0
    for v_c, f_c in comp_list:
        all_v.extend(v_c)
        for tri in f_c:
            all_f.append((tri[0] + v_off, tri[1] + v_off, tri[2] + v_off))
        v_off += len(v_c)
    return all_v, all_f

# -------------------------------------------------------------
# 1. HYPER-REALISTIC SPACE STATION (Modular Orbital Outpost)
# -------------------------------------------------------------
def build_hyper_space_station():
    comps = []
    # Core Pressurized Habitation & Lab Modules (Multi-segment node layout)
    comps.append(make_cylinder(r=2.1, length=14.0, rings=8, sectors=36, axis='z', center=(0, 0, 0)))
    comps.append(make_cylinder(r=1.9, length=9.5, rings=6, sectors=32, axis='x', center=(0, 0, -2.5)))
    comps.append(make_cylinder(r=1.8, length=10.0, rings=6, sectors=32, axis='y', center=(0, 0, 3.2)))

    # Beveled Micrometeoroid Shield Rings on modules
    for z_ring in [-5.0, -2.5, 0.0, 2.5, 5.0]:
        comps.append(make_torus(r_major=2.2, r_minor=0.12, segs_maj=36, segs_min=12, center=(0, 0, z_ring)))

    # Multi-window Cupola observation dome (+Y zenith)
    comps.append(make_cylinder(r=1.4, length=1.2, rings=3, sectors=24, axis='y', center=(0, 2.4, -0.8)))
    for c_th in range(8):
        ang = c_th * (math.pi / 4.0)
        comps.append(make_box(size=(0.45, 0.35, 0.08), center=(math.cos(ang)*1.2, 2.7, -0.8 + math.sin(ang)*1.2)))

    # Main Integrated Lattice Truss Structure (38 meters span)
    comps.append(make_box(size=(38.0, 1.4, 1.4), center=(0, -2.4, 0)))
    # Truss Web diagonals
    for tx in np.linspace(-17.0, 17.0, 18):
        comps.append(make_cylinder(r=0.08, length=2.0, rings=2, sectors=8, axis='y', center=(tx, -2.4, 0)))

    # 4 Massive High-Efficiency Photovoltaic Solar Arrays
    for side in [-1, 1]:
        base_x = side * 16.5
        # Solar Alpha Rotary Joint (SARJ) Gimbal
        comps.append(make_cylinder(r=0.9, length=1.8, rings=3, sectors=24, axis='x', center=(base_x - side*1.0, -2.4, 0)))
        # Array Support Booms
        comps.append(make_cylinder(r=0.28, length=22.0, rings=4, sectors=16, axis='z', center=(base_x, -2.4, 0)))
        
        # Upper & Lower Solar Blankets (+Z and -Z)
        for z_dir in [-1, 1]:
            panel_cz = z_dir * 5.8
            comps.append(make_box(size=(6.8, 0.12, 10.4), center=(base_x, -2.4, panel_cz)))
            # Photovoltaic grid structural ribs
            for rx in [-2.2, 0.0, 2.2]:
                comps.append(make_box(size=(0.15, 0.22, 10.4), center=(base_x + rx, -2.4, panel_cz)))
                
        # Thermal Control Radiator Panels (Tri-fold vertical deployment)
        rad_x = side * 8.5
        comps.append(make_box(size=(2.2, 5.4, 0.15), center=(rad_x, -0.2, 1.8)))
        comps.append(make_box(size=(2.2, 5.4, 0.15), center=(rad_x, -0.2, -1.8)))

    # Forward International Docking Adapter (IDA-3) Ring
    comps.append(make_cylinder(r=1.05, length=2.2, rings=3, sectors=24, axis='z', center=(0, 0, 7.8)))
    for p in range(3):
        p_ang = p * (2.0 * math.pi / 3.0)
        comps.append(make_box(size=(0.25, 0.15, 0.6), center=(math.cos(p_ang)*1.1, math.sin(p_ang)*1.1, 8.8)))

    # High-Gain Communication Dish Antenna Mast
    comps.append(make_cylinder(r=0.12, length=3.5, rings=2, sectors=12, axis='y', center=(3.2, 3.2, -3.0)))
    comps.append(make_parabolic_dish(radius=1.6, depth=-0.4, rings=8, sectors=24, center=(3.2, 5.0, -3.0)))

    v, f = merge_mesh_components(comps)
    write_obj_with_materials(os.path.join(models_dir, "space_station_v2.obj"), v, f, name="SpaceStationV2")

# -------------------------------------------------------------
# 2. HYPER-REALISTIC CREW CAPSULE (Dragon/Starliner Class)
# -------------------------------------------------------------
def build_hyper_crew_capsule():
    comps = []
    # Conical Command Module with Beveled PICA-X Heatshield
    capsule_rings = 16
    capsule_sectors = 36
    c_verts, c_faces = [], []
    for r in range(capsule_rings + 1):
        t = r / float(capsule_rings)
        z = -1.3 + t * 3.2 # -1.3 to 1.9
        if t < 0.15:
            # Curved convex heatshield
            rad = 2.15 * math.sqrt(t / 0.15)
        else:
            t_cone = (t - 0.15) / 0.85
            rad = 2.15 * (1.0 - t_cone * 0.68)
        for s in range(capsule_sectors):
            th = (s / float(capsule_sectors)) * 2.0 * math.pi
            c_verts.append((rad * math.cos(th), rad * math.sin(th), z))
            
    for r in range(capsule_rings):
        for s in range(capsule_sectors):
            s_next = (s + 1) % capsule_sectors
            v00 = r * capsule_sectors + s
            v01 = r * capsule_sectors + s_next
            v10 = (r + 1) * capsule_sectors + s
            v11 = (r + 1) * capsule_sectors + s_next
            c_faces.append((v00, v10, v11))
            c_faces.append((v00, v11, v01))
    comps.append((c_verts, c_faces))

    # Forward Docking Mechanism & Nose Cone Petals
    comps.append(make_cylinder(r=0.72, length=0.6, rings=2, sectors=24, axis='z', center=(0, 0, 2.1)))
    for p in range(3):
        ang = p * (2.0 * math.pi / 3.0)
        comps.append(make_box(size=(0.18, 0.12, 0.4), center=(math.cos(ang)*0.78, math.sin(ang)*0.78, 2.2)))

    # Crew Cabin Windows & Side Hatch
    comps.append(make_box(size=(0.55, 0.42, 0.1), center=(0.6, 0.9, 0.5)))
    comps.append(make_box(size=(0.55, 0.42, 0.1), center=(-0.6, 0.9, 0.5)))

    # Quad Draco RCS Thruster Pods (4 pods around capsule shoulders)
    for q in range(4):
        q_ang = q * (math.pi / 2.0) + (math.pi / 4.0)
        qx = math.cos(q_ang) * 1.55
        qy = math.sin(q_ang) * 1.55
        comps.append(make_box(size=(0.4, 0.4, 0.5), center=(qx, qy, 0.8)))
        # Twin micro-nozzles per pod
        comps.append(make_cylinder(r=0.06, length=0.18, rings=1, sectors=8, axis='x', center=(qx + math.cos(q_ang)*0.22, qy, 0.8)))

    # Cylindrical Service Trunk with Conformal Radiator & Solar Arrays
    comps.append(make_cylinder(r=2.1, length=2.6, rings=6, sectors=36, axis='z', center=(0, 0, -2.5)))
    # Aerodynamic Solar Winglets
    comps.append(make_box(size=(9.4, 0.1, 1.8), center=(0, 0, -2.8)))
    # Main Propulsion Engine Bell
    comps.append(make_cylinder(r=0.55, length=0.9, rings=3, sectors=20, axis='z', center=(0, 0, -4.1)))

    v, f = merge_mesh_components(comps)
    write_obj_with_materials(os.path.join(models_dir, "crew_capsule_v2.obj"), v, f, name="CrewCapsuleV2")

# -------------------------------------------------------------
# 3. HYPER-REALISTIC LUNAR LANDER (Artemis Deep Space Lander)
# -------------------------------------------------------------
def build_hyper_lunar_lander():
    comps = []
    # Octagonal Descent Stage Chassis with Multi-Layer Insulation
    comps.append(make_cylinder(r=2.9, length=2.4, rings=4, sectors=8, axis='y', center=(0, 1.2, 0)))
    
    # 4 Articulated Outrigger Landing Legs with Telescoping Struts & Footpads
    for leg in range(4):
        th = leg * (math.pi / 2.0) + (math.pi / 4.0)
        c_th, s_th = math.cos(th), math.sin(th)
        lx = c_th * 4.2
        lz = s_th * 4.2
        
        # Outrigger truss truss
        comps.append(make_cylinder(r=0.18, length=3.8, rings=3, sectors=10, axis='y', center=(lx*0.62, 0.5, lz*0.62)))
        # Diagonal shock-absorbing strut
        comps.append(make_cylinder(r=0.12, length=3.2, rings=2, sectors=8, axis='x', center=(lx*0.4, 0.8, lz*0.4)))
        # Inverted honeycomb footpad plate
        comps.append(make_cylinder(r=0.85, length=0.18, rings=2, sectors=16, axis='y', center=(lx, -0.65, lz)))
        # Lunar surface probe rod extending down from footpad
        comps.append(make_cylinder(r=0.03, length=1.2, rings=1, sectors=6, axis='y', center=(lx, -1.25, lz)))

    # Gimballed Deep Throttling Descent Rocket Engine Bell
    comps.append(make_cylinder(r=1.05, length=1.4, rings=4, sectors=24, axis='y', center=(0, -0.3, 0)))

    # Cylindrical Ascent Stage Crew Cockpit Module
    comps.append(make_cylinder(r=2.0, length=2.4, rings=4, sectors=24, axis='y', center=(0, 3.4, 0)))
    # Angled Forward Cockpit Windows
    comps.append(make_box(size=(0.7, 0.5, 0.12), center=(0.6, 3.7, 1.95)))
    comps.append(make_box(size=(0.7, 0.5, 0.12), center=(-0.6, 3.7, 1.95)))

    # Forward EVA Egress Porch & Ladder
    comps.append(make_box(size=(1.4, 0.12, 1.0), center=(0, 2.3, 2.5)))
    comps.append(make_cylinder(r=0.04, length=3.2, rings=2, sectors=6, axis='y', center=(0.4, 0.8, 2.9)))
    comps.append(make_cylinder(r=0.04, length=3.2, rings=2, sectors=6, axis='y', center=(-0.4, 0.8, 2.9)))
    for rungs in np.linspace(-0.5, 2.1, 7):
        comps.append(make_box(size=(0.8, 0.04, 0.04), center=(0, rungs, 2.9)))

    # Steerable Parabolic High-Gain Comm Dish
    comps.append(make_cylinder(r=0.1, length=1.5, rings=2, sectors=8, axis='y', center=(1.8, 4.6, -1.2)))
    comps.append(make_parabolic_dish(radius=0.9, depth=-0.25, rings=6, sectors=18, center=(1.8, 5.4, -1.2)))

    # 4 Reaction Control System (RCS) Thruster Clusters
    for q in range(4):
        q_ang = q * (math.pi / 2.0)
        qx = math.cos(q_ang) * 2.1
        qz = math.sin(q_ang) * 2.1
        comps.append(make_box(size=(0.3, 0.3, 0.3), center=(qx, 3.8, qz)))

    v, f = merge_mesh_components(comps)
    write_obj_with_materials(os.path.join(models_dir, "lunar_lander_v2.obj"), v, f, name="ArtemisLanderV2")

# -------------------------------------------------------------
# 4. HYPER-REALISTIC DEEP SPACE CRUISER (Solaris Class)
# -------------------------------------------------------------
def build_hyper_deep_space_cruiser():
    comps = []
    # Main Modular Spine Spine Truss (42 meters)
    comps.append(make_cylinder(r=0.9, length=38.0, rings=12, sectors=24, axis='z', center=(0, 0, 0)))
    
    # 4 Clustered Cryogenic Propellant Spheres (with gold foil)
    for sph_idx in range(4):
        ang = sph_idx * (math.pi / 2.0)
        sx = math.cos(ang) * 2.2
        sy = math.sin(ang) * 2.2
        comps.append(make_torus(r_major=1.4, r_minor=0.8, segs_maj=16, segs_min=12, center=(sx, sy, -2.0)))

    # Rotating Artificial Gravity Centrifuge (Twin-tier Torus)
    comps.append(make_torus(r_major=9.8, r_minor=1.5, segs_maj=48, segs_min=24, center=(0, 0, 5.0)))
    # 4 Centrifuge Access Spokes
    for s in range(4):
        s_ang = s * (math.pi / 2.0)
        comps.append(make_cylinder(r=0.35, length=9.5, rings=2, sectors=12, axis='x', center=(math.cos(s_ang)*4.8, math.sin(s_ang)*4.8, 5.0)))

    # Forward Command Citadel & Bridge
    comps.append(make_cylinder(r=2.4, length=6.0, rings=4, sectors=32, axis='z', center=(0, 0, 18.0)))
    # Primary Cassegrain High-Gain Antenna Dish (4.5 meter aperture)
    comps.append(make_parabolic_dish(radius=4.5, depth=-1.1, rings=10, sectors=36, center=(0, 0, 22.0)))
    # Antenna Sub-Reflector Tripod
    comps.append(make_cylinder(r=0.08, length=2.2, rings=2, sectors=8, axis='z', center=(0, 0, 23.5)))

    # High-Temperature Carbon-Carbon Thermal Radiator Fins (Aft)
    comps.append(make_box(size=(16.0, 0.16, 10.0), center=(0, 0, -9.0)))
    comps.append(make_box(size=(0.16, 16.0, 10.0), center=(0, 0, -9.0)))

    # Triple Nuclear/Ion Propulsion Engines at Aft (-Z)
    for ang in [0, 2*math.pi/3, 4*math.pi/3]:
        ex = math.cos(ang) * 2.1
        ey = math.sin(ang) * 2.1
        comps.append(make_cylinder(r=1.05, length=4.2, rings=4, sectors=24, axis='z', center=(ex, ey, -21.0)))

    v, f = merge_mesh_components(comps)
    write_obj_with_materials(os.path.join(models_dir, "deep_space_cruiser_v2.obj"), v, f, name="SolarisCruiserV2")

if __name__ == "__main__":
    build_hyper_space_station()
    build_hyper_crew_capsule()
    build_hyper_lunar_lander()
    build_hyper_deep_space_cruiser()
    print("All Hyper-Realistic 3D Models synthesized successfully.")
