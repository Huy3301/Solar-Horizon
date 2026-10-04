# Contributing to Solar Horizon

Welcome to the **Solar Horizon** developer and contributor guide. This document defines our engineering standards, architecture rules, precision requirements, mobile performance budgets, and testing protocols.

Solar Horizon is being actively overhauled from a small prototype into a high-fidelity, seamless space-exploration game targeting both modern desktop hardware (Forward+ renderer) and flagship mobile devices led by the **Samsung Galaxy S26+** (Mobile renderer, Vulkan).

---

## 1. Multi-Agent & Parallel Development Guidelines

Multiple engineers and AI agents work simultaneously within this repository on independent work packages. To prevent merge conflicts and regressions:

* **Strict File Ownership:** You may only create, modify, or delete files explicitly assigned to your work package. You may read any file in the repository.
* **No State-Altering Git Operations:** Do not run commands that alter repository state (`git commit`, `git checkout`, `git reset`, `git stash`, `git clean`, `git push`, etc.). Read-only commands (`git status`, `git diff`, `git log`) are permitted.
* **Project Settings Coordination:** Do not edit `project.godot` unless your package explicitly owns it. If you need new autoloads, input actions, or rendering configurations, document them in your completion report under *"Requests for other owners"*.

---

## 2. Repository Layout & Folder Rules

All new code, scenes, and resources must adhere to the modular project layout:

```
Solar-Horizon/
├── game/                       # PRIMARY DIRECTORY FOR ALL NEW ARCHITECTURE
│   ├── core/                   # 64-bit math, coordinate transforms, origin management, clocks
│   ├── universe/               # Keplerian orbits, gravity service, celestial body resources
│   ├── planet/                 # Quadtree cube-sphere, CDLOD, compute shaders, atmospheres
│   ├── player/                 # PlayerRig state machine, flight models, on-foot controller
│   ├── gameplay/               # Inventory, crafting, life support, hazard protection, scanning
│   ├── ui/                     # Diegetic HUD, sim telemetry overlay, touch interfaces
│   └── audio/                  # Audio buses, procedural atmosphere audio, vacuum filtering
├── tests/                      # Headless automated testing framework
│   ├── run_tests.gd            # Command-line test runner entrypoint
│   └── test_case.gd            # Base test case harness (TestCase)
├── tools/                      # Engineering and asset pipeline tools
│   ├── validate.ps1            # Headless project validation script
│   └── legacy/                 # Archived Python scripts (.gdignore)
├── concept_mockups/            # Offline rasterised concept imagery (.gdignore)
├── archive/                    # Archived early prototype scripts (.gdignore)
├── scripts/                    # Legacy prototype scripts (UNDER MIGRATION — DO NOT ADD NEW FILES)
├── scenes/                     # Legacy prototype scenes (UNDER MIGRATION)
├── shaders/                    # Visual shaders (terrain, atmosphere, sky, clouds)
└── assets/                     # glTF 2.0 models, textures, audio assets, materials
```

### Folder Placement Rules
1. **New Code:** Must be placed under `game/` inside the appropriate subsystem folder.
2. **Legacy Code:** Existing scripts in `scripts/` are being migrated or refactored into `game/`. **Never add new scripts to `scripts/`**.
3. **Ignored Directories:** Legacy tools (`tools/legacy/`), rasterised concept mockups (`concept_mockups/`), and retired scenes (`archive/`) contain a `.gdignore` file so Godot does not parse or import them.

---

## 3. GDScript Style Guide

We write clean, robust, statically typed GDScript conforming to Godot 4.x standards:

### 3.1 Static Typing Everywhere
Every variable, function parameter, return value, and collection must have an explicit static type:
```gdscript
# Correct
var current_velocity: float = 0.0
var active_bodies: Array[CelestialBodyDef] = []

func calculate_true_anomaly(mean_anomaly: float, eccentricity: float) -> float:
	return 0.0

# Incorrect
var current_velocity = 0.0
var active_bodies = []

func calculate_true_anomaly(mean_anomaly, eccentricity):
	return 0.0
```

