# Visuals Wiring Guide (Earth, Moon & Sky Environment)

This document describes how to integrate the Phase 2 visual presentation components into `scenes/main.tscn` (or any gameplay scene).

---

## 1. Overview & Scale Conventions

Per the locked architecture decisions:
- **World Scale:** 1:10 scaled astronomical units.
- **Earth Radius:** `637,100.0 m` (scaled from 6,371,000 m).
  - Cloud deck: `638,600.0 m` (+1,500 m altitude).
  - Atmosphere scattering shell: `646,100.0 m` (+9,000 m scaled scale-height envelope).
- **Moon Radius:** `173,740.0 m` (scaled from 1,737,400 m in `game/universe/data/bodies/moon.tres`).

---

## 2. Reusable Scenes

### 2.1 Earth Visual (`res://game/fx/earth_visual.tscn`)

Self-contained Earth representation featuring:
- Physically-shaded PBR surface (`shaders/earth_surface.gdshader`) with anisotropic ocean sun glint, coastal bathymetry, dynamic cloud shadows, atmospheric aerial haze, and night-side city lights.
- Dynamic cloud shell (`shaders/earth_clouds.gdshader`) with volumetric self-shadowing, golden sunset scattering, and wind drift.
- Rayleigh + Mie atmospheric scattering shell (`shaders/earth_atmosphere.gdshader`) with orbital limb glow, terminator extinction, stratospheric ozone absorption, and mesospheric airglow ribbon.
- Integrated `AtmosphereSystem` and `WeatherSystem` nodes.

#### Exports & Parameters (`EarthVisual` script):
| Property | Type | Default | Description |
|---|---|---|---|
| `radius` | `float` | `637100.0` | Radius of the solid planetary surface mesh (m). |
| `cloud_altitude` | `float` | `1500.0` | Height of the cloud layer above surface (m). |
| `atmosphere_thickness` | `float` | `9000.0` | Thickness of the atmospheric scattering shell (m). |
| `rotation_speed_deg_per_sec` | `float` | `0.00417` | Continental rotation speed (deg/s). |
| `sun_direction` | `Vector3` | `(0.707, 0.35, 0.612)` | Direction vector towards the sun (normalized). |
| `quality_tier` | `int` | `1` | `0` = Low (Mobile optimized), `1` = High (Desktop physical). |
| `surface_material` | `ShaderMaterial` | `earth_surface_mat.tres` | Planetary surface material override. |
| `clouds_material` | `ShaderMaterial` | `earth_clouds_mat.tres` | Cloud layer material override. |
| `atmosphere_material` | `ShaderMaterial` | `earth_atmosphere_mat.tres` | Atmospheric shell material override. |

#### Methods:
- `set_sun_direction(dir: Vector3)`: Updates sun direction across surface, cloud, and atmosphere shaders in sync.
- `set_quality_tier(tier: int)`: Switches all sub-shaders between Low (0) and High (1) tiers.

---

### 2.2 Moon Visual (`res://game/fx/moon_visual.tscn`)

Self-contained Moon representation featuring:
- Multi-scale procedural cratering (`shaders/lunar_surface.gdshader`) with terraced rims and central rebound peaks.
- High-fidelity normal perturbation for relief and terminator shadows.
- Dual-phase albedo: dark mare basalts vs pale anorthosite highlands.
- Radial ejecta ray networks (Tycho and Copernicus).
- Hapke opposition surge (retroreflective brightening when phase angle approaches zero).

#### Exports & Parameters (`MoonVisual` script):
| Property | Type | Default | Description |
|---|---|---|---|
| `radius` | `float` | `173740.0` | Radius of the lunar surface mesh (m). |
| `rotation_speed_deg_per_sec` | `float` | `0.0` | Rotation speed (default 0 for synchronous rotation). |
| `sun_direction` | `Vector3` | `(0.707, 0.35, 0.612)` | Direction vector towards the sun. |
| `quality_tier` | `int` | `1` | `0` = Low, `1` = High. |
| `surface_material` | `ShaderMaterial` | `lunar_surface_mat.tres` | Lunar material override. |

#### Methods:
- `set_sun_direction(dir: Vector3)`: Updates solar illumination vector.
- `set_quality_tier(tier: int)`: Toggles between fast cratering and full multi-octave relief.

---

### 2.3 Sky & Environment (`res://game/fx/sky_environment.tscn`)

Manages the celestial backdrop, solar lighting, and HDR glare billboard:
- Procedural deep-space skybox (`shaders/space_sky.gdshader`) with seamless 3D procedural starfield (no polar pinching), realistic spectral colors, and procedural Milky Way dust lanes and core bulge.
- HDR solar glare billboard (`shaders/fx/sun_glare.gdshader`) facing the camera with diffraction spikes, corona halo, and dynamic eclipse attenuation.
- `SunController` (`game/fx/sun.gd`) handling directional sunlight and eclipse occlusion tests against spherical bodies.
- `WorldEnvironment` pre-tuned for ACES tonemapping and HDR bloom.

#### Exports & Parameters (`SkyEnvironmentVisual` script):
| Property | Type | Default | Description |
|---|---|---|---|
| `sun_direction` | `Vector3` | `(0.707, 0.35, 0.612)` | Direction vector towards the sun. |
| `sun_energy` | `float` | `2.4` | Solar directional light intensity. |
| `quality_tier` | `int` | `1` | `0` = Low, `1` = High. |
| `star_catalog_node` | `Node` | `/root/StarCatalog` | Optional node reference providing star catalog data. |

#### Methods:
- `set_sun_direction(dir: Vector3)`: Propagates sun vector to sky shader and directional light.
- `sun_node.add_occluder(node: Node3D, radius_m: float)`: Registers an astronomical body (Earth, Moon) for geometric solar eclipse calculation.

---

## 3. Drop-In Wiring into `scenes/main.tscn`

To wire these components into the main scene:

```gdscript
# In main.gd or level setup script:

@onready var sky_env: SkyEnvironmentVisual = $SkyEnvironment
@onready var earth_visual: EarthVisual = $EarthVisual
@onready var moon_visual: MoonVisual = $MoonVisual

func _ready() -> void:
    # Register Earth and Moon as solar eclipse occluders
    if sky_env and sky_env.sun_node:
        sky_env.sun_node.add_occluder(earth_visual, 637100.0)
        sky_env.sun_node.add_occluder(moon_visual, 173740.0)

func _process(_delta: float) -> void:
    # Fetch current sun vector from simulation clock
    var sun_dir = SimulationClock.get_sun_direction()
    sky_env.set_sun_direction(sun_dir)
    earth_visual.set_sun_direction(sun_dir)
    moon_visual.set_sun_direction(sun_dir)
```

### Quality Governor Integration:
When integrating with `QualityGovernor`:
- Desktop / High tier: call `set_quality_tier(1)`.
- Mobile / Low tier: call `set_quality_tier(0)`.
