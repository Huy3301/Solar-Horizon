# Solar Horizon — Asset Pipeline Specification

This document defines the 3D asset standards, naming conventions, poly budgets, material pipelines, and export guidelines for Solar Horizon (Godot 4.7 Forward+ / Mobile).

---

## 1. Coordinate System & Scale

- **Units:** 1 unit = 1.0 meter.
- **Orientation (Godot 4 Standard):**
  - **Forward:** $-Z$
  - **Up:** $+Y$
  - **Right:** $+X$
- **Rotations:** Right-handed coordinate system. Roll rotates around $-Z$, Pitch around $+X$, Yaw around $+Y$.
- **Pivot / Origin:** 
  - For vehicles and spacecraft, origin $(0, 0, 0)$ is at the nominal Center of Mass (CoM).
  - Landing gear feet should touch the horizontal ground plane $(Y = 0)$ or have a documented ground offset when fully extended.

---

## 2. Naming Conventions & Scene Hierarchy

Godot glTF 2.0 importer supports semantic node prefixes and suffixes.

### 2.1 Mesh LODs
Assets implement progressive Level of Detail (LOD):
- `[AssetName]_LOD0` — Full detail mesh for close-up and cockpit/chase views.
- `[AssetName]_LOD1` — Medium distance mesh (decimated, simplified silhouette).
- `[AssetName]_LOD2` — Far distance proxy mesh.

Godot 4's visibility range (`visibility_range_begin` / `visibility_range_end`) or LOD mesh generation can be hooked to these nodes.

### 2.2 Sockets
Empties / marker transforms in Blender are exported into glTF as `Node3D`. Use the `SOCKET_` prefix:
- `SOCKET_engine_L`, `SOCKET_engine_R` — Main propulsion engine nozzle centers (attachment point for engine plume VFX, thrust vectors, point lights).
- `SOCKET_nav_port` — Port (left) navigation light (Red, $+X$ negative side).
- `SOCKET_nav_stbd` — Starboard (right) navigation light (Green, $+X$ positive side).
- `SOCKET_rcs_[location]_[direction]` — Reaction control thruster nozzle exits (e.g. `SOCKET_rcs_nose_pitch_up`, `SOCKET_rcs_tail_yaw_left`).
- `SOCKET_cockpit_cam` — Interior pilot eye-point position and orientation.
- `SOCKET_chase_cam` — Recommended chase camera anchor point.
- `SOCKET_docking` — Docking collar alignment and contact point.

### 2.3 Collision Meshes
Collision geometry must be simplified to ensure high physics performance (Jolt / Godot Physics):
- Prefix `COL_` (e.g. `COL_hull`, `COL_gear_front`, `COL_gear_main_L`, `COL_gear_main_R`).
- Godot glTF importer convention: Nodes ending with `-col` or `-convcol` automatically generate `CollisionShape3D` on import.

---

## 3. Geometric & Poly Budgets

Target platforms range from Desktop (Forward+) down to modern mobile devices (Mobile Vulkan).

| Asset Category | LOD0 (Triangles) | LOD1 (Triangles) | LOD2 (Triangles) | Max Draw Calls |
|---|---|---|---|---|
| **Hero Ship (Orbiter)** | 40,000 – 60,000 | $\le$ 8,000 | $\le$ 1,500 | 4 |
| **Cruisers / Large Ships** | 30,000 – 50,000 | $\le$ 8,000 | $\le$ 1,200 | 6 |
| **Landers / Transports** | 20,000 – 35,000 | $\le$ 6,000 | $\le$ 1,000 | 4 |
| **Modular Station Modules**| 10,000 – 25,000 | $\le$ 4,000 | $\le$ 800 | 2 per module |
| **Surface Rovers / Vehicles**| 15,000 – 30,000 | $\le$ 5,000 | $\le$ 800 | 3 |
| **Props / Components** | 1,000 – 5,000 | $\le$ 1,000 | $\le$ 200 | 1 |

---

## 4. Materials & Textures (PBR Workflow)

