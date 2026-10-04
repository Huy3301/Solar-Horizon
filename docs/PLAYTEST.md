# Solar Horizon — Earth & Moon Vertical Slice Playtest Guide

This document outlines the controls, systems, and visual checklist for testing the unified **Earth & Moon Vertical Slice** (Phases 0–4) in Godot 4.7.

---

## 1. Quick Start

1. Open the project in **Godot Engine 4.7.2-stable**.
2. Press **[F5]** (or the Play button) to run the main scene (`res://scenes/main.tscn`).
3. You will spawn aboard the **Spacecraft Orbiter** in orbit above Earth, with Adelaide Base marked below.

---

## 2. Controls Summary

### Spacecraft Flight Controls
| Action | Keyboard / Mouse | Gamepad | Description |
|---|---|---|---|
| **Pitch** | `[W]` / `[S]` | Left Stick (Up/Down) | Pitch aircraft nose down / up |
| **Roll** | `[A]` / `[D]` | Left Stick (Left/Right) | Roll aircraft wings left / right |
| **Yaw** | `[Q]` / `[E]` | Bumpers `[LB]` / `[RB]` | Rudder yaw left / right |
| **Throttle Up** | `[Shift]` | Right Trigger `[RT]` | Spool main engines forward |
| **Throttle Down** | `[Ctrl]` | Left Trigger `[LT]` | Spool down / idle engines |
| **Landing Gear** | `[G]` | `[Y]` / Top Button | Toggle animated landing gear struts |
| **Wheel Brakes** | `[B]` | `[X]` / Left Button | Apply ground friction brakes |
| **VTOL / RCS Up** | `[Space]` | `[A]` / Bottom Button | Vertical translation thrusters |
| **Camera View** | `[V]` | Right Stick Click | Cycle Cockpit / Chase / Free Orbit |
| **Interact / Airlock**| `[F]` | `[X]` / Left Button | Board / exit vessel when safely landed |

### On-Foot (EVA) Astronaut Controls
| Action | Keyboard / Mouse | Gamepad | Description |
|---|---|---|---|
| **Move** | `[W]`, `[A]`, `[S]`, `[D]` | Left Stick | Walk in camera-relative directions |
| **Sprint** | `[Shift]` | Left Stick Click | Sprint across terrain |
| **Jump** | `[Space]` | `[A]` / Bottom Button | Jump (scales with local gravity) |
| **Jetpack** | Hold `[Space]` | Hold `[A]` | Engage EVA jetpack thrusters |
| **Multi-Tool Laser**| `Left Click` | Right Trigger `[RT]` | Mine scannable resource deposits |
| **Scanner** | `[C]` | `[RB]` / Right Bumper | Area scan & discover minerals/anomalies |
| **Visor Mode** | `[T]` / `[X]` | `[D-Pad Up]` | Toggle analytical visor HUD overlay |
| **Camera View** | `[V]` | Right Stick Click | Toggle 3rd-person / 1st-person view |
| **Interact / Board** | `[F]` | `[X]` / Left Button | Re-enter spacecraft airlock |

### General UI & System Controls
| Action | Shortcut | Description |
|---|---|---|
| **Inventory Grid** | `[Tab]` or `[I]` | Open 20-slot inventory, inspect items, view mass |
| **Orbit Map** | `[M]` | Toggle 2D orbital trajectory map (Ap/Pe tags) |
| **Quick Save** | `[F5]` | Save game profile to `user://solar_horizon_save.json` |
| **Quick Load** | `[F9]` | Restore saved vessel position, inventory, and mission |
| **Pause Menu** | `[Esc]` | Settings, control mapping, respawn at Adelaide Base |

---

## 3. What to Test (Visual & Gameplay Checklist)

### 3.1 Planetary Graphics & Skybox
- [ ] **Earth Atmosphere**: Descending from 200 km to ground level smoothly transitions from dark space through the blue Rayleigh glow, twilight scattering, and dense lower troposphere.
- [ ] **Earth Cloud Layer**: Clouds display self-shadowing and cast soft shadows onto the terrain below.
- [ ] **Sun & Lens Flare**: Sun glare billboard responds to angle; Earth and Moon occlude the solar disk during eclipse alignment.
- [ ] **Deep Space Skybox**: Procedural Milky Way band and stars with no visible polar seams.
- [ ] **Terrain LOD & Biomes**: Spherified cube quadtree transitions smoothly with skirts preventing gaps; procedural PBR textures show grass, sand, rock, snow (Earth) and cratered regolith (Moon).
- [ ] **Ocean Rendering**: Spherical Gerstner water surface displays sun glint, wave crest foam, and shore depth absorption.

### 3.2 Spacecraft & 3D Model
- [ ] **Orbiter GLB**: Verify 3D model with beveled paneling, thermal protection tiles, cockpit glazing, twin engines, and RCS sockets.
- [ ] **Landing Gear**: Pressing `[G]` triggers the smooth 1-second `gear_deploy` extension/retraction animation.
- [ ] **Engine Plumes**: Throttle scaling expands the plume geometry and emissive heat core.
- [ ] **Collision**: Touchdown on terrain with gear extended at `< 40 m/s` anchors the vessel and sets `is_landed`.

### 3.3 Core Gameplay & EVA Loop
- [ ] **Onboarding Tutorial**: Displays mission steps at the top of the screen (Adelaide Launch → Orbital Insertion → Moon Landing → EVA Exit → Regolith Analysis → Return).
- [ ] **Airlock EVA**: When landed, approach the port hatch and press `[F]` to step out as an astronaut.
- [ ] **Lunar Gravity**: On the Moon, gravity is ~1.62 m/s²; jump and jetpack allow floaty traversal.
- [ ] **Scanning**: Press `[C]` near resource deposits to register new catalog entries and earn credits.
- [ ] **Mining**: Target mineral boulders and fire the mining laser to harvest iron ore, silicates, ice, or Helium-3 into your inventory.
- [ ] **Inventory & Crafting**: Press `[Tab]` to check harvested minerals and craft upgrades.
- [ ] **Save / Load**: Press `[F5]` to quick-save anywhere; press `[F9]` to reload state.

---

## 4. Headless vs Windowed Limitations
- In automated CI and headless tests (`tools/ci.ps1`), Godot runs without a hardware `RenderingDevice`. Shader execution falls back to CPU height approximations and shaders cannot be visually rendered.
- **Visual shaders and GPU compute require running the game in a graphical window** via Godot Editor or executable build.
