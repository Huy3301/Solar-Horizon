# Solar Horizon: Earth Low Orbit (LEO) & Aerospace Simulation

A realistic 3D space exploration and orbital flight simulator built on **Godot Engine 4.3+**, centered on high-fidelity **Earth Low Orbit (LEO)** flight dynamics, photorealistic planetary rendering, high-polygon spacecraft modeling, and next-generation glassmorphism flight instrumentation.

---

## 1. Visual & Graphic Fidelity Overhaul

### Photorealistic Earth Low Orbit Planetary Rendering
1. **Multi-Layered Atmospheric Scattering (`shaders/earth_atmosphere.gdshader`)**:
   - Physics-grounded **Rayleigh scattering** rim shader creating realistic wavelength-dependent blue gradients along the curved horizon limb.
   - **Mie forward solar scattering** producing intense corona halos when viewing in the sun direction.
   - **Sunset/Sunrise limb transition**: Extinction red-shifting turns the atmosphere into crimson/orange hues along the day/night terminator.
   - **High-altitude airglow layer**: Subtle green/cyan chemiluminescence ribbon (~90–100 km altitude) accurately replicating astronaut photography from the International Space Station.

2. **High-Fidelity Surface Shader (`shaders/earth_surface.gdshader`)**:
   - 2048x1024 high-resolution albedo map depicting continents, coastlines, and ocean bathymetry.
   - Specular ocean water mask enabling realistic sun glint reflections across oceans, gulfs, and coastlines.
   - Topographic normal mapping bringing mountain relief and elevation to life.
   - Night-side city lights emission map smoothly fading in across the night hemisphere with golden urban clusters and highway filaments.

3. **Volumetric Cloud Shell (`shaders/earth_clouds.gdshader`)**:
   - High-resolution cloud map featuring the Intertropical Convergence Zone (ITCZ), mid-latitude cyclonic swirls, and trade wind belts.
   - Subsurface forward scattering illuminating clouds when backlit by the sun.
   - Sunset golden hour tinting along cloud tops facing the terminator.
   - Independent axial drift rotation simulating upper atmospheric winds.

4. **Deep Space Vacuum Skybox (`shaders/space_sky.gdshader`)**:
   - High-contrast pure black vacuum of space.
   - Multi-tier procedural starfield with pin-point stars spanning diverse color temperatures (hot blue-white, solar yellow, cool reddish-orange) and magnitudes.
   - Inclined Milky Way galactic plane band with cosmic dust lanes and nebular glow.
   - High dynamic range solar disk with glowing corona and bloom.

---

## 2. High-Polygon Aerospace Exploration Orbiter

Primitive box and wedge meshes have been replaced with a high-polygon aerospace orbiter (`assets/models/spacecraft_orbiter.obj`):
* **Geometry**: 3,883 vertices, 7,348 smooth polygons.
* **Aerodynamic Airframe**: Swept double-delta wings with NACA-profile camber, canted vertical winglets, and aerodynamic chines.
* **Cockpit Canopy**: High-subdivision curved glass blister with interior instrument backlighting.
* **Thermal Protection System (TPS)**: Realistic black ceramic silica tiles on the belly and white silica thermal insulation blankets on the upper hull.
* **Twin Rocket Engines & Supersonic Plume**: Detailed bell nozzles with internal expansion throats and dynamic supersonic exhaust plumes (`shaders/engine_plume.gdshader`) with Mach shock diamonds.

---

## 3. Next-Gen Glassmorphism Aerospace Flight HUD

The flight HUD (`scenes/ui/hud.tscn` & `scripts/hud.gd`) features:
* **Glassmorphism Panels**: Frosted semi-transparent dark panels with glowing cyan (`#00f0ff`) and amber (`#ffaa00`) vector borders.
* **Orbital Mechanics Telemetry**:
  * **Orbital Velocity**: Real-time readouts in m/s and km/h (`7,725 m/s | 27,810 km/h`).
  * **Hypersonic Regime**: Mach status display (`M 22.7 [HYPERSONIC ORBIT]`).
  * **Orbital Altitudes**: Altitude ASL in km and surface radar distance.
  * **Keplerian Orbital Metrics**: Apoapsis ($Ap$), Periapsis ($Pe$), Orbital Period ($T$), and Eccentricity ($e$).
  * **Reentry Thermal Flux**: Dynamic pressure ($q$) and heat shield thermal flux monitor.
  * **Microgravity Load**: Freefall indicator (`0.00 G [MICROGRAVITY]`).