Solar Horizon uses the standard Metallic-Roughness PBR workflow.

### 4.1 Texture Sets
Each material supports:
1. **Base Color / Albedo:** RGB (sRGB color space).
2. **ORM Texture (Combined packed texture):** Linear color space.
   - **Red channel:** Ambient Occlusion (AO).
   - **Green channel:** Roughness (0.0 = mirror smooth, 1.0 = rough matte).
   - **Blue channel:** Metallic (0.0 = dielectric/insulator, 1.0 = raw metal).
3. **Normal Map:** Tangent space Normal (OpenGL format, $+Y$ Green channel = Up).
4. **Emission Map:** RGB (sRGB color space) with emission strength multiplier.

### 4.2 Texture Resolutions

| Tier | Hero Ship Textures | Secondary Ships / Props |
|---|---|---|
| **Desktop / Forward+** | 2048 $\times$ 2048 | 1024 $\times$ 1024 |
| **Mobile / Low Tier** | 1024 $\times$ 1024 | 512 $\times$ 512 |

---

## 5. Animation Standards

- Animations are authored in Blender and exported in the glTF file.
- Action names must follow semantic naming:
  - `gear_deploy` — Landing gear deployment (1.0 second duration, frame 0 = retracted/stowed inside wheel bays, frame 30 = fully deployed and locked).
  - `gear_retract` — Optional dedicated reverse clip, or runtime playback in reverse (`-1.0` speed).
  - `hatch_open` / `hatch_close` — EVA airlock or canopy opening sequence.
  - `bay_doors_open` / `bay_doors_close` — Payload bay doors opening sequence.

---

## 6. Export Pipeline

1. **Source Tool:** Blender 4.x / 5.x via background Python automation (`tools/blender/build_*.py`).
2. **Target Format:** Binary glTF (`.glb`).
3. **Export Settings:**
   - Format: `GLB` (self-contained binary).
   - Include: Selected objects / collection (`Visible Objects`), Custom Properties, Punctual Lights (if applicable).
   - Transform: $+Y$ Up (glTF standard).
   - Geometry: Apply Modifiers = True, Tangents = True, UVs = True, Normals = True.
   - Animation: Group by NLA Actions / Active Actions, Sample Animations = True.

---

## 7. Integration & Wiring Note: Swapping `orbiter.glb` into `scenes/ship.tscn`

To integrate the new hero orbiter asset (`assets/models/ships/orbiter/orbiter.glb`) into the game without modifying scenes during other agents' concurrent edits:

1. **Open `scenes/ship.tscn`** in Godot Editor (or text editor).
2. **Replace Mesh Reference:**
   - Locate the root ship body or visual node (`MeshInstance3D` named `MeshInstance3D` or `ShipMesh`).
   - Replace the legacy `.obj` reference (`res://assets/models/spacecraft_orbiter.obj`) by instancing `res://assets/models/ships/orbiter/orbiter.glb` as a child node `OrbiterModel`.
3. **Connect Sockets:**
   - Attach left main thruster plume VFX to `$OrbiterModel/SOCKET_engine_L`.
   - Attach right main thruster plume VFX to `$OrbiterModel/SOCKET_engine_R`.
   - Attach red port light to `$OrbiterModel/SOCKET_nav_port`.
   - Attach green starboard light to `$OrbiterModel/SOCKET_nav_stbd`.
4. **Wire Landing Gear Animation:**
   - Access the `AnimationPlayer` embedded in the imported `orbiter.glb` instance.
   - In `ship_flight_controller.gd`, when toggling gear:
     ```gdscript
     func _toggle_landing_gear(deployed: bool) -> void:
         var anim_player = $OrbiterModel/AnimationPlayer
         if deployed:
             anim_player.play("gear_deploy")
         else:
             anim_player.play_backwards("gear_deploy")
     ```
5. **Collision Setup:**
   - Use the embedded `COL_hull` mesh shape or Godot's automatic `CollisionShape3D` generated from `-col` to define the Jolt physics collider, replacing the placeholder box collider.