### 3.2 Symbols and Architecture
* **`class_name` on reusable types:** Declare `class_name` at the top of script files intended for reuse across systems.
* **Doc comments:** Use `##` doc comments above classes, exported variables, and public functions so Godot's built-in documentation generator picks them up.
* **Indentation:** Use **tabs** for indentation (Godot standard).
* **Naming Conventions:**
  * `snake_case` for file names, directories, functions, variables, signals.
  * `PascalCase` for classes, types, enums.
  * `CONSTANT_CASE` for constants and enum values.

### 3.3 Constants vs. Magic Numbers
Never embed raw numbers into gameplay or simulation logic:
```gdscript
# Correct
const EARTH_RADIUS_METRES: float = 6371000.0
const REBASE_THRESHOLD_DISTANCE_M: float = 2000.0

# Incorrect
if distance > 2000.0:
	radius = 6371000.0
```

### 3.4 Zero Per-Frame Allocations in Hot Paths
The Garbage Collector in GDScript can cause micro-stutter if temporary objects are allocated in high-frequency loops:
* Do **not** instantiate new `Node`, `RefCounted`, `Array`, or `Dictionary` objects inside `_process()` or `_physics_process()`.
* Preallocate reusable scratch math vectors and buffers as class member variables.
* Prefer typed arrays and avoid resizing them inside per-frame updates.

---

## 4. The Precision Rule (CRITICAL)

Space exploration spans scales from millimeters (character boots) to gigameters (solar systems). Understanding floating-point limitations is mandatory for all Solar Horizon code:

> [!CAUTION]
> **Precision Axiom:**
> * Godot's internal 3D engine primitives (`Vector3`, `Transform3D`) are **32-bit floats** (`float32`).
> * Beyond ~5–10 km from the origin `(0, 0, 0)`, `float32` suffers from catastrophic cancellation, causing severe vertex jitter, z-fighting, and physics instabilities.
> * GDScript's primitive `float` is an **IEEE 754 64-bit double** (`float64`).

### Precision Guidelines
1. **Universe & Orbital Coordinates:** All universe-scale positions, planetary orbits, Keplerian state vectors, and interplanetary velocities **MUST** be stored and computed in 64-bit doubles using `DVec3` and `UniversePosition`.
2. **Never store astronomical positions in `Vector3`:** Any vector representing astronomical scale in `Vector3` is a bug.
3. **Local Render Space Rebase:** Local rendering and physics space are float32, centered around the player. `OriginService` automatically shifts a single `WorldRoot` node whenever the player moves more than **2 km (Mobile)** / **5 km (Desktop)** from the origin.
4. **Body-Fixed Rotating Frame:** When operating near a celestial body (below 2× atmosphere height), calculations and local origins bind to the body-fixed rotating reference frame to eliminate planetary surface sliding jitter.

---

## 5. Mobile Engineering Guidelines (Samsung Galaxy S26+)

The mobile baseline target is the **Samsung Galaxy S26+** (Adelaide/Global: Exynos 2600 with AMD Xclipse 960 GPU; US/CN: Snapdragon 8 Elite Gen 5 with Adreno 840 GPU).

### 5.1 Mobile Renderer (Vulkan Mobile)
* Core shaders and materials **must** run on the Mobile renderer.
* Features exclusive to Forward+ (SSAO, SSIL, SSR, SDFGI, volumetric fog) must never be required by core gameplay paths; they must be gated behind desktop graphics settings.
* All textures must be compressed with **ASTC** (6×6 for albedo, 4×4 for normal maps).

### 5.2 Performance Budgets (S26+ "Performance 60" Mode)