* **Artificial Horizon & Navball**:
  * Dual-axis pitch ladder (-90° to +90°) and roll indicator.
  * Precision flight director reticle and crosshairs.
* **Mobile & Touch Parity**:
  * Virtual analog thumbstick for pitch and roll control.
  * Vertical throttle slider and glass-styled action buttons (`GEAR`, `BRAKE`, `RCS/VTOL`, `CAM`).

---

## 4. Project Structure

```
solar_horizon_godot/
├── project.godot               # Forward+ / Mobile engine configuration, TAA & FXAA
├── README.md                   # Technical documentation
├── scenes/
│   ├── world.tscn              # Earth Low Orbit scene with EarthGlobe, SunLight & Sky
│   ├── ship.tscn               # High-poly orbiter, collision hulls, cameras, plumes
│   └── ui/
│       └── hud.tscn            # Glassmorphism flight HUD & orbital telemetry
├── assets/
│   ├── models/
│   │   └── spacecraft_orbiter.obj # 7,348-polygon aerospace orbiter mesh
│   ├── textures/
│   │   ├── earth_albedo.png       # 2048x1024 surface continents & oceans
│   │   ├── earth_normal.png       # Topographic relief normal map
│   │   ├── earth_specular_water.png # Water reflection mask
│   │   ├── earth_city_lights.png  # Night urban emission map
│   │   ├── earth_clouds.png       # Cloud shell texture
│   │   ├── orbiter_albedo.png     # Spacecraft TPS tile livery
│   │   ├── orbiter_normal.png     # Panel seams and rivets
│   │   ├── orbiter_roughness.png  # Ceramic tile roughness
│   │   └── orbiter_emission.png   # Cockpit and engine glow
│   └── materials/
│       ├── earth_surface_mat.tres
│       ├── earth_atmosphere_mat.tres
│       ├── earth_clouds_mat.tres
│       ├── space_sky_mat.tres
│       ├── engine_plume.tres
│       └── spacecraft_hull.tres
├── shaders/
│   ├── earth_surface.gdshader
│   ├── earth_atmosphere.gdshader
│   ├── earth_clouds.gdshader
│   ├── space_sky.gdshader
│   └── engine_plume.gdshader
└── scripts/
    ├── ship_flight_controller.gd # Orbital mechanics, spherical gravity, vacuum RCS
    ├── earth_environment.gd    # Planetary axial rotation and solar tracking
    ├── camera_controller.gd    # Chase, cockpit, and 360° inspection orbit cameras
    ├── virtual_joystick.gd     # Touch analog thumbstick
    └── hud.gd                  # Orbital telemetry calculations & UI pipeline
```

---

## 5. Controls

| Action | Desktop Key | Gamepad | Mobile Touch |
| :--- | :--- | :--- | :--- |
| **Pitch Down / Up** | `W` / `S` | Left Stick (Y) | On-screen Joystick (Y) |
| **Roll Left / Right** | `A` / `D` | Left Stick (X) | On-screen Joystick (X) |
| **Yaw Left / Right** | `Q` / `E` | Bumpers (LB / RB) | On-screen Rudder |
| **Throttle Up / Down** | `Shift` / `Ctrl` | Triggers (RT / LT) | Right Vertical Slider |
| **Toggle Landing Gear** | `G` | Y Button | `[GEAR]` Button |
| **Brakes** | `B` (hold) | X Button | `[BRAKE]` Button |
| **RCS / VTOL Burst** | `Space` (hold) | A Button | `[RCS/VTOL]` Button |
| **Cycle Camera** | `V` | Back / Select | `[CAM]` Button |
| **Inspect Camera Orbit** | Right Click + Drag | Right Stick | Screen Drag |

---

## 6. How to Run

1. Open **Godot 4.3+**.
2. Click **Import**, browse to `solar_horizon_godot/project.godot`, and click **Import & Edit**.
3. Press **F5** to launch the Earth Low Orbit simulation.
