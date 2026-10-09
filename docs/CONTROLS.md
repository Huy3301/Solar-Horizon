# Solar Horizon — Controls & Input Bindings

This document defines the unified input mappings for Solar Horizon across Desktop (Keyboard & Mouse), Gamepad (Standard Xbox / PlayStation Controller), and Mobile Touchscreens.

---

## 1. Flight Controls (Orbital & Atmospheric Flight)

| Action | Action Name | Keyboard / Mouse | Gamepad (Xbox / PS) | Touch / Mobile UI |
|---|---|---|---|---|
| **Pitch Down** (Nose Down) | `pitch_down` | <kbd>W</kbd> | Left Stick Up | Virtual Joystick Y- |
| **Pitch Up** (Nose Up) | `pitch_up` | <kbd>S</kbd> | Left Stick Down | Virtual Joystick Y+ |
| **Roll Left** (Bank Left) | `roll_left` | <kbd>A</kbd> | Left Stick Left | Virtual Joystick X- |
| **Roll Right** (Bank Right) | `roll_right` | <kbd>D</kbd> | Left Stick Right | Virtual Joystick X+ |
| **Yaw Left** (Rudder Left) | `yaw_left` | <kbd>Q</kbd> | Left Bumper (<kbd>LB</kbd> / <kbd>L1</kbd>) | Screen Yaw Left |
| **Yaw Right** (Rudder Right) | `yaw_right` | <kbd>E</kbd> | Right Bumper (<kbd>RB</kbd> / <kbd>R1</kbd>) | Screen Yaw Right |
| **Throttle Up** | `throttle_up` | <kbd>Shift</kbd> | Right Trigger (<kbd>RT</kbd> / <kbd>R2</kbd>) | Throttle Slider Up |
| **Throttle Down** | `throttle_down` | <kbd>Ctrl</kbd> | Left Trigger (<kbd>LT</kbd> / <kbd>L2</kbd>) | Throttle Slider Down |
| **VTOL / RCS Up** | `vtol_up` | <kbd>Space</kbd> | <kbd>A</kbd> / <kbd>Cross</kbd> | VTOL Button |
| **Airbrakes / Wheel Brakes** | `brake` | <kbd>B</kbd> | <kbd>B</kbd> / <kbd>Circle</kbd> | Brake Button |
| **Toggle Landing Gear** | `toggle_gear` | <kbd>G</kbd> | <kbd>Y</kbd> / <kbd>Triangle</kbd> | Gear Button |
| **Toggle Camera View** | `toggle_camera` | <kbd>V</kbd> | <kbd>Back</kbd> / <kbd>Share</kbd> | Camera Button |
| **Toggle System Map** | `toggle_map` | <kbd>M</kbd> | <kbd>D-Pad Up</kbd> | Map Button |
| **Time Warp Increase** | `time_warp_increase` | <kbd>.</kbd> | <kbd>D-Pad Right</kbd> | Warp (+) Button |
| **Time Warp Decrease** | `time_warp_decrease` | <kbd>,</kbd> | <kbd>D-Pad Left</kbd> | Warp (-) Button |

---

## 2. On-Foot Controls (Surface EVA)

| Action | Action Name | Keyboard / Mouse | Gamepad (Xbox / PS) | Touch / Mobile UI |
|---|---|---|---|---|
| **Move Forward** | `move_forward` | <kbd>W</kbd> | Left Stick Up | Movement Joystick Up |
| **Move Backward** | `move_back` | <kbd>S</kbd> | Left Stick Down | Movement Joystick Down |
| **Move Left** (Strafe) | `move_left` | <kbd>A</kbd> | Left Stick Left | Movement Joystick Left |
| **Move Right** (Strafe) | `move_right` | <kbd>D</kbd> | Left Stick Right | Movement Joystick Right |
| **Look / Aim** | `look_up` / `look_down` / `look_left` / `look_right` | Mouse Motion | Right Stick | Touch Look Area |
| **Jump** | `jump` | <kbd>Space</kbd> | <kbd>A</kbd> / <kbd>Cross</kbd> | Jump Button |
| **Jetpack Thrust** | `jetpack` | <kbd>Space</kbd> (airborne) / <kbd>Ctrl</kbd> | <kbd>A</kbd> (airborne) / <kbd>RT</kbd> | Jetpack Button |
| **Sprint** | `sprint` | <kbd>Shift</kbd> | Left Stick Click (<kbd>L3</kbd>) | Joystick Double-Tap / Drag |
| **Interact** | `interact` | <kbd>F</kbd> | <kbd>X</kbd> / <kbd>Square</kbd> | Interact Button |
| **Environmental Scan** | `scan` | <kbd>C</kbd> | Right Stick Click (<kbd>R3</kbd>) | Scan Button |
| **Visor Mode Toggle** | `visor` | <kbd>T</kbd> / <kbd>X</kbd> | <kbd>D-Pad Down</kbd> | Visor Button |
| **Pause / Menu** | `pause` | <kbd>Escape</kbd> | <kbd>Start</kbd> / <kbd>Options</kbd> | Pause Button |

---

## 3. Dedicated Actions & Input Separation

To eliminate input conflicts identified in previous versions (e.g. B-07 where `interact` previously toggled visor mode):
- **`interact`** is strictly reserved for contextual world interaction (doors, resource collection, cockpit switches).
- **`scan`** triggers an active planetary sensor ping to locate scannable entities, mineral deposits, and points of interest.
- **`visor`** toggles the analytical HUD visor mode independently.
- **`jetpack`** operates as a discrete action while also supporting double-jump / airborne space for intuitive platforming.


## Flight controls (Slice 1, NMS-style default)

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle up / down | Up / Down arrow | RT / LT |
| Boost | Shift | L3 |
| Pulse drive (toggle; needs >= 60 km clear of any body) | Tab | R3 |
| Lift / descend (VTOL) | Space / Ctrl | A / - |
| Pitch / roll / yaw | W,S / A,D / Q,E | sticks |
| Camera | V | - |

Touch Boost/Pulse buttons are not implemented yet. See docs/OVERHAUL_V3.md.
Tests: `godot --headless --path . --script res://tests/run_tests.gd` (~4 min). Filter with
`SH_TEST_FILE=test_slice1 SH_TEST_METHOD=takeoff`.
