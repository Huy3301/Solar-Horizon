# Player & UI Wiring Guide (Phase 4)

This document describes the modular architecture of the Phase 4 Player Controller, EVA State Machine, Explorer HUD Components, and Tutorial Director, and how to wire them into the main game scene without modifying `project.godot` or `scenes/main.tscn`.

---

## 1. Scene Architecture Overview

```
Main Scene (e.g. scenes/main.tscn or scenes/world.tscn)
 ├── OriginService (Autoload)
 ├── SimulationClock (Autoload)
 ├── Ship (RigidBody3D with ship_flight_controller.gd)
 │    ├── CameraController (scripts/camera_controller.gd)
 │    │    └── Camera3D
 │    └── Hatch (Marker3D / Node3D at port airlock)
 ├── PlayerRig (game/player/player_rig.tscn)
 │    └── OnFootRig (game/player/on_foot_rig.gd - CharacterBody3D)
 │         ├── CameraPivot
 │         │    └── SpringArm3D
 │         │         └── Camera3D (Third/First Person)
 │         └── CollisionShape3D (Capsule)
 ├── GameUI (game/ui/game_ui.tscn - CanvasLayer)
 │    ├── FlightTelemetry (game/ui/components/flight_telemetry.tscn)
 │    ├── SuitBars (game/ui/components/suit_bars.tscn)
 │    ├── InventoryMenu (game/ui/inventory_menu.tscn)
 │    ├── OrbitMap (game/ui/orbit_map.tscn)
 │    ├── PauseMenu (game/ui/components/pause_menu.tscn)
 │    ├── TouchControls (game/ui/touch_controls.tscn)
 │    ├── InteractionPrompt (PanelContainer)
 │    └── TutorialBanner (PanelContainer)
 └── TutorialDirector (game/tutorial/tutorial_director.gd - Node)
```

---

## 2. Component Specifications

### 2.1 PlayerRig (`game/player/player_rig.gd` / `player_rig.tscn`)
- **State Machine**:
  - `PlayerMode.SHIP (0)`: Player controls the spacecraft. Ship flight controller and camera active; OnFootRig deactivated and hidden.
  - `PlayerMode.WALK (1)`: Player controls astronaut in EVA on-foot. OnFootRig active with third-person / first-person camera; ship controls neutralized.
- **EVA Transitions**:
  - `can_exit_ship()` checks if vessel is landed (`ship.is_landed == true` or low velocity near terrain).
  - Pressing `interact` ([F] / Gamepad X) exits ship at port airlock hatch (`hatch_relative_offset = Vector3(-3.5, 0.0, 0.0)` or `Ship/Hatch`).
  - Pressing `interact` within `hatch_interaction_distance` (6.0m) re-boards spacecraft.
- **Duck-Typed Subsystems**:
  - Queries `SurvivalSystem`: sets `is_inside_ship = (current_mode == PlayerMode.SHIP)`.

### 2.2 OnFootRig (`game/player/on_foot_rig.gd`)
- **Locomotion**: Walk (`4.0 m/s`), Sprint (`7.0 m/s`), Jump (`4.5 m/s`), Jetpack (`15.0 m/s²`).
- **Celestial Gravity**:
  - Dynamically samples `GravityService.gravity_accel(universe_pos, sim_time)`.
  - On the Moon: surface gravity is ~1.62 m/s², producing high buoyant jumps and extended jetpack hang time.
  - On Earth: standard 9.81 m/s² gravity.
- **Cameras**:
  - Third-person spring arm (`3.5m` distance) by default.
  - Toggle between 3rd-person and 1st-person via `toggle_camera` ([V] / Gamepad Right Stick Click).

### 2.3 CameraController (`scripts/camera_controller.gd`)
- 3 camera modes: `COCKPIT` (1st person), `CHASE` (3rd person), and `FREE` (360° orbit/fly).
- Dynamic speed FOV expansion from base 72° up to 90°.
- Trauma-based camera shake decaying smoothly over time.
- Switch modes via `toggle_camera` action ([V]).

### 2.4 Explorer HUD Components (`game/ui/components/` & `game/ui/`)
1. **FlightTelemetry (`flight_telemetry.tscn`)**:
   - Telemetry readouts: Speed (m/s, km/h, Mach), Altitude AGL and ASL, Apoapsis / Periapsis in km, Throttle gauge, Gear state.
2. **SuitBars (`suit_bars.tscn`)**:
   - Life support (O2) bar, hazard protection bar, jetpack fuel bar, digital compass heading.
3. **InventoryMenu (`inventory_menu.tscn`)**:
   - 16-slot grid navigable with keyboard arrow keys or gamepad D-pad/analog stick.
   - Slot focus triggers real-time item details inspection.
   - Duck-typed synchronization with `InventorySystem`.
4. **OrbitMap (`orbit_map.tscn`)**:
   - 2D orbital trajectory projection map with Ap / Pe marker labels, altitude tags, zoom in/out, pan, and trajectory color changes on atmospheric entry.
5. **PauseMenu (`pause_menu.tscn`)**:
   - Gamepad/keyboard navigable menu with Resume, Settings, Respawn at Base, and Quit.
   - Includes embedded `SettingsMenu` for accessibility, UI scale, and controls.
6. **TouchControls (`touch_controls.tscn`)**:
   - Automatically displayed when touch is available.
   - Contextually swaps between flight controls and on-foot buttons.

### 2.5 Master UI (`game/ui/game_ui.gd` / `game_ui.tscn`)
- Manages visibility of all HUD overlays and menus based on player state.
- Automatically toggles Flight Telemetry when in `SHIP` mode, and Suit Bars when in `WALK` mode.
- Global key shortcuts:
  - `[Tab]` or `[I]`: Toggle Inventory Menu.
  - `[M]`: Toggle Orbit Projection Map.
  - `[Esc]` or Pause button: Toggle Pause Menu.

### 2.6 TutorialDirector (`game/tutorial/tutorial_director.gd`)
- Data-driven sequence guiding the player through the complete loop:
  1. `adelaide_launch`: Launch from Adelaide Base, ascend through atmosphere.
  2. `achieve_orbit`: Circularize Low Earth Orbit (Ap/Pe > 80 km).
  3. `moon_landing`: Trans-lunar flight, lunar orbit, landing gear deployment, touchdown.
  4. `eva_exit`: Hatch interaction and exit onto lunar surface.
  5. `scan_sample`: Exploration scanner analysis of lunar regolith.
  6. `return_to_ship`: Return to vessel and board spacecraft.
- Failure recovery: on vessel destruction or player casualty, automatically resets vessel and player state to Adelaide Base and restarts onboarding.

---

## 3. Integration & Wiring Instructions

To connect these modules into `scenes/main.tscn`:

1. **Instance `PlayerRig`**:
   - Add an instance of `res://game/player/player_rig.tscn` to the scene.
   - Set `ship_path = NodePath("../Ship")`.
2. **Instance `GameUI`**:
   - Add an instance of `res://game/ui/game_ui.tscn` to the scene root.
   - Set `player_rig_path = NodePath("../PlayerRig")`.
   - Set `ship_path = NodePath("../Ship")`.
3. **Add `TutorialDirector`**:
   - Add a child node with script `res://game/tutorial/tutorial_director.gd`.
   - Set `ship = get_node("../Ship")`.
   - Set `player_rig = get_node("../PlayerRig")`.
   - Set `game_ui = get_node("../GameUI")`.
