import math
import os
import numpy as np

planets_dir = "/working_dir/c_498f6079368ce6ce/solar_horizon_godot/assets/models/planets"
os.makedirs(planets_dir, exist_ok=True)

def generate_sphere_obj(filepath, name, radius=10.0, rings=64, sectors=128, oblate_factor=1.0):
    verts = []
    uvs = []
    normals = []
    faces = []

    for r in range(rings + 1):
        v = r / float(rings)
        phi = v * math.pi # 0 to pi (north pole to south pole)
        sin_p = math.sin(phi)
        cos_p = math.cos(phi)

        for s in range(sectors + 1):
            u = s / float(sectors)
            theta = u * 2.0 * math.pi # 0 to 2pi

            nx = sin_p * math.cos(theta)
            ny = cos_p
            nz = sin_p * math.sin(theta)

            # Apply oblateness along Y polar axis
            vx = nx * radius
            vy = ny * radius * oblate_factor
            vz = nz * radius

            verts.append((vx, vy, vz))
            uvs.append((u, 1.0 - v))
            normals.append((nx, ny, nz))

    stride = sectors + 1
    for r in range(rings):
        for s in range(sectors):
            v00 = r * stride + s
            v01 = r * stride + (s + 1)
            v10 = (r + 1) * stride + s
            v11 = (r + 1) * stride + (s + 1)

            faces.append((v00, v10, v11))
            faces.append((v00, v11, v01))

    with open(filepath, "w") as f:
        f.write(f"# Solar Horizon Planetary Model: {name}\n")
        f.write(f"# Vertices: {len(verts)}, Faces: {len(faces)}\n\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        f.write("\n")
        for vt in uvs:
            f.write(f"vt {vt[0]:.6f} {vt[1]:.6f}\n")
        f.write("\n")
        for vn in normals:
            f.write(f"vn {vn[0]:.6f} {vn[1]:.6f} {vn[2]:.6f}\n")
        f.write("\n")
        f.write(f"g {name}\n")
        f.write("s 1\n")
        for tri in faces:
            v0, v1, v2 = tri[0] + 1, tri[1] + 1, tri[2] + 1
            f.write(f"f {v0}/{v0}/{v0} {v1}/{v1}/{v1} {v2}/{v2}/{v2}\n")

    print(f"Exported {filepath}: {len(verts)} vertices, {len(faces)} faces.")

def generate_rings_obj(filepath, name, r_inner=12.2, r_outer=22.7, rings=8, sectors=144):
    verts = []
    uvs = []
    normals = []
    faces = []

    # Two sides (top and bottom) for double-sided visibility
    for side in [1.0, -1.0]:
        base_v = len(verts)
        ny = side
        for r in range(rings + 1):
            t = r / float(rings)
            radius = r_inner + t * (r_outer - r_inner)
            for s in range(sectors + 1):
                u = s / float(sectors)
                theta = u * 2.0 * math.pi
                vx = radius * math.cos(theta)
                vy = 0.0
                vz = radius * math.sin(theta)
                verts.append((vx, vy, vz))
                uvs.append((u, t))
                normals.append((0.0, ny, 0.0))

        stride = sectors + 1
        for r in range(rings):
            for s in range(sectors):
                v00 = base_v + r * stride + s
                v01 = base_v + r * stride + (s + 1)
                v10 = base_v + (r + 1) * stride + s
                v11 = base_v + (r + 1) * stride + (s + 1)

                if side > 0:
                    faces.append((v00, v10, v11))
                    faces.append((v00, v11, v01))
                else:
                    faces.append((v00, v11, v10))
                    faces.append((v00, v01, v11))

    with open(filepath, "w") as f:
        f.write(f"# Solar Horizon Ring Model: {name}\n")
        f.write(f"# Vertices: {len(verts)}, Faces: {len(faces)}\n\n")
        for v in verts:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        f.write("\n")
        for vt in uvs:
            f.write(f"vt {vt[0]:.6f} {vt[1]:.6f}\n")
        f.write("\n")
        for vn in normals:
            f.write(f"vn {vn[0]:.6f} {vn[1]:.6f} {vn[2]:.6f}\n")
        f.write("\n")
        f.write(f"g {name}\n")
        f.write("s 1\n")
        for tri in faces:
            v0, v1, v2 = tri[0] + 1, tri[1] + 1, tri[2] + 1
            f.write(f"f {v0}/{v0}/{v0} {v1}/{v1}/{v1} {v2}/{v2}/{v2}\n")

    print(f"Exported {filepath}: {len(verts)} vertices, {len(faces)} faces.")

if __name__ == "__main__":
    # 1. Earth
    generate_sphere_obj(os.path.join(planets_dir, "planet_earth.obj"), "PlanetEarth", radius=10.0, rings=64, sectors=128, oblate_factor=0.9966)
    # 2. Moon
    generate_sphere_obj(os.path.join(planets_dir, "planet_moon.obj"), "PlanetMoon", radius=2.72, rings=48, sectors=96, oblate_factor=1.0)
    # 3. Mars
    generate_sphere_obj(os.path.join(planets_dir, "planet_mars.obj"), "PlanetMars", radius=5.32, rings=48, sectors=96, oblate_factor=0.9942)
    # 4. Mercury
    generate_sphere_obj(os.path.join(planets_dir, "planet_mercury.obj"), "PlanetMercury", radius=3.83, rings=40, sectors=80, oblate_factor=1.0)
    # 5. Venus
    generate_sphere_obj(os.path.join(planets_dir, "planet_venus.obj"), "PlanetVenus", radius=9.50, rings=48, sectors=96, oblate_factor=1.0)
    # 6. Jupiter (Rapid rotator with 0.935 oblateness)
    generate_sphere_obj(os.path.join(planets_dir, "planet_jupiter.obj"), "PlanetJupiter", radius=109.7, rings=64, sectors=128, oblate_factor=0.9351)
    # 7. Saturn (0.902 oblateness) + Rings
    generate_sphere_obj(os.path.join(planets_dir, "planet_saturn.obj"), "PlanetSaturn", radius=91.4, rings=64, sectors=128, oblate_factor=0.9024)
    generate_rings_obj(os.path.join(planets_dir, "saturn_rings.obj"), "SaturnRings", r_inner=111.5, r_outer=207.5, rings=12, sectors=144)
    # 8. Europa (Jupiter Moon)
    generate_sphere_obj(os.path.join(planets_dir, "moon_europa.obj"), "MoonEuropa", radius=2.45, rings=40, sectors=80, oblate_factor=1.0)
    # 9. Titan (Saturn Moon with thick atmosphere)
    generate_sphere_obj(os.path.join(planets_dir, "moon_titan.obj"), "MoonTitan", radius=4.04, rings=40, sectors=80, oblate_factor=1.0)

    print("All planetary 3D meshes successfully synthesized in assets/models/planets/.")