| Budget Area | Target Limit | Rationale |
|---|---|---|
| **Frame Time** | 16.6 ms (sustained 60 FPS) | Smooth gameplay on 120 Hz LTPO display |
| **GPU Frame Target** | **≤ 12.5 ms average** | 25% thermal headroom prevents OS clock throttling |
| **Render Resolution** | 1560×720 → FHD+ (2340×1080) | Upscaled via AMD FSR 1.0 (dynamic 0.6–0.8 scale) |
| **Draw Calls** | **≤ 600** per frame | Minimizes command buffer dispatch overhead |
| **Visible Triangles** | **≤ 1.5 M** per frame | Balances mobile vertex processing bandwidth |
| **Texture VRAM** | **≤ 1.2 GB** (ASTC compressed) | Keeps graphics memory footprint low |
| **Total RSS Memory** | **≤ 3.5 GB** | Prevents Android Low Memory Killer (LMK) eviction |
| **CPU Main Thread** | **≤ 8.0 ms** (Physics ≤ 2.0 ms) | CPU headroom for generation and OS tasks |
| **Shadows** | 2 cascades, 2048 res, Sun light only | Directional shadows only on mobile |
| **Dynamic Lights** | ≤ 4 visible omni/spot lights | Forward+ tiled lighting is absent on Mobile |

### 5.3 Thermal Awareness
Mobile phones have no active cooling fans. Sustained performance after 10–15 minutes drops to 50–65% of peak. Features must be architected for the throttled state:
* Integrate with Android Dynamic Performance Framework (ADPF) via `PowerManager.getThermalHeadroom()`.
* Dynamically adjust FSR scale, scatter density, and shadow cascades *before* thermal throttling engages.

---

## 6. Testing Protocols

Solar Horizon includes a lightweight, headless unit testing framework.

### 6.1 Writing Unit Tests
* Place test files in `tests/**/test_*.gd` (e.g. `tests/core/test_dvec3.gd`).
* Test classes must extend `TestCase` (`res://tests/test_case.gd`):
  ```gdscript
  class_name TestDVec3 extends TestCase

  func test_vector_addition() -> void:
  	var a: DVec3 = DVec3.new(1.0, 2.0, 3.0)
  	var b: DVec3 = DVec3.new(4.0, 5.0, 6.0)
  	var sum: DVec3 = a.add(b)
  	assert_almost_eq(sum.x, 5.0, 1e-6, "X components should match")
  	assert_almost_eq(sum.y, 7.0, 1e-6, "Y components should match")
  	assert_almost_eq(sum.z, 9.0, 1e-6, "Z components should match")
  ```
* Test methods must begin with the prefix `test_`.
* Available assertions in `TestCase`:
  * `assert_true(condition: bool, msg: String = "")`
  * `assert_false(condition: bool, msg: String = "")`
  * `assert_eq(a: Variant, b: Variant, msg: String = "")`
  * `assert_almost_eq(a: float, b: float, tol: float = 1e-5, msg: String = "")`
  * `assert_vec_almost_eq(a: Variant, b: Variant, tol: float = 1e-5, msg: String = "")`
  * `fail(msg: String)`

### 6.2 Running Tests Headlessly
Always validate your changes headlessly before pushing code:
```powershell
# Run the complete validation script
powershell -File tools/validate.ps1

# Or run tests directly with Godot
godot --headless --path . --script res://tests/run_tests.gd
```

---

## 7. Asset Pipelines & Licensing

* **3D Models:** Author models in Blender and export to **glTF 2.0** (`.glb` / `.gltf`). Models must include LOD levels (`_LOD0`, `_LOD1`, `_LOD2`) and simplified collision hulls (`-col`, `-colonly`).
* **Terrain Textures:** Scanned PBR material sets packed into `Texture2DArray` resources.
* **Licensing Requirement:** All external assets must have explicit licensing. **Creative Commons CC0 / Public Domain** is strongly preferred.
* **Attribution Tracking:** Every third-party texture, mesh, audio clip, or dataset must be logged in `assets/LICENSES.md` with:
  * Asset name and file path
  * Original author / organisation
  * Source URL
  * License type (e.g. CC0, Public Domain NASA, MIT)

---

## 8. Commit Message Conventions

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

* `feat: <description>` — A new feature, system, or capability.
* `fix: <description>` — A bug fix or correction.
* `docs: <description>` — Documentation changes (README, ROADMAP, CONTRIBUTING, doc comments).
* `refactor: <description>` — Code restructuring without altering external functionality.
* `perf: <description>` — Performance optimizations.
* `test: <description>` — Adding or updating test cases and test harnesses.
* `chore: <description>` — Maintenance, build scripts, ignore files, or project settings.
